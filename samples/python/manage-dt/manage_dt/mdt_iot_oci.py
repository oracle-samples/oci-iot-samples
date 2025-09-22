#!/usr/bin/env python3
"""
Manage-dt: OCI IoT interactions.

Copyright (c) 2025 Oracle and/or its affiliates.
Licensed under the Universal Permissive License v 1.0 as shown at
https://oss.oracle.com/licenses/upl

DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
"""
import json
import logging
import pathlib
from typing import Optional

from oci import exceptions as oci_exceptions, iot as oci_iot
from rich.console import Console
from rich.panel import Panel
from rich.pretty import Pretty
from rich.table import Table

from . import mdt_iot_data

logger = logging.getLogger(__name__)


def create_digital_twin_model(
    client: oci_iot.IotClient,
    display_name: str,
    description: Optional[str],
    iot_domain_id: str,
    spec_dtdl: dict,
) -> Optional[str]:
    """Create a Digital Twin Model.

    Args:
        client (oci_iot.IotClient): OCI IoT client.
        display_name (str): Model name.
        description (Optional[str]): Description.
        iot_domain_id (str): IoT Domain OCID.
        spec_dtdl (dict): DTDL spec.

    Returns:
        Optional[str]: Model OCID or None.
    """
    digital_twin_model = oci_iot.models.CreateDigitalTwinModelDetails(
        display_name=display_name,
        description=description,
        iot_domain_id=iot_domain_id,
        spec=spec_dtdl,
    )
    ocid = None
    try:
        response = client.create_digital_twin_model(digital_twin_model)
    except oci_exceptions.ServiceError as exc:
        logger.error("Cannot create Digital Twin Model")
        logger.error("  Status : %d - %s", exc.status, exc.code)
        logger.error("  Message: %s", exc.message)
    else:
        if response and response.status == 200:
            logger.info("Digital Twin Model created")
            ocid = response.data.id
        else:
            logger.error(
                "Cannot create Digital Twin Model: %s",
                response.status if response else None,
            )
    return ocid


def delete_digital_twin_model_by_spec_uri(
    client: oci_iot.IotClient,
    spec_uri: str,
    iot_domain_id: str,
) -> bool:
    """Delete a Digital Twin Model by spec URI.

    Args:
        client (oci_iot.IotClient): OCI IoT client.
        spec_uri (str): Model spec URI.
        iot_domain_id (str): IoT Domain OCID.

    Returns:
        bool: True if deleted, else False.
    """
    response = client.list_digital_twin_models(
        iot_domain_id=iot_domain_id,
        digital_twin_model_spec_uri_starts_with=spec_uri,
        lifecycle_state="ACTIVE",
    )
    if not response or response.status != 200:
        logger.error(
            "Cannot get Digital Twin Model list - %s",
            response.status if response else None,
        )
        return False
    if len(response.data.items) == 0:
        logger.error("Digital Twin Model does not exist")
        return False
    try:
        response = client.delete_digital_twin_model(
            digital_twin_model_id=response.data.items[0].id
        )
    except oci_exceptions.ServiceError as exc:
        logger.error("Cannot delete Digital Twin Model")
        logger.error("  Status : %d - %s", exc.status, exc.code)
        logger.error("  Message: %s", exc.message)
        return False
    if response and response.status == 204:
        logger.info("Digital Twin Model deleted")
        return True
    else:
        logger.error(
            "Cannot delete Digital Twin Model - %s",
            response.status if response else None,
        )
        return False


