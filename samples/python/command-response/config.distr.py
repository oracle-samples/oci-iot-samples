#!/usr/bin/env python3
# Configuration file

# Device host.
# The device host is an IoT Domain property and can be retrieved using:
#   oci iot domain get --iot-domain-id <IoT Domain OCID> \
#       --query data.deviceHost --raw-output
iot_device_host = "<Device Host>"

# The MQTT topic.
iot_endpoint = "iot/v1/mqtt"

# Delay in seconds between messages.
message_delay = 10

# MQTT client id
client_id = "your_device_name"

# Quality of Service
qos = 1

# Path to the CA certificate for the OCI IoT Platform.
# ca_certs = "/path/to/ca.crt"
# On modern Python, the system's default certificate authority is used,
# so this parameter does not typically need to be set.
ca_certs = None

# Proxy settings
# Paho MQTT supports HTTP and SOCKS proxies; see:
# https://eclipse.dev/paho/files/paho.mqtt.python/html/client.html#paho.mqtt.client.Client.proxy_set
# Define your proxy settings here if needed. For example, for an HTTP proxy:
# Note: The PySocks library must be installed to use proxies.
# import socks
# proxy_args = {
#     "proxy_type": socks.HTTP,
#     "proxy_addr": "my.proxy.host.name",
#     "proxy_port": 80,
# }
proxy_args = None

###
# Authentication
###

# The username is the "externalKey" property of your Digital Twin.
username = "your_device_username"

# The Digital Twin password. This should be the content of the vault secret
# corresponding to the authId property of your Digital Twin.
password = "your_device_password"
