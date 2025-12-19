# Direct database connection

The OCI Internet of Things Platform allows you to connect directly to the
database storing your Digital Twin definitions and telemetry.

The
[Scenario: Connecting Directly to the IoT Database](https://docs.oracle.com/en-us/iaas/Content/internet-of-things/connect-database.htm)
section of the documentation shows how to establish a database connection with
[SQLcl](https://www.oracle.com/database/sqldeveloper/technologies/sqlcl/).
This guide focuses on how to connect to your IoT database using a Python script.

## Concepts

Each IoT Domain Group uses an Oracle Autonomous Database, which is shared by
all IoT Domains in that group.

To access the database, you must ensure that your client VCN is
included in the Allow List defined at the IoT Domain Group level –
[Documentation](https://docs.oracle.com/en-us/iaas/Content/internet-of-things/connect-database.htm#top__create-vcn).

When connected, to access the database schemas related to a particular IoT
Domain, the OCI user initiating the connection must be part of one of the
Identity Domain (Dynamic) Groups listed at the IoT Domain level –
[Documentation](https://docs.oracle.com/en-us/iaas/Content/internet-of-things/connect-database.htm#top__identity-domain).

Database authentication is handled using
[OCI Identity Database Tokens](https://docs.oracle.com/en/cloud/paas/autonomous-database/serverless/adbsb/iam-access-database.html#GUID-CFC74EAF-E887-4B1F-9E9A-C956BCA0BEA9).
The user account running the script must be properly configured to retrieve
`db-tokens`; for example, the following command should succeed:

```shell
oci iam db-token get --scope "urn:oracle:db::id::*"
```

The `oracledb` Python module handles token retrieval seamlessly when
specifying `extra_auth_params=token_based_auth` at connection time.

When connected, you will have access to two schemas:

- `<DomainShortId>__IOT`: read-only access to your Digital Twin definitions and telemetry.
- `<DomainShortId>__WKSP`: full access to the APEX workspace schema.

The `DomainShortId` is the hostname part of the IoT Domain Device Host.

## Prerequisites

Install the Python dependencies  
(using a [Python virtual environment](https://docs.python.org/3/library/venv.html)
is recommended):

```shell
pip install -r requirements.txt
```

When using `oracledb` in _Thick_ mode, the
[Oracle Instant Client](https://www.oracle.com/europe/database/technologies/instant-client.html)
must be installed (the latest 23ai Release Update is recommended).
Also, the `sqlnet.ora` parameter `SSL_SERVER_DN_MATCH` must be set to `true`.

## Configure and run the script

Copy `config.distr.py` to `config.py` and set the following variables:

- `db_connect_string`: The dbConnectionString property of your IoT Domain Group.
- `db_token_scope`: The dbTokenScope property of your IoT Domain Group.
- `iot_domain_short_name`: The hostname part of the deviceHost property of your IoT Domain.
- `oci_auth_type`: The OCI Authentication type. Must be either "ConfigFileAuthentication"
   for API Key authentication,  "InstancePrincipal" or "SecurityToken".
- `oci_profile`: OCI CLI profile to use for token retrieval when using API Key authentication.
- `row_count`: The number of rows retrieved by the sample queries.
- `thick_mode`: Set to `True` to use the `oracledb` Thick mode driver.

Run the script:

```shell
./query_db.py
```
