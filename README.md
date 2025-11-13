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

| Description                                          | Command Line          | Python       |
|------------------------------------------------------|:---------------------:|:------------:|
| IoT from scratch (Setup IoT environment from command line) | [Sample](./samples/script/iot-from-scratch/) |              |
| IoT from scratch (Setup IoT environment with Terraform   ) | [Terraform Sample](./samples/terraform/iot-from-scratch/) |              |
| Manage Digital Twins (Create, query, delete). The Python sample demonstrates the use of the OCI Python SDK and the IoT Platform Data API           | [Sample](./samples/script/manage-dt/) | [Sample](./samples/python/manage-dt/) |
| Publish telemetry (HTTPS - REST API)                 | [Sample](./samples/script/publish-https/) | [Sample](./samples/python/publish-https/)  |
| Publish telemetry (MQTTS - Secure MQTT)              |                       | [Sample](./samples/python/publish-mqtt/)  |
| Publish telemetry (WSS - Secure MQTT over WebSocket) |                       | [Sample](./samples/python/publish-websockets/)  |
| Raw command-response scenario                        |                       | [Sample](./samples/python/command-response/)  |
| Direct database connection — query telemetry         | [Sample](./samples/script/query-db/) | [Sample](./samples/python/query-db/)  |
| Streaming IoT Platform data (Database queues)        |                       | [Sample](./samples/python/queues/)  |

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
