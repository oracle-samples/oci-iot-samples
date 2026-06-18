import json
from datetime import datetime, timezone

import pytest

from archive_domain.object_storage import (
    ObjectStorageStateStore,
    build_dataset_object_prefix,
    should_advance_checkpoint,
)


class _FakeObjectStorageError(Exception):
    def __init__(self, status=None, code=None):
        super().__init__("simulated object storage error")
        self.status = status
        self.code = code


class _FakeGetObjectResponse:
    def __init__(self, payload: str):
        self.data = type("Data", (), {"content": payload.encode("utf-8")})()


class _FakeObjectStorageClient:
    def __init__(self, response=None, exc=None):
        self.response = response
        self.exc = exc

    def get_object(self, **_kwargs):
        if self.exc is not None:
            raise self.exc
        return self.response


def test_checkpoint_advances_only_when_all_selected_datasets_succeed():
    statuses = {"raw": "succeeded", "historized": "failed"}

    assert should_advance_checkpoint(statuses) is False
    assert should_advance_checkpoint({"raw": "succeeded", "historized": "succeeded"})
    assert should_advance_checkpoint({}) is False


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


def test_load_checkpoint_returns_empty_state_only_for_not_found():
    store = ObjectStorageStateStore(
        client=_FakeObjectStorageClient(exc=_FakeObjectStorageError(status=404)),
        namespace="sample-ns",
        bucket_name="archive-bucket",
    )

    checkpoint = store.load_checkpoint("_state/checkpoint.json")

    assert checkpoint.last_successful_run_at is None


def test_load_checkpoint_raises_for_non_not_found_errors():
    store = ObjectStorageStateStore(
        client=_FakeObjectStorageClient(exc=_FakeObjectStorageError(status=500)),
        namespace="sample-ns",
        bucket_name="archive-bucket",
    )

    with pytest.raises(_FakeObjectStorageError):
        store.load_checkpoint("_state/checkpoint.json")


def test_load_checkpoint_raises_for_malformed_json():
    store = ObjectStorageStateStore(
        client=_FakeObjectStorageClient(response=_FakeGetObjectResponse("{not-json}")),
        namespace="sample-ns",
        bucket_name="archive-bucket",
    )

    with pytest.raises(json.JSONDecodeError):
        store.load_checkpoint("_state/checkpoint.json")
