#
# provider.tf
#
# Copyright (c) 2025 Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at
# https://oss.oracle.com/licenses/upl.
#
# DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
#

terraform {
  # Tested with Terraform 1.13, but not strictly required. Adjust as desired.
  required_version = "~> 1.13.0"
  required_providers {
    oci = {
      # Minimum version required to support the IoT Platform resources
      source  = "oracle/oci"
      version = "~> 7.0, >= 7.22.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5.0"
    }
  }
  # Use your preferred backend configuration here.
  backend "local" {
  }
}

# Configure the OCI provider through variables.
# Refer to: https://docs.oracle.com/en-us/iaas/Content/dev/terraform/configuring.htm
# The "config_file_profile" parameter may not work as expected (see:
# https://github.com/oracle/terraform-provider-oci/issues/2057).
provider "oci" {
  region = var.region
}

provider "oci" {
  alias  = "home"
  region = data.oci_identity_tenancy.this.home_region_key
}

data "oci_identity_tenancy" "this" {
  tenancy_id = var.tenancy_id
}
