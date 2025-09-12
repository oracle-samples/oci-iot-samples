#!/usr/bin/env python3

"""
Publish Telemetry through the OCI IoT Platform REST API using basic authentication.

Copyright (c) 2025 Oracle and/or its affiliates.
Licensed under the Universal Permissive License v 1.0 as shown at
https://oss.oracle.com/licenses/upl

DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
"""

import json
import os
import sys

sys.path.append(
    os.path.abspath(os.path.join(os.path.dirname(__file__), os.pardir, "shared"))
)

import config
import environmental_sensor_simulator
import requests

telemetry = environmental_sensor_simulator.EnvironmentalSensorSimulator(
    time_format=config.time_format
)
payload = json.dumps(telemetry.get_telemetry())

try:
    response = requests.post(
        f"https://{config.iot_device_host}/{config.iot_endpoint}",
        data=payload,
        headers={"Content-Type": "application/json"},
        auth=(config.username, config.password),  # Basic auth
    )
    if response.ok:
        print("Telemetry data published successfully!")
    else:
        print(
            f"Failed to publish telemetry data: {response.status_code}, {response.text}"
        )
except requests.exceptions.RequestException as e:
    print(f"An error occurred: {e}")
