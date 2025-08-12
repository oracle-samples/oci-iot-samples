# Publish Telemetry Using the REST Endpoint

Publishing telemetry through the OCI IoT Platform REST API is straightforward.

## Prerequisites

Install the Python dependencies (using a
[Python virtual environment](https://docs.python.org/3/library/venv.html) is recommended):

```shell
pip install -r requirements.txt
```

## Using Password-Based Authentication

Copy `config.distr.py` to `config.py` and set the following variables:

- `iot_device_host`: The Device Host for your IoT Domain
- `iot_endpoint`: The _path_ for your telemetry (equivalent to an MQTT topic)
- `username` and `password`: Credentials for your device

Run the script:

```shell
./pub-https-vault.py
```

## Using Certificate-Based Authentication

Copy `config.distr.py` to `config.py` and set the following variables:

- `iot_device_host`: The Device Host for your IoT Domain
- `iot_endpoint`: The _path_ for your telemetry (equivalent to an MQTT topic)
- `client_cert` and `client_key`: Paths to your client certificate and key

Run the script:

```shell
./pub-https-cert.py
```
