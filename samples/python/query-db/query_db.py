#!/usr/bin/env python3
"""
Direct database connection to the OCI IoT Platform.

Copyright (c) 2025 Oracle and/or its affiliates.
Licensed under the Universal Permissive License v 1.0 as shown at
https://oss.oracle.com/licenses/upl

DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.

This script demonstrates a direct database connection to the OCI IoT Platform
and queries the telemetry tables.

Relevant oracledb documentation:
https://python-oracledb.readthedocs.io/en/latest/user_guide/connection_handling.html#oci-cloud-native-authentication-with-the-oci-tokens-plugin
"""
import decimal
import json
import re
from typing import Tuple

import config
import oracledb
import oracledb.plugins.oci_tokens


class DecimalEncoder(json.JSONEncoder):
    """
    Encode Decimal objects as floats or ints for JSON serialization.

    The default Python JSON encoder does not support Decimal.
    For simplicity, this encoder represents Decimals as floats (or ints, when integral).
    Note: Converting to float may lose precision for large/small decimals.
    """

    def default(self, o):
        """Convert Decimal to int if whole number; otherwise, to float."""
        if isinstance(o, decimal.Decimal):
            return int(o) if o == o.to_integral_value() else float(o)
        return super().default(o)


def get_blob(blob: oracledb.LOB) -> Tuple[str, str]:
    """
    Provide a string representation of an Oracle LOB.

    Args:
        blob: The LOB field.

    Returns:
        tuple (type, string representation of the blob)
    """
    content = blob.read()
    if isinstance(content, bytes):
        try:
            content_str = content.decode()
        except Exception:
            # Cannot decode content; return as a hex-encoded binary string
            return "Binary", content.hex()
    else:
        content_str = str(content)

    try:
        content_json = json.loads(content_str)
    except Exception:
        # Content is not JSON; treat as text
        return "Text", content_str
    else:
        # Content is valid JSON; return pretty-formatted JSON string
        return "JSON", json.dumps(content_json, indent=2, cls=DecimalEncoder)


# Extract hostname, port, and service from the connect string
m = re.match(r"tcps:(.*):(\d+)/([^?]*)(\?.*)?", config.db_connect_string)
if not m:
    raise ValueError("Invalid connect string")
hostname, port, service, _ = m.groups()

# Construct DSN for connection
dsn = f"""
    (DESCRIPTION =
        (ADDRESS=(PROTOCOL=TCPS)(PORT={port})(HOST={hostname}))
        (CONNECT_DATA=(SERVICE_NAME={service}))
    )"""

# Parameters for OCI token-based authentication
token_based_auth = {
    "auth_type": config.oci_auth_type,
    "scope": config.db_token_scope,
}
if config.oci_auth_type in ["ConfigFileAuthentication", "SecurityToken"]:
    token_based_auth["profile"] = config.oci_profile

extra_connect_params = {}
if config.thick_mode:
    print("Using oracledb Thick mode")
    oracledb.init_oracle_client(lib_dir=config.lib_dir, config_dir=".")
    extra_connect_params["externalauth"] = True
else:
    print("Using oracledb Thin mode")

try:
    with oracledb.connect(
        dsn=dsn, extra_auth_params=token_based_auth, **extra_connect_params
    ) as connection:
        with connection.cursor() as cursor:
            # Set default schema to the IoT schema for simplified queries
            sql = f"alter session set current_schema = {config.iot_domain_short_name}__iot"
            cursor.execute(sql)

            # Fetch latest raw messages. Join with Digital Twin to display device name.
            # Note: the "content" field is a BLOB.
            print("\n--- Latest raw messages ---")
            sql = f"""
                select dt.data.displayName, rd.time_received, rd.endpoint, rd.content
                from raw_data rd, digital_twin_instances dt
                where rd.digital_twin_instance_id = dt.data."_id"
                order by rd.id desc
                fetch first {config.row_count} rows only
            """
            for r in cursor.execute(sql):
                display_name, time_received, endpoint, content = r
                content_type, content = get_blob(content)
                print(f"{time_received} - {display_name} - {endpoint}:")
                print(f"\t{content_type}: {content}")

            # Fetch latest historized messages. The "value" field is JSON.
            print("\n--- Latest historized messages ---")
            sql = f"""
                select dt.data.displayName, hd.time_observed, hd.content_path, hd.value
                from historized_data hd, digital_twin_instances dt
                where hd.digital_twin_instance_id = dt.data."_id"
                order by hd.id desc
                fetch first {config.row_count} rows only
            """
            for r in cursor.execute(sql):
                display_name, time_observed, content_path, value = r
                print(f"{time_observed} - {display_name}:")
                print(
                    f"\t{content_path} = {json.dumps(value, indent=2, cls=DecimalEncoder)}"
                )

            # Fetch latest rejected data. The "content" field is a BLOB.
            print("\n--- Latest rejected messages ---")
            sql = f"""
                select dt.data.displayName, rd.time_received, rd.endpoint, rd.content,
                    rd.reason_code, rd.reason_message
                from rejected_data rd, digital_twin_instances dt
                where rd.digital_twin_instance_id = dt.data."_id"
                order by rd.id desc
                fetch first {config.row_count} rows only
            """
            for r in cursor.execute(sql):
                display_name, time_received, endpoint, content, r_code, r_message = r
                content_type, content = get_blob(content)
                print(f"{time_received} - {display_name} - {endpoint}:")
                print(f"\t{content_type}: {content}")
                print(f"\tError: {r_code}: {r_message}")

except oracledb.Error as e:
    (error_obj,) = e.args
    print(f"Oracle error: {error_obj.message}")
