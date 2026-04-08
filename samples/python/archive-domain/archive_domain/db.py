"""Direct database helpers for archive-domain."""

from __future__ import annotations

import re
from typing import Any


def choose_execution_mode(
    requested_mode: str,
    dbms_cloud_available: bool,
    has_db_export_credentials: bool,
) -> str:
    """Choose between bulk export and SQL fallback."""
    if requested_mode == "sql":
        return "sql"
    if dbms_cloud_available and has_db_export_credentials:
        return "bulk"
    return "sql"


def build_dsn(connect_string: str) -> str:
    """Convert the IoT DB connect string into an Oracle DSN."""
    match = re.match(r"tcps:(.*):(\d+)/([^?]*)(\?.*)?", connect_string)
    if not match:
        raise ValueError("Invalid connect string")

    hostname, port, service, _ = match.groups()
    return f"""
        (DESCRIPTION =
            (ADDRESS=(PROTOCOL=TCPS)(PORT={port})(HOST={hostname}))
            (CONNECT_DATA=(SERVICE_NAME={service}))
        )"""


def connect(database_config: Any):
    """Create a direct database connection using OCI token auth."""
    try:
        import oracledb
        import oracledb.plugins.oci_tokens  # noqa: F401
    except ModuleNotFoundError as exc:
        raise RuntimeError(
            "python-oracledb with OCI token support is required for direct DB access"
        ) from exc

    extra_auth_params = {
        "auth_type": database_config.auth_type,
        "scope": database_config.token_scope,
    }
    if database_config.auth_type in {"ConfigFileAuthentication", "SecurityToken"}:
        extra_auth_params["profile"] = database_config.profile

    connect_kwargs: dict[str, Any] = {}
    if database_config.thick_mode:
        oracledb.init_oracle_client(lib_dir=database_config.lib_dir, config_dir=".")
        connect_kwargs["externalauth"] = True

    return oracledb.connect(
        dsn=build_dsn(database_config.connect_string),
        extra_auth_params=extra_auth_params,
        **connect_kwargs,
    )


def set_current_schema(connection: Any, iot_domain_short_name: str) -> None:
    """Switch the session to the IoT schema for the selected domain."""
    with connection.cursor() as cursor:
        cursor.execute(
            f"alter session set current_schema = {iot_domain_short_name}__iot"
        )


def execute_statement(cursor: Any, statement: str, binds: dict[str, Any]) -> None:
    """Execute one statement with bind values."""
    cursor.execute(statement, binds)
