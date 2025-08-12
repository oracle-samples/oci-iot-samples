#!/usr/bin/env bash
#
# Create Environmental digital twin in custom format
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

echo "${PGM}: Create Environmental DT Model ${DTC_ENV_MODEL_ID}"
oci iot digital-twin-model create \
  --display-name "${DTC_ENV_MODEL_NAME}" \
  --description "A device with environmental sensors" \
  --iot-domain-id "${IOT_DOMAIN_ID}" \
  --spec '{
    "@context":[
      "dtmi:dtdl:context;3",
      "dtmi:dtdl:extension:historization;1",
      "dtmi:dtdl:extension:quantitativeTypes;1"
    ],
    "@id":"'"${DTC_ENV_MODEL_ID}"'",
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
      },
      {
        "@type": ["Telemetry", "Historized"],
        "name": "system",
        "displayName":"System Message",
        "schema": {
          "@type":"Object"
        }
      }
    ]
  }'

echo "${PGM}: Create Custom Environmental DT Adapter ${DTC_ENV_ADAPTER}"
oci iot digital-twin-adapter create \
  --display-name "${DTC_ENV_ADAPTER}" \
  --description "A digital twin adapter for ${DTC_ENV_MODEL_ID}" \
  --iot-domain-id "${IOT_DOMAIN_ID}" \
  --digital-twin-model-spec-uri "${DTC_ENV_MODEL_ID}" \
  --inbound-envelope '{
      "envelopeMapping": {
        "timeObserved": "$.time"
      },
      "referenceEndpoint": "/",
      "referencePayload": {
        "data": {
          "count": 0,
          "humidity": 0.0,
          "pressure": 0.0,
          "qmp_temperature": 0.0,
          "sht_temperature": 0.0
        },
        "dataFormat": "JSON"
      }
    }' \
  --inbound-routes '[
      {
        "condition": "${endpoint(1) == \"iot\"}",
        "description": "Environment data",
        "payloadMapping": {
          "$.count": "$.count",
          "$.humidity": "$.humidity",
          "$.pressure": "$.pressure",
          "$.qmp_temperature": "$.qmp_temperature",
          "$.sht_temperature": "$.sht_temperature"
        }
      },
      {
        "condition": "*",
        "description": "Default condition",
        "payloadMapping": {
          "$.system": "$"
        }
      }
    ]'

echo "${PGM}: Retrieve ${DTC_ENV_ADAPTER} ocid"
adapter_id=$(oci iot digital-twin-adapter list \
  --iot-domain-id "${IOT_DOMAIN_ID}" \
  --display-name "${DTC_ENV_ADAPTER}" \
  --lifecycle-state ACTIVE \
  --query "data[0].id" --raw-output
)
if [[ ! ${adapter_id} =~ ^ocid1\.iotdigitaltwinadapter\. ]]; then
  echo "${PGM}: Cannot find adapter"
  exit 1
fi

echo "${PGM}: Create Environmental DT ${DTC_ENV_ID}"
oci iot digital-twin-instance create \
  --display-name "${DTC_ENV_ID}" \
  --description "${DTC_ENV_ID}" \
  --iot-domain-id "${IOT_DOMAIN_ID}" \
  --digital-twin-adapter-id "${adapter_id}" \
  --external-key "${DTC_ENV_DEVICE_USER}" \
  --auth-id "${DTC_ENV_DEVICE_PASSWORD_ID_ID}"
