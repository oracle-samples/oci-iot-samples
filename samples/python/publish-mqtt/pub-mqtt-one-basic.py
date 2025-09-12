#!/usr/bin/env python3

"""
Publish Telemetry to the OCI IoT Platform MQTT endpoint using basic authentication.

Telemetry is sent using "one-shot" MQTT connections.

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

MQTT_PORT = 8883

# TLS/SSL configuration
tls = {
    "ca_certs": config.ca_certs,
}

# Authentication
auth = {
    "username": config.username,
    "password": config.password,
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
        port=MQTT_PORT,
        auth=auth,  # type: ignore[assignment]
        tls=tls,  # type: ignore[assignment]
        proxy_args=config.proxy_args,
    )
    time.sleep(config.message_delay)
