from datetime import datetime, timezone

from archive_domain.object_storage import (
    build_dataset_object_prefix,
    should_advance_checkpoint,
)


def test_checkpoint_advances_only_when_all_selected_datasets_succeed():
    statuses = {"raw": "succeeded", "historized": "failed"}

    assert should_advance_checkpoint(statuses) is False
    assert should_advance_checkpoint({"raw": "succeeded", "historized": "succeeded"})


def test_build_dataset_object_prefix_partitions_by_domain_dataset_and_hour():
    run_at = datetime(2026, 4, 8, 12, 34, tzinfo=timezone.utc)

    object_prefix = build_dataset_object_prefix(
        prefix="iot-archive",
        domain_short_name="demo",
        zone="bronze",
        dataset="raw",
        run_id="run-123",
        run_at=run_at,
    )

    assert object_prefix == (
        "iot-archive/domain=demo/zone=bronze/dataset=raw/"
        "year=2026/month=04/day=08/hour=12/run_id=run-123"
    )
