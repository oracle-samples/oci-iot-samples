# Raw Command-Response Scenario

This guide explains how to manage command-response scenarios using MQTT.

We are using the [Eclipse Paho](http://eclipse.org/paho/) MQTT Python client library,
[`paho-mqtt`](https://pypi.org/project/paho-mqtt/) version 2.x.

Note that the OCI IoT Platform only supports MQTT Secure (MQTTS) on port 8883.

## Scenario

The `command-response.py` script will establish an MQTT connection with the OCI IoT
Platform and send telemetry data on a regular basis.
It will listen for commands by subscribing to topics ending in `/cmd` and acknowledge
by sending a response.
The script will terminate when it receives a _shutdown_ command or a keyboard interrupt (Control-C).

## Prerequisites

Install the Python dependencies
(using a [Python virtual environment](https://docs.python.org/3/library/venv.html) is recommended):

```shell
pip install -r requirements.txt
```

The script assumes a Digital Twin has already been created.

## Configure and run the script

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

### Configuration file

Copy `config.distr.py` to `config.py` and set the following variables:

- `iot_device_host`: The Device Host for your IoT Domain.
- `iot_endpoint`: The  MQTT topic for your telemetry.
- `message_delay`: The delay in seconds between messages.
- `client_id`: The client ID used for the MQTT connection (typically the name of your device).
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
- `auth_type`: Authentication type: `basic` or `cert`.
- For basic authentication:
  - `username`: The "externalKey" property of your Digital Twin.
  - `password`: The Digital Twin password; that is, the content of the vault secret
    corresponding to the authId property of your Digital Twin.
- For certificate authentication:
  - Set the path to your client certificate and key in the `client_cert` and `client_key`
    variables.
  - Keep in mind that the `authId` property of your Digital Twin must match the
    Common Name (CN) of the certificate.

Run the script:

```shell
./command-response.py
```

While the script is running, send raw commands using the OCI CLI -- e.g.:

```shell
oci iot digital-twin-instance invoke-raw-json-command \
  --digital-twin-instance-id <DigitalTwin OCID> \
  --request-endpoint "iot/v1/cmd" \
  --request-duration "PT10M" \
  --response-endpoint "iot/v1/rsp" \
  --response-duration "PT10M" \
  --request-data '{
    "hello": "world"
  }'
```

Sample session:

```text
$ ./command-response.py
Telemetry loop -- Press Ctrl-C to stop.
Sending message #1
Connected with result code Success
Sending message #2
Sending message #3
Sending message #4
Sending message #5
Sending message #6
Sending message #7
Received command on iot/v1/cmd: {"hello":"world"}
Sending ack to iot/v1/rsp: {"status": "acknowledged", "time": 1753456852150}
Sending message #8
Sending message #9
Received command on iot/v1/cmd: {"shutdown":true}
Shutdown command received. Preparing to exit...
Sending ack to iot/v1/rsp: {"status": "acknowledged", "time": 1753456874872}
Waiting 2 seconds to process possible /cmd messages...
Terminated
$
```

You can check the status of the message delivery and response in the `RAW_COMMAND_DATA`
database view.
