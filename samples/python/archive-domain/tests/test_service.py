from datetime import datetime, timezone
from pathlib import Path

import pytest

from archive_domain.config import (
    ArchiveConfig,
    DatabaseConfig,
    IotConfig,
    ObjectStorageConfig,
    load_config,
)
from archive_domain.models import CheckpointState
from archive_domain.service import ArchiveService


class _StaticRetentionLookup:
    def get_retention_days(self):
        return {"raw": 16, "historized": 30, "rejected": 16}


class _MemoryStateStore:
    def __init__(self):
        self.objects = {}
        self.saved_checkpoints = []

    def load_checkpoint(self, _object_name):
        return CheckpointState()

    def put_json_object(self, object_name, payload):
        self.objects[object_name] = payload

    def save_checkpoint(self, object_name, checkpoint):
        self.saved_checkpoints.append((object_name, checkpoint))


class _FailingExecutor:
    def execute_dataset(self, **_kwargs):
        raise RuntimeError("simulated export failure")


def _build_config(export_format: str = "parquet"):
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


def _build_plan_service(config):
    return ArchiveService(
        config=config,
        retention_lookup=_StaticRetentionLookup(),
    )


def test_run_records_failed_dataset_and_writes_manifest_without_advancing_checkpoint():
    state_store = _MemoryStateStore()
    service = ArchiveService(
        config=_build_config(),
        retention_lookup=_StaticRetentionLookup(),
        state_store=state_store,
        executor=_FailingExecutor(),
        clock=lambda: datetime(2026, 4, 8, 12, 0, tzinfo=timezone.utc),
    )

    result = service.run(datasets="raw")

    assert result.checkpoint_advanced is False
    assert result.dataset_results[0].name == "raw"
    assert result.dataset_results[0].status == "failed"
    assert result.dataset_results[0].error_message == "simulated export failure"
    assert result.manifest_object_name in state_store.objects
    assert state_store.saved_checkpoints == []


def test_load_config_reads_run_level_export_format(tmp_path):
    config_path = tmp_path / "archive_config.yaml"
    config_path.write_text(
        """
export_format: parquet
iot:
  domain_id: ocid1.iotdomain.oc1..exampleuniqueID
  retention_days:
    raw: 16
  bootstrap_lookback_days: 1
database:
  connect_string: "tcps:adb.example.com:1522/archive_high"
  token_scope: "urn:oracle:db::id::*"
  iot_domain_short_name: sample
  auth_type: SecurityToken
  profile: DEFAULT
  thick_mode: false
  lib_dir: null
  dbms_cloud_credential_name: ARCHIVE_CRED
object_storage:
  namespace: sample-ns
  bucket_name: archive-bucket
  prefix: archive-root
  manifest_prefix: _manifests
  checkpoint_object: _state/checkpoint.json
""".strip(),
        encoding="utf-8",
    )

    config = load_config(config_path)

    assert config.export_format == "parquet"


def test_distributed_config_template_defaults_to_parquet():
    template = (
        Path(__file__).resolve().parents[1] / "data" / "archive_config.distr.yaml"
    ).read_text(encoding="utf-8")

    assert "export_format: parquet" in template


def test_run_rejects_datapump_when_feature_flag_disabled(monkeypatch):
    monkeypatch.delenv("ARCHIVE_DOMAIN_DATAPUMP_ENABLED", raising=False)
    service = _build_plan_service(_build_config(export_format="datapump"))

    with pytest.raises(ValueError, match="datapump export format is not enabled"):
        service.run(datasets="raw", dry_run=True)


def test_plan_rejects_multiple_datasets_for_datapump(monkeypatch):
    monkeypatch.setenv("ARCHIVE_DOMAIN_DATAPUMP_ENABLED", "true")
    service = _build_plan_service(_build_config(export_format="datapump"))

    with pytest.raises(
        ValueError,
        match="datapump export format requires selecting exactly one dataset",
    ):
        service.plan(datasets="raw,historized")


def test_plan_rejects_empty_normalized_dataset_selection():
    service = _build_plan_service(_build_config(export_format="parquet"))

    with pytest.raises(ValueError, match="Dataset list cannot be empty"):
        service.plan(datasets=" , , ")


def test_plan_allows_multiple_datasets_for_parquet(monkeypatch):
    monkeypatch.delenv("ARCHIVE_DOMAIN_DATAPUMP_ENABLED", raising=False)
    service = ArchiveService(
        config=_build_config(export_format="parquet"),
        retention_lookup=_StaticRetentionLookup(),
        clock=lambda: datetime(2026, 4, 8, 12, 0, tzinfo=timezone.utc),
    )

    result = service.plan(datasets="raw,historized")

    assert result.export_format == "parquet"
    assert result.plan.selected_datasets == ("raw", "historized")


def test_run_does_not_advance_checkpoint_for_empty_status_map():
    state_store = _MemoryStateStore()
    service = ArchiveService(
        config=_build_config(export_format="parquet"),
        retention_lookup=_StaticRetentionLookup(),
        state_store=state_store,
        executor=_FailingExecutor(),
        clock=lambda: datetime(2026, 4, 8, 12, 0, tzinfo=timezone.utc),
    )

    with pytest.raises(ValueError, match="Dataset list cannot be empty"):
        service.run(datasets=" , , ")

    assert state_store.saved_checkpoints == []
