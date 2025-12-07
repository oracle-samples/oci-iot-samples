#
# vault.tf
#
# Copyright (c) 2025 Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at
# https://oss.oracle.com/licenses/upl.
#
# DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
#

# Create the KMS vault
resource "oci_kms_vault" "this" {
  compartment_id = local.compartment_id
  display_name   = "${local.org_name}-${var.app_id}-vlt-${local.region_short_name}"
  vault_type     = "DEFAULT"
  defined_tags   = var.defined_tags
  freeform_tags  = var.freeform_tags
  lifecycle {
    ignore_changes = [defined_tags, freeform_tags]
  }
  timeouts {
    create = "30m"
  }
}

# Master encryption keys: RSA for Certificate Authority, AES for Digital Twin secrets.
resource "oci_kms_key" "ca" {
  compartment_id = local.compartment_id
  display_name   = "${local.org_name}-${var.app_id}-key-${local.region_short_name}-cert"
  key_shape {
    algorithm = "RSA"
    # 2048 bits
    length = 256
  }
  defined_tags  = var.defined_tags
  freeform_tags = var.freeform_tags
  lifecycle {
    ignore_changes = [defined_tags, freeform_tags]
  }
  management_endpoint = oci_kms_vault.this.management_endpoint
}

resource "oci_kms_key" "secret" {
  compartment_id = local.compartment_id
  display_name   = "${local.org_name}-${var.app_id}-key-${local.region_short_name}-secret"
  key_shape {
    algorithm = "AES"
    length    = 16
  }
  defined_tags  = var.defined_tags
  freeform_tags = var.freeform_tags
  lifecycle {
    ignore_changes = [defined_tags, freeform_tags]
  }
  management_endpoint = oci_kms_vault.this.management_endpoint
}

# Auto-generates a unique secret/password for each basic Digital Twin.
resource "oci_vault_secret" "this" {
  count = var.iot_digital_twin_basic_count

  secret_name            = "${local.org_name}-${var.app_id}-secret-${local.region_short_name}-${var.iot_digital_twin_basic_name}-${format("%02d", count.index + 1)}"
  description            = "Secret for Digital Twin ${var.iot_digital_twin_basic_name}-${format("%02d", count.index + 1)} for ${var.app_id}${local.org_description}"
  compartment_id         = local.compartment_id
  key_id                 = oci_kms_key.secret.id
  vault_id               = oci_kms_vault.this.id
  enable_auto_generation = true
  metadata = {
    "externalKey" = "${var.iot_digital_twin_basic_name}-${format("%02d", count.index + 1)}"
  }
  secret_generation_context {
    generation_template = "DBAAS_DEFAULT_PASSWORD"
    generation_type     = "PASSPHRASE"
  }
  defined_tags  = var.defined_tags
  freeform_tags = var.freeform_tags
  lifecycle {
    ignore_changes = [defined_tags, freeform_tags]
  }
}

# Extract secrets and save them to a local file
data "oci_secrets_secretbundle" "this" {
  count = var.iot_digital_twin_basic_count

  secret_id = oci_vault_secret.this[count.index].id
  stage     = "CURRENT"
}

locals {
  iot_digital_twin_secrets = {
    for secret in data.oci_secrets_secretbundle.this : secret.metadata.externalKey => base64decode(secret.secret_bundle_content[0].content)
  }
}

# Write Digital Twin secrets to a local JSON file for use by sample devices/apps.
resource "local_sensitive_file" "secrets" {
  filename = "data/iot-device-secrets${local.org_name}.json"
  content  = jsonencode(local.iot_digital_twin_secrets)
}
