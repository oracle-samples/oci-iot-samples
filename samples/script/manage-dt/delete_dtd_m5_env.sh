#!/usr/bin/env bash
#
# Delete Environmental digital twin (Default format)
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

echo "${PGM}: Retrieve ${DTD_ENV_ID} ocid"
dt_id=$(oci iot digital-twin-instance list \
  --iot-domain-id "${IOT_DOMAIN_ID}" \
  --display-name "${DTD_ENV_ID}" \
  --lifecycle-state ACTIVE \
  --query "data.items[0].id" --raw-output
)
if [[ ! ${dt_id} =~ ^ocid1\.iotdigitaltwininstance\. ]]; then
  echo "${PGM}: Cannot find digital twin"
else
  echo "${PGM}: Delete Environmental DT ${DTD_ENV_ID}"
  oci iot digital-twin-instance delete --digital-twin-instance-id "${dt_id}"

fi

echo "${PGM}: Retrieve ${DTD_ENV_ADAPTER} ocid"
adapter_id=$(oci iot digital-twin-adapter list \
  --iot-domain-id "${IOT_DOMAIN_ID}" \
  --display-name "${DTD_ENV_ADAPTER}" \
  --lifecycle-state ACTIVE \
  --query "data.items[0].id" --raw-output
)
if [[ ! ${adapter_id} =~ ^ocid1\.iotdigitaltwinadapter\. ]]; then
  echo "${PGM}: Cannot find adapter"
else
  echo "${PGM}: Delete adapter ${DTD_ENV_ADAPTER}"
  oci iot digital-twin-adapter delete --digital-twin-adapter-id "${adapter_id}"
fi

echo "${PGM}: Retrieve model ${DTD_ENV_MODEL_ID} ocid"
model_id=$(oci iot digital-twin-model list \
  --iot-domain-id "${IOT_DOMAIN_ID}" \
  --spec-uri-starts-with "${DTD_ENV_MODEL_ID}" \
  --lifecycle-state ACTIVE \
  --query "data.items[0].id" --raw-output
)
if [[ ! ${model_id} =~ ^ocid1\.iotdigitaltwinmodel\. ]]; then
  echo "${PGM}: Cannot find model"
else
  echo "${PGM}: Delete model ${DTD_ENV_MODEL_ID}"
  oci iot digital-twin-model delete --digital-twin-model-id "${model_id}"
fi
