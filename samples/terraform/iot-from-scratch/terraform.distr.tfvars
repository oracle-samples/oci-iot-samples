#
# terraform.distr.tfvars
#
# Template for terraform.tfvars (Rename to terraform.tfvars and edit)
#
# Copyright (c) 2025 Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at
# https://oss.oracle.com/licenses/upl.
#
# DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
#

########## Environment ##########
# Tenancy OCID (Required)
# tenancy_id = "YOUR_TENANCY_OCID"

# Region where resources are created (Required)
# region = "YOUR_OCI_REGION"

# The organization ID will be used in naming resources (Required)
# org_id = "YOUR_ORG_ID"
# The application ID will be used in naming resources (Optional, default: "iot")
# app_id = "iot"

# Freeform tags to add when creating resources (Optional)
# freeform_tags = {
#   terraformed = "Please do not edit manually"
# }

# Defined tags to add when creating resources (Optional)
# defined_tags = null

########## Identity ##########
# Create the service policies required by the Certificate Authorities Service and the IoT Platform.
# If you do not have "manage policies" granted, set this to "false" and ask an administrator.
# create_service_policies = false

########## Compartment ##########
# Create a sub-compartment for the IoT Platform resources. Requires "manage compartments".
# create_compartment = true

# Compartment where resources are created.
# (Required when create_compartment is false)
# compartment_id = null

# Parent compartment where the IoT compartment will be created.
# (Required when create_compartment is true)
# parent_compartment_id = null

########## Certificates ##########
# The maximum amount of days that any certificate issued can be valid
# leaf_certificate_max_validity_duration = 90

# Optional domain name to append to Canonical Name (CN) of certificates.
# E.g.: example.com
# certificate_domain = ""

########## IoT Digital Twin Model ##########
# Path to a Digital Twin Model DTDL (in "data" dir) (Optional).
# If this variable is set, a Digital Twin Model will be created and the
# Digital Twin Instances will use it.
# For demo/testing purposes, the following aligns with other samples in this
# repository:
#     - No value: creates Digital Twin Instances with unstructured telemetry
#     - "m5_model_default.json": creates Digital Twin Instances with structured
#     telemetry based on a default adapter
#     - "m5_model_custom.json": creates Digital Twin Instances with structured
#     telemetry based on a custom adapter
# iot_digital_twin_model_spec = null
# The Spec URI of the Digital Twin Model (required if model spec is set)
# iot_digital_twin_model_spec_uri = null

########## IoT Digital Twin Adapter ##########
# Path to a Digital Twin Adapter Envelope (in "data" dir). Optional, matches custom model.
# iot_digital_twin_adapter_envelope = null
# Path to Digital Twin Adapter Routes (in "data" dir). Required if envelope is set.
# iot_digital_twin_adapter_routes = null

########## IoT Digital Twin Instances ##########
# Number of Digital Twin Instances to create using basic authentication
# iot_digital_twin_basic_count = 0
# Name prefix for basic auth Digital Twins (device number appended)
# iot_digital_twin_basic_name = "device-basic"

# Number of Digital Twin Instances to create using certificate authentication
# iot_digital_twin_cert_count = 0
# Name prefix for cert auth Digital Twins (device number appended)
# iot_digital_twin_cert_name = "device-cert"

########## IoT Data Access ##########

# Configure APEX environment for the IoT Domain
# configure_apex_data_access = true

# Initial APEX admin password.
# Password must be between 12 and 30 characters long.
# apex_admin_initial_password = ""

# Configure ORDS data access.
# Terraform will ensure "Configure client access" is enabled in the Identity
# Domain configuration.
# Terraform will create the required "Confidential Application" if the user
# running the script has the necessary privileges (see create_confidential_app
# variable).
# Output will show the API endpoints.
# configure_ords_data_access = true

# Name of your Identity Domain. For ORDS data access; only change if using non-default.
# identity_domain_name = "Default"

# Compartment OCID where your Identity Domain resides (if not in root, for non-default domain)
# identity_domain_compartment_id = null

# Identity Domain endpoint (URL without "https://"). Terraform auto-discovers if not set.
# identity_domain_endpoint = null

# ORDS data access requires "Configure client access" to be enabled in the
# Identity Domain configuration.
# Updating this property requires "Identity Domain Administrator" role. if you do
# not have this role, set this variable to false and ask an administrator to assist.
# configure_identity_domain_client_access = true

# Create "Confidential Application" for ORDS OAuth.
# User must have "Identity Domain Application Administrator" privilege.
# create_confidential_app = true

# Expiry time (seconds) for OAuth Access Tokens.
# access_token_expiry = 3600

# Configure direct database access. This will allowlist VCNs and specify which
# (Dynamic) Identity Groups are allowed to connect to the database.
# configure_direct_database_access = true

# List of VCNs to allowlist for direct database access.
# db_allow_listed_vcn_ids = []

# List of (Dynamic) Groups to allowlist for direct database access.
# If the (Dynamic) Group is not in the Default Identity Domain, it must be prefixed
# by the Identity Domain name. Eg.: "IdentityDomainName/IdentityGroupName"
# If the group is not in this tenancy, prefix by "<other tenancy OCID>:"
# db_allow_listed_identity_group_names =[]
