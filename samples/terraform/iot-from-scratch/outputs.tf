#
# outputs.tf
#
# Copyright (c) 2025 Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at
# https://oss.oracle.com/licenses/upl.
#
# DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
#

########## Compartment ##########

output "compartment_id" {
  description = "The OCID of the Compartment where all resources are created"
  value       = local.compartment_id
}

########## Vault ##########

output "vault_id" {
  description = "The OCID of the Vault used for Digital Twin Instances secret"
  value       = oci_kms_vault.this.id
}

output "vault_secrets_id" {
  description = "The OCID of the Digital Twin Instances secrets"
  value = {
    for secret in oci_vault_secret.this : secret.metadata.externalKey => secret.id
  }
}

########## Certificates ##########

output "certificate_root_ca_id" {
  description = "The OCID of the Root CA used for Digital Twin Instances certificates"
  value       = oci_certificates_management_certificate_authority.root_ca.id
}

output "certificate_sub_ca_id" {
  description = "The OCID of the Subordinate CA used for Digital Twin Instances certificates"
  value       = oci_certificates_management_certificate_authority.sub_ca.id
}

output "certificate_id" {
  description = "The OCID of the Digital Twin Instances certificates"
  value = {
    for cert in oci_certificates_management_certificate.this :
    cert.certificate_config[0].subject[0].common_name => cert.id
  }
}

########## IoT ##########

output "iot_domain_group_id" {
  description = "The OCID of the IoT Domain Group"
  value       = oci_iot_iot_domain_group.this.id
}

output "iot_domain_id" {
  description = "The OCID of the IoT Domain"
  value       = oci_iot_iot_domain.this.id
}

output "iot_data_host" {
  description = "The IoT Domain Group Data Host"
  value       = oci_iot_iot_domain_group.this.data_host
}

output "iot_device_host" {
  description = "The IoT Domain Device host"
  value       = oci_iot_iot_domain.this.device_host
}

output "iot_digital_twin_instances" {
  description = "Map of digital Twin Instances"
  value = {
    for iot_digital_twin in oci_iot_digital_twin_instance.this :
    iot_digital_twin.display_name => iot_digital_twin.id
  }
}

########## IoT - APEX data access ##########

output "iot_data_access_apex_url" {
  description = "The URL for the APEX environment"
  value       = var.configure_apex_data_access ? "https://${oci_iot_iot_domain_group.this.data_host}/ords/apex" : null
}

output "iot_data_access_apex_workspace_and_user" {
  description = "The workspace and username for the APEX environment"
  value       = var.configure_apex_data_access ? "${split(".", oci_iot_iot_domain.this.device_host)[0]}__wksp" : null
}

########## IoT - ORDS data access ##########

output "iot_data_access_ords_oauth_client_access" {
  description = "Ensure 'Configure client access' is enabled"
  value = (
    !var.configure_ords_data_access || var.configure_identity_domain_client_access ? null :
    <<-TEXT
    Ensure "Configure client access" for your Identity Domain is enabled via the Console
    or the OCI CLI:
      oci identity-domains setting patch \
          --setting-id Settings \
          --endpoint "https://${local.identity_domain_endpoint}" \
          --operations '[{"op": "replace", "path": "SigningCertPublicAccess", "value": true}]' \
          --schemas '["urn:ietf:params:scim:api:messages:2.0:PatchOp"]'
    TEXT
  )
}

output "iot_data_access_ords_confidential_app" {
  description = "The OCID of the Confidential App or the command to create it"
  value = (
    !var.configure_ords_data_access ? null :
    var.create_confidential_app ? "Created" : <<-TEXT
    Use the OCI console to create the Confidential App or run the following CLI command:
      oci identity-domains app create \
        --endpoint "https://${local.identity_domain_endpoint}" \
        --display-name "app${local.environment_name}" \
        --based-on-template '{
            "$ref": "${local.identity_domain_endpoint}/admin/v1/AppTemplates/CustomWebAppTemplateId",
            "value": "CustomWebAppTemplateId",
            "well-known-id": "CustomWebAppTemplateId"
        }' \
        --schemas '[
            "urn:ietf:params:scim:schemas:oracle:idcs:App",
            "urn:ietf:params:scim:schemas:oracle:idcs:extension:OCITags"
        ]' \
        --access-token-expiry ${var.access_token_expiry} \
        --active true \
        --allowed-grants '[
            "refresh_token",
            "password",
            "client_credentials",
            "urn:ietf:params:oauth:grant-type:jwt-bearer"
        ]' \
        --audience "/${split(".", oci_iot_iot_domain_group.this.data_host)[0]}" \
        --client-type confidential \
        --description "Confidential App${local.environment_description}" \
        --is-login-target true \
        --is-o-auth-client true \
        --is-o-auth-resource true \
        --scopes '[{
          "description": "${oci_iot_iot_domain.this.description}",
          "displayName": "${oci_iot_iot_domain.this.display_name}",
          "requiresConsent": false,
          "value": "/iot/${split(".", oci_iot_iot_domain.this.device_host)[0]}"
        }]'
    TEXT
  )
}

output "iot_data_access_ords_confidential_app_client_id" {
  description = "The Client Id to use in token requests"
  value       = var.create_confidential_app ? oci_identity_domains_app.this[0].name : null
}
output "iot_data_access_ords_confidential_app_client_secret" {
  description = "The Client Secret to use in token requests"
  value       = var.create_confidential_app ? oci_identity_domains_app.this[0].client_secret : null
}

output "iot_data_access_ords_oauth_endpoint" {
  description = "The OAuth endpoint to use to retrieve access token"
  value = (
    var.configure_ords_data_access ? "https://${local.identity_domain_endpoint}/${split(".", oci_iot_iot_domain_group.this.data_host)[0]}/iot/${split(".", oci_iot_iot_domain.this.device_host)[0]}" : null
  )
}

output "iot_data_access_ords_data_endpoint" {
  description = "The ORDS endpoint to use to query IoT data"
  value = (
    var.configure_ords_data_access ? "https://${oci_iot_iot_domain_group.this.data_host}/ords/${split(".", oci_iot_iot_domain.this.device_host)[0]}/20250531" : null
  )
}

########## IoT - direct database data access ##########

output "iot_data_access_direct_db_token_scope" {
  description = "The database token scope"
  value = (
    !var.configure_direct_database_access ? null : data.oci_iot_iot_domain_group.this[0].db_token_scope
  )
}

output "iot_data_access_direct_db_connect_string" {
  description = "The database connection string"
  value = (
    !var.configure_direct_database_access ? null : data.oci_iot_iot_domain_group.this[0].db_connection_string
  )
}

output "iot_data_access_direct_db_allow_listed_vcn_ids" {
  description = "The database connection string"
  value = (
    !var.configure_direct_database_access ? null : data.oci_iot_iot_domain_group.this[0].db_allow_listed_vcn_ids
  )
}

output "iot_data_access_direct_db_allow_listed_identity_group_names" {
  description = "The database connection string"
  value = (
    !var.configure_direct_database_access ? null : data.oci_iot_iot_domain.this[0].db_allow_listed_identity_group_names
  )
}

output "iot_data_access_direct_db_schema_iot" {
  description = "The database schema with IoT data (read-only)"
  value       = var.configure_direct_database_access ? "${split(".", oci_iot_iot_domain.this.device_host)[0]}__iot" : null
}

output "iot_data_access_direct_db_schema_workspace" {
  description = "The Workspace database schema (read/write)"
  value       = var.configure_direct_database_access ? "${split(".", oci_iot_iot_domain.this.device_host)[0]}__wksp" : null
}
