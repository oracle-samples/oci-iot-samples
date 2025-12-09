#
# iot.tf
#
# Copyright (c) 2025 Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at
# https://oss.oracle.com/licenses/upl.
#
# DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
#

resource "oci_iot_iot_domain_group" "this" {
  compartment_id = local.compartment_id
  display_name   = "${local.org_name}-${var.app_id}-iotdmngrp-${local.region_short_name}"
  description    = "IoT Domain Group for ${var.app_id}${local.org_description}"

  defined_tags  = var.defined_tags
  freeform_tags = var.freeform_tags
  lifecycle {
    ignore_changes = [defined_tags, freeform_tags]
  }
  timeouts {
    create = "30m"
  }
}

resource "oci_iot_iot_domain" "this" {
  compartment_id      = local.compartment_id
  iot_domain_group_id = oci_iot_iot_domain_group.this.id
  display_name        = "${local.org_name}-${var.app_id}-iotdmn-${local.region_short_name}"
  description         = "IoT Domain for ${var.app_id}${local.org_description}"
  defined_tags        = var.defined_tags
  freeform_tags       = var.freeform_tags
  lifecycle {
    ignore_changes = [defined_tags, freeform_tags]
  }
}

# Create a Digital Twin Model using the "var.iot_digital_twin_model_spec" DTDL file.
# The Spec URI in the DTDL will be overridden by the "iot_digital_twin_model_spec_uri"
# variable. Model creation is optional. If devices are created (see below), they will use
# this model. If no model is created, devices will use unstructured telemetry.
resource "oci_iot_digital_twin_model" "this" {
  count = var.iot_digital_twin_model_spec == null ? 0 : 1

  iot_domain_id = oci_iot_iot_domain.this.id
  display_name  = "${local.org_name}-${var.app_id}-iotmdl-${local.region_short_name}"
  description   = "Digital Twin Model for ${var.app_id}${local.org_description}"
  spec = jsonencode(
    merge(
      jsondecode(file("${path.module}/data/${var.iot_digital_twin_model_spec}")),
      {
        "@id" = var.iot_digital_twin_model_spec_uri
      }
    )
  )

  defined_tags  = var.defined_tags
  freeform_tags = var.freeform_tags
  lifecycle {
    ignore_changes = [defined_tags, freeform_tags]
  }
}

# Create a Digital Twin Adapter.
# The adapter will be created if a model is created.
# If no Digital Twin Adapter envelope and routes are specified, a default adapter is created.
resource "oci_iot_digital_twin_adapter" "this" {
  # We only need an adapter if we have a Model
  count = var.iot_digital_twin_model_spec == null ? 0 : 1

  iot_domain_id         = oci_iot_iot_domain.this.id
  display_name          = "${local.org_name}-${var.app_id}-iotadptr-${local.region_short_name}"
  description           = "Digital Twin Adapter for ${var.app_id}${local.org_description}"
  digital_twin_model_id = oci_iot_digital_twin_model.this[0].id

  dynamic "inbound_envelope" {
    for_each = var.iot_digital_twin_adapter_envelope == null ? {} : { envelope = true }
    content {
      reference_endpoint = local.iot_digital_twin_adapter_envelope.referenceEndpoint
      dynamic "envelope_mapping" {
        for_each = contains(keys(local.iot_digital_twin_adapter_envelope), "envelopeMapping") ? { envelope_mapping = true } : {}
        content {
          time_observed = try(local.iot_digital_twin_adapter_envelope.envelopeMapping.timeObserved, null)
        }
      }
      dynamic "reference_payload" {
        for_each = contains(keys(local.iot_digital_twin_adapter_envelope), "referencePayload") ? { reference_payload = true } : {}
        content {
          data        = local.iot_digital_twin_adapter_envelope.referencePayload.data
          data_format = local.iot_digital_twin_adapter_envelope.referencePayload.dataFormat
        }
      }
    }
  }

  dynamic "inbound_routes" {
    for_each = var.iot_digital_twin_adapter_routes == null ? [] : local.iot_digital_twin_adapter_routes
    content {
      condition       = inbound_routes.value.condition
      description     = try(inbound_routes.value.description, null)
      payload_mapping = try(inbound_routes.value.payloadMapping, null)
      dynamic "reference_payload" {
        for_each = contains(keys(inbound_routes.value), "referencePayload") ? { reference_payload = true } : {}
        content {
          data        = inbound_routes.value.referencePayload.data
          data_format = inbound_routes.value.referencePayload.dataFormat
        }
      }

    }
  }

  defined_tags  = var.defined_tags
  freeform_tags = var.freeform_tags
  lifecycle {
    ignore_changes = [defined_tags, freeform_tags]
  }
}

