#
# variables.tf
#
# Copyright (c) 2025 Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at
# https://oss.oracle.com/licenses/upl.
#
# DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
#

########## Environment ##########
variable "tenancy_id" {
  description = "Tenancy OCID"
  type        = string
}
variable "region" {
  description = "Region where resources are created"
  type        = string
}
variable "org_id" {
  description = "The organization ID will be used in naming resources"
  type        = string
}
variable "app_id" {
  description = "The application ID will be used in naming resources"
  type        = string
  default     = "iot"
}
variable "freeform_tags" {
  description = "Freeform tags to add when creating resources"
  type        = map(string)
  default = {
    terraformed = "Please do not edit manually"
  }
}
variable "defined_tags" {
  description = "Defined tags to add when creating resources"
  type        = map(string)
  default     = null
}

########## Identity ##########
variable "create_service_policies" {
  description = <<-DESC
    Create the service policies required by the Certificate Authorities Service and
    the IoT Platform.
    If you do not have "manage policies" granted, set this to "false" and ask an
    administrator to create these.
    DESC
  type        = bool
  default     = false
}

########## Compartment ##########
variable "create_compartment" {
  description = <<-DESC
    Create a sub-compartment for the IoT Platform resources.
    "manage compartments" privilege is required for this.
    DESC
  type        = bool
  default     = true
}
variable "compartment_id" {
  description = <<-DESC
    Compartment where resources are created.
    (Required when create_compartment is false)
    DESC
  type        = string
  default     = null
  validation {
    condition     = var.create_compartment == (var.compartment_id == null || var.compartment_id == "")
    error_message = "If create_compartment is false, compartment_id must be set; if true, compartment_id must not be set."
  }
}
variable "parent_compartment_id" {
  description = <<-DESC
    Parent compartment where the IoT compartment will be created.
    (Required when create_compartment is true)
    DESC
  type        = string
  default     = null
  validation {
    condition     = var.create_compartment != (var.parent_compartment_id == null || var.parent_compartment_id == "")
    error_message = "If create_compartment is true, parent_compartment_id must be set; if false, parent_compartment_id must not be set."
  }
}

########## Vault ##########

########## Certificates ##########
variable "leaf_certificate_max_validity_duration" {
  description = "The maximum amount of days that any certificate issued can be valid"
  type        = number
  default     = 90
}
variable "certificate_domain" {
  description = <<-DESC
    Optional domain name that will be appended to the Canonical Name (CN) of the created
    certificate resources.
    E.g.: example.com
    DESC
  type        = string
  default     = ""
}

########## IoT Domain Group ##########

########## IoT Domain ##########

########## IoT Digital Twin Model ##########

variable "iot_digital_twin_model_spec" {
  description = <<-DESC
    The path to a Digital Twin Model DTDL, relative to the "data" directory.
    Optional.
    If this variable is set, a Digital Twin Model will be created and the
    Digital Twin Instances will use it.
    For demo/testing purposes, the following aligns with other samples in this
    repository:
      - No value: creates Digital Twin Instances with unstructured telemetry
      - "m5_model_default.json": creates Digital Twin Instances with structured
        telemetry based on a default adapter
      - "m5_model_custom.json": creates Digital Twin Instances with structured
        telemetry based on a custom adapter
    DESC
  type        = string
  default     = null
}

variable "iot_digital_twin_model_spec_uri" {
  description = <<-DESC
    The Spec URI of the Digital Twin Model.
    Mandatory when a Model is created.
    DESC
  type        = string
  default     = null
  validation {
    condition     = (var.iot_digital_twin_model_spec == null || var.iot_digital_twin_model_spec == "") == (var.iot_digital_twin_model_spec_uri == null || var.iot_digital_twin_model_spec_uri == "")
    error_message = "iot_digital_twin_model_spec and iot_digital_twin_model_spec_uri must be both set or unset"
  }
}

########## IoT Digital Twin Adapter ##########

variable "iot_digital_twin_adapter_envelope" {
  description = <<-DESC
    The path to a Digital Twin Adapter Envelope, relative to the "data" directory.
    Optional.
    If not specified and when a Digital Twin Model is created, a Default Adapter
    will be created.
    When specified, a Custom Adapter will be created using the Envelope and Routes
    files.
    The "m5_adapter_envelope.json" sample file can be used with the "m5_model_custom.json"
    Model DTDL to create Digital Twin Instances with telemetry in custom format
    and can be used with other samples from this repo.
    DESC
  type        = string
  default     = null
}

variable "iot_digital_twin_adapter_routes" {
  description = <<-DESC
    The path to Digital Twin Adapter Routes, relative to the "data" directory.
    Mandatory when iot_digital_twin_adapter_envelope is specified.
    The "m5_adapter_routes.json" sample file can be used with the "m5_model_custom.json"
    Model DTDL to create Digital Twin Instances with telemetry in custom format,
    and can be used with other samples from this repo.
    DESC
  type        = string
  default     = null
  validation {
    condition     = (var.iot_digital_twin_adapter_envelope == null || var.iot_digital_twin_adapter_envelope == "") == (var.iot_digital_twin_adapter_routes == null || var.iot_digital_twin_adapter_routes == "")
    error_message = "iot_digital_twin_adapter_routes and iot_digital_twin_adapter_envelope must be both set or unset"
  }
}

