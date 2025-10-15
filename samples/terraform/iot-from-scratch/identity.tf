#
# identity.tf
#
# Copyright (c) 2025 Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at
# https://oss.oracle.com/licenses/upl.
#
# DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
#

# List of regions
data "oci_identity_regions" "all" {}

# Retrieve Identity Domain information (for ORDS data access)
data "oci_identity_domains" "this" {
  count = var.configure_ords_data_access && (var.identity_domain_endpoint == null) ? 1 : 0

  compartment_id = local.identity_domain_compartment_id
  display_name   = var.identity_domain_name
  state          = "ACTIVE"
}

# Ensures "Configure client access" is enabled in the Identity Domain configuration.
# Requires "read domains in tenancy" permission.
data "oci_identity_domains_setting" "this" {
  count = var.configure_identity_domain_client_access ? 1 : 0

  idcs_endpoint = local.identity_domain_endpoint
  setting_id    = "Settings"
}

# Requires "Identity Domain Administrator" role.
resource "terraform_data" "oci_identity_domains_setting_signing_cert_public_access" {
  count = var.configure_identity_domain_client_access ? 1 : 0

  triggers_replace = {
    idcs_domain_id             = data.oci_identity_domains_setting.this[0].domain_ocid
    signing_cert_public_access = data.oci_identity_domains_setting.this[0].signing_cert_public_access
  }

  provisioner "local-exec" {
    when        = create
    interpreter = ["/bin/bash", "-c"]
    command     = <<-CMD
      if [[ ${self.triggers_replace.signing_cert_public_access} == "false" ]]; then
        oci identity-domains setting patch \
            --setting-id Settings \
            --endpoint "https://${local.identity_domain_endpoint}" \
            --operations '[{"op": "replace", "path": "SigningCertPublicAccess", "value": true}]' \
            --schemas '["urn:ietf:params:scim:api:messages:2.0:PatchOp"]'
      fi
    CMD
  }
}


# Confidential Application for ORDS data access.
resource "oci_identity_domains_app" "this" {
  count = var.configure_ords_data_access && var.create_confidential_app ? 1 : 0

  display_name  = "app${local.environment_name}"
  idcs_endpoint = local.identity_domain_endpoint
  based_on_template {
    value         = "CustomWebAppTemplateId"
    well_known_id = "CustomWebAppTemplateId"
  }
  schemas = [
    "urn:ietf:params:scim:schemas:oracle:idcs:App",
    "urn:ietf:params:scim:schemas:oracle:idcs:extension:OCITags",
  ]
  access_token_expiry = var.access_token_expiry
  active              = true
  allowed_grants = [
    "refresh_token",
    "password",
    "client_credentials",
    "urn:ietf:params:oauth:grant-type:jwt-bearer",
  ]
  audience          = "/${split(".", oci_iot_iot_domain_group.this.data_host)[0]}"
  client_type       = "confidential"
  description       = "Confidential App${local.environment_description}"
  is_login_target   = true
  is_oauth_client   = true
  is_oauth_resource = true
  scopes {
    value            = "/iot/${split(".", oci_iot_iot_domain.this.device_host)[0]}"
    description      = oci_iot_iot_domain.this.description
    display_name     = oci_iot_iot_domain.this.display_name
    requires_consent = false
  }
  # The application must be disabled before being destroyed.
  provisioner "local-exec" {
    when    = destroy
    command = <<-CMD
      oci identity-domains app patch \
        --endpoint "https://${self.idcs_endpoint}" \
        --app-id ${self.id} \
        --schemas '["urn:ietf:params:scim:api:messages:2.0:PatchOp"]' \
        --operations '[{"op": "replace", "path": "active", "value": false}]'
    CMD
  }
  lifecycle {
    ignore_changes = [schemas]
  }
}

########## Service Policies ##########

# Policy for Certificate Authority Service access.
resource "oci_identity_policy" "ca" {
  count = var.create_service_policies ? 1 : 0

  provider       = oci.home
  compartment_id = local.compartment_id
  name           = "plc${local.environment_name}-ca"
  description    = "Certificate Authority Service policy${local.environment_description}"
  statements = [
    "allow any-user to use keys in compartment id ${local.compartment_id} where request.principal.type = 'certificateauthority'",
    "allow any-user to manage objects in compartment id ${local.compartment_id} where request.principal.type = 'certificateauthority'",
  ]
  defined_tags  = var.defined_tags
  freeform_tags = var.freeform_tags
  lifecycle {
    ignore_changes = [defined_tags, freeform_tags]
  }
}

# Policy for IoT Platform access.
resource "oci_identity_policy" "iot" {
  count = var.create_service_policies ? 1 : 0

  provider       = oci.home
  compartment_id = local.compartment_id
  name           = "plc${local.environment_name}-iot"
  description    = "IoT Platform policy${local.environment_description}"
  statements = [
    "allow any-user to {SECRET_BUNDLE_READ, SECRET_READ} in compartment id ${local.compartment_id} where request.principal.type = 'iotdomain'",
    "allow any-user to {CERTIFICATE_BUNDLE_READ, CERTIFICATE_READ} in compartment id ${local.compartment_id} where request.principal.type = 'iotdomain'",
    "allow any-user to {CERTIFICATE_AUTHORITY_BUNDLE_READ, CERTIFICATE_AUTHORITY_READ} in compartment id ${local.compartment_id} where request.principal.type = 'iotdomain'",
    "allow any-user to {CABUNDLE_READ} in compartment id ${local.compartment_id} where request.principal.type = 'iotdomain'",
  ]
  defined_tags  = var.defined_tags
  freeform_tags = var.freeform_tags
  lifecycle {
    ignore_changes = [defined_tags, freeform_tags]
  }
}

########## Compartment ##########

# Creates a compartment for all IoT resources (if requested).
resource "oci_identity_compartment" "this" {
  count = var.create_compartment ? 1 : 0

  provider       = oci.home
  compartment_id = var.parent_compartment_id
  name           = "cmp${local.environment_name}"
  description    = "IoT compartment ${local.environment_description}"
  defined_tags   = var.defined_tags
  freeform_tags  = var.freeform_tags
  lifecycle {
    ignore_changes = [defined_tags, freeform_tags]
  }
}
