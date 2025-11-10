#!/usr/bin/env python3
"""
Subscribe to the raw_data_in queue and print received messages.

Copyright (c) 2025 Oracle and/or its affiliates.
Licensed under the Universal Permissive License v 1.0 as shown at
https://oss.oracle.com/licenses/upl

DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.

Simple client to stream raw messages received by the IoT Platform.
This example focus on the usage of the queues; for more information on
database connection, see the "Direct database connection" example.
"""
import argparse
import logging
import re
from typing import Optional
import uuid

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
    endpoint: Optional[str],
) -> Optional[str]:
    """Build subscriber rule string.

    Args:
        connection (oracledb.Connection): The database connection to use.
        digital_twin_instance_id (Optional[str]): The digital twin instance OCID.
        display_name (Optional[str]): The digital twin instance display name.
        endpoint (Optional[str]): The endpoint (topic) to filter messages on.

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
            condition = f"tab.user_data.digital_twin_instance_id = {quoted_digital_twin_instance_id}"
            rule = f"{rule} and {condition}" if rule is not None else condition
        if endpoint:
            quoted_endpoint = cursor.callfunc(
                "dbms_assert.enquote_literal", str, [endpoint]
            )
            condition = f"tab.user_data.endpoint = {quoted_endpoint}"
            rule = f"{rule} and {condition}" if rule is not None else condition
    logger.debug("Queue rule is: %s", rule)
    return rule


def subscribe(
    connection: oracledb.Connection,
    queue_name: str,
    digital_twin_instance_id: Optional[str],
    display_name: Optional[str],
    endpoint: Optional[str],
) -> Optional[oracledb.DbObject]:
    """Subscribe to the queue.

    Args:
        connection (oracledb.Connection): The database connection.
        queue_name (str): the name a the queue to subscribe to.
        digital_twin_instance_id (Optional[str]): The digital twin instance OCID.
        display_name (Optional[str]): The digital twin instance display name.
        endpoint (Optional[str]): The endpoint (topic) to filter messages on.

    Returns:
        A subscriber agent database object.
    """
    try:
        rule = build_subscriber_rule(
            connection=connection,
            digital_twin_instance_id=digital_twin_instance_id,
            display_name=display_name,
            endpoint=endpoint,
        )
    except Exception as e:
        logger.error("Exception occurred while building rule: %s", e)
        return None

    try:
        agent_type = connection.gettype("SYS.AQ$_AGENT")
        subscriber = agent_type.newobject()
        subscriber.NAME = f"aq_sub_{str(uuid.uuid4()).replace('-', '_')}"
        subscriber.ADDRESS = None
        subscriber.PROTOCOL = 0
        with connection.cursor() as cursor:
            cursor.callproc(
                "dbms_aqadm.add_subscriber",
                keyword_parameters={
                    "queue_name": queue_name,
                    "subscriber": subscriber,
                    "rule": rule,
                    "transformation": None,
                    "queue_to_queue": False,
                    "delivery_mode": oracledb.MSG_PERSISTENT_OR_BUFFERED,
                },
            )
    except Exception as e:
        logger.error("Cannot register subscriber: %s", e)
        return None
    logger.info("Subscriber %s registered", subscriber.NAME)
    return subscriber


def stream(
    connection: oracledb.Connection, queue_name: str, subscriber: oracledb.DbObject
) -> None:
    """Stream data.

    Args:
        connection (oracledb.Connection): The database connection.
        queue_name (str): the name a the queue to stream from.
        subscriber (oracledb.DbObject): A subscriber agent database object.
    """
    try:
        raw_data_in_type = connection.gettype(queue_name + "_TYPE")
        queue = connection.queue(name=queue_name, payload_type=raw_data_in_type)
        queue.deqOptions.mode = oracledb.DEQ_REMOVE
        queue.deqOptions.wait = 10
        queue.deqOptions.navigation = oracledb.DEQ_NEXT_MSG
        queue.deqOptions.consumername = subscriber.NAME

        logger.info("Listening for messages")
        while True:
            message: Optional[oracledb.aq.MessageProperties] = queue.deqone()
            if message:
                print(f"\nOCID         : {message.payload.DIGITAL_TWIN_INSTANCE_ID}")
                print(f"Time received: {message.payload.TIME_RECEIVED}")
                print(f"Endpoint     : {message.payload.ENDPOINT}")
                content = message.payload.CONTENT.read()
                print(f"Content      : {(content.decode())}")
                connection.commit()
            else:
                print(".", end="", flush=True)
    except KeyboardInterrupt:
        print("\nInterrupted")
    except Exception as e:
        print()
        logger.error("Error while dequeuing messages: %s", e)


def unsubscribe(
    connection: oracledb.Connection, queue_name: str, subscriber: oracledb.DbObject
) -> None:
    """Unsubscribe from the queue.

    Args:
        connection (oracledb.Connection): The database connection.
        queue_name (str): the name a the queue to stream from.
        subscriber (oracledb.DbObject): A subscriber agent database object.
    """
    try:
        with connection.cursor() as cursor:
            cursor.callproc(
                "dbms_aqadm.remove_subscriber",
                keyword_parameters={
                    "queue_name": queue_name,
                    "subscriber": subscriber,
                },
            )
    except Exception as e:
        logger.error("Cannot unregister subscriber: %s", e)
        return
    logger.info("Subscriber %s unregistered", subscriber.NAME)


def parse_args():
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(
        description="Subscribe to the raw messages stream from IoT Platform."
    )
    parser.add_argument(
        "-v",
        "--verbose",
        action="store_true",
        help="Enable verbose (INFO level) logging.",
    )
    parser.add_argument(
        "-d",
        "--debug",
        action="store_true",
        help="Enable debug (DEBUG level) logging.",
    )
    group = parser.add_mutually_exclusive_group()
    group.add_argument(
        "--id",
        type=str,
        help="The Digital Twin Instance OCID (mutually exclusive with --display-name).",
    )
    group.add_argument(
        "--display-name",
        type=str,
        help="The Digital Twin Instance display name (mutually exclusive with --id).",
    )
    parser.add_argument("--endpoint", type=str, help="The message endpoint (topic).")
    args = parser.parse_args()
    return args


def main():
    args = parse_args()

    log_level = logging.WARNING
    if args.verbose:
        log_level = logging.INFO
    if args.debug:
        log_level = logging.DEBUG
        # Silence third party libraries
        logging.getLogger("oci._vendor.urllib3.connectionpool").setLevel(logging.INFO)
        logging.getLogger("oci.circuit_breaker").setLevel(logging.INFO)
        logging.getLogger("oci.config").setLevel(logging.INFO)
        logging.getLogger("oci.util").setLevel(logging.INFO)
    logging.basicConfig(level=log_level, format=LOGGER_FMT, style="{")

    try:
        connection = db_connect()
    except Exception as e:
        logger.error("Database connection failed: %s", e)
        return

    queue_name = f"{config.iot_domain_short_name}__iot.raw_data_in".upper()
    subscriber = subscribe(
        connection=connection,
        queue_name=queue_name,
        digital_twin_instance_id=args.id,
        display_name=args.display_name,
        endpoint=args.endpoint,
    )
    if subscriber:
        stream(connection=connection, queue_name=queue_name, subscriber=subscriber)
        unsubscribe(connection=connection, queue_name=queue_name, subscriber=subscriber)
    try:
        db_disconnect(connection=connection)
        logger.info("Disconnected")
    except Exception as e:
        logger.warning("Failed to disconnect: %s", e)


if __name__ == "__main__":
    main()