########## IoT Digital Twin Instances ##########

variable "iot_digital_twin_basic_count" {
  description = "The number of Digital Twin Instances to create, using basic authentication"
  type        = number
  default     = 0
}
variable "iot_digital_twin_basic_name" {
  description = "The name prefix for the created Digital Twin Instances (device number will be added)"
  type        = string
  default     = "device-basic"
}

variable "iot_digital_twin_cert_count" {
  description = "The number of Digital Twin Instances to create, using certificate authentication"
  type        = number
  default     = 0
}
variable "iot_digital_twin_cert_name" {
  description = "The name prefix for the created Digital Twin Instances (device number will be added)"
  type        = string
  default     = "device-cert"
}

########## IoT Data Access ##########

# APEX
variable "configure_apex_data_access" {
  description = <<-DESC
    Configure APEX environment.
    This will configure the APEX environment for the IoT Domain and output the
    APEX URL as well as the Workspace/Username.
    DESC
  type        = bool
  default     = true
}
variable "apex_admin_initial_password" {
  description = <<-DESC
    The initial APEX admin password.
    Password must be between 12 and 30 characters long.
    DESC
  type        = string
  default     = ""
  sensitive   = true
  validation {
    condition = var.configure_apex_data_access == false || (
      length(var.apex_admin_initial_password) >= 12 &&
    length(var.apex_admin_initial_password) <= 30)
    error_message = "The apex_admin_initial_password must be between 12 and 30 characters long when configure_apex_data_access is true."
  }
}

# ORDS
variable "configure_ords_data_access" {
  description = <<-DESC
    Configure ORDS data access.
    Terraform will ensure "Configure client access" is enabled in the Identity
    Domain configuration.
    Terraform will create the required "Confidential Application" if the user
    running the script has the necessary privileges (see create_confidential_app
    variable).
    Output will show the API endpoints.
  DESC
  type        = bool
  default     = true
}
variable "identity_domain_name" {
  description = <<-DESC
    Name of your Identity Domain.
    Required for ORDS data access if you use a non-default Identity Domain.
    DESC
  type        = string
  default     = "Default"
}
variable "identity_domain_compartment_id" {
  description = <<-DESC
    The compartment OCID where your Identity Domain resides.
    Only required for ORDS data access and using a non-default Identity Domain
    which isn't in the root compartment.
    DESC
  type        = string
  default     = null
}
variable "identity_domain_endpoint" {
  description = <<-DESC
    The Identity Domain endpoint.
    That is: the Identity Domain URL, without the "https://" prefix and the port number.
    Only required for ORDS data access.
    Terraform will retrieve this for you if you have enough privileges ("read domains in tenancy"),
    otherwise, ask an administrator to provide you with the endpoint.
    DESC
  type        = string
  default     = null
}
variable "configure_identity_domain_client_access" {
  description = <<-DESC
    ORDS data access requires "Configure client access" to be enabled in the
    Identity Domain configuration.
    Updating this property requires "Identity Domain Administrator" role. if you do
    not have this role, set this variable to false and ask an administrator to assist.
  DESC
  type        = bool
  default     = true
}
variable "create_confidential_app" {
  description = <<-DESC
    "Confidential Application" to manage OAuth tokens for ORDS data access.
    This requires "Identity Domain Application Administrator" privilege.
    Set this variable to false if the Terraform user doesn't have enough privileges.
    DESC
  type        = bool
  default     = true
  validation {
    condition     = (var.create_confidential_app && var.configure_ords_data_access) || !var.create_confidential_app
    error_message = "create_confidential_app is only useful when configure_ords_data_access is true"
  }
}
variable "access_token_expiry" {
  description = "Expiry-time in seconds for the OAuth Access Tokens"
  type        = number
  default     = 3600
}

# Direct database access
variable "configure_direct_database_access" {
  description = <<-DESC
    Configure direct database access.
    This will allowlist VCNs and specify which (Dynamic) Identity Groups are
    allowed to connect to the database.
    Output will show the commands to run and retrieve the database token scope
    as well as the connect string.
    DESC
  type        = bool
  default     = true
}

variable "db_allow_listed_vcn_ids" {
  description = <<-DESC
    List of VCNs to allowlist for direct database access.
    DESC
  type        = list(string)
  default     = []
  validation {
    condition     = (length(var.db_allow_listed_vcn_ids) > 0) == var.configure_direct_database_access
    error_message = "If configure_direct_database_access is true, db_allow_listed_vcn_ids must be set; if false, db_allow_listed_vcn_ids must not be set."
  }
}

variable "db_allow_listed_identity_group_names" {
  description = <<-DESC
    List of (Dynamic) Groups to allowlist for direct database access.
    If the (Dynamic) Group is not in the Default Identity Domain, it must be prefixed
    by the Identity Domain name. Eg.: "IdentityDomainName/IdentityGroupName"
    DESC
  type        = list(string)
  default     = []
  validation {
    condition     = (length(var.db_allow_listed_identity_group_names) > 0) == var.configure_direct_database_access
    error_message = "If configure_direct_database_access is true, db_allow_listed_identity_group_names must be set; if false, db_allow_listed_identity_group_names must not be set."
  }
}
