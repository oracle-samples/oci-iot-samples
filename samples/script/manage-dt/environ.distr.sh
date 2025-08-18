#!/usr/bin/env bash
# Script configuration - IoT IR3

# shellcheck disable=SC2034

###
# Mandatory parameters - you must set up the following:
###

# Device Key - Used to generate unique names for various components
DEVICE_KEY=

# The OCI CLI profile for your IoT tenancy
export OCI_CLI_PROFILE="DEFAULT"

# Your IoT Domain OCID
IOT_DOMAIN_ID="ocid1.iotdomain...."

###
# Optional: ORDS Data Access
###

# The Domain Group Short ID is the first element of the dataHost property of
# the Domain Group.
# You can retrieve it with the following command:
# oci iot domain-group get --iot-domain-group-id <IoT Domain Group OCID> \
#   --query 'data."data-host"' --raw-output
DOMAIN_GROUP_SHORT_ID=

# The Domain Short ID is the first element of the deviceHost property of the
# Domain.
# You can retrieve it with the following command:
# oci iot domain get --iot-domain-id <IoT Domain OCID> \
#   --query 'data."device-host"' --raw-output
DOMAIN_SHORT_ID=

# IAM Domain URL (format: https://idcs-<redacted>.identity.oraclecloud.com:443)
IAM_DOMAIN_URL=

# Confidential Application Client ID and Secret
# You can find these in the OCI Console:
# Identity > Domain > Your Domain > Integrated App > OAuth
IAM_APP_CLIENT_ID=
IAM_APP_CLIENT_SECRET=

# The OCI user and password for the compartment where the Confidential
# Application is created. (Typically, this will be your OCI username and password,
# unless the application is created in a separate IAM domain.)
IAM_USER=
IAM_PASSWORD=

###
# IoT OCI Endpoints - Do not change
###
DOMAIN_REGION=us-ashburn-1
if [[ -n ${DOMAIN_GROUP_SHORT_ID} && -n ${DOMAIN_SHORT_ID} && -n ${IAM_DOMAIN_URL} ]]; then
    IOT_DATA_ENDPOINT="https://${DOMAIN_GROUP_SHORT_ID}.data.iot.${DOMAIN_REGION}.oci.oraclecloud.com/ords/${DOMAIN_SHORT_ID}/20250531"
    OAUTH_ENDPOINT="${IAM_DOMAIN_URL}/oauth2/v1/token"
fi

###
# Digital Twin Parameters
# Default values usually do not need to be changed.
# You must provide a _DEVICE_PASSWORD_ID, which should be the OCID of a vault
# secret or certificate.
###

# Unstructured Digital Twin
# You can send any telemetry to this Digital Twin.
UDT_ID="${DEVICE_KEY}-01"
UDT_DEVICE_USER="${UDT_ID}"
UDT_DEVICE_PASSWORD_ID_ID=

# M5 Stack with EnvIII sensor - Structured telemetry with Adapter in default format
# Payload should match the expected telemetry format as described in the README.
DTD_ENV_ID="${DEVICE_KEY}-m5-env-dflt-01"
DTD_ENV_MODEL_ID="dtmi:com:oracle:${DEVICE_KEY}:m5:env:dflt;1"
DTD_ENV_MODEL_NAME="M5 with EnvIII sensors (${DEVICE_KEY}-default)"
DTD_ENV_ADAPTER="${DEVICE_KEY}-m5-env-dflt-adapter"
DTD_ENV_DEVICE_USER="${DTD_ENV_ID}"
DTD_ENV_DEVICE_PASSWORD_ID_ID=

# M5 Stack with EnvIII sensor - Structured telemetry with Adapter in custom format
# Payload should match the expected telemetry format as described in the README.
DTC_ENV_ID="${DEVICE_KEY}-m5-env-cstm-01"
DTC_ENV_MODEL_ID="dtmi:com:oracle:${DEVICE_KEY}:m5:env:cstm;1"
DTC_ENV_MODEL_NAME="M5 with EnvIII sensors (${DEVICE_KEY}-custom)"
DTC_ENV_ADAPTER="${DEVICE_KEY}-m5-env-cstm-adapter"
DTC_ENV_DEVICE_USER="${DTC_ENV_ID}"
DTC_ENV_DEVICE_PASSWORD_ID_ID=
