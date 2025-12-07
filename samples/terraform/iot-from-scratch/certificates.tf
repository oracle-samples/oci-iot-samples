#
# certificates.tf
#
# Copyright (c) 2025 Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at
# https://oss.oracle.com/licenses/upl.
#
# DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
#

# Notes:
# - The Root CA is generated for 10 years, allowing:
#     - var.leaf_certificate_max_validity_duration days for leaf certificates
#     - 3650 days for subordinate CAs
# - The Subordinate CA is generated for the maximum duration allowed (3650 days):
#     - var.leaf_certificate_max_validity_duration days for leaf certificates
#     - 3649 days for subordinate CAs (must be slightly shorter than the maximum duration)
#
# (As of Sep 2025) There is a known API issue requiring timestamps in milliseconds.
# The Terraform module strips milliseconds if they are zero, hence 1 millisecond is added to timestamps.

# Root CA
resource "oci_certificates_management_certificate_authority" "root_ca" {
  name           = "${local.org_name}-${var.app_id}-ca-${local.region_short_name}-root"
  description    = "Root CA for ${var.app_id}${local.org_description}"
  compartment_id = local.compartment_id
  kms_key_id     = oci_kms_key.ca.id
  certificate_authority_config {
    config_type       = "ROOT_CA_GENERATED_INTERNALLY"
    signing_algorithm = "SHA256_WITH_RSA"
    subject {
      common_name = "root-ca${local.certificate_domain}"
    }
    validity {
      # 10 years
      time_of_validity_not_after = replace(timeadd(timestamp(), "87660h"), "Z", ".001Z")
    }
  }
  certificate_authority_rules {
    rule_type                                   = "CERTIFICATE_AUTHORITY_ISSUANCE_EXPIRY_RULE"
    certificate_authority_max_validity_duration = "P3650D"
    leaf_certificate_max_validity_duration      = "P${var.leaf_certificate_max_validity_duration}D"
  }
  defined_tags  = var.defined_tags
  freeform_tags = var.freeform_tags
  lifecycle {
    ignore_changes = [defined_tags, freeform_tags, certificate_authority_config[0].validity]
  }
}

# Subordinate CA
resource "oci_certificates_management_certificate_authority" "sub_ca" {
  name           = "${local.org_name}-${var.app_id}-ca-${local.region_short_name}-sub"
  description    = "Subordinate CA for ${var.app_id}${local.org_description}"
  compartment_id = local.compartment_id
  kms_key_id     = oci_kms_key.ca.id
  certificate_authority_config {
    config_type                     = "SUBORDINATE_CA_ISSUED_BY_INTERNAL_CA"
    issuer_certificate_authority_id = oci_certificates_management_certificate_authority.root_ca.id
    signing_algorithm               = "SHA256_WITH_RSA"
    subject {
      common_name = "sub-ca${local.certificate_domain}"
    }
    validity {
      # Maximum allowed
      time_of_validity_not_after = replace(timeadd(timestamp(), "${3650 * 24}h"), "Z", ".001Z")
    }
  }
  certificate_authority_rules {
    rule_type                                   = "CERTIFICATE_AUTHORITY_ISSUANCE_EXPIRY_RULE"
    certificate_authority_max_validity_duration = "P3649D"
    leaf_certificate_max_validity_duration      = "P${var.leaf_certificate_max_validity_duration}D"
  }
  defined_tags  = var.defined_tags
  freeform_tags = var.freeform_tags
  lifecycle {
    ignore_changes = [defined_tags, freeform_tags, certificate_authority_config[0].validity]
  }
}

# Generate certificates for Digital Twin Instances.
resource "oci_certificates_management_certificate" "this" {
  count = var.iot_digital_twin_cert_count

  name           = "${local.org_name}-${var.app_id}-cert-${local.region_short_name}-${var.iot_digital_twin_cert_name}-${format("%02d", count.index + 1)}"
  description    = "Certificate for Digital Twin ${var.iot_digital_twin_cert_name}-${format("%02d", count.index + 1)} ${local.region_short_name}${local.org_description}"
  compartment_id = local.compartment_id
  certificate_config {
    config_type                     = "ISSUED_BY_INTERNAL_CA"
    certificate_profile_type        = "TLS_CLIENT"
    issuer_certificate_authority_id = oci_certificates_management_certificate_authority.sub_ca.id
    subject {
      common_name = "${var.iot_digital_twin_cert_name}-${format("%02d", count.index + 1)}${local.certificate_domain}"
    }
    validity {
      time_of_validity_not_after = replace(timeadd(timestamp(), "${var.leaf_certificate_max_validity_duration * 24}h"), "Z", ".001Z")
    }
  }
  certificate_rules {
    rule_type              = "CERTIFICATE_RENEWAL_RULE"
    advance_renewal_period = "P${floor(var.leaf_certificate_max_validity_duration / 10)}D"
    renewal_interval       = "P${var.leaf_certificate_max_validity_duration - 1}D"
  }
  defined_tags  = var.defined_tags
  freeform_tags = var.freeform_tags
  lifecycle {
    ignore_changes = [defined_tags, freeform_tags, certificate_config[0].validity]
  }
}

# Save certificate OCIDs to a local file
# The OCI Terraform provider does not permit retrieval of certificate keys.
# This must be handled separately.
locals {
  iot_digital_twin_cert_id = {
    for c in oci_certificates_management_certificate.this : c.certificate_config[0].subject[0].common_name => c.id
  }
}

resource "local_file" "certificates" {
  filename = "data/iot-device-cert-id${local.org_name}-${var.app_id}.json"
  content  = jsonencode(local.iot_digital_twin_cert_id)
}
