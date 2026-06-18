from datetime import datetime, timedelta, timezone

import pytest

from archive_domain.planner import build_archive_plan, parse_datasets


def test_build_archive_plan_computes_newly_at_risk_window_per_dataset():
    now = datetime(2026, 4, 8, 12, 0, tzinfo=timezone.utc)
    last_success = now - timedelta(days=1)

    plan = build_archive_plan(
        selected_datasets=["raw", "historized"],
        retention_days={"raw": 16, "historized": 30},
        now=now,
        last_successful_run_at=last_success,
    )

    assert plan.datasets["raw"].window_end == now - timedelta(days=16)
    assert plan.datasets["raw"].window_start == last_success - timedelta(days=16)
    assert plan.datasets["historized"].window_end == now - timedelta(days=30)
    assert plan.datasets["historized"].window_start == last_success - timedelta(days=30)


def test_build_archive_plan_uses_bootstrap_lookback_for_first_run():
    now = datetime(2026, 4, 8, 12, 0, tzinfo=timezone.utc)

    plan = build_archive_plan(
        selected_datasets=["raw"],
        retention_days={"raw": 16},
        now=now,
        bootstrap_lookback_days=2,
    )

    assert plan.datasets["raw"].window_end == now - timedelta(days=16)
    assert plan.datasets["raw"].window_start == now - timedelta(days=18)


def test_parse_datasets_normalizes_and_validates_values():
    assert parse_datasets("rejected, raw ,historized") == (
        "raw",
        "historized",
        "rejected",
    )

    with pytest.raises(ValueError, match="Unknown datasets"):
        parse_datasets("raw,unknown")
