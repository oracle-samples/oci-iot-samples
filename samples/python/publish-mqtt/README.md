# Publish Telemetry Using MQTT

This guide explains how to publish telemetry to the OCI IoT Platform using MQTT.

We are using the [Eclipse Paho](http://eclipse.org/paho/) MQTT Python client library,
[`paho-mqtt`](https://pypi.org/project/paho-mqtt/) version 2.x.

Note that the OCI IoT Platform only supports MQTT Secure (MQTTS) on port 8883.

We will consider two use cases:

- One-shot publishing with the `publish.single` method, useful when maintaining a
  session is not necessary (low message rate).
- Instantiating an `mqtt.Client` to establish and maintain a connection with the OCI
  IoT Platform. This approach is preferred for higher message rates and is mandatory for
  bi-directional messaging between the client and the platform (pub/sub).

These examples illustrate publishing only, which is the most common use case.  
For a pub/sub scenario where the device also listens to messages from the OCI IoT Platform,
see the [Command and Response](../../..) example.

## Prerequisites

Install the Python dependencies
(using a [Python virtual environment](https://docs.python.org/3/library/venv.html) is recommended):

```shell
pip install -r requirements.txt
```

The script assumes a Digital Twin has already been created.
The sample payload sent will be accepted by any of the Digital Twins created by the
[Manage Digital Twins](../../script/manage-dt/) section of this repository.

## Configure and run the scripts

### Telemetry payload

- For unstructured telemetry, the content can be arbitrary.
- For structured telemetry, it must match the Model/Adapter.
- For structured telemetry in the default format, if a "time" property is specified,
  it must be an epoch time in microseconds and will override the "time_observed" field
  in the database.
- The same applies to structured telemetry in a custom format, but the mapping must be
  defined in the adapter.

The sample telemetry used by the scripts is compatible with all three Digital Twins
created in the "Manage Digital Twins" section of this repository:

```json
telemetry_data = {
    "time": 1757512025226854,
    "sht_temperature": 23.8,
    "qmp_temperature": 24.4,
    "humidity": 56.1,
    "pressure": 1012.2,
    "count": 1,
}
```

The `time` field is optional, this can be specified in the configuration file (see below)

### Common configuration

Copy `config.distr.py` to `config.py` and set the following variables:

- `iot_device_host`: The Device Host for your IoT Domain.
- `iot_endpoint`: The  MQTT topic for your telemetry.
- `message_count` and `message_delay`: The number of messages to send and the delay in
  seconds between messages.
- `time_format`: format of the `time` field in the payload:
  - `none`: No time information is included in the payload.
  - `epoch`: Current time as integer microseconds since Unix epoch.
  - `iso`: Current time as an ISO8601 string in UTC (with 'Z' suffix).
- `ca_certs`: The path to the CA certificate for the OCI IoT Platform.  
  In most cases, you won't need to specify this: OCI uses certificate authorities from
  well-established providers, and recent Python versions will find the CA certificate
  in the system store.  
  If your system does not provide this information, you can retrieve the root CA by
  examining the output of:

  ```shell
  openssl s_client -connect <iot_device_host>:8883
  ```

- `proxy_args`: If you are behind an HTTP or SOCKS proxy, enter your proxy configuration
  here. See the
  [proxy_set](https://eclipse.dev/paho/files/paho.mqtt.python/html/client.html#paho.mqtt.client.Client.proxy_set)
  documentation for more details.

### Using Password-Based Authentication

Set your device credentials in `config.py`:

- `username`: The "externalKey" property of your Digital Twin.
- `password`: The Digital Twin password, i.e., the content of the vault secret
  corresponding to the authId property of your Digital Twin.

Run the script:

```shell
# One-shot version
./pub-mqtt-one-basic.py
# mqtt.Client version
./pub-mqtt-client-basic.py
```

### Using Certificate-Based Authentication

Set the path to your client certificate and key in the `client_cert` and `client_key`
variables of the `config.py` file.

Keep in mind that the `authId` property of your Digital Twin must match the
Common Name (CN) of the certificate.

Run the script:

```shell
# One-shot version
./pub-mqtt-one-cert.py
# mqtt.Client version
./pub-mqtt-client-cert.py
```
