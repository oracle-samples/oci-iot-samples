#!/usr/bin/env python3
"""
Stream Digital Twin normalized data.

Copyright (c) 2025 Oracle and/or its affiliates.
Licensed under the Universal Permissive License v 1.0 as shown at
https://oss.oracle.com/licenses/upl

DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.

Simple client to stream normalized data received by the IoT Platform.
This example focus on the usage of the queues; for more information on
database connection, see the "Direct database connection" example.
"""
import logging
import re
from typing import Optional

import click
import config
import oracledb
import oracledb.plugins.oci_tokens

LOGGER_FMT = "{asctime} - {levelname:8} - {filename:16.16} - {message}"
logger = logging.getLogger(__name__)


def db_connect() -> oracledb.Connection:
    """Establish and returns a database connection using the configured settings.

    Returns:
        oracledb.Connection: The database connection object.

    Raises:
        ValueError: If the connection string is invalid.
    """
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
    if config.oci_auth_type == "ConfigFileAuthentication":
        token_based_auth["profile"] = config.oci_profile

    extra_connect_params = {}
    if config.thick_mode:
        logger.debug("Connecting using oracledb Thick mode")
        oracledb.init_oracle_client(lib_dir=config.lib_dir, config_dir=".")
        extra_connect_params["externalauth"] = True
    else:
        logger.debug("Connecting using oracledb Thin mode")

    connection = oracledb.connect(
        dsn=dsn, extra_auth_params=token_based_auth, **extra_connect_params
    )
    logger.info("Connected")
    return connection


def db_disconnect(connection: oracledb.Connection) -> None:
    """Close the provided database connection.

    Args:
        connection (oracledb.Connection): The database connection to close.
    """
    connection.close()


def build_subscriber_rule(
    connection: oracledb.Connection,
    digital_twin_instance_id: Optional[str],
    display_name: Optional[str],
    content_path: Optional[str],
) -> Optional[str]:
    """Build subscriber rule string.

    Args:
        connection (oracledb.Connection): The database connection to use.
        digital_twin_instance_id (Optional[str]): The digital twin instance OCID.
        display_name (Optional[str]): The digital twin instance display name.
        content_path (Optional[str]): The content path to filter messages on.

    Raises:
        ValueError: No digital twin instance with that display name.

    Returns:
        A rule string
    """
    rule = None
    with connection.cursor() as cursor:
        if display_name:
            cursor.execute(
                f"""
                    select dti.data.id
                    from {config.iot_domain_short_name}__iot.digital_twin_instances dti
                    where dti.data."displayName" = :display_name
                    and dti.data."lifecycleState" = 'ACTIVE'
                    order by dti.data."timeUpdated" desc
                """,
                {"display_name": display_name},
            )
            row = cursor.fetchone()
            if row and row[0]:
                digital_twin_instance_id = row[0]
            else:
                raise ValueError(f"No such display name: {display_name}")

        if digital_twin_instance_id:
            quoted_digital_twin_instance_id = cursor.callfunc(
                "dbms_assert.enquote_literal", str, [digital_twin_instance_id]
            )
            condition = f'tab.user_data."digitalTwinInstanceId" = {quoted_digital_twin_instance_id}'
            rule = f"{rule} and {condition}" if rule is not None else condition
        if content_path:
            quoted_content_path = cursor.callfunc(
                "dbms_assert.enquote_literal", str, [content_path]
            )
            condition = f'tab.user_data."contentPath" = {quoted_content_path}'
            rule = f"{rule} and {condition}" if rule is not None else condition
    logger.debug("Queue rule is: %s", rule)
    return rule


class CLIContext:
    """Context object for CLI, holding DB connection."""

    def __init__(self):
        """Initialize class."""
        self.connection = None
        self.queue_name = f"{config.iot_domain_short_name}__iot.normalized_data".upper()


@click.group()
@click.option("-v", "--verbose", is_flag=True, help="Verbose mode")
@click.option("-d", "--debug", is_flag=True, help="Debug mode")
@click.pass_context
def cli(ctx: click.Context, verbose: bool, debug: bool) -> None:
    """Stream Digital Twin normalized data.

    This example illustrate the use of "durable subscribers": once the
    subscriber has been created, messages are retained and returned when the
    client connects.
    """
    ctx.ensure_object(CLIContext)
    log_level = logging.WARNING
    if verbose:
        log_level = logging.INFO
    if debug:
        log_level = logging.DEBUG
        # Silence third party libraries
        logging.getLogger("oci._vendor.urllib3.connectionpool").setLevel(logging.INFO)
        logging.getLogger("oci.circuit_breaker").setLevel(logging.INFO)
        logging.getLogger("oci.config").setLevel(logging.INFO)
        logging.getLogger("oci.util").setLevel(logging.INFO)
    logging.basicConfig(level=log_level, format=LOGGER_FMT, style="{")


