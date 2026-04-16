from datetime import datetime, timezone

from click.testing import CliRunner

from archive_domain.cli import cli
from archive_domain.models import (
    ArchivePlan,
    CheckpointState,
    DatasetPlan,
    DatasetResult,
    PlanResult,
    RunResult,
)


class _FakeService:
    def __init__(self):
        now = datetime(2026, 4, 8, 12, 0, tzinfo=timezone.utc)
        datasets = {
            "raw": DatasetPlan(
                name="raw",
                retention_days=16,
                purge_boundary=datetime(2026, 3, 23, 12, 0, tzinfo=timezone.utc),
                window_start=datetime(2026, 3, 22, 12, 0, tzinfo=timezone.utc),
                window_end=datetime(2026, 3, 23, 12, 0, tzinfo=timezone.utc),
            ),
            "historized": DatasetPlan(
                name="historized",
                retention_days=30,
                purge_boundary=datetime(2026, 3, 9, 12, 0, tzinfo=timezone.utc),
                window_start=datetime(2026, 3, 8, 12, 0, tzinfo=timezone.utc),
                window_end=datetime(2026, 3, 9, 12, 0, tzinfo=timezone.utc),
            ),
        }
        self.plan_result = PlanResult(
            plan=ArchivePlan(
                now=now,
                selected_datasets=("raw", "historized"),
                datasets=datasets,
            ),
            export_format="parquet",
            retention_days={"raw": 16, "historized": 30},
            checkpoint=CheckpointState(
                last_successful_run_at=datetime(
                    2026, 4, 7, 12, 0, tzinfo=timezone.utc
                )
            ),
        )
        self.run_result = RunResult(
            run_id="run-123",
            mode="bulk",
            export_format="parquet",
            plan_result=self.plan_result,
            dataset_results=(
                DatasetResult(
                    name="raw",
                    status="planned",
                    export_mode="bulk",
                    export_format="datapump",
                ),
                DatasetResult(
                    name="historized",
                    status="planned",
                    export_mode="bulk",
                    export_format="parquet",
                ),
            ),
            checkpoint_advanced=False,
        )

    def plan(self, **_kwargs):
        return self.plan_result

    def run(self, **_kwargs):
        return self.run_result


def test_plan_command_prints_selected_dataset_windows(monkeypatch):
    runner = CliRunner()

    monkeypatch.setattr(
        "archive_domain.cli.build_service", lambda *_args, **_kwargs: _FakeService()
    )

    result = runner.invoke(cli, ["plan", "--datasets", "raw,historized"])

    assert result.exit_code == 0
    assert "raw" in result.output
    assert "historized" in result.output
    assert "2026-03-22T12:00:00Z" in result.output


def test_run_dry_run_does_not_advance_checkpoint(monkeypatch):
    runner = CliRunner()

    monkeypatch.setattr(
        "archive_domain.cli.build_service", lambda *_args, **_kwargs: _FakeService()
    )

    result = runner.invoke(cli, ["run", "--datasets", "raw,historized", "--dry-run"])

    assert result.exit_code == 0
    assert "Checkpoint advanced: no" in result.output
    assert "raw: planned" in result.output
