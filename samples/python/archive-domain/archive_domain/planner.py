"""Archive planning helpers."""

from datetime import datetime, timedelta

from .models import ArchivePlan, DatasetPlan, VALID_DATASETS


def parse_datasets(value: str | None) -> tuple[str, ...]:
    """Normalize a comma-separated dataset selection."""
    if not value:
        return VALID_DATASETS

    selected = {item.strip().lower() for item in value.split(",") if item.strip()}
    unknown = sorted(selected.difference(VALID_DATASETS))
    if unknown:
        raise ValueError(f"Unknown datasets: {', '.join(unknown)}")

    return tuple(dataset for dataset in VALID_DATASETS if dataset in selected)


def build_archive_plan(
    selected_datasets: list[str] | tuple[str, ...],
    retention_days: dict[str, int],
    now: datetime,
    last_successful_run_at: datetime | None = None,
    bootstrap_lookback_days: int | None = None,
    explicit_start_time: datetime | None = None,
    explicit_end_time: datetime | None = None,
) -> ArchivePlan:
    """Build a retention-aware archive plan for the selected datasets."""
    datasets: dict[str, DatasetPlan] = {}

    for dataset in selected_datasets:
        retention = retention_days[dataset]
        purge_boundary = now - timedelta(days=retention)
        window_end = explicit_end_time or purge_boundary

        if explicit_start_time is not None:
            window_start = explicit_start_time
        elif last_successful_run_at is not None:
            window_start = last_successful_run_at - timedelta(days=retention)
        elif bootstrap_lookback_days is not None:
            window_start = purge_boundary - timedelta(days=bootstrap_lookback_days)
        else:
            raise ValueError(
                "A checkpoint, explicit start time, or bootstrap lookback is required"
            )

        datasets[dataset] = DatasetPlan(
            name=dataset,
            retention_days=retention,
            purge_boundary=purge_boundary,
            window_start=window_start,
            window_end=window_end,
        )

    return ArchivePlan(
        now=now,
        selected_datasets=tuple(selected_datasets),
        datasets=datasets,
    )