def create_digital_twin_adapter(
    client: oci_iot.IotClient,
    display_name: str,
    description: Optional[str],
    iot_domain_id: str,
    digital_twin_model_spec_uri: str,
    inbound_envelope: Optional[dict],
    inbound_routes: Optional[dict],
) -> Optional[str]:
    """Create a Digital Twin Adapter.

    Args:
        client (oci_iot.IotClient): OCI IoT client.
        display_name (str): Adapter name.
        description (Optional[str]): Description.
        iot_domain_id (str): IoT Domain OCID.
        digital_twin_model_spec_uri (str): Model spec URI.
        inbound_envelope (Optional[dict]): Envelope data.
        inbound_routes (Optional[dict]): Routes data.

    Returns:
        Optional[str]: Adapter OCID or None.
    """
    digital_twin_adapter = oci_iot.models.CreateDigitalTwinAdapterDetails(
        display_name=display_name,
        description=description,
        iot_domain_id=iot_domain_id,
        digital_twin_model_spec_uri=digital_twin_model_spec_uri,
        inbound_envelope=inbound_envelope,
        inbound_routes=inbound_routes,
    )
    ocid = None
    try:
        response = client.create_digital_twin_adapter(digital_twin_adapter)
    except oci_exceptions.ServiceError as exc:
        logger.error("Cannot create Digital Twin Adapter")
        logger.error("  Status : %d - %s", exc.status, exc.code)
        logger.error("  Message: %s", exc.message)
    else:
        if response and response.status == 200:
            logger.info("Digital Twin Adapter created")
            ocid = response.data.id
        else:
            logger.error(
                "Cannot create Digital Twin Adapter: %s",
                response.status if response else None,
            )
    return ocid


def delete_digital_twin_adapter_by_name(
    client: oci_iot.IotClient,
    display_name: str,
    iot_domain_id: str,
) -> bool:
    """Delete a Digital Twin Adapter by name.

    Args:
        client (oci_iot.IotClient): OCI IoT client.
        display_name (str): Adapter name.
        iot_domain_id (str): IoT Domain OCID.

    Returns:
        bool: True if deleted, else False.
    """
    response = client.list_digital_twin_adapters(
        iot_domain_id=iot_domain_id,
        display_name=display_name,
        lifecycle_state="ACTIVE",
    )
    if not response or response.status != 200:
        logger.error(
            "Cannot get Digital Twin Adapter list - %s",
            response.status if response else None,
        )
        return False
    if len(response.data.items) == 0:
        logger.error("Digital Twin Adapter does not exist")
        return False
    elif len(response.data.items) > 1:
        logger.error("Multiple Digital Twin Adapters exist with the same name")
        return False
    try:
        response = client.delete_digital_twin_adapter(
            digital_twin_adapter_id=response.data.items[0].id
        )
    except oci_exceptions.ServiceError as exc:
        logger.error("Cannot delete Digital Twin Adapter")
        logger.error("  Status : %d - %s", exc.status, exc.code)
        logger.error("  Message: %s", exc.message)
        return False
    if response and response.status == 204:
        logger.info("Digital Twin Adapter deleted")
        return True
    else:
        logger.error(
            "Cannot delete Digital Twin Adapter - %s",
            response.status if response else None,
        )
        return False


def create_digital_twin_instance(
    client: oci_iot.IotClient,
    display_name: str,
    description: Optional[str],
    iot_domain_id: str,
    digital_twin_adapter_id: Optional[str],
    external_key: str,
    auth_id: str,
) -> Optional[str]:
    """Create a Digital Twin Instance.

    Args:
        client (oci_iot.IotClient): OCI IoT client.
        display_name (str): Instance name.
        description (Optional[str]): Description.
        iot_domain_id (str): IoT Domain OCID.
        digital_twin_adapter_id (Optional[str]): Adapter OCID.
        external_key (str): Device key.
        auth_id (str): Auth ID.

    Returns:
        Optional[str]: Instance OCID or None.
    """
    digital_twin_instance = oci_iot.models.CreateDigitalTwinInstanceDetails(
        display_name=display_name,
        description=description,
        iot_domain_id=iot_domain_id,
        digital_twin_adapter_id=digital_twin_adapter_id,
        external_key=external_key,
        auth_id=auth_id,
    )
    ocid = None
    try:
        response = client.create_digital_twin_instance(digital_twin_instance)
    except oci_exceptions.ServiceError as exc:
        logger.error("Cannot create Digital Twin Instance")
        logger.error("  Status : %d - %s", exc.status, exc.code)
        logger.error("  Message: %s", exc.message)
    else:
        if response and response.status == 200:
            logger.info("Digital Twin Instance created")
            ocid = response.data.id
        else:
            logger.error(
                "Cannot create Digital Twin Instance: %s",
                response.status if response else None,
            )
    return ocid


