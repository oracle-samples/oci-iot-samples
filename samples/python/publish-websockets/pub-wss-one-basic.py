#!/usr/bin/env python3

"""
Publish Telemetry to the OCI IoT Platform WebSockets endpoint using basic authentication.

Telemetry is sent using "one-shot" WebSockets connections.

Copyright (c) 2025 Oracle and/or its affiliates.
Licensed under the Universal Permissive License v 1.0 as shown at
https://oss.oracle.com/licenses/upl

DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
"""

import json
import time

import config
import paho.mqtt.publish as publish

WEBSOCKET_PORT = 443


# Get the current UTC time as epoch in microseconds
def current_epoch_microseconds():
    return int(time.time() * 1000 * 1000)


# Telemetry data.
# - For unstructured telemetry, the content can be arbitrary.
# - For structured telemetry, it must match the Model/Adapter.
# - For structured telemetry in the default format, if a "time" property is
#     specified, it must be an epoch time in microseconds and will override the
#     "time_observed" property.
# - The same applies to structured telemetry in a custom format, but the
#   mapping must be defined in the adapter.
#
# The sample telemetry below is compatible with all three Digital Twins created
# in the "Manage Digital Twins" section of this repository.
telemetry_data = {
    "timestamp": 0,
    "sht_temperature": 23.8,
    "qmp_temperature": 24.4,
    "humidity": 56.1,
    "pressure": 1012.2,
    "count": 0,
}

# TLS/SSL configuration
tls = {
    "ca_certs": config.ca_certs,
}

# Authentication
auth = {
    "username": config.username,
    "password": config.password,
}

for count in range(1, config.message_count + 1):
    print(f"Sending message #{count}")
    telemetry_data["timestamp"] = current_epoch_microseconds()
    telemetry_data["count"] = count
    publish.single(
        topic=config.iot_endpoint,
        payload=json.dumps(telemetry_data),
        qos=config.qos,
        hostname=config.iot_device_host,
        port=WEBSOCKET_PORT,
        auth=auth,  # type: ignore[assignment]
        tls=tls,  # type: ignore[assignment]
        transport="websockets",
        proxy_args=config.proxy_args,
    )
    time.sleep(config.message_delay)
