"""Runtime executor for archive-domain."""

from __future__ import annotations

import base64
import decimal
import gzip
import io
import json
from datetime import date, datetime, timezone
from typing import Any

from .db import choose_execution_mode, connect, execute_statement, set_current_schema
from .exporters import build_bulk_export_request, export_format_for_dataset
from .models import DatasetResult
from .object_storage import build_dbms_cloud_file_uri, build_object_name
from .sql import build_dataset_query


def _normalize_value(value: Any) -> Any:
    if hasattr(value, "read"):
        value = value.read()

    if isinstance(value, bytes):
        return {
            "encoding": "base64",
            "data": base64.b64encode(value).decode("ascii"),
        }
    if isinstance(value, datetime):
        return value.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")
    if isinstance(value, date):
        return value.isoformat()
    if isinstance(value, decimal.Decimal):
        return str(value)
    if isinstance(value, dict):
        return {key: _normalize_value(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [_normalize_value(item) for item in value]
    return value


class LiveArchiveExecutor:
    """Execute dataset archives using direct DB and Object Storage clients."""

    def __init__(
        self,
        config,
        object_storage_client: Any,
        namespace: str,
        region: str | None,
    ):
        """Store runtime dependencies for live archive execution."""
        self.config = config
        self.object_storage_client = object_storage_client
        self.namespace = namespace
        self.region = region

    def execute_dataset(
        self,
        dataset,
        dataset_plan,
        mode,
        object_prefix,
        export_format,
    ) -> DatasetResult:
        """Execute archive export for one dataset."""
        actual_mode = choose_execution_mode(
            requested_mode=mode,
            dbms_cloud_available=bool(
                self.region and self.config.database.dbms_cloud_credential_name
            ),
            has_db_export_credentials=bool(
                self.config.database.dbms_cloud_credential_name
            ),
        )
        if actual_mode == "sql":
            raise RuntimeError(
                f"sql mode does not support configured export_format {export_format}"
            )
        if actual_mode == "bulk":
            return self._execute_bulk(
                dataset, dataset_plan, object_prefix, export_format
            )
        return self._execute_sql(dataset, dataset_plan, object_prefix, export_format)

    def _execute_bulk(
        self, dataset, dataset_plan, object_prefix, export_format
    ) -> DatasetResult:
        file_uri_list = build_dbms_cloud_file_uri(
            region=self.region,
            namespace=self.namespace,
            bucket_name=self.config.object_storage.bucket_name,
            object_prefix=object_prefix,
            basename=dataset,
        )
        dataset_query, statement, binds = build_bulk_export_request(
            dataset=dataset,
            window_start=dataset_plan.window_start,
            window_end=dataset_plan.window_end,
            credential_name=self.config.database.dbms_cloud_credential_name,
            file_uri_list=file_uri_list,
            domain_short_name=self.config.database.iot_domain_short_name,
            export_format=export_format,
        )

        with connect(self.config.database) as connection:
            set_current_schema(connection, self.config.database.iot_domain_short_name)
            with connection.cursor() as cursor:
                execute_statement(cursor, statement, binds)

        return DatasetResult(
            name=dataset,
            status="succeeded",
            export_mode="bulk",
            export_format=export_format_for_dataset(dataset, export_format),
            object_prefix=object_prefix,
        )

    def _execute_sql(
        self, dataset, dataset_plan, object_prefix, export_format
    ) -> DatasetResult:
        dataset_query = build_dataset_query(
            dataset,
            dataset_plan.window_start,
            dataset_plan.window_end,
            domain_short_name=self.config.database.iot_domain_short_name,
            export_format=export_format,
        )

        buffer = io.BytesIO()
        with connect(self.config.database) as connection:
            set_current_schema(connection, self.config.database.iot_domain_short_name)
            with connection.cursor() as cursor:
                cursor.execute(dataset_query.sql_text, dataset_query.binds)
                columns = [column[0].lower() for column in cursor.description]

                with gzip.GzipFile(fileobj=buffer, mode="wb") as gzip_file:
                    for row in cursor:
                        record = {
                            column: _normalize_value(value)
                            for column, value in zip(columns, row)
                        }
                        gzip_file.write(
                            json.dumps(record, sort_keys=True).encode("utf-8")
                        )
                        gzip_file.write(b"\n")

        object_name = build_object_name(object_prefix, "part-00000.jsonl.gz")
        self.object_storage_client.put_object(
            namespace_name=self.namespace,
            bucket_name=self.config.object_storage.bucket_name,
            object_name=object_name,
            put_object_body=buffer.getvalue(),
        )

        return DatasetResult(
            name=dataset,
            status="succeeded",
            export_mode="sql",
            export_format=export_format,
            object_prefix=object_prefix,
            object_names=(object_name,),
        )
