# Direct database connection

The OCI Internet of Things Platform allows you to connect directly to the
database storing your Digital Twin definitions and telemetry.

This guide shows how to connect to your IoT database using
[Oracle SQLcl](https://www.oracle.com/database/sqldeveloper/technologies/sqlcl/).

## Prerequisites

<!-- markdownlint-disable MD013 -->
- Your client IP address must be included in the Allow List defined at the IoT
  Domain Group level – [Documentation](.).
- Database authentication is handled by
  [OCI Identity Database Tokens](https://docs.oracle.com/en/cloud/paas/autonomous-database/serverless/adbsb/iam-access-database.html#GUID-CFC74EAF-E887-4B1F-9E9A-C956BCA0BEA9).  
  To retrieve a valid token, the requester must be part of one of the identity
  groups listed at the IoT Domain level – [Documentation](.).
  The OCI IoT Platform supports _Instance Principal_ authentication; that is,
  the identity group can be a _Dynamic Group_.
<!-- markdownlint-enable MD013 -->

## Connecting to the database

For the `oci` command:

- API key authentication: add the `--profile` option to use a non-default profile.
- Instance principal authentication: use the `--auth instance_principal` option.

Obtain the database token scope and retrieve a token:

```shell
# Retrieve scope
iot_domain_group_id="<IoT Domain Group OCID>"
iot_db_token_scope=$(
  oci iot domain-group get --iot-domain-group-id "${iot_domain_group_id}" \
   --query data.dbTokenScope --raw-output
)
# Get token (valid for 60 minutes)
oci iam db-token get --scope "${iot_db_token_scope}"
```

Obtain the JDBC connect string and connect to the database:

```shell
iot_db_connect_string=$(
  oci iot domain-group get --iot-domain-group-id "${iot_domain_group_id}" \
  --query data.dbConnectionString --raw-output
)
sql "/@jdbc:oracle:thin:@${iot_db_connect_string}&TOKEN_AUTH=OCI_TOKEN"
```

When connected, you will have access to two schemas:

- `<DomainShortId>__IOT`: Read-only access to your Digital Twin definitions and telemetry.
- `<DomainShortId>__WKSP`: Full access to the APEX workspace schema.

The `DomainShortId` is the hostname part of the IoT Domain Device Host and
can be retrieved with:

```shell
iot_domain_id="<IoT Domain OCID>"
  oci iot domain get --iot-domain-id "${iot_domain_group_id}" |
  jq -r '.data.deviceHost | split(".")[0]'
```

## Sample SQL sessions

Select raw messages received in the last 5 minutes. Join with Digital Twin
to display device names. The query assumes that messages aren't binary.

```sql
alter session set current_schema = <DomainShortId>__iot;
select
    dt.data.displayName,
    rd.time_received,
    rd.endpoint,
    utl_raw.cast_to_varchar2(dbms_lob.substr(rd.content, 40)) as content
from raw_data rd, digital_twins dt
where rd.digital_twin_instance_id = dt.data."_id"
  and rd.time_received > sysdate - 1/24/12
order by rd.time_received;
```

Select historized messages observed in the last 5 minutes. The `value` column
is of JSON type.

```sql
select
    dt.data.displayName,
    hd.time_observed,
    hd.content_path,
    json_serialize (hd.value returning varchar2(40) truncate error on error) as value
from digital_twin_historized_data hd, digital_twins dt
where hd.digital_twin_id = dt.data."_id"
  and hd.time_observed > sysdate - 1/24/12
order by hd.time_observed;
```

Select rejected messages received in the last 5 minutes. The query assumes that
messages aren't binary.

```sql
select
    dt.data.displayName,
    rd.time_received,
    rd.endpoint,
    rd.reason_code,
    rd.reason_message,
    utl_raw.cast_to_varchar2(dbms_lob.substr(rd.content, 40)) as content
from rejected_data rd, digital_twins dt
where rd.digital_twin_instance_id = dt.data."_id"
  and rd.time_received > sysdate - 1/24/12
order by rd.time_received;
```
