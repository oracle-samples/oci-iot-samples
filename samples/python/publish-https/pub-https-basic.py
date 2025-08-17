#!/usr/bin/env python3

"""
Publish Telemetry through the OCI IoT Platform REST API using basic authentication.

Copyright (c) 2025 Oracle and/or its affiliates.
Licensed under the Universal Permissive License v 1.0 as shown at
https://oss.oracle.com/licenses/upl

DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
"""

import json
from time import time

import config
import requests


# Get the current UTC time as epoch in microseconds
def current_epoch_microseconds():
    return int(time() * 1000 * 1000)


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
    "timestamp": current_epoch_microseconds(),
    "sht_temperature": 23.8,
    "qmp_temperature": 24.4,
    "humidity": 56.1,
    "pressure": 1012.2,
    "count": 5479,
}

try:
    response = requests.post(
        f"https://{config.iot_device_host}/{config.iot_endpoint}",
        data=json.dumps(telemetry_data),
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
