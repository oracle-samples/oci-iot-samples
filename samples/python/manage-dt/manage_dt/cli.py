#!/usr/bin/env python3
"""
Manage Digital Twins for the OCI IoT Platform.

Copyright (c) 2025 Oracle and/or its affiliates.
Licensed under the Universal Permissive License v 1.0 as shown at
https://oss.oracle.com/licenses/upl

DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
"""
import logging
import os
import pathlib
import string
from typing import Any

import click
import manage_dt
import yaml

from . import mdt_constants, mdt_iot_oci, mdt_oci

LOGGER_FMT = "{asctime} - {levelname:8} - {filename:16} - {message}"
logger = logging.getLogger(__name__)


def load_config(config_file: pathlib.Path) -> dict:
    """Load and substitute values in the config file.

    Args:
        config_file (pathlib.Path): Path to the configuration YAML file.

    Returns:
        dict: Loaded and processed configuration.
    """
    logger.debug("Loading configuration")
    with open(config_file, "r") as fp:
        config = yaml.safe_load(fp)
    environ = config["environ"]

    for digital_twin_data in config["digital_twins"].values():
        for key, value in digital_twin_data.items():
            digital_twin_data[key] = string.Template(value).safe_substitute(environ)
    return config


def validate_digital_twin(
    ctx: click.Context, param: click.Parameter, value: Any
) -> Any:
    """Validate Digital Twin argument for Click commands.

    Args:
        ctx (click.Context): Click context.
        param (click.Parameter): Click parameter.
        value (Any): Argument value.

    Returns:
        Any: Validated argument.

    Raises:
        click.BadParameter: If value is not a valid Digital Twin.
    """
    digital_twin_list = list(ctx.obj["iot_config"]["digital_twins"].keys())
    if value not in digital_twin_list:
        raise click.BadParameter(f"must be one of: {digital_twin_list}")
    return value


@click.group()
@click.option("-v", "--verbose", is_flag=True, help="Verbose mode")
@click.option("-d", "--debug", is_flag=True, help="Debug mode")
@click.option(
    "--profile",
    help="The profile in the config file to load.",
    default=os.getenv("OCI_CLI_PROFILE", "DEFAULT"),
    show_default=True,
)
@click.option(
    "--auth",
    type=click.Choice(["api_key", "instance_principal", "resource_principal"]),
    help="The type of auth to use for the API request.",
    default=os.getenv("OCI_CLI_AUTH", "api_key"),
    show_default=True,
)
@click.option(
    "--data-dir",
    type=click.Path(
        exists=True,
        file_okay=False,
        dir_okay=True,
        writable=True,
        path_type=pathlib.Path,
    ),
    default=mdt_constants.DEFAULT_DATA_DIR,
    help="Data directory",
    show_default=True,
)
@click.option(
    "--iot-config-file",
    type=click.Path(exists=False, dir_okay=False, path_type=pathlib.Path),
    default=mdt_constants.DEFAULT_IOT_CONFIG,
    help="The path to the IoT config file.",
    show_default=True,
)
@click.version_option(version=manage_dt.__version__)
@click.pass_context
def cli(
    ctx: click.Context,
    verbose: bool,
    debug: bool,
    profile: str,
    auth: str,
    data_dir: pathlib.Path,
    iot_config_file: pathlib.Path,
):
    """Manage Digital Twins.

    Sample application to create/query/delete Digital Twins for the OCI Iot Platform.

    \f
    Args:
        ctx (click.Context): Click context object.
        verbose (bool): Enable verbose mode.
        debug (bool): Enable debug mode.
        profile (str): OCI config profile name.
        auth (str): OCI authentication type.
        data_dir (pathlib.Path): Data directory path.
        iot_config_file (pathlib.Path): IoT config filename.

    Raises:
        click.BadParameter: If IoT config file is invalid.
    """  # noqa: D301
    # Validate iot_config_file
    iot_config_file = data_dir / iot_config_file
    if not iot_config_file.is_file():
        raise click.BadParameter(
            f"File '{iot_config_file}' does not exist.",
            param_hint="'--iot-config-file'",
        )
    if not os.access(iot_config_file, os.R_OK):
        raise click.BadParameter(
            f"File '{iot_config_file}' is not readable.",
            param_hint="'--iot-config-file'",
        )

    # Setup logging
    log_level = logging.WARNING
    if verbose:
        log_level = logging.INFO
    if debug:
        log_level = logging.DEBUG
        # Silence third party libraries
        logging.getLogger("urllib3.connectionpool").setLevel(logging.INFO)
        logging.getLogger("oci._vendor.urllib3.connectionpool").setLevel(logging.INFO)
        logging.getLogger("oci.util").setLevel(logging.INFO)
        logging.getLogger("oci.circuit_breaker").setLevel(logging.INFO)
    logging.basicConfig(level=log_level, format=LOGGER_FMT, style="{")

    # Preserve context
    ctx.ensure_object(dict)
    ctx.obj["verbose"] = verbose
    ctx.obj["debug"] = debug
    ctx.obj["data_dir"] = data_dir
    ctx.obj["iot_config"] = load_config(iot_config_file)
    config, signer = mdt_oci.get_oci_config(profile=profile, auth=auth)
    ctx.obj["oci_config"] = {"config": config, "signer": signer}


