#!/usr/bin/env python3
# Configuration file

# Device host.
# The device host is an IoT Domain property and can be retrieved using:
#   oci iot domain get --iot-domain-id <IoT Domain OCID> \
#       --query data.deviceHost --raw-output
iot_device_host = "<Device Host>"

# The IoT endpoint can be any value, similar to the MQTT topic.
iot_endpoint = "iot/v1/http"


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
# Keep in mind that the authId property of your Digital Twin must match the
# Common Name (CN) of the certificate.
client_cert = "/path/to/client_certificate.pem"
client_key = ""
