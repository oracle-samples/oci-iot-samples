#!/usr/bin/env python3

"""
Command-response scenario for the OCI IoT Platform.

Copyright (c) 2025 Oracle and/or its affiliates.
Licensed under the Universal Permissive License v 1.0 as shown at
https://oss.oracle.com/licenses/upl

DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
"""

import json
import os
import sys
import threading
import time

sys.path.append(
    os.path.abspath(os.path.join(os.path.dirname(__file__), os.pardir, "shared"))
)

import config
import environmental_sensor_simulator
import paho.mqtt.client as mqtt

MQTT_PORT = 8883


# Get the current UTC time as an epoch value in microseconds.
def current_epoch_microseconds():
    return int(time.time() * 1000 * 1000)


# Callback for MQTT connection event.
def on_connect(client, userdata, flags, reason_code, properties=None):
    print(f"Connected with result code {reason_code}")
    # Subscribe to all topics ending with /cmd (using '#' and filtering in callback).
    client.subscribe("#", qos=config.qos)


# Callback for MQTT message received event.
def on_message(client, userdata, message, properties=None):
    topic = message.topic
    payload = message.payload.decode()
    state = userdata
    if topic.endswith("/cmd"):
        print(f"Received command on {topic}: {payload}")
        # Command handling logic goes here.
        # For this example, only the shutdown command is handled, which will
        # terminate the script.
        try:
            cmd = json.loads(payload)
        except json.JSONDecodeError:
            cmd = None

        if cmd and cmd.get("shutdown", False):
            print("Shutdown command received. Preparing to exit...")
            state["shutdown_event"].set()  # Signal the telemetry loop to stop.

        # Build corresponding /rsp topic
        rsp_topic = topic[:-4] + "/rsp"
        ack_msg = json.dumps(
            {"status": "acknowledged", "time": current_epoch_microseconds()}
        )
        state["ack_msg_info"].append(
            client.publish(topic=rsp_topic, payload=ack_msg, qos=config.qos)
        )


client = mqtt.Client(
    client_id=config.client_id,  # Ensure client_id is set for persistent sessions.
    clean_session=False,  # Enable persistent session.
    protocol=mqtt.MQTTv311,  # Use v311 unless v5 features are needed.
    callback_api_version=mqtt.CallbackAPIVersion.VERSION2,  # type: ignore
)
state = {
    "ack_msg_info": [],
    "shutdown_event": threading.Event(),
}
client.user_data_set(state)
client.on_connect = on_connect
client.on_message = on_message

# TLS/SSL configuration.
client.tls_set(ca_certs=config.ca_certs)

# Authentication.
client.username_pw_set(username=config.username, password=config.password)

# Configure proxy if needed.
if config.proxy_args:
    client.proxy_set(**config.proxy_args)

# Connect to the OCI IoT Platform and start the client loop.
rc = client.connect(host=config.iot_device_host, port=MQTT_PORT, keepalive=60)
if rc != mqtt.MQTT_ERR_SUCCESS:
    print(f"Unable to connect - error: {rc}")
    sys.exit(1)
client.loop_start()

# Send telemetry messages.
try:
    telemetry = environmental_sensor_simulator.EnvironmentalSensorSimulator(
        time_format=config.time_format
    )
    count = 1
    print("Telemetry loop -- Press Ctrl-C to stop.")
    while not state["shutdown_event"].is_set():
        print(f"Sending message #{count}")
        rc_pub = client.publish(
            topic=config.iot_endpoint,
            payload=json.dumps(telemetry.get_telemetry()),
            qos=config.qos,
        )
        rc_pub.wait_for_publish()
        count += 1
        time.sleep(config.message_delay)
        # Drain ack_msg_info
        while state["ack_msg_info"]:
            state["ack_msg_info"].pop(0).wait_for_publish()

except KeyboardInterrupt:
    print("\nInterrupted by user. Exiting...")

# Wait to process any potential /cmd messages before exit.
print("Waiting 2 seconds to process possible /cmd messages...")
time.sleep(2)
# Drain ack_msg_info
while state["ack_msg_info"]:
    state["ack_msg_info"].pop(0).wait_for_publish()

# Tear down the client and exit.
client.loop_stop()
client.disconnect()
print("Terminated")
