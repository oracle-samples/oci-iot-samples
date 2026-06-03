#!/bin/bash
set -euo pipefail

seed_marker=/data/.oci-iot-node-red-gateway-seeded
default_flow_warning="WARNING: please check you have started this container"

if [ ! -f "${seed_marker}" ]; then
  if [ ! -f /data/flows.json ] || grep -q "${default_flow_warning}" /data/flows.json; then
    cp /opt/oci-iot-node-red/flows.json /data/flows.json
  fi

  if [ ! -f /data/flows_cred.json ]; then
    cp /opt/oci-iot-node-red/flows_cred.json /data/flows_cred.json
  fi

  touch "${seed_marker}"
fi

exec /usr/src/node-red/entrypoint.sh
