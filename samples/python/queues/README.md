# Streaming IoT Platform data

This example demonstrates how to use
[Transactional Event Queues](https://www.oracle.com/database/advanced-queuing/)
to stream IoT Platform data.

You should already be familiar with connecting to the IoT Platform database.
If not, review the [Direct database connection example](../query-db/README.md)
in this repository.

The provided scripts allow you to subscribe and stream from the raw and normalized
message queues.

## Concepts

Digital Twin Instances data is available through data tables, but it can also be
streamed using database Transactional Event Queues.

The following queues are available:

| Queue name       | Data type             | Description                      |
| ---------------- | --------------------- | -------------------------------- |
| raw_data_in      | raw_data_in_type      | Incoming raw messages            |
| raw_data_out     | raw_data_out_type     | Outgoing raw messages (commands) |
| normalized_data  | JSON                  | Normalized data                  |
| rejected_data_in | rejected_data_in_type | Rejected incoming messages       |

The `normalized_data` queues is a JSON queue, while the others use an Abstract Data Type
(ADT).
More information on the data model is available in the
[Transactional Event Queues](https://docs.oracle.com/en-us/iaas/Content/internet-of-things/iot-domain-database-schema.htm#queues)
section of the IoT Platform documentation.

Queue subscribers can be implemented in  a durable or non-durable way:

- Durable subscribers: messages are kept in the queue until a client connects and read
  available messages.
  Note that the retention for the IoT Platform queues is set to 24 hours.
- Non-durable subscribers: only receive messages issued while the client is
  connected.
  The Python SDK does not support non-durable subscribers as such, but this can be
  emulated by registering an ephemeral subscriber when a client connects.

## Sample scripts

Two sample scripts are provided:

- `sub-raw`: subscribe and stream all incoming raw data (ADT). It is implemented
  as a non-durable subscriber.
- `sub-norm`: subscribe and stream the normalized data (JSON), using a durable subscriber.

Both scripts demonstrate how to use rules to filter data based on the Digital Twin
Instance Id and/or the endpoint (raw data) or content path (normalized data).

More information on using queues with the Python SDK is available on
[Using Oracle Transactional Event Queues and Advanced Queuing](https://python-oracledb.readthedocs.io/en/stable/user_guide/aq.html).

## Prerequisites

Install the Python dependencies.  
(Using a [Python virtual environment](https://docs.python.org/3/library/venv.html) is recommended):

```sh
pip install -r requirements.txt
```

When using `oracledb` in _Thick_ mode, the
[Oracle Instant Client](https://www.oracle.com/europe/database/technologies/instant-client.html)
must be installed (the 23ai Release Update or newer is recommended).
The `sqlnet.ora` parameter `SSL_SERVER_DN_MATCH` must also be set to `true`.

## Configure and run the scripts

Copy `config.distr.py` to `config.py` and set the following variables:

- `db_connect_string`: The `dbConnectionString` property of your IoT Domain Group.
- `db_token_scope`: The `dbTokenScope` property of your IoT Domain Group.
- `iot_domain_short_name`: The hostname part of the `deviceHost` property of your IoT Domain.
- `oci_auth_type`: The OCI authentication type. Use "ConfigFileAuthentication"
  for API key authentication, or "InstancePrincipal".
- `oci_profile`: OCI CLI profile to use for token retrieval (API key authentication only).
- `thick_mode`: Set to `True` to use the `oracledb` thick mode driver.
- `subscriber_name`: Name of the durable subscriber for the `sub-norm` sample.

### `sub-raw`

Run the script. Without parameter, it will show all messages.
You can filter by Digital Twin Instance OCID, display name, or endpoint (MQTT topic).

```text
$ ./sub-raw.py --help
usage: sub-raw.py [-h] [-v] [-d] [--id ID | --display-name DISPLAY_NAME] [--endpoint ENDPOINT]

Subscribe to the raw messages stream from IoT Platform.

options:
  -h, --help            show this help message and exit
  -v, --verbose         Enable verbose (INFO level) logging.
  -d, --debug           Enable debug (DEBUG level) logging.
  --id ID               The Digital Twin Instance OCID (mutually exclusive with --display-name).
  --display-name DISPLAY_NAME
                        The Digital Twin Instance display name (mutually exclusive with --id).
  --endpoint ENDPOINT   The message endpoint (topic).
./sub-raw.py -v
2025-11-10 14:24:03,316 - INFO     - sub-raw.py       - Connected
2025-11-10 14:24:06,785 - INFO     - sub-raw.py       - Subscriber aq_sub_183a199f_8820_449e_a912_99339877c23a registered
2025-11-10 14:24:06,807 - INFO     - sub-raw.py       - Listening for messages
....
OCID         : ocid1.iotdigitaltwininstance.oc1.<redacted>
Time received: 2025-11-10 13:24:52.109055
Endpoint     : zigbee2mqtt/sonoff-temp-04
Content      : {"temperature":19.8,"humidity":64.9,"battery":71,"linkquality":51}
.....
OCID         : ocid1.iotdigitaltwininstance.oc1.<redacted>
Time received: 2025-11-10 13:25:48.182738
Endpoint     : ttn/devices/bulles-minilora-01/up
Content      : {"temperature":16.1,"humidity":11,"battery":96,"rssi":-76,"snr":12}

OCID         : ocid1.iotdigitaltwininstance.oc1.<redacted>
Time received: 2025-11-10 13:25:50.742284
Endpoint     : zigbee2mqtt/sonoff-temp-06
Content      : {"temperature":21.2,"humidity":51.7,"battery":80,"linkquality":58}
^C
Interrupted
2025-11-10 14:25:51,831 - INFO     - sub-raw.py       - Subscriber aq_sub_183a199f_8820_449e_a912_99339877c23a unregistered
2025-11-10 14:25:51,855 - INFO     - sub-raw.py       - Disconnected
```

### `sub-norm`

The `sub-norm` script is similar and provides additional commands to manage
the durable subscription:

```text
$ ./sub-norm.py --help
Usage: sub-norm.py [OPTIONS] COMMAND [ARGS]...

  Stream Digital Twin normalized data.

  This example illustrate the use of "durable subscribers": once the
  subscriber has been created, messages are retained and returned when the
  client connects.

Options:
  -v, --verbose  Verbose mode
  -d, --debug    Debug mode
  --help         Show this message and exit.

Commands:
  stream       Stream data.
  subscribe    Subscribe to the normalized queue.
  unsubscribe  Unsubscribe to the normalized queue.
$ ./sub-norm.py subscribe --help
Usage: sub-norm.py subscribe [OPTIONS]

  Subscribe to the normalized queue.

Options:
  --id TEXT            Digital Twin Instance ID (mutually exclusive with
                       --display-name)
  --display-name TEXT  Digital Twin Instance display name (mutually exclusive
                       with --id)
  --content-path TEXT  Path to the content
  --help               Show this message and exit.
$ ./sub-norm.py -v subscribe --content-path temperature
2025-11-10 14:30:19,053 - INFO     - sub-norm.py      - Connected
2025-11-10 14:30:22,026 - INFO     - sub-norm.py      - Subscriber sub_norm_subscriber registered
2025-11-10 14:30:22,048 - INFO     - sub-norm.py      - Disconnected
$ ./sub-norm.py -v stream                              
2025-11-10 14:30:32,240 - INFO     - sub-norm.py      - Connected
2025-11-10 14:30:32,242 - INFO     - sub-norm.py      - Listening for messages
.
OCID         : ocid1.iotdigitaltwininstance.oc1.<redacted>
Time observed: 2025-11-10T13:30:51.351412Z
Content path : temperature
Value        : 15.9
..
OCID         : ocid1.iotdigitaltwininstance.oc1.<redacted>
Time observed: 2025-11-10T13:31:14.526270Z
Content path : temperature
Value        : 21.0
^C
Interrupted
2025-11-10 14:31:17,731 - INFO     - sub-norm.py      - Disconnected
$ ./sub-norm.py -v unsubscribe                         
2025-11-10 14:31:26,963 - INFO     - sub-norm.py      - Connected
2025-11-10 14:31:27,275 - INFO     - sub-norm.py      - Subscriber sub_norm_subscriber unregistered
2025-11-10 14:31:27,296 - INFO     - sub-norm.py      - Disconnected
```