def get_digital_twin_instance_by_name(
    client: oci_iot.IotClient,
    display_name: str,
    iot_domain_id: str,
) -> Optional[oci_iot.models.DigitalTwinInstance]:
    """Get a Digital Twin Instance by name.

    Args:
        client (oci_iot.IotClient): OCI IoT client.
        display_name (str): Instance name.
        iot_domain_id (str): IoT Domain OCID.

    Returns:
        Optional[oci_iot.models.DigitalTwinInstance]: The instance or None.
    """
    response = client.list_digital_twin_instances(
        iot_domain_id=iot_domain_id,
        display_name=display_name,
        lifecycle_state="ACTIVE",
    )
    if not response or response.status != 200:
        logger.error(
            "Cannot get Digital Twin Instance list - %s",
            response.status if response else None,
        )
        return None
    if len(response.data.items) == 0:
        logger.error("Digital Twin Instance does not exist")
        return None
    elif len(response.data.items) > 1:
        logger.error("Multiple Digital Twins exist with the same name")
        return None
    try:
        response = client.get_digital_twin_instance(
            digital_twin_instance_id=response.data.items[0].id
        )
    except oci_exceptions.ServiceError as exc:
        logger.error("Cannot get Digital Twin Instance")
        logger.error("  Status : %d - %s", exc.status, exc.code)
        logger.error("  Message: %s", exc.message)
        return None
    if response and response.status == 200:
        logger.info("Digital Twin Instance retrieved")
        return response.data
    else:
        logger.error(
            "Cannot retrieve Digital Twin Instance - %s",
            response.status if response else None,
        )
        return None


def get_digital_twin_instance_content(
    client: oci_iot.IotClient,
    digital_twin_instance_id: str,
) -> Optional[dict]:
    """Get content of a Digital Twin Instance.

    Args:
        client (oci_iot.IotClient): OCI IoT client.
        digital_twin_instance_id (str): Instance OCID.

    Returns:
        Optional[dict]: Instance content or None.
    """
    try:
        response = client.get_digital_twin_instance_content(
            digital_twin_instance_id=digital_twin_instance_id
        )
    except oci_exceptions.ServiceError as exc:
        logger.error("Cannot get Digital Twin Instance content")
        logger.error("  Status : %d - %s", exc.status, exc.code)
        logger.error("  Message: %s", exc.message)
        return None
    if response and response.status == 200:
        logger.info("Digital Twin Instance content retrieved")
        return response.data
    else:
        logger.error(
            "Cannot retrieve Digital Twin Instance content - %s",
            response.status if response else None,
        )
        return None


def delete_digital_twin_instance_by_name(
    client: oci_iot.IotClient,
    display_name: str,
    iot_domain_id: str,
) -> bool:
    """Delete a Digital Twin Instance by name.

    Args:
        client (oci_iot.IotClient): OCI IoT client.
        display_name (str): Instance name.
        iot_domain_id (str): Domain OCID.

    Returns:
        bool: True if deleted, else False.
    """
    response = client.list_digital_twin_instances(
        iot_domain_id=iot_domain_id,
        display_name=display_name,
        lifecycle_state="ACTIVE",
    )
    if not response or response.status != 200:
        logger.error(
            "Cannot get Digital Twin Instance list - %s",
            response.status if response else None,
        )
        return False
    if len(response.data.items) == 0:
        logger.error("Digital Twin Instance does not exist")
        return False
    try:
        response = client.delete_digital_twin_instance(
            digital_twin_instance_id=response.data.items[0].id
        )
    except oci_exceptions.ServiceError as exc:
        logger.error("Cannot delete Digital Twin Instance")
        logger.error("  Status : %d - %s", exc.status, exc.code)
        logger.error("  Message: %s", exc.message)
        return False
    if response and response.status == 204:
        logger.info("Digital Twin Instance deleted")
        return True
    else:
        logger.error(
            "Cannot delete Digital Twin Instance - %s",
            response.status if response else None,
        )
        return False


