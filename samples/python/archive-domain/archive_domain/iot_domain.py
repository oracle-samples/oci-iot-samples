"""IoT Domain metadata helpers."""

from collections.abc import Mapping
from typing import Any

from .models import VALID_DATASETS


class IotDomainLookup:
    """Thin wrapper around an IoT client."""

    def __init__(self, client: Any, iot_domain_id: str):
        """Capture the IoT client and target IoT Domain identifier."""
        self.client = client
        self.iot_domain_id = iot_domain_id

    def get_retention_days(self) -> dict[str, int]:
        """Fetch retention settings for the configured IoT Domain."""
        response = self.client.get_iot_domain(iot_domain_id=self.iot_domain_id)
        return extract_retention_days(response.data)


def _read_value(source: Any, *keys: str) -> Any:
    if source is None:
        return None

    if isinstance(source, Mapping):
        for key in keys:
            if key in source:
                return source[key]
            normalized_key = key.replace("-", "_")
            if normalized_key in source:
                return source[normalized_key]
        return None

    for key in keys:
        if hasattr(source, key):
            return getattr(source, key)
        normalized_key = key.replace("-", "_")
        if hasattr(source, normalized_key):
            return getattr(source, normalized_key)
    return None


def extract_retention_days(domain: Any) -> dict[str, int]:
    """Extract retention days from an IoT Domain response object or mapping."""
    retention_source = _read_value(
        domain,
        "data-retention-periods-in-days",
        "data_retention_periods_in_days",
    )

    if retention_source is None:
        return {}

    key_map = {
        "raw": ("raw", "rawData", "raw_data", "raw-data"),
        "historized": (
            "historized",
            "historizedData",
            "historized_data",
            "historized-data",
        ),
        "rejected": ("rejected", "rejectedData", "rejected_data", "rejected-data"),
    }

    resolved: dict[str, int] = {}
    for dataset, keys in key_map.items():
        value = _read_value(retention_source, *keys)
        if value is not None:
            resolved[dataset] = int(value)
    return resolved


def resolve_retention_days(
    lookup_client: Any,
    configured_overrides: dict[str, int | None],
    required_datasets: tuple[str, ...] = VALID_DATASETS,
) -> dict[str, int]:
    """Resolve retention days from live lookup first, then configured overrides."""
    resolved: dict[str, int] = {}

    try:
        resolved.update(lookup_client.get_retention_days())
    except Exception:
        pass

    for dataset in required_datasets:
        value = configured_overrides.get(dataset)
        if value is not None:
            resolved[dataset] = int(value)

    missing = [dataset for dataset in required_datasets if dataset not in resolved]
    if missing:
        missing_text = ", ".join(missing)
        raise ValueError(f"Missing retention values for datasets: {missing_text}")

    return resolved
