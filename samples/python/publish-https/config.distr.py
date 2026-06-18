#!/usr/bin/env python3

"""
Configuration template for the HTTPS publish sample.

Copyright (c) 2025, 2026 Oracle and/or its affiliates.
Licensed under the Universal Permissive License v 1.0 as shown at
https://oss.oracle.com/licenses/upl

DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
"""

# Device host.
# The device host is an IoT Domain property and can be retrieved using:
#   oci iot domain get --iot-domain-id <IoT Domain OCID> \
#       --query 'data."device-host"' --raw-output
iot_device_host = "<Device Host>"

# The IoT endpoint can be any value, similar to the MQTT topic.
iot_endpoint = "iot/v1/telemetry"

# Format of the "time" field in the payload ("none", "epoch", "iso")
time_format = "epoch"

###
# For basic authentication
###

# The username is the "externalKey" property of your Digital Twin.
username = "your_device_username"

# The Digital Twin password: this should be the content of the vault secret
# corresponding to the authId property of your Digital Twin.
password = "your_device_password"

###
# For certificate authentication (mTLS)
###

# Path to your client certificate and key.
# If both certificate and private key are in the same file, leave client_key
# empty
# You can retrieve a certificate bundle from the OCI certificate store with:
# oci certificates certificate-bundle get \
#   --certificate-id  <certificate OCID> \
#   --bundle-type CERTIFICATE_CONTENT_WITH_PRIVATE_KEY |
#   jq -r '.data."certificate-pem"','.data."private-key-pem"' > client_certificate_bundle.pem
# Keep in mind that the externalKey property of your Digital Twin must match the
# Common Name (CN) of the certificate.
client_cert = "/path/to/client_certificate.pem"
client_key = ""