@cli.command()
@click.argument(
    "digital_twin", type=str, required=True, callback=validate_digital_twin, nargs=1
)
@click.pass_context
def create(ctx: click.Context, digital_twin: str):
    """Create a new Digital Twin.

    For Digital Twins with telemetry in structured format, Model and Adapter
    will be created as well.

    \f
    Args:
        ctx (click.Context): Click context.
        digital_twin (str): Name of the Digital Twin.
    """  # noqa: D301
    mdt_iot_oci.create_digital_twin(
        digital_twin=digital_twin,
        iot_config=ctx.obj["iot_config"],
        data_dir=ctx.obj["data_dir"],
        config=ctx.obj["oci_config"]["config"],
        signer=ctx.obj["oci_config"]["signer"],
    )


@cli.command()
@click.option(
    "--last-minutes",
    "-l",
    type=int,
    help="The query will show data received in the 'last-minutes'.",
    default=mdt_constants.DEFAULT_LAST_MINUTES,
    show_default=True,
)
@click.argument(
    "digital_twin", type=str, required=True, callback=validate_digital_twin, nargs=1
)
@click.pass_context
def query(ctx, last_minutes, digital_twin):
    """Query recent data for a Digital Twin.

    For Digital Twins with telemetry in structured format, the Digital Twin Content
    is retrieved using the Python SDK.
    Raw data, historized data and rejected data are retrieved using the
    IoT Platform Data API.

    \f
    Args:
        ctx (click.Context): Click context.
        last_minutes (int): Time window for the query.
        digital_twin (str): Name of the Digital Twin.
    """  # noqa: D301
    mdt_iot_oci.query_digital_twin(
        digital_twin=digital_twin,
        last_minutes=last_minutes,
        iot_config=ctx.obj["iot_config"],
        data_dir=ctx.obj["data_dir"],
        config=ctx.obj["oci_config"]["config"],
        signer=ctx.obj["oci_config"]["signer"],
    )


@cli.command()
@click.argument(
    "digital_twin", type=str, required=True, callback=validate_digital_twin, nargs=1
)
@click.pass_context
def delete(ctx: click.Context, digital_twin: str):
    """Delete a Digital Twin.

    For Digital Twins with telemetry in structured format, Model and Adapter
    will be deleted as well.

    \f
    Args:
        ctx (click.Context): Click context.
        digital_twin (str): Name of the Digital Twin.
    """  # noqa: D301
    mdt_iot_oci.delete_digital_twin(
        digital_twin=digital_twin,
        iot_config=ctx.obj["iot_config"],
        config=ctx.obj["oci_config"]["config"],
        signer=ctx.obj["oci_config"]["signer"],
    )


if __name__ == "__main__":
    cli()
