from datetime import datetime, timezone
from types import SimpleNamespace

import pytest

from archive_domain.config import (
    ArchiveConfig,
    DatabaseConfig,
    IotConfig,
    ObjectStorageConfig,
)
from archive_domain.db import choose_execution_mode
from archive_domain.executor import LiveArchiveExecutor
from archive_domain.models import DatasetPlan


def test_choose_execution_mode_uses_sql_when_bulk_mode_is_unavailable():
    mode = choose_execution_mode(
        requested_mode="bulk",
        dbms_cloud_available=False,
        has_db_export_credentials=True,
    )

    assert mode == "sql"


def test_choose_execution_mode_retains_bulk_when_prerequisites_exist():
    mode = choose_execution_mode(
        requested_mode="bulk",
        dbms_cloud_available=True,
        has_db_export_credentials=True,
    )

    assert mode == "bulk"


def _build_config(export_format: str = "parquet") -> ArchiveConfig:
    return ArchiveConfig(
        iot=IotConfig(
            domain_id="ocid1.iotdomain.oc1..exampleuniqueID",
            retention_days={"raw": 16, "historized": 30, "rejected": 16},
            bootstrap_lookback_days=1,
        ),
        database=DatabaseConfig(
            connect_string="tcps:adb.example.com:1522/archive_high",
            token_scope="urn:oracle:db::id::*",
            iot_domain_short_name="sample",
            auth_type="SecurityToken",
            profile="DEFAULT",
            thick_mode=False,
            lib_dir=None,
            dbms_cloud_credential_name="ARCHIVE_CRED",
        ),
        object_storage=ObjectStorageConfig(
            namespace="sample-ns",
            bucket_name="archive-bucket",
            prefix="archive-root",
            manifest_prefix="_manifests",
            checkpoint_object="_state/checkpoint.json",
        ),
        export_format=export_format,
    )


def _build_dataset_plan(
    name: str, retention_days: int, time_column: str
) -> DatasetPlan:
    now = datetime(2026, 4, 8, 12, 0, tzinfo=timezone.utc)
    return DatasetPlan(
        name=name,
        retention_days=retention_days,
        purge_boundary=now,
        window_start=now,
        window_end=now,
    )


class _FakeCursor:
    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb):
        return False


class _FakeConnection:
    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb):
        return False

    def cursor(self):
        return _FakeCursor()


def test_execute_dataset_bulk_uses_parquet_for_bronze_datasets(monkeypatch):
    captured = []

    def fake_build_bulk_export_request(**kwargs):
        captured.append(kwargs)
        return (
            SimpleNamespace(
                dataset=kwargs["dataset"],
                sql_text="select 1 from dual",
                binds={},
                time_column="time_received",
            ),
            "begin null; end;",
            {},
        )

    monkeypatch.setattr(
        "archive_domain.executor.build_bulk_export_request",
        fake_build_bulk_export_request,
    )
    monkeypatch.setattr(
        "archive_domain.executor.connect", lambda _cfg: _FakeConnection()
    )
    monkeypatch.setattr(
        "archive_domain.executor.set_current_schema", lambda *_args, **_kwargs: None
    )
    monkeypatch.setattr(
        "archive_domain.executor.execute_statement", lambda *_args, **_kwargs: None
    )

    executor = LiveArchiveExecutor(
        config=_build_config(export_format="parquet"),
        object_storage_client=SimpleNamespace(),
        namespace="sample-ns",
        region="us-phoenix-1",
    )

    raw_result = executor.execute_dataset(
        dataset="raw",
        dataset_plan=_build_dataset_plan("raw", 16, "time_received"),
        mode="bulk",
        object_prefix="archive-root/raw",
        export_format="parquet",
    )
    rejected_result = executor.execute_dataset(
        dataset="rejected",
        dataset_plan=_build_dataset_plan("rejected", 16, "time_received"),
        mode="bulk",
        object_prefix="archive-root/rejected",
        export_format="parquet",
    )

    assert [item["export_format"] for item in captured] == ["parquet", "parquet"]
    assert raw_result.export_mode == "bulk"
    assert raw_result.export_format == "parquet"
    assert rejected_result.export_mode == "bulk"
    assert rejected_result.export_format == "parquet"


def test_execute_dataset_sql_mode_routes_to_direct_query_for_parquet(monkeypatch):
    executor = LiveArchiveExecutor(
        config=_build_config(export_format="parquet"),
        object_storage_client=SimpleNamespace(),
        namespace="sample-ns",
        region="us-phoenix-1",
    )
    captured = []

    def fake_execute_sql(dataset, dataset_plan, object_prefix, export_format):
        captured.append(
            {
                "dataset": dataset,
                "dataset_plan": dataset_plan,
                "object_prefix": object_prefix,
                "export_format": export_format,
            }
        )
        return SimpleNamespace(
            name=dataset,
            status="succeeded",
            export_mode="sql",
            export_format=export_format,
            object_prefix=object_prefix,
        )

    monkeypatch.setattr(executor, "_execute_sql", fake_execute_sql)

    result = executor.execute_dataset(
        dataset="raw",
        dataset_plan=_build_dataset_plan("raw", 16, "time_received"),
        mode="sql",
        object_prefix="archive-root/raw",
        export_format="parquet",
    )

    assert result.export_mode == "sql"
    assert captured[0]["export_format"] == "parquet"


def test_execute_dataset_sql_mode_rejects_datapump():
    executor = LiveArchiveExecutor(
        config=_build_config(export_format="datapump"),
        object_storage_client=SimpleNamespace(),
        namespace="sample-ns",
        region="us-phoenix-1",
    )

    with pytest.raises(RuntimeError, match="sql mode supports only parquet exports"):
        executor.execute_dataset(
            dataset="raw",
            dataset_plan=_build_dataset_plan("raw", 16, "time_received"),
            mode="sql",
            object_prefix="archive-root/raw",
            export_format="datapump",
        )
