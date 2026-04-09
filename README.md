# Oracle Internet of Things Platform Samples

This repository provides examples demonstrating how to use the
[Oracle Internet of Things Platform](https://docs.oracle.com/en-us/iaas/Content/internet-of-things/).

## Setup

The examples and tutorials in this repository assume you have already provisioned an IoT
Domain Group and an IoT Domain. The [IoT from scratch](./samples/script/iot-from-scratch/README.md)
example can be used to setup a complete environment from the command line.

## Sending Messages to the OCI IoT Platform Using a GUI

The samples below show you how to send messages from the command line or using programming
languages.  
If you want to send test messages using a GUI, you can use any MQTT-compliant client,
such as the following (Oracle has no preference or affiliation with any of these products):

- [MQTT Explorer](https://mqtt-explorer.com/)
- [MQTTX](https://mqttx.app/)
- ...

**Note:** The OCI IoT Platform is _not_ an MQTT broker; you will not be able to listen
for messages from your devices.

Similarly, to test the REST APIs (for example, sending telemetry or querying telemetry
via ORDS endpoints), you can use:

- [Insomnia](https://insomnia.rest/)
- [Postman](https://www.postman.com/)
- ...

## Viewing Telemetry

There are several options to view telemetry:

- The APEX IoT Platform Explorer (see below): this is the easiest way to get an
  overview of your telemetry data.
- The APEX SQL Workshop to browse the database.
- Connect directly to the database with
  [SQLcl](https://www.oracle.com/database/sqldeveloper/technologies/sqlcl/) or
  [SQL Developer](https://www.oracle.com/database/sqldeveloper/) (see below).
- Query the database using the ORDS endpoints (see below).

## IoT Platform Explorer

Sample [APEX application](./apex/dashboard) that allows you to browse your IoT devices
as well as the messages received.

## How To

| Description                                          | Command Line          | Python       | C            | Java         |
|------------------------------------------------------|:---------------------:|:------------:|:------------:|:------------:|
| IoT from scratch (Setup IoT environment from command line) | [Sample](./samples/script/iot-from-scratch/) |              |              |              |
| IoT from scratch (Setup IoT environment with Terraform   ) | [Terraform Sample](./samples/terraform/iot-from-scratch/) |              |              |              |
| Manage Digital Twins (Create, query, delete). The Python sample demonstrates the use of the OCI Python SDK and the IoT Platform Data API           | [Sample](./samples/script/manage-dt/) | [Sample](./samples/python/manage-dt/) |              |              |
| Publish telemetry (HTTPS - REST API)                 | [Sample](./samples/script/publish-https/) | [Sample](./samples/python/publish-https/)  |              |              |
| Publish telemetry (MQTTS - Secure MQTT)              |                       | [Sample](./samples/python/publish-mqtt/)  | [Sample](./samples/C/M5Stack/) |              |
| Publish telemetry (WSS - Secure MQTT over WebSocket) |                       | [Sample](./samples/python/publish-websockets/)  |              |              |
| Node-RED gateway                                     | [Sample](./samples/node/node-red-gateway/) |              |              |              |
| Sending observed time in device payload              | [Sample](./samples/script/time-observed/) |              | [Sample](./samples/C/M5Stack/) |              |
| Raw command-response scenario                        |                       | [Sample](./samples/python/command-response/)  | [Sample](./samples/C/M5Stack/) |              |
| Direct database connection — query telemetry         | [Sample](./samples/script/query-db/) | [Sample](./samples/python/query-db/)  |              | [Sample](./samples/java/src/main/java/com/oracle/iot/samples/SampleDataAccess.java) |
| Archive IoT Domain data to Object Storage            | [Sample](./samples/sql/archive-domain/) | [Sample](./samples/python/archive-domain/) |              |              |
| Streaming IoT Platform data (Database queues)        |                       | [Sample](./samples/python/queues/)  |              | [Sample](./samples/java/src/main/java/com/oracle/iot/samples/SampleDataStreaming.java) |

## End-to-End Samples

- The [`M5Stack CoreS3`](./samples/C/M5Stack/) C sample shows how to connect a
  microcontroller device to the OCI IoT Platform over secure MQTT,
  publish environmental telemetry, handle command-response messages,
  and perform OTA firmware updates triggered through the IoT Platform.
- The [`Node-RED gateway`](./samples/node/node-red-gateway/) sample shows how
  to run a local Node-RED gateway and Mosquitto broker, link a `GATEWAY`
  digital twin to `INDIRECT` devices, forward telemetry and commands between
  local MQTT devices and OCI IoT, and publish gateway metrics.
- The [`File Upload Agent`](./samples/python/file-agent/) Python sample shows how
  a device can request an upload over MQTT, have a backend agent consume IoT
  Platform database queue messages, create short-lived Object Storage upload
  URLs, send responses through raw commands, and run optional post-processing.

The SQL archive sample exposes `archive_domain_pkg.plan` and `archive_domain_pkg.run`, stores runtime settings in `archive_domain_config`, and uses `DBMS_CLOUD` APIs from the workspace schema.

## Documentation

You can find the online documentation for the Oracle Internet of Things Platform at
[docs.cloud.oracle.com](https://docs.oracle.com/en-us/iaas/Content/internet-of-things/).

## Contributing

See [CONTRIBUTING](./CONTRIBUTING.md).

## Security

Please consult the [security guide](./SECURITY.md) for our responsible security
vulnerability disclosure process.

## License

See [LICENSE](./LICENSE.txt).

## Disclaimer

Oracle and its affiliates do not provide any warranty whatsoever, express or implied, for
any software, material or content of any kind contained or produced within this
repository, and in particular specifically disclaim any and all implied warranties of
title, non-infringement, merchantability, and fitness for a particular purpose.
Furthermore, Oracle and its affiliates do not represent that any customary security
review has been performed with respect to any software, material or content contained or
produced within this repository. In addition, and without limiting the foregoing,
third parties may have posted software, material or content to this repository
without any review. Use at your own risk.
