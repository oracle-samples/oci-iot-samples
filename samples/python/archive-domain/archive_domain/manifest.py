"""Manifest helpers for archive-domain."""

from __future__ import annotations

from dataclasses import asdict, is_dataclass
from datetime import datetime
from typing import Any

from .models import DatasetResult


def _to_jsonable(value: Any) -> Any:
    if is_dataclass(value):
        return asdict(value)
    if isinstance(value, datetime):
        return value.isoformat().replace("+00:00", "Z")
    if isinstance(value, dict):
        return {key: _to_jsonable(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [_to_jsonable(item) for item in value]
    return value


def build_run_manifest(
    run_id: str,
    selected_datasets: tuple[str, ...],
    retention_days: dict[str, int],
    checkpoint_before: str | None,
    dataset_results: list[DatasetResult],
) -> dict[str, Any]:
    """Build a minimal run manifest payload."""
    return {
        "run_id": run_id,
        "selected_datasets": list(selected_datasets),
        "retention_days": retention_days,
        "checkpoint_before": checkpoint_before,
        "dataset_results": [_to_jsonable(result) for result in dataset_results],
    }