def create_digital_twin(
    digital_twin: str,
    iot_config: dict,
    data_dir: pathlib.Path,
    config: dict,
    signer: dict,
) -> None:
    """Create a new Digital Twin with related resources (Model and Adapter).

    Args:
        digital_twin (str): Name of Digital Twin.
        iot_config (dict): IoT configuration.
        data_dir (pathlib.Path): Data directory.
        config (dict): OCI config.
        signer (dict): OCI signer.
    """
    digital_twin_config = iot_config["digital_twins"][digital_twin]
    client = oci_iot.IotClient(config=config, **signer)

    if "model_dtdl" not in digital_twin_config:
        description = f"{digital_twin_config['device_name']} - Unstructured Telemetry"
        digital_twin_adapter_id = None
    else:
        logger.info("Create Digital Twin Model '%s'", digital_twin_config["model_name"])
        with open(data_dir / digital_twin_config["model_dtdl"], "r") as fp:
            spec_dtdl = json.load(fp)
        spec_dtdl["@id"] = digital_twin_config["model_name"]
        ocid = create_digital_twin_model(
            client=client,
            display_name=digital_twin_config["model_name"],
            description=digital_twin_config["model_description"],
            iot_domain_id=iot_config["iot"]["domain_id"],
            spec_dtdl=spec_dtdl,
        )
        if not ocid:
            return
        if "adapter_envelope" not in digital_twin_config:
            description = f"{digital_twin_config['device_name']} - Structured Telemetry with default Adapter"
            logger.info(
                "Create default Digital Twin Adapter '%s'",
                digital_twin_config["adapter_name"],
            )
            ocid = create_digital_twin_adapter(
                client=client,
                display_name=digital_twin_config["adapter_name"],
                description=f"Default Adapter for {digital_twin_config['model_name']}",
                iot_domain_id=iot_config["iot"]["domain_id"],
                digital_twin_model_spec_uri=digital_twin_config["model_name"],
                inbound_envelope=None,
                inbound_routes=None,
            )
        else:
            description = f"{digital_twin_config['device_name']} - Structured Telemetry with custom Adapter"
            logger.info(
                "Create custom Digital Twin Adapter '%s'",
                digital_twin_config["adapter_name"],
            )
            with open(data_dir / digital_twin_config["adapter_envelope"], "r") as fp:
                inbound_envelope = json.load(fp)
            with open(data_dir / digital_twin_config["adapter_routes"], "r") as fp:
                inbound_routes = json.load(fp)
            ocid = create_digital_twin_adapter(
                client=client,
                display_name=digital_twin_config["adapter_name"],
                description=f"Default Adapter for {digital_twin_config['model_name']}",
                iot_domain_id=iot_config["iot"]["domain_id"],
                digital_twin_model_spec_uri=digital_twin_config["model_name"],
                inbound_envelope=inbound_envelope,
                inbound_routes=inbound_routes,
            )
        if not ocid:
            return
        digital_twin_adapter_id = ocid

    logger.info("Create Digital Twin Instance %s", description)
    create_digital_twin_instance(
        client=client,
        display_name=digital_twin_config["device_name"],
        description=description,
        iot_domain_id=iot_config["iot"]["domain_id"],
        digital_twin_adapter_id=digital_twin_adapter_id,
        external_key=digital_twin_config["external_key"],
        auth_id=digital_twin_config["auth_id"],
    )


