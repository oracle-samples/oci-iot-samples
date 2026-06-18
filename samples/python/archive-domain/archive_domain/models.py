"""Domain models for the archive-domain sample.

Copyright (c) 2026 Oracle and/or its affiliates.
Licensed under the Universal Permissive License v 1.0 as shown at
https://oss.oracle.com/licenses/upl

DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime

VALID_DATASETS = ("raw", "historized", "rejected")

EXPORT_FORMAT_PARQUET = "parquet"
EXPORT_FORMAT_DATAPUMP = "datapump"
VALID_EXPORT_FORMATS = (EXPORT_FORMAT_PARQUET, EXPORT_FORMAT_DATAPUMP)


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
    export_format: str
    retention_days: dict[str, int]
    checkpoint: CheckpointState


@dataclass(frozen=True)
class RunResult:
    """Result of one archive run."""

    run_id: str
    mode: str
    export_format: str
    plan_result: PlanResult
    dataset_results: tuple[DatasetResult, ...]
    checkpoint_advanced: bool
    manifest_object_name: str | None = None
