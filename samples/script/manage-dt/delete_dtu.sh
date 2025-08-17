#!/usr/bin/env bash
#
# Workflow 1 - Teardown unstructured DT
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

echo "${PGM}: Retrieve ${UDT_ID} OCID"
dt_id=$(oci iot digital-twin-instance list \
  --iot-domain-id "${IOT_DOMAIN_ID}" \
  --display-name "${UDT_ID}" \
  --lifecycle-state ACTIVE \
  --query "data.items[0].id" --raw-output
)
if [[ ! ${dt_id} =~ ^ocid1\.iotdigitaltwininstance\. ]]; then
  echo "${PGM}: Cannot find digital twin"
  exit 1
fi

echo "${PGM}: Delete opaque DT ${UDT_ID}"
  oci iot digital-twin-instance delete --digital-twin-instance-id "${dt_id}"
