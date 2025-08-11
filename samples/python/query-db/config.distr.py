#!/usr/bin/env python3
# Configuration file
import os

# Database connect string and token scope as provided by the OCI IoT Platform.
# These are the dbConnectionString and dbTokenScope properties of your IoT Domain Group.
# They can be retrieved with:
#   oci iot domain-group get --iot-domain-id <IoT Domain Group OCID> \
#     --query 'data.[dbConnectionString, dbTokenScope]
db_connect_string = "tcps:adb.<region>.oraclecloud.com:1521/<redacted>"
db_token_scope = "urn:oracle:db::id::<Compartment OCID>"

# Domain short name.
# This is the hostname part of the IoT Domain device host and can be retrieved using:
#   oci iot domain get --iot-domain-id <IoT Domain OCID> |
#     jq -r '.data.deviceHost | split(".")[0]'
iot_domain_short_name = "<Domain SHort Name>"

# OCI CLI profile to use for token retrieval.
oci_profile = os.getenv("OCI_CLI_PROFILE", "DEFAULT")

# Number of rows to retrieve in the sample queries.
row_count = 5

# Select Thick or Thin mode for oracledb.
# TL;DR: use Thin mode unless you specifically need the Thick driver.
# See
# https://python-oracledb.readthedocs.io/en/latest/user_guide/appendix_b.html
# for a detailed explanation.
thick_mode = False
# In Thick mode, if the Oracle Client libraries can't be found, set the location below. See
# https://python-oracledb.readthedocs.io/en/latest/user_guide/initialization.html#enabling-python-oracledb-thick-mode
# for more information on setting lib_dir for your operating system.
lib_dir = None
