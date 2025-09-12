#!/usr/bin/env python3

"""
Publish Telemetry to the OCI IoT Platform WebSockets endpoint using certificate authentication.

Telemetry is sent using "one-shot" WebSockets connections.

Copyright (c) 2025 Oracle and/or its affiliates.
Licensed under the Universal Permissive License v 1.0 as shown at
https://oss.oracle.com/licenses/upl

DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
"""

import json
import os
import sys
import time

sys.path.append(
    os.path.abspath(os.path.join(os.path.dirname(__file__), os.pardir, "shared"))
)

import config
import environmental_sensor_simulator
import paho.mqtt.publish as publish

WEBSOCKET_PORT = 443

# TLS/SSL configuration
tls = {
    "ca_certs": config.ca_certs,
    "certfile": config.client_cert,
    "keyfile": config.client_key,
}

telemetry = environmental_sensor_simulator.EnvironmentalSensorSimulator(
    time_format=config.time_format
)

for count in range(1, config.message_count + 1):
    print(f"Sending message #{count}")
    publish.single(
        topic=config.iot_endpoint,
        payload=json.dumps(telemetry.get_telemetry()),
        qos=config.qos,
        hostname=config.iot_device_host,
        port=WEBSOCKET_PORT,
        tls=tls,  # type: ignore[assignment]
        transport="websockets",
        proxy_args=config.proxy_args,
    )
    time.sleep(config.message_delay)
