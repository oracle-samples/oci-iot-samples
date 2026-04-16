"""Configuration loading for archive-domain."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import yaml


@dataclass(frozen=True)
class IotConfig:
    """IoT-specific configuration."""

    domain_id: str
    retention_days: dict[str, int | None]
    bootstrap_lookback_days: int


@dataclass(frozen=True)
class DatabaseConfig:
    """Direct database configuration."""

    connect_string: str
    token_scope: str
    iot_domain_short_name: str
    auth_type: str
    profile: str
    thick_mode: bool
    lib_dir: str | None
    dbms_cloud_credential_name: str | None


@dataclass(frozen=True)
class ObjectStorageConfig:
    """Object Storage configuration."""

    namespace: str | None
    bucket_name: str
    prefix: str
    manifest_prefix: str
    checkpoint_object: str


@dataclass(frozen=True)
class ArchiveConfig:
    """Full archive-domain configuration."""

    iot: IotConfig
    database: DatabaseConfig
    object_storage: ObjectStorageConfig
    export_format: str = "parquet"


def load_config(path: str | Path) -> ArchiveConfig:
    """Load archive-domain YAML configuration."""
    config_path = Path(path)
    with config_path.open("r", encoding="utf-8") as file_obj:
        data = yaml.safe_load(file_obj) or {}

    iot = data.get("iot", {})
    database = data.get("database", {})
    object_storage = data.get("object_storage", {})

    return ArchiveConfig(
        iot=IotConfig(
            domain_id=iot["domain_id"],
            retention_days=iot.get("retention_days", {}),
            bootstrap_lookback_days=int(iot.get("bootstrap_lookback_days", 1)),
        ),
        database=DatabaseConfig(
            connect_string=database["connect_string"],
            token_scope=database["token_scope"],
            iot_domain_short_name=database["iot_domain_short_name"],
            auth_type=database.get("auth_type", "InstancePrincipal"),
            profile=database.get("profile", "DEFAULT"),
            thick_mode=bool(database.get("thick_mode", False)),
            lib_dir=database.get("lib_dir"),
            dbms_cloud_credential_name=database.get("dbms_cloud_credential_name"),
        ),
        object_storage=ObjectStorageConfig(
            namespace=object_storage.get("namespace"),
            bucket_name=object_storage["bucket_name"],
            prefix=object_storage.get("prefix", "iot-archive"),
            manifest_prefix=object_storage.get("manifest_prefix", "_manifests"),
            checkpoint_object=object_storage.get(
                "checkpoint_object", "_state/checkpoint.json"
            ),
        ),
        export_format=str(data.get("export_format", "parquet")).lower(),
    )