def query_digital_twin(
    digital_twin: str,
    last_minutes: int,
    iot_config: dict,
    data_dir: pathlib.Path,
    config: dict,
    signer: dict,
) -> None:
    """Query and print data for a Digital Twin.

    Args:
        digital_twin (str): Name of Digital Twin.
        last_minutes (int): Lookback period in minutes.
        iot_config (dict): IoT configuration.
        data_dir (pathlib.Path): Data directory.
        config (dict): OCI config.
        signer (dict): OCI signer.
    """
    digital_twin_config = iot_config["digital_twins"][digital_twin]
    client = oci_iot.IotClient(config=config, **signer)

    digital_twin_instance = get_digital_twin_instance_by_name(
        client=client,
        display_name=digital_twin_config["device_name"],
        iot_domain_id=iot_config["iot"]["domain_id"],
    )
    if not digital_twin_instance:
        return

    digital_twin_instance_id: str = digital_twin_instance.id  # type: ignore
    console = Console()
    if "model_dtdl" in digital_twin_config:
        # Digital Twin content is only available for structured telemetry
        logger.info("Query Digital Twin Instance '%s'", digital_twin)
        digital_twin_instance_content = get_digital_twin_instance_content(
            client=client, digital_twin_instance_id=digital_twin_instance_id
        )
        console.print(
            Panel(
                Pretty(digital_twin_instance_content),
                title="Digital Twin Instance content",
            )
        )

    data_access = mdt_iot_data.get_data_access_parameters(
        client=client, iot_config=iot_config, data_dir=data_dir
    )
    if not data_access:
        return

    raw_data = mdt_iot_data.get_recent_raw_data(
        data_access=data_access,
        digital_twin_instance_id=digital_twin_instance_id,
        last_minutes=last_minutes,
    )
    if raw_data is not None:
        table = Table(
            "Id",
            "Time received (UTC)",
            "Endpoint",
            title=f"Recent raw data - {len(raw_data)} record(s)",
        )
        for record in raw_data:
            table.add_row(
                str(record["id"]), record["time_received"], record["endpoint"]
            )
        console.print(table)

    historized_data = mdt_iot_data.get_recent_historized_data(
        data_access=data_access,
        digital_twin_instance_id=digital_twin_instance_id,
        last_minutes=last_minutes,
    )
    if historized_data is not None:
        table = Table(
            "Id",
            "Time observed (UTC)",
            "Content path",
            "Value",
            title=f"Recent historized data - {len(historized_data)} record(s)",
        )
        for record in historized_data:
            table.add_row(
                str(record["id"]),
                record["time_observed"],
                record["content_path"],
                str(record["value"]),
            )
        console.print(table)

    rejected_data = mdt_iot_data.get_recent_rejected_data(
        data_access=data_access,
        digital_twin_instance_id=digital_twin_instance_id,
        last_minutes=last_minutes,
    )
    if rejected_data is not None:
        table = Table(
            "Id",
            "Time received (UTC)",
            "Endpoint",
            "Reason code",
            "Reason message",
            title=f"Recent rejected data - {len(rejected_data)} record(s)",
        )
        for record in rejected_data:
            table.add_row(
                str(record["id"]),
                record["time_received"],
                record["endpoint"],
                str(record["reason_code"]),
                record["reason_message"],
            )
        console.print(table)


def delete_digital_twin(
    digital_twin: str, iot_config: dict, config: dict, signer: dict
) -> None:
    """Delete a Digital Twin and all related OCI resources (Model and Adapter).

    Args:
        digital_twin (str): Name of Digital Twin.
        iot_config (dict): IoT configuration.
        config (dict): OCI config.
        signer (dict): OCI signer.
    """
    digital_twin_config = iot_config["digital_twins"][digital_twin]
    client = oci_iot.IotClient(config=config, **signer)

    logger.info("Delete Digital Twin Instance '%s'", digital_twin)
    delete_digital_twin_instance_by_name(
        client=client,
        display_name=digital_twin_config["device_name"],
        iot_domain_id=iot_config["iot"]["domain_id"],
    )

    if "model_dtdl" in digital_twin_config:
        logger.info(
            "Delete Digital Twin Adapter '%s'", digital_twin_config["adapter_name"]
        )
        delete_digital_twin_adapter_by_name(
            client=client,
            display_name=digital_twin_config["adapter_name"],
            iot_domain_id=iot_config["iot"]["domain_id"],
        )
        logger.info("Delete Digital Twin Model '%s'", digital_twin_config["model_name"])
        delete_digital_twin_model_by_spec_uri(
            client=client,
            spec_uri=digital_twin_config["model_name"],
            iot_domain_id=iot_config["iot"]["domain_id"],
        )
