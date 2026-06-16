# OCI Internet of Things Platform Java Samples

This project contains Java samples that demonstrate how to access data consumed by
an OCI IoT Domain.

The samples show two access patterns:

- `SampleDataAccess` connects directly to the IoT Domain database and prints the
  number of records in the raw data table.
- `SampleDataStreaming` subscribes to the raw and normalized data queues and
  prints messages as they arrive.

For more information about configuring access to IoT data, see the Oracle docs:
<https://docs.oracle.com/en-us/iaas/Content/internet-of-things/connecting-to-data.htm>.

## Prerequisites

- JDK 25 or later.
- Apache Maven.

The samples use instance principal authentication by default. With this
authentication flow, run the sample in OCI and configure the required dynamic
group, policies, IoT Domain Group, and IoT Domain.

To use another authentication flow, replace the
`InstancePrincipalsAuthenticationDetailsProvider` in the sample class with the
appropriate OCI SDK authentication details provider.

## Run the Direct Data Access Sample

`SampleDataAccess` expects one argument: the IoT Domain OCID.

```sh
mvn -q compile exec:java \
  -Dexec.mainClass=com.oracle.iot.samples.SampleDataAccess \
  -Dexec.args="<iot-domain-ocid>"
```

The sample connects to the IoT Domain database and prints the number of records
in the `RAW_DATA` table.

## Run the Data Streaming Sample

`SampleDataStreaming` expects the IoT Domain OCID and accepts an optional Digital
Twin Instance OCID.

Stream all raw and normalized data:

```sh
mvn -q compile exec:java \
  -Dexec.mainClass=com.oracle.iot.samples.SampleDataStreaming \
  -Dexec.args="<iot-domain-ocid>"
```

Stream data for one Digital Twin Instance:

```sh
mvn -q compile exec:java \
  -Dexec.mainClass=com.oracle.iot.samples.SampleDataStreaming \
  -Dexec.args="<iot-domain-ocid> <digital-twin-instance-ocid>"
```

The streaming sample registers subscribers for the `RAW_DATA_IN` and
`NORMALIZED_DATA` queues, prints delivered messages, and waits until you press
Enter. Subscribers created by the current run are unregistered before exit.
