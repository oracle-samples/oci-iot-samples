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


@dataclass(frozen=True)
class DatasetResult:
    """Outcome for one dataset in a run."""

    name: str
    status: str
    export_mode: str | None = None
    export_format: str | None = None
    object_prefix: str | None = None
    object_names: tuple[str, ...] = ()
    error_message: str | None = None


@dataclass(frozen=True)
class PlanResult:
    """Planned archive work plus supporting context."""

    plan: ArchivePlan
    retention_days: dict[str, int]
    checkpoint: CheckpointState


@dataclass(frozen=True)
class RunResult:
    """Result of one archive run."""

    run_id: str
    mode: str
    plan_result: PlanResult
    dataset_results: tuple[DatasetResult, ...]
    checkpoint_advanced: bool
    manifest_object_name: str | None = None
