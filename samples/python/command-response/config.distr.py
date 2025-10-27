#!/usr/bin/env python3
# Configuration file

# Device host.
# The device host is an IoT Domain property and can be retrieved using:
#   oci iot domain get --iot-domain-id <IoT Domain OCID> \
#       --query 'data."device-host"' --raw-output
iot_device_host = "<Device Host>"

# The MQTT topic.
iot_endpoint = "iot/v1/mqtt"

# Delay in seconds between messages.
message_delay = 10

# MQTT client id
client_id = "your_device_name"

# Format of the "time" field in the payload ("none", "epoch", "iso")
time_format = "epoch"

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

# Authentication type: basic or cert
auth_type = "basic"

###
# For basic authentication
###

# The username is the "externalKey" property of your Digital Twin.
username = "your_device_username"

# The Digital Twin password. This should be the content of the vault secret
# corresponding to the authId property of your Digital Twin.
password = "your_device_password"

###
# For certificate authentication (mTLS)
###

# Path to your client certificate and key.
# If both the certificate and private key are in the same file, set client_key to None.
# You can retrieve a certificate bundle from the OCI certificate store with:
# oci certificates certificate-bundle get \
#   --certificate-id <Certificate OCID> \
#   --bundle-type CERTIFICATE_CONTENT_WITH_PRIVATE_KEY |
#   jq -r '.data."certificate-pem"','.data."private-key-pem"' > client_certificate_bundle.pem
# Keep in mind that the externalKey property of your Digital Twin must match the
# Common Name (CN) of the certificate.
client_cert = "/path/to/client_certificate.pem"
client_key = ""
