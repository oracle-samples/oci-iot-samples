#!/usr/bin/env python3

"""
Publish Telemetry to the OCI IoT Platform MQTT endpoint using basic authentication.

Telemetry is sent using a persistent MQTT connection.

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
import paho.mqtt.client as mqtt

MQTT_PORT = 8883


# Callbacks - we only implement the on_connect
def on_connect(client, userdata, flags, reason_code, properties):
    print(f"Connected with result code {reason_code}")


client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)  # type: ignore
client.on_connect = on_connect

# TLS/SSL configuration
client.tls_set(ca_certs=config.ca_certs)

# Authentication
client.username_pw_set(username=config.username, password=config.password)

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
telemetry = environmental_sensor_simulator.EnvironmentalSensorSimulator(
    time_format=config.time_format
)
for count in range(1, config.message_count + 1):
    print(f"Sending message #{count}")
    rc = client.publish(
        topic=config.iot_endpoint,
        payload=json.dumps(telemetry.get_telemetry()),
        qos=config.qos,
    )
    rc.wait_for_publish()
    time.sleep(config.message_delay)

# Tear down and exit
client.loop_stop()
client.disconnect()
