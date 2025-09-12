# Publish Telemetry Using the REST Endpoint

Publishing telemetry through the OCI IoT Platform REST API is straightforward.

## Prerequisites

Install the Python dependencies (using a
[Python virtual environment](https://docs.python.org/3/library/venv.html) is recommended):

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
- `time_format`: format of the `time` field in the payload:
  - `none`: No time information is included in the payload.
  - `epoch`: Current time as integer microseconds since Unix epoch.
  - `iso`: Current time as an ISO8601 string in UTC (with 'Z' suffix).

### Using Password-Based Authentication

Set your device credentials in `config.py`:

- `username`: The "externalKey" property of your Digital Twin.
- `password`: The Digital Twin password, i.e., the content of the vault secret
  corresponding to the authId property of your Digital Twin.

Run the script:

```shell
./pub-https-basic.py
```

### Using Certificate-Based Authentication

Set the path to your client certificate and key in the `client_cert` and `client_key`
variables of the `config.py` file.

Keep in mind that the `authId` property of your Digital Twin must match the
Common Name (CN) of the certificate.

Run the script:

```shell
./pub-https-cert.py
```
