#!/usr/bin/env bash
#
# Create unstructured DT
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

echo "${PGM}: Create unstructured DT ${UDT_ID}"
oci iot digital-twin-instance create \
  --display-name "${UDT_ID}" \
  --description "${UDT_ID}" \
  --iot-domain-id "${IOT_DOMAIN_ID}" \
  --external-key "${UDT_DEVICE_USER}" \
  --auth-id "${UDT_DEVICE_PASSWORD_ID_ID}"
