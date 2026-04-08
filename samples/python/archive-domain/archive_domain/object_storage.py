"""Object Storage state helpers for archive-domain."""

from __future__ import annotations

import json
from dataclasses import asdict, is_dataclass
from datetime import datetime
from typing import Any

from .models import CheckpointState


def should_advance_checkpoint(statuses: dict[str, str]) -> bool:
    """Advance the checkpoint only if all selected datasets succeeded."""
    return all(status == "succeeded" for status in statuses.values())


def build_dataset_object_prefix(
    prefix: str,
    domain_short_name: str,
    zone: str,
    dataset: str,
    run_id: str,
    run_at: datetime,
) -> str:
    """Build the partitioned object prefix for one dataset."""
    normalized_prefix = prefix.strip("/")
    return (
        f"{normalized_prefix}/domain={domain_short_name}/zone={zone}/dataset={dataset}/"
        f"year={run_at:%Y}/month={run_at:%m}/day={run_at:%d}/hour={run_at:%H}/"
        f"run_id={run_id}"
    )


def build_manifest_object_name(manifest_prefix: str, run_id: str) -> str:
    """Build the manifest object name for a run."""
    return f"{manifest_prefix.strip('/')}/run_id={run_id}.json"


def _serialize(payload: Any) -> bytes:
    if is_dataclass(payload):
        payload = asdict(payload)
    return json.dumps(payload, indent=2, sort_keys=True).encode("utf-8")


def _parse_timestamp(value: str | None) -> datetime | None:
    if value is None:
        return None
    normalized = value.replace("Z", "+00:00")
    return datetime.fromisoformat(normalized)


class ObjectStorageStateStore:
    """Thin JSON-oriented wrapper around Object Storage operations."""

    def __init__(self, client: Any, namespace: str, bucket_name: str):
        self.client = client
        self.namespace = namespace
        self.bucket_name = bucket_name

    def get_json_object(self, object_name: str) -> dict[str, Any] | None:
        """Read one JSON object from Object Storage."""
        try:
            response = self.client.get_object(
                namespace_name=self.namespace,
                bucket_name=self.bucket_name,
                object_name=object_name,
            )
        except Exception:
            return None

        return json.loads(response.data.content.decode("utf-8"))

    def put_json_object(self, object_name: str, payload: Any) -> None:
        """Write one JSON object to Object Storage."""
        self.client.put_object(
            namespace_name=self.namespace,
            bucket_name=self.bucket_name,
            object_name=object_name,
            put_object_body=_serialize(payload),
        )

    def load_checkpoint(self, object_name: str) -> CheckpointState:
        """Load the current checkpoint or return an empty one."""
        payload = self.get_json_object(object_name)
        if payload is None:
            return CheckpointState()

        return CheckpointState(
            last_successful_run_at=_parse_timestamp(payload.get("last_successful_run_at"))
        )

    def save_checkpoint(self, object_name: str, checkpoint: CheckpointState) -> None:
        """Persist checkpoint state."""
        payload = {
            "last_successful_run_at": (
                checkpoint.last_successful_run_at.isoformat().replace("+00:00", "Z")
                if checkpoint.last_successful_run_at is not None
                else None
            )
        }
        self.put_json_object(object_name, payload)
