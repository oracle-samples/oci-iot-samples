#!/usr/bin/env bash
#
# Query unstructured twin
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

"${PGM_DIR}/get_oauth_token.sh"
# shellcheck disable=SC1091
source "${PGM_DIR}/token.sh"

echo "${PGM}: Retrieve ${UDT_ID} ocid"
dt_id=$(oci iot digital-twin-instance list \
  --iot-domain-id "${IOT_DOMAIN_ID}" \
  --display-name "${UDT_ID}" \
  --lifecycle-state ACTIVE \
  --query "data[0].id" --raw-output
)
if [[ ! ${dt_id} =~ ^ocid1\.iotdigitaltwininstance\. ]]; then
  echo "${PGM}: Cannot find digital twin"
  exit 1
fi

echo "${PGM}: Query unstructured DT ${UDT_ID}"
oci iot digital-twin-instance get -digital-twin-instance-id "${dt_id}"

echo "${PGM}: Recent raw data"
if [[ $(uname -s) == "Darwin" ]]; then
  gnu_date="gdate"
else
  gnu_date="date"
fi
recently=$(${gnu_date} -u +"%Y-%m-%dT%H:%M:%SZ" --date='5 minutes ago')
curl -k -s --get \
  --location "${IOT_DATA_ENDPOINT}/rawData" \
  --data-urlencode 'q={"$and":[{"digital_twin_instance_id":"'"${dt_id}"'"},{"time_received":{"$gte":{"$date":"'"${recently}"'"}}}]}' \
  --data-urlencode offset=0 \
  --data-urlencode limit=100 \
  --header "Authorization: Bearer ${API_DATA_TOKEN}"  \
  --header "Content-Type: application/json" | jq '.items'

echo "${PGM}: Recent rejected data"
curl -k -s --get \
  --location "${IOT_DATA_ENDPOINT}/rejectedData" \
  --data-urlencode 'q={"$and":[{"digital_twin_instance_id":"'"${dt_id}"'"},{"time_received":{"$gte":{"$date":"'"${recently}"'"}}}]}' \
  --data-urlencode offset=0 \
  --data-urlencode limit=100 \
  --header "Authorization: Bearer ${API_DATA_TOKEN}"  \
  --header "Content-Type: application/json" | jq '.items'
