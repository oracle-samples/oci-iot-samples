# Publish Telemetry Using the REST Endpoint

You can use `curl` to publish telemetry from the command line or within a shell script.

## Prerequisites

You will need the Device Host for your IoT Domain. It can be retrieved with:

```shell
iot_domain_id="<IoT Domain OCID>"
iot_device_host=$(oci iot domain get --iot-domain-id "${iot_domain_id}" \
  --query 'data."device-host"' --raw-output
)
```

## Using Password-Based Authentication

```shell
iot_device_host="your.device.host"
# The IoT endpoint can be any value, similar to the MQTT topic.
iot_endpoint="iot/v1/http"
# The username is the "externalKey" property of your Digital Twin.
iot_device_user="your_device_username"
# The Digital Twin password: this should be the content of the vault secret
# corresponding to the authId property of your Digital Twin.
iot_device_password="your_device_password"
curl -X POST "https://${iot_device_host}/${iot_endpoint}" \
  --user "${iot_device_user}:${iot_device_password}" \
  --header "Content-Type: application/json" \
  --data  '{
      "count": 2,
      "humidity": 73,
      "pressure": 1023,
      "qmp_temperature": 22.1,
      "sht_temperature": 22.3
    }'
```

## Using Certificate-Based Authentication

You can retrieve a certificate bundle from the OCI certificate store with:

```shell
iot_certificate_id="<Certificate OCID>"
oci certificates certificate-bundle get \
  --certificate-id "${iot_certificate_id}" \
  --bundle-type CERTIFICATE_CONTENT_WITH_PRIVATE_KEY |
  jq -r '.data."certificate-pem"' > client_certificate.pem
oci certificates certificate-bundle get \
  --certificate-id "${iot_certificate_id}" \
  --bundle-type CERTIFICATE_CONTENT_WITH_PRIVATE_KEY |
  jq -r '.data."private-key-pem"' > client_key.pem
```

Keep in mind that the `externalKey` property of your Digital Twin must match the
Common Name (CN) of the certificate.

To publish telemetry:

```shell
iot_device_host="your.device.host"
# The IoT endpoint can be any value, similar to the MQTT topic.
iot_endpoint="iot/v1/http"
# Path to your client certificate and key.
client_cert="client_certificate.pem"
client_key="client_key.pem"
curl -X POST "https://${iot_device_host}/${iot_endpoint}" \
  --cert "${client_cert}" \
  --key "${client_key}" \
  --header "Content-Type: application/json" \
  --data  '{
      "count": 2,
      "humidity": 73,
      "pressure": 1023,
      "qmp_temperature": 22.1,
      "sht_temperature": 22.3
    }'
```
