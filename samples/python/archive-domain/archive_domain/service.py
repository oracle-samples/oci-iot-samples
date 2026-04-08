"""Service layer for archive-domain."""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from .config import load_config
from .executor import LiveArchiveExecutor
from .exporters import dataset_zone, export_format_for_dataset
from .iot_domain import IotDomainLookup, resolve_retention_days
from .manifest import build_run_manifest
from .models import CheckpointState, DatasetResult, PlanResult, RunResult
from .object_storage import (
    ObjectStorageStateStore,
    build_dataset_object_prefix,
    build_manifest_object_name,
    should_advance_checkpoint,
)
from .oci_utils import (
    build_iot_client,
    build_object_storage_client,
    get_oci_config,
    resolve_region,
)
from .planner import build_archive_plan, parse_datasets


class NullRetentionLookup:
    """Fallback retention lookup that returns no live values."""

    def get_retention_days(self) -> dict[str, int]:
        """Return no live retention values."""
        return {}


class ArchiveService:
    """High-level archive planning and execution orchestration."""

    def __init__(
        self,
        config,
        retention_lookup: Any | None = None,
        state_store: Any | None = None,
        executor: Any | None = None,
        clock: Any | None = None,
    ):
        """Store configuration and runtime collaborators for archive work."""
        self.config = config
        self.retention_lookup = retention_lookup or NullRetentionLookup()
        self.state_store = state_store
        self.executor = executor
        self.clock = clock or (lambda: datetime.now(timezone.utc).replace(microsecond=0))

    def _load_checkpoint(self) -> CheckpointState:
        if self.state_store is None:
            return CheckpointState()
        return self.state_store.load_checkpoint(
            self.config.object_storage.checkpoint_object
        )

    def plan(
        self,
        datasets: str | None = None,
        start_time: datetime | None = None,
        end_time: datetime | None = None,
    ) -> PlanResult:
        """Compute the archive plan for the selected datasets."""
        selected_datasets = parse_datasets(datasets)
        checkpoint = self._load_checkpoint()
        retention_days = resolve_retention_days(
            lookup_client=self.retention_lookup,
            configured_overrides=self.config.iot.retention_days,
            required_datasets=selected_datasets,
        )
        plan = build_archive_plan(
            selected_datasets=list(selected_datasets),
            retention_days=retention_days,
            now=self.clock(),
            last_successful_run_at=checkpoint.last_successful_run_at,
            bootstrap_lookback_days=self.config.iot.bootstrap_lookback_days,
            explicit_start_time=start_time,
            explicit_end_time=end_time,
        )
        return PlanResult(
            plan=plan,
            retention_days=retention_days,
            checkpoint=checkpoint,
        )

    def run(
        self,
        datasets: str | None = None,
        mode: str = "bulk",
        dry_run: bool = False,
        start_time: datetime | None = None,
        end_time: datetime | None = None,
    ) -> RunResult:
        """Run or simulate the archive flow."""
        plan_result = self.plan(
            datasets=datasets, start_time=start_time, end_time=end_time
        )
        run_at = plan_result.plan.now
        run_id = run_at.strftime("%Y%m%dT%H%M%SZ")
        dataset_results = []

        for dataset in plan_result.plan.selected_datasets:
            object_prefix = build_dataset_object_prefix(
                prefix=self.config.object_storage.prefix,
                domain_short_name=self.config.database.iot_domain_short_name,
                zone=dataset_zone(dataset),
                dataset=dataset,
                run_id=run_id,
                run_at=run_at,
            )

            if dry_run:
                dataset_results.append(
                    DatasetResult(
                        name=dataset,
                        status="planned",
                        export_mode=mode,
                        export_format=export_format_for_dataset(dataset),
                        object_prefix=object_prefix,
                    )
                )
                continue

            if self.executor is None:
                raise RuntimeError(
                    "No archive executor is configured. Use --dry-run or provide a runtime executor."
                )

            dataset_results.append(
                self.executor.execute_dataset(
                    dataset=dataset,
                    dataset_plan=plan_result.plan.datasets[dataset],
                    mode=mode,
                    object_prefix=object_prefix,
                )
            )

        manifest_object_name = build_manifest_object_name(
            self.config.object_storage.manifest_prefix, run_id
        )
        manifest = build_run_manifest(
            run_id=run_id,
            selected_datasets=plan_result.plan.selected_datasets,
            retention_days=plan_result.retention_days,
            checkpoint_before=(
                plan_result.checkpoint.last_successful_run_at.isoformat().replace(
                    "+00:00", "Z"
                )
                if plan_result.checkpoint.last_successful_run_at is not None
                else None
            ),
            dataset_results=list(dataset_results),
        )

        checkpoint_advanced = False
        if not dry_run:
            statuses = {result.name: result.status for result in dataset_results}
            checkpoint_advanced = should_advance_checkpoint(statuses)
            if self.state_store is not None:
                self.state_store.put_json_object(manifest_object_name, manifest)
                if checkpoint_advanced:
                    self.state_store.save_checkpoint(
                        self.config.object_storage.checkpoint_object,
                        CheckpointState(last_successful_run_at=run_at),
                    )

        return RunResult(
            run_id=run_id,
            mode=mode,
            plan_result=plan_result,
            dataset_results=tuple(dataset_results),
            checkpoint_advanced=checkpoint_advanced,
            manifest_object_name=manifest_object_name,
        )


def build_service(config_path: str, profile: str | None = None, auth: str | None = None):
    """Build the archive service from configuration."""
    config = load_config(config_path)
    oci_config, signer = get_oci_config(
        profile=profile or "DEFAULT", auth=auth or "api_key"
    )
    iot_client = build_iot_client(oci_config, signer)
    object_storage_client = build_object_storage_client(oci_config, signer)

    namespace = config.object_storage.namespace
    if namespace is None:
        namespace = object_storage_client.get_namespace().data

    state_store = ObjectStorageStateStore(
        client=object_storage_client,
        namespace=namespace,
        bucket_name=config.object_storage.bucket_name,
    )
    executor = LiveArchiveExecutor(
        config=config,
        object_storage_client=object_storage_client,
        namespace=namespace,
        region=resolve_region(oci_config),
    )
    return ArchiveService(
        config=config,
        retention_lookup=IotDomainLookup(iot_client, config.iot.domain_id),
        state_store=state_store,
        executor=executor,
    )
