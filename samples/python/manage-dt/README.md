# OCI IoT Platform Device Workflow Demo Python script

Sample Python application to create, query, and delete devices to illustrate the use of the
[OCI Python SDK](https://docs.oracle.com/en-us/iaas/tools/python/latest/), in particular
the bindings for the [OCI IoT Platform](https://docs.oracle.com/en-us/iaas/tools/python/latest/api/iot.html)
as well as the [ORDS API](https://docs.oracle.com/iaas/tools/internet-of-things/data-api/index.html)
for data access.

The `manage-dt` package consists of several source files and can be installed with `pip`
(see below). If you are only interested in looking at the sample code:

- [mdt_iot_oci.py](./manage_dt/mdt_iot_oci.py) contains the calls to the OCI Python SDK
- [mdt_iot_data.py](./manage_dt/mdt_iot_data.py) focuses on the ORDS data API

## Prerequisites

The application assumes that you have already set up an OCI IoT Platform environment in
your OCI tenancy:

- an OCI IoT Domain Group and Domain
- OCI Vault secrets and/or OCI Certificates for your device credentials
- a Confidential Application to issue tokens for querying telemetry via ORDS. This step is
  only required for the `query` command of `manage-dt`.

## Installation

To install and run the `manage-dt` application, you need **Python 3.12 or higher**.

We recommend installing in an isolated virtual environment:

```sh
# Ensure Python 3.12+ is available
python3 --version

# Create and activate a new virtual environment
python3 -m venv venv
source venv/bin/activate

# Upgrade pip (optional but recommended)
python -m pip install --upgrade pip

# Install the application and dependencies
pip install .
```

You can now use the console command:

```sh
manage-dt --help
```

## Configuration file

The application gets its configuration from the `iot_config.yaml` file in the `data`
directory. Copy the `iot_config.distr.yaml` template to `iot_config.yaml` and enter the
required data.

### `iot` section

This section is for the IoT Platform parameters:

- `domain_id`: the OCID of your IoT Domain

### `identity` section

This section contains the OCI Identity parameters and relates to the OAuth configuration
needed to access the ORDS API.

This section is needed for the `query` command of the application.

- `app_client_id` and `app_client_secret`: the Confidential Application Client ID and
  Secret. You can find these in the OCI Console: `Identity > Domain > Your Domain >
  Integrated App > OAuth`
- `user` and `password`: the OCI User and Password in the Identity Domain where the
  Confidential Application is created. Typically, this will be your OCI username and
  password, unless the application is created in a separate Identity Domain.

### `environ` section

Define here environment variables which can be referenced in the `digital_twins`
section. The sample data defines a `device_key` variable, used to name your digital
twins and avoid duplicate names if different users run the same sample application.
It also defines `auth_id`, the OCID of a Vault Secret containing the password for the device.

### `digital_twins` section

Describes the Digital Twins that can be managed by the application. The sample data
provides 3 different digital twins:

- `unstructured`: a Digital Twin with unstructured telemetry
- `default-adapter`: a Digital Twin with structured telemetry using the default Adapter
- `custom-adapter`: a Digital Twin with structured telemetry with a custom Adapter

You can use these definitions as-is, customize them, or create your own Digital Twin
definitions.

For each Digital Twin, you must have:

- `device_name`: the name of the device
- `external_key`: the username the device will use to authenticate
- `auth_id`: the OCID of a Vault Secret containing the password for the device
  (Basic authentication) or the OCID of a Certificate for the device (Certificate
  authentication)

These parameters are sufficient for a Digital Twin with unstructured telemetry.

Additionally, for a Digital Twin with structured telemetry using the default Adapter, you
also need to provide a model:

- `model_name`: the Digital Twin Model Identifier (DTMI) for your model
- `model_description`: a plain text description of the model
- `model_dtdl`: the name of a file containing the model definition (relative to the data
  directory)
- `adapter_name`: name for the adapter that will be generated

Finally, for a Digital Twin with structured telemetry with a custom Adapter you will need
to provide the Adapter definition:

- `adapter_name`: the name of the Adapter
- `adapter_envelope`: the name of a file containing the inbound envelope definition
  (relative to the data directory)
- `adapter_routes`: the name of a file containing the inbound routes definition (relative
  to the data directory)

The sample definitions in this repository are for an Environmental Sensor reporting two
temperatures in degrees Celsius, pressure in hectoPascals, and relative humidity in
percent.

Note that while the OCI CLI uses hyphen-separated words for the Adapter definitions, the
API uses camelCase notation. For example, `envelope-mapping` for the OCI CLI becomes
`envelopeMapping` when using the Python SDK or the API.

**Note:** The structured telemetry defined in this script is based on the payload sent by
an [M5Stack CoreS3](https://docs.m5stack.com/en/core/CoreS3) device with an
[Env-III](https://docs.m5stack.com/en/unit/envIII) environmental sensor.  
The expected payload is:

```json
{
  "sht_temperature": 23.8,
  "qmp_temperature": 24.4,
  "humidity": 56.1,
  "pressure": 1012.2,
  "count": 5479
}
```

This payload can be emulated by the various sample scripts in this repository.

## Usage

```text
$ Usage: manage-dt [OPTIONS] COMMAND [ARGS]...

  Manage Digital Twins.

  Sample application to create/query/delete Digital Twins for the OCI Iot
  Platform.

Options:
  -v, --verbose                   Verbose mode
  -d, --debug                     Debug mode
  --profile TEXT                  The profile in the config file to load.
                                  [default: wim-iot-fra]
  --auth [api_key|instance_principal|resource_principal]
                                  The type of auth to use for the API request.
                                  [default: api_key]
  --data-dir DIRECTORY            Data directory  [default: ./data]
  --iot-config-file FILE          The path to the IoT config file.  [default:
                                  iot_config.yaml]
  --version                       Show the version and exit.
  --help                          Show this message and exit.

Commands:
  create  Create a new Digital Twin.
  delete  Delete a Digital Twin.
  query   Query recent data for a Digital Twin.
```

The `verbose`/`debug` options control the verbosity of the tool.

The `profile` and `auth` options are similar to those used with the OCI CLI. Similarly,
they can be set with environment variables: `OCI_CLI_PROFILE` and `OCI_CLI_AUTH`
respectively.

`data-dir` allows you to specify the location of the data directory, and `iot-config-file`
can be used to specify an alternative configuration file.

The script supports three basic commands:

- `create`: creates the Digital Twin (with the Model and Adapter if applicable)
- `query`: queries the content of the Digital Twin (structured telemetry) as well as the
  Raw Data, Historized Data, and Rejected Data using the ORDS Data API. By default, data
  for the last 5 minutes is retrieved. You can use the `last-minutes` parameter to
  specify a different duration.
- `delete`: deletes the Digital Twin (with the Model and Adapter if applicable)

## Sample session

```text
$ manage-dt --debug create custom-adapter 
2025-09-18 20:30:59,503 - DEBUG    - cli.py           - Loading configuration
2025-09-18 20:30:59,505 - DEBUG    - mdt_oci.py       - OCI authentication: Config file
2025-09-18 20:30:59,506 - DEBUG    - config.py        - Config file found at ~/.oci/config
2025-09-18 20:30:59,575 - INFO     - mdt_iot_oci.py   - Create Digital Twin Model 'dtmi:com:oracle:pvhd:m5:env:cstm;1'
2025-09-18 20:30:59,795 - INFO     - mdt_iot_oci.py   - Digital Twin Model created
2025-09-18 20:30:59,798 - INFO     - mdt_iot_oci.py   - Create custom Digital Twin Adapter 'pvhd-m5-env-cstm-adapter'
2025-09-18 20:31:01,116 - INFO     - mdt_iot_oci.py   - Digital Twin Adapter created
2025-09-18 20:31:01,116 - INFO     - mdt_iot_oci.py   - Create Digital Twin Instance pvhd-m5-env-cstm-01 - Structured Telemetry with custom Adapter
2025-09-18 20:31:02,947 - INFO     - mdt_iot_oci.py   - Digital Twin Instance created
$ # Send some data and query:
$ manage-dt --debug query custom-adapter
2025-09-18 20:32:39,566 - DEBUG    - cli.py           - Loading configuration
2025-09-18 20:32:39,569 - DEBUG    - mdt_oci.py       - OCI authentication: Config file
2025-09-18 20:32:39,569 - DEBUG    - config.py        - Config file found at ~/.oci/config
2025-09-18 20:32:40,356 - INFO     - mdt_iot_oci.py   - Digital Twin Instance retrieved
2025-09-18 20:32:40,357 - INFO     - mdt_iot_oci.py   - Query Digital Twin Instance 'custom-adapter'
2025-09-18 20:32:40,556 - INFO     - mdt_iot_oci.py   - Digital Twin Instance content retrieved
╭────────────────────────────────────────── Digital Twin Instance content ────────────────────────────╮
│ {'humidity': 73, 'count': 2, 'pressure': 1023, 'sht_temperature': 22.3, 'qmp_temperature': 22.1}    │
╰─────────────────────────────────────────────────────────────────────────────────────────────────────╯
2025-09-18 20:32:40,573 - DEBUG    - mdt_iot_data.py  - Using cached data access configuration and token
         Recent raw data - 2 record(s)          
┏━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━┓
┃ Id  ┃ Time received (UTC)         ┃ Endpoint ┃
┡━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━╇━━━━━━━━━━┩
│ 535 │ 2025-09-18T18:32:28.847244Z │ iot/pvhd │
│ 536 │ 2025-09-18T18:32:34.621067Z │ iot/pvhd │
└─────┴─────────────────────────────┴──────────┘
              Recent historized data - 4 record(s)              
┏━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━┳━━━━━━━┓
┃ Id   ┃ Time observed (UTC)         ┃ Content path    ┃ Value ┃
┡━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━╇━━━━━━━┩
│ 1852 │ 2025-09-18T18:32:28.847244Z │ sht_temperature │ 22.3  │
│ 1853 │ 2025-09-18T18:32:28.847244Z │ humidity        │ 73    │
│ 1854 │ 2025-09-18T18:32:28.847244Z │ pressure        │ 1023  │
│ 1855 │ 2025-09-18T18:32:28.847244Z │ qmp_temperature │ 22.1  │
└──────┴─────────────────────────────┴─────────────────┴───────┘
                             Recent rejected data - 1 record(s)                              
┏━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ Id ┃ Time received (UTC)         ┃ Endpoint ┃ Reason code ┃ Reason message                ┃
┡━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┩
│ 48 │ 2025-09-18T18:32:34.621067Z │ iot/pvhd │ 500         │ Normalization output is empty │
└────┴─────────────────────────────┴──────────┴─────────────┴───────────────────────────────┘
$ manage-dt --debug delete custom-adapter
2025-09-18 20:33:33,603 - DEBUG    - cli.py           - Loading configuration
2025-09-18 20:33:33,605 - DEBUG    - mdt_oci.py       - OCI authentication: Config file
2025-09-18 20:33:33,605 - DEBUG    - config.py        - Config file found at ~/.oci/config
2025-09-18 20:33:33,673 - INFO     - mdt_iot_oci.py   - Delete Digital Twin Instance 'custom-adapter'
2025-09-18 20:33:34,514 - INFO     - mdt_iot_oci.py   - Digital Twin Instance deleted
2025-09-18 20:33:34,514 - INFO     - mdt_iot_oci.py   - Delete Digital Twin Adapter 'pvhd-m5-env-cstm-adapter'
2025-09-18 20:33:35,434 - INFO     - mdt_iot_oci.py   - Digital Twin Adapter deleted
2025-09-18 20:33:35,434 - INFO     - mdt_iot_oci.py   - Delete Digital Twin Model 'dtmi:com:oracle:pvhd:m5:env:cstm;1'
2025-09-18 20:33:36,204 - INFO     - mdt_iot_oci.py   - Digital Twin Model deleted
$ 
```

## Caveat

As we do not store OCIDs of the IoT objects created, identification is done based on
_Display Name_. However, as with most OCI resources, the _Display Name_ is not a unique
identifier! While it is not a recommended practice, it is possible to have two Digital
Twins with the same name. This sample application might not handle such cases properly.
