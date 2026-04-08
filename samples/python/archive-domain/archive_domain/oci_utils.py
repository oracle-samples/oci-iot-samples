"""OCI client helpers for archive-domain."""

from __future__ import annotations

import os
from typing import Any


def get_oci_config(
    profile: str = os.getenv("OCI_CLI_PROFILE", "DEFAULT"),
    auth: str = os.getenv("OCI_CLI_AUTH", "api_key"),
) -> tuple[dict[str, Any], dict[str, Any]]:
    """Load OCI config and signer details for the chosen auth mode."""
    try:
        from oci import config as oci_config
        from oci import signer as oci_signer
        from oci.auth import signers as oci_auth_signers
    except ModuleNotFoundError as exc:
        raise RuntimeError("The oci package is required for live OCI operations") from exc

    match auth:
        case "api_key":
            if os.getenv("OCI_CLI_KEY_CONTENT"):
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
                signer = {}
                config = oci_config.from_file(profile_name=profile)
        case "instance_principal":
            signer = {
                "signer": oci_auth_signers.InstancePrincipalsSecurityTokenSigner(),
            }
            config = {"region": os.getenv("OCI_CLI_REGION")} if os.getenv("OCI_CLI_REGION") else {}
        case "resource_principal":
            signer = {
                "signer": oci_auth_signers.get_resource_principals_signer(),
            }
            config = {"region": os.getenv("OCI_CLI_REGION")} if os.getenv("OCI_CLI_REGION") else {}
        case "security_token":
            config = oci_config.from_file(profile_name=profile)
            with open(config["security_token_file"], "r", encoding="utf-8") as token_file:
                token = token_file.read()
            private_key = oci_signer.load_private_key_from_file(config["key_file"])
            signer = {
                "signer": oci_auth_signers.SecurityTokenSigner(token, private_key),
            }
        case _:
            raise ValueError(f"unsupported auth scheme {auth}")
    return config, signer


def resolve_region(config: dict[str, Any]) -> str | None:
    """Resolve the OCI region from config or environment."""
    return config.get("region") or os.getenv("OCI_CLI_REGION") or os.getenv("OCI_REGION")


def build_iot_client(config: dict[str, Any], signer: dict[str, Any]):
    """Create an OCI IoT client."""
    try:
        from oci import iot as oci_iot
    except ModuleNotFoundError as exc:
        raise RuntimeError("The oci package is required for live IoT operations") from exc
    return oci_iot.IotClient(config, **signer)


def build_object_storage_client(config: dict[str, Any], signer: dict[str, Any]):
    """Create an OCI Object Storage client."""
    try:
        from oci import object_storage
    except ModuleNotFoundError as exc:
        raise RuntimeError(
            "The oci package is required for live Object Storage operations"
        ) from exc
    return object_storage.ObjectStorageClient(config, **signer)
