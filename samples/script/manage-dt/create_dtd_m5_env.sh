#!/usr/bin/env bash
#
# Create Environmental digital twin in default format
#
# Copyright (c) 2025 Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at
# https://oss.oracle.com/licenses/upl.
#
# DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
#

# shellcheck disable=SC2016

PGM=$(basename "$0")
readonly PGM
PGM_DIR=$( cd "$(dirname "$0")" && pwd -P )
readonly PGM_DIR

# shellcheck disable=SC1091
source "${PGM_DIR}/environ.sh"

echo "${PGM}: Create Environmental DT Model ${DTD_ENV_MODEL_ID}"
oci iot digital-twin-model create \
  --display-name "${DTD_ENV_MODEL_NAME}" \
  --description "A device with environmental sensors" \
  --iot-domain-id "${IOT_DOMAIN_ID}" \
  --spec '{
    "@context":[
      "dtmi:dtdl:context;3",
      "dtmi:dtdl:extension:historization;1",
      "dtmi:dtdl:extension:quantitativeTypes;1"
    ],
    "@id":"'"${DTD_ENV_MODEL_ID}"'",
    "@type":"Interface",
    "contents":[
      {
        "@type": ["Telemetry", "Historized", "Temperature"],
        "name": "sht_temperature",
        "displayName":"SHT Temperature",
        "schema": "double",
        "unit" : "degreeCelsius"
      },
      {
        "@type": ["Telemetry", "Historized", "Temperature"],
        "name": "qmp_temperature",
        "displayName":"QMP Temperature",
        "schema": "double",
        "unit" : "degreeCelsius"
      },
      {
        "@type": ["Telemetry", "Historized", "RelativeHumidity"],
        "name": "humidity",
        "displayName":"Relative Humidity",
        "schema" : "double",
        "unit" : "percent"
      },
      {
        "@type": ["Telemetry", "Historized", "Pressure"],
        "name": "pressure",
        "displayName":"Pressure",
        "schema" : "double",
        "unit" : "millibar"
      },
      {
        "@type": ["Telemetry"],
        "name": "count",
        "displayName":"Message Count",
        "schema": "integer"
      }
    ]
  }'

echo "${PGM}: Create Default Environmental DT Adapter ${DTD_ENV_ADAPTER}"
oci iot digital-twin-adapter create \
  --iot-domain-id "${IOT_DOMAIN_ID}" \
  --display-name "${DTD_ENV_ADAPTER}" \
  --description "A digital twin adapter for ${DTD_ENV_MODEL_ID}" \
  --digital-twin-model-spec-uri "${DTD_ENV_MODEL_ID}"

echo "${PGM}: Retrieve ${DTD_ENV_ADAPTER} ocid"
adapter_id=$(oci iot digital-twin-adapter list \
  --iot-domain-id "${IOT_DOMAIN_ID}" \
  --display-name "${DTD_ENV_ADAPTER}" \
  --lifecycle-state ACTIVE \
  --query "data[0].id" --raw-output
)
if [[ ! ${adapter_id} =~ ^ocid1\.iotdigitaltwinadapter\. ]]; then
  echo "${PGM}: Cannot find adapter"
  exit 1
fi

echo "${PGM}: Create Environmental DT ${DTD_ENV_ID}"
oci iot digital-twin-instance create \
  --display-name "${DTD_ENV_ID}" \
  --description "${DTD_ENV_ID}" \
  --iot-domain-id "${IOT_DOMAIN_ID}" \
  --digital-twin-adapter-id "${adapter_id}" \
  --external-key "${DTD_ENV_DEVICE_USER}" \
  --auth-id "${DTD_ENV_DEVICE_PASSWORD_ID_ID}"
