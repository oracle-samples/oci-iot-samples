#!/usr/bin/env python3

"""
Publish Telemetry to the OCI IoT Platform MQTT endpoint using certificate authentication.

Telemetry is sent using a persistent MQTT connection.

Copyright (c) 2025 Oracle and/or its affiliates.
Licensed under the Universal Permissive License v 1.0 as shown at
https://oss.oracle.com/licenses/upl

DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
"""

import json
import sys
import time

import config
import paho.mqtt.client as mqtt

MQTT_PORT = 8883


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


# Callbacks - we only implement the on_connect
def on_connect(client, userdata, flags, reason_code, properties):
    print(f"Connected with result code {reason_code}")


client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)  # type: ignore
client.on_connect = on_connect

# TLS/SSL configuration
client.tls_set(
    ca_certs=config.ca_certs, certfile=config.client_cert, keyfile=config.client_key
)

# Proxy
if config.proxy_args:
    client.proxy_set(**config.proxy_args)

# Connect to the OCI IoT Platform and start the client loop
rc = client.connect(host=config.iot_device_host, port=MQTT_PORT, keepalive=60)
if rc != mqtt.MQTT_ERR_SUCCESS:
    print(f"Unable to connect - error: {rc}")
    sys.exit(1)
client.loop_start()

# Send telemetry
for count in range(1, config.message_count + 1):
    print(f"Sending message #{count}")
    telemetry_data["timestamp"] = current_epoch_microseconds()
    telemetry_data["count"] = count
    rc = client.publish(
        topic=config.iot_endpoint,
        payload=json.dumps(telemetry_data),
        qos=config.qos,
    )
    rc.wait_for_publish()
    time.sleep(config.message_delay)

# Tear down and exit
client.loop_stop()
client.disconnect()
