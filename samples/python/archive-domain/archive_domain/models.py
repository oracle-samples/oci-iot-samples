"""Domain models for the archive-domain sample."""

from dataclasses import dataclass
from datetime import datetime


VALID_DATASETS = ("raw", "historized", "rejected")


@dataclass(frozen=True)
class DatasetPlan:
    """Archive plan details for one dataset."""

    name: str
    retention_days: int
    purge_boundary: datetime
    window_start: datetime
    window_end: datetime


@dataclass(frozen=True)
class ArchivePlan:
    """Archive plan for the selected datasets."""

    now: datetime
    selected_datasets: tuple[str, ...]
    datasets: dict[str, DatasetPlan]


@dataclass(frozen=True)
class CheckpointState:
    """Latest successful archive checkpoint."""

    last_successful_run_at: datetime | None = None