@cli.result_callback()
@click.pass_context
def after_command(ctx: click.Context, *args, **kwargs) -> None:
    """Ensure DB disconnect after command runs."""
    logger.debug("Cleanup")
    if hasattr(ctx.obj, "connection") and ctx.obj.connection:
        try:
            db_disconnect(ctx.obj.connection)
            logger.info("Disconnected")
        except Exception as e:
            logger.warning("Failed to disconnect: %s", e)


@cli.command()
@click.option(
    "--id",
    "digital_twin_instance_id",
    required=False,
    type=str,
    help="Digital Twin Instance ID (mutually exclusive with --display-name)",
)
@click.option(
    "--display-name",
    "display_name",
    required=False,
    type=str,
    help="Digital Twin Instance display name (mutually exclusive with --id)",
)
@click.option(
    "--content-path",
    required=False,
    type=str,
    help="Path to the content",
)
@click.pass_context
def subscribe(
    ctx: click.Context,
    digital_twin_instance_id: Optional[str],
    display_name: Optional[str],
    content_path: Optional[str],
) -> None:
    """Subscribe to the normalized queue."""
    if digital_twin_instance_id and display_name:
        raise click.UsageError(
            "--id and --display-name are mutually exclusive options."
        )

    try:
        ctx.obj.connection = db_connect()
    except Exception as e:
        logger.error("Database connection failed: %s", e)
        return

    try:
        rule = build_subscriber_rule(
            connection=ctx.obj.connection,
            digital_twin_instance_id=digital_twin_instance_id,
            display_name=display_name,
            content_path=content_path,
        )
    except Exception as e:
        logger.error("Exception occurred while building rule: %s", e)
        return

    try:
        agent_type = ctx.obj.connection.gettype("SYS.AQ$_AGENT")
        subscriber = agent_type.newobject()
        subscriber.NAME = config.subscriber_name
        subscriber.ADDRESS = None
        subscriber.PROTOCOL = 0
        with ctx.obj.connection.cursor() as cursor:
            cursor.callproc(
                "dbms_aqadm.add_subscriber",
                keyword_parameters={
                    "queue_name": ctx.obj.queue_name,
                    "subscriber": subscriber,
                    "rule": rule,
                    "transformation": None,
                    "queue_to_queue": False,
                    "delivery_mode": oracledb.MSG_PERSISTENT_OR_BUFFERED,
                },
            )
    except Exception as e:
        logger.error("Cannot register subscriber: %s", e)
        return
    logger.info("Subscriber %s registered", config.subscriber_name)


@cli.command()
@click.pass_context
def stream(ctx: click.Context) -> None:
    """Stream data."""
    try:
        ctx.obj.connection = db_connect()
    except Exception as e:
        logger.error("Database connection failed: %s", e)
        return

    try:
        queue = ctx.obj.connection.queue(name=ctx.obj.queue_name, payload_type="JSON")
        queue.deqOptions.mode = oracledb.DEQ_REMOVE
        queue.deqOptions.wait = 10
        queue.deqOptions.navigation = oracledb.DEQ_FIRST_MSG
        queue.deqOptions.consumername = config.subscriber_name

        logger.info("Listening for messages")
        while True:
            message: Optional[oracledb.aq.MessageProperties] = queue.deqone()
            if message:
                print(f"\nOCID         : {message.payload['digitalTwinInstanceId']}")
                print(f"Time observed: {message.payload['timeObserved']}")
                print(f"Content path : {message.payload['contentPath']}")
                print(f"Value        : {message.payload['value']}")
                ctx.obj.connection.commit()
            else:
                print(".", end="", flush=True)
    except KeyboardInterrupt:
        print("\nInterrupted")
    except Exception as e:
        print()
        logger.error("Error while dequeuing messages: %s", e)


@cli.command()
@click.pass_context
def unsubscribe(ctx: click.Context) -> None:
    """Unsubscribe to the normalized queue."""
    try:
        ctx.obj.connection = db_connect()
    except Exception as e:
        logger.error("Database connection failed: %s", e)
        return

    try:
        agent_type = ctx.obj.connection.gettype("SYS.AQ$_AGENT")
        subscriber = agent_type.newobject()
        subscriber.NAME = config.subscriber_name
        subscriber.ADDRESS = None
        subscriber.PROTOCOL = 0
        with ctx.obj.connection.cursor() as cursor:
            cursor.callproc(
                "dbms_aqadm.remove_subscriber",
                keyword_parameters={
                    "queue_name": ctx.obj.queue_name,
                    "subscriber": subscriber,
                },
            )
    except Exception as e:
        logger.error("Cannot unregister subscriber: %s", e)
        return
    logger.info("Subscriber %s unregistered", config.subscriber_name)


if __name__ == "__main__":
    cli()
