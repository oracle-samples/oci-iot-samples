# OCI IoT Platform Device Workflow Demo Scripts

Sample scripts to create, query, and delete devices from the command line. These are not
bulletproof scripts; rather, they serve as a cookbook to get you started.

## Prerequisites

These scripts assume that you have the
[OCI CLI](https://docs.oracle.com/en-us/iaas/Content/API/Concepts/cliconcepts.htm)
installed and configured for your OCI tenancy, with the required policies set up to
manage Digital Twins, and the following resources already created:

- an OCI IoT Domain
- OCI Vault secrets and/or OCI Certificates for your device credentials
- Optional: a Confidential Application to issue tokens for querying telemetry via ORDS

## Usage

Copy `environ.distr.sh` to `environ.sh` and customize it as needed. Simply follow the
instructions in the file.

## Shell Scripts

There are three sets of scripts:

- `*_dt_unstructured.sh`: Digital twin with telemetry in unstructured format
- `*_dtd_m5_env.sh`: Digital twin with telemetry in structured format using the default
  adapter format
- `*_dtc_m5_env.sh`: Digital twin with telemetry in structured format using a custom
  adapter format

For each of these sets, there are three scripts:

- `create_*`: Creates the Model, Adapter and Digital Twin
- `query_*`: Queries created objects, including the data received in the last 5 minutes
  if the Confidential Application has been set up
- `delete_*`: Deletes the Digital Twin, Adapter and Model

Additionally, the `get_oauth_token.sh` script retrieves an authentication token for data
API calls. The token is stored in `token.sh` and expires after 30 minutes.
This script is invoked by the query scripts.

**Note:** The structured telemetry defined in these scripts is based on the payload sent
by an [M5Stack CoreS3](https://docs.m5stack.com/en/core/CoreS3) device with an
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

There are no scripts to actually send telemetry; this is illustrated in other samples in
this repository.

## Requirements

These scripts have been tested on Oracle Linux and macOS. For macOS, the GNU `date` and
`stat` (`gdate` and `gstat`) require the `coreutils` package, which can be installed using
Homebrew:

```bash
brew install coreutils
```