# Create sample Digital Twin Instance.
# If Digital Twin Model/Adapter is created, the Instance will expect telemetry
# in structured format (default or custom Adapter). Otherwise, it will accept unstructured telemetry.
resource "oci_iot_digital_twin_instance" "this" {
  for_each = local.iot_digital_twin_instances

  iot_domain_id = oci_iot_iot_domain.this.id
  display_name  = each.key
  description   = each.value.description

  digital_twin_adapter_id = var.iot_digital_twin_model_spec == null ? null : oci_iot_digital_twin_adapter.this[0].id

  auth_id      = each.value.auth_id
  external_key = each.value.external_key

  defined_tags  = var.defined_tags
  freeform_tags = var.freeform_tags
  lifecycle {
    ignore_changes = [defined_tags, freeform_tags]
  }
}

########## Data access ##########
# Add dependencies to avoid concurrent data access resource creation

########## APEX data access ##########
resource "oci_iot_iot_domain_configure_data_access" "apex" {
  count = var.configure_apex_data_access ? 1 : 0

  iot_domain_id                       = oci_iot_iot_domain.this.id
  type                                = "APEX"
  db_workspace_admin_initial_password = var.apex_admin_initial_password
}

########## ORDS data access ##########
resource "oci_iot_iot_domain_configure_data_access" "ords" {
  count = var.configure_ords_data_access ? 1 : 0

  iot_domain_id                   = oci_iot_iot_domain.this.id
  type                            = "ORDS"
  db_allowed_identity_domain_host = local.identity_domain_endpoint
  depends_on = [
    oci_iot_iot_domain_configure_data_access.apex
  ]
}

########## Direct database data access ##########
resource "oci_iot_iot_domain_group_configure_data_access" "direct" {
  count = var.configure_direct_database_access ? 1 : 0

  iot_domain_group_id     = oci_iot_iot_domain_group.this.id
  db_allow_listed_vcn_ids = var.db_allow_listed_vcn_ids
  depends_on = [
    oci_iot_iot_domain_configure_data_access.ords
  ]
}

resource "oci_iot_iot_domain_configure_data_access" "direct" {
  count = var.configure_direct_database_access ? 1 : 0

  iot_domain_id                        = oci_iot_iot_domain.this.id
  type                                 = "DIRECT"
  db_allow_listed_identity_group_names = local.prefixed_allow_listed_identity_groups
  depends_on = [
    oci_iot_iot_domain_group_configure_data_access.direct
  ]
}

# Re-query IoT Domain Group to get database token scope and connect string
# after being configured
data "oci_iot_iot_domain_group" "this" {
  count = var.configure_direct_database_access ? 1 : 0

  iot_domain_group_id = oci_iot_iot_domain_group.this.id
  depends_on = [
    oci_iot_iot_domain_group_configure_data_access.direct
  ]
}

# Re-query IoT Domain to list allowlisted Identity Groups for database access
# after being configured
data "oci_iot_iot_domain" "this" {
  count = var.configure_direct_database_access ? 1 : 0

  iot_domain_id = oci_iot_iot_domain.this.id
  depends_on = [
    oci_iot_iot_domain_configure_data_access.direct
  ]
}
