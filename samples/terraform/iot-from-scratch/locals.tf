#
# locals.tf
#
# Copyright (c) 2025 Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at
# https://oss.oracle.com/licenses/upl.
#
# DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
#

# Locals used for resource naming conventions.
locals {
  org_name        = lower(replace(var.org_id, " ", ""))
  org_description = " (${var.org_id})"
  region_short_name = [
    for region in data.oci_identity_regions.all.regions :
    lower(region.key) if region.name == var.region
  ][0]
}

# Derived defaults for compartment and domain assignment.
locals {
  identity_domain_compartment_id = coalesce(var.identity_domain_compartment_id, var.tenancy_id)
  compartment_id                 = var.create_compartment ? oci_identity_compartment.this[0].id : var.compartment_id
  certificate_domain             = var.certificate_domain == "" ? "" : ".${var.certificate_domain}"
}


# Locals for Identity Domain and endpoint handling.
locals {
  identity_domain          = var.configure_ords_data_access && var.identity_domain_endpoint == null ? one(data.oci_identity_domains.this[0].domains) : null
  identity_domain_endpoint = var.configure_ords_data_access && var.identity_domain_endpoint == null ? regex("^https?://([^/:]+)", local.identity_domain.url)[0] : var.identity_domain_endpoint
}

# Load Digital Twin Adapter envelope and routes JSON files if specified.
locals {
  iot_digital_twin_adapter_envelope = var.iot_digital_twin_adapter_envelope == null ? null : jsondecode(file("${path.module}/data/${var.iot_digital_twin_adapter_envelope}"))
  iot_digital_twin_adapter_routes   = var.iot_digital_twin_adapter_routes == null ? null : jsondecode(file("${path.module}/data/${var.iot_digital_twin_adapter_routes}"))
}

# List of Digital Twin instances for this environment, including authentication data.
locals {
  iot_digital_twin_instances = merge(
    {
      for index, secret in oci_vault_secret.this :
      "${local.org_name}-${var.app_id}-iotdti-${local.region_short_name}-${var.iot_digital_twin_basic_name}-${format("%02d", index + 1)}" => {
        description  = "Digital Twin Instance ${var.iot_digital_twin_basic_name}-${format("%02d", index + 1)}"
        external_key = secret.metadata.externalKey
        auth_id      = secret.id
      }
    },
    {
      for index, cert in oci_certificates_management_certificate.this :
      "${local.org_name}-${var.app_id}-iotdti-${local.region_short_name}-${var.iot_digital_twin_cert_name}-${format("%02d", index + 1)}" => {
        description  = "Digital Twin Instance ${var.iot_digital_twin_cert_name}-${format("%02d", index + 1)}"
        external_key = cert.subject[0].common_name
        auth_id      = cert.id
      }
    }
  )
}

# List of allowlisted identity groups, prefixed by the tenancy OCID
locals {
  prefixed_allow_listed_identity_groups = [
    for group_name in var.db_allow_listed_identity_group_names :
    strcontains(group_name, ":") ? group_name : "${var.tenancy_id}:${group_name}"
  ]
}
