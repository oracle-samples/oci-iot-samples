#!/usr/bin/env python3

"""
Command-response scenario for the OCI IoT Platform.

Copyright (c) 2025 Oracle and/or its affiliates.
Licensed under the Universal Permissive License v 1.0 as shown at
https://oss.oracle.com/licenses/upl

DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
"""

import json
import sys
import threading
import time

import config
import paho.mqtt.client as mqtt

MQTT_PORT = 8883


# Get the current UTC time as an epoch value in microseconds.
def current_epoch_microseconds():
    return int(time.time() * 1000 * 1000)


# Telemetry data example.
telemetry_data = {
    "time": 0,
    "sht_temperature": 23.8,
    "qmp_temperature": 24.4,
    "humidity": 56.1,
    "pressure": 1012.2,
    "count": 0,
}

shutdown_event = threading.Event()


# Callback for MQTT connection event.
def on_connect(client, userdata, flags, reason_code, properties=None):
    print(f"Connected with result code {reason_code}")
    # Subscribe to all topics ending with /cmd (using '#' and filtering in callback).
    client.subscribe("#", qos=config.qos)


# Callback for MQTT message received event.
def on_message(client, userdata, message, properties=None):
    topic = message.topic
    payload = message.payload.decode()
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
            shutdown_event.set()  # Signal the telemetry loop to stop.

        # Build corresponding /rsp topic
        rsp_topic = topic[:-4] + "/rsp"
        ack_msg = json.dumps(
            {"status": "acknowledged", "time": current_epoch_microseconds()}
        )
        print(f"Sending ack to {rsp_topic}: {ack_msg}")
        client.publish(topic=rsp_topic, payload=ack_msg, qos=config.qos)


client = mqtt.Client(
    client_id=config.client_id,  # Ensure client_id is set for persistent sessions.
    clean_session=False,  # Enable persistent session.
    protocol=mqtt.MQTTv311,  # Use v311 unless v5 features are needed.
    callback_api_version=mqtt.CallbackAPIVersion.VERSION2,  # type: ignore
)
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
    count = 1
    print("Telemetry loop -- Press Ctrl-C to stop.")
    while not shutdown_event.is_set():
        print(f"Sending message #{count}")
        telemetry_data["time"] = current_epoch_microseconds()
        telemetry_data["count"] = count
        rc_pub = client.publish(
            topic=config.iot_endpoint,
            payload=json.dumps(telemetry_data),
            qos=config.qos,
        )
        rc_pub.wait_for_publish()
        count += 1
        time.sleep(config.message_delay)
except KeyboardInterrupt:
    print("\nInterrupted by user. Exiting...")

# Wait to process any potential /cmd messages before exit.
print("Waiting 2 seconds to process possible /cmd messages...")
time.sleep(2)

# Tear down the client and exit.
client.loop_stop()
client.disconnect()
print("Terminated")
