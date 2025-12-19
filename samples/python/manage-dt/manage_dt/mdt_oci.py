#!/usr/bin/env python3
"""
Manage-dt: OCI Helpers.

Copyright (c) 2025 Oracle and/or its affiliates.
Licensed under the Universal Permissive License v 1.0 as shown at
https://oss.oracle.com/licenses/upl

DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
"""
import logging
import os
from typing import Tuple

from oci import config as oci_config
from oci import signer as oci_signer
from oci.auth import signers as oci_auth_signers


logger = logging.getLogger(__name__)


def get_oci_config(
    profile: str = os.getenv("OCI_CLI_PROFILE", "DEFAULT"),
    auth: str = os.getenv("OCI_CLI_AUTH", "api_key"),
) -> Tuple[dict, dict]:
    """Obtain OCI configuration and signer.

    Determines the appropriate OCI configuration and authentication signer
    based on the provided profile and authentication method. Supports
    authentication via API Key (either key content from environment variables
    or configuration file), instance principal, or resource principal.

    Args:
        profile (str, optional): The OCI CLI profile name to use. Defaults to
            the value of the environment variable "OCI_CLI_PROFILE" or "DEFAULT".
        auth (str, optional): The authentication method to use. Supported
            values are "api_key", "instance_principal", and "resource_principal".
            Defaults to the value of the environment variable "OCI_CLI_AUTH"
            or "api_key".

    Returns:
        Tuple[dict, dict]: A tuple containing:
            - config (dict): OCI configuration details, or empty dict for
              principal-based authentication.
            - signer (dict): Signer details or empty dict if not required.

    Raises:
        ValueError: If an unsupported authentication scheme is provided.
        oci_exceptions.ClientError: If the configuration is invalid (config
            file not found, invalid profile, missing resource for principals, ...)

    """
    match auth:
        case "api_key":
            if os.getenv("OCI_CLI_KEY_CONTENT"):
                logger.debug("OCI authentication: Environment")
                signer = {}
                config = {
                    "user": os.getenv("OCI_CLI_USER"),
                    "key_content": os.getenv("OCI_CLI_KEY_CONTENT"),
                    "fingerprint": os.getenv("OCI_CLI_FINGERPRINT"),
                    "tenancy": os.getenv("OCI_CLI_TENANCY"),
                    "region": os.getenv("OCI_CLI_REGION"),
                }
                oci_config.validate_config(config)
            else:
                logger.debug("OCI authentication: Config file")
                signer = {}
                config = oci_config.from_file(profile_name=profile)
        case "instance_principal":
            logger.debug("OCI authentication: Instance Principal")
            signer = {
                "signer": oci_auth_signers.InstancePrincipalsSecurityTokenSigner(),
            }
            config = {}
        case "resource_principal":
            logger.debug("OCI authentication: Resource Principals")
            signer = {
                "signer": oci_auth_signers.get_resource_principals_signer(),
            }
            config = {}
        case "security_token":
            logger.debug("OCI authentication: Session Token")
            config = oci_config.from_file(profile_name=profile)
            token_file = config["security_token_file"]
            token = None
            with open(token_file, "r") as f:
                token = f.read()
            private_key = oci_signer.load_private_key_from_file(config["key_file"])
            signer = {
                "signer": oci_auth_signers.SecurityTokenSigner(token, private_key),
            }
        case _:
            raise ValueError(f"unsupported auth scheme {auth}")
    return config, signer
