from datetime import datetime, timezone

from archive_domain.config import (
    ArchiveConfig,
    DatabaseConfig,
    IotConfig,
    ObjectStorageConfig,
)
from archive_domain.models import CheckpointState
from archive_domain.service import ArchiveService


class _StaticRetentionLookup:
    def get_retention_days(self):
        return {"raw": 16}


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


def _build_config():
    return ArchiveConfig(
        iot=IotConfig(
            domain_id="ocid1.iotdomain.oc1..exampleuniqueID",
            retention_days={"raw": 16},
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
