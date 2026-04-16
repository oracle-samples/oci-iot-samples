from datetime import datetime, timezone

from archive_domain.exporters import (
    build_bulk_export_request,
    export_format_for_dataset,
)
from archive_domain.sql import build_dataset_query


def test_export_format_for_dataset_uses_configured_run_format():
    assert export_format_for_dataset("raw", "parquet") == "parquet"
    assert export_format_for_dataset("rejected", "parquet") == "parquet"
    assert export_format_for_dataset("historized", "datapump") == "datapump"


def test_parquet_raw_and_rejected_queries_project_blob_content_as_json():
    window_start = datetime(2026, 4, 1, 0, 0, tzinfo=timezone.utc)
    window_end = datetime(2026, 4, 2, 0, 0, tzinfo=timezone.utc)

    raw_query = build_dataset_query(
        "raw", window_start, window_end, export_format="parquet"
    )
    rejected_query = build_dataset_query(
        "rejected", window_start, window_end, export_format="parquet"
    )

    assert "content_type" in raw_query.sql_text
    assert (
        "ords_utils.blobToJson(content, content_type) as content" in raw_query.sql_text
    )
    assert "time_received >= :window_start" in raw_query.sql_text
    assert "time_received < :window_end" in raw_query.sql_text

    assert "reason_code" in rejected_query.sql_text
    assert "reason_message" in rejected_query.sql_text
    assert (
        "ords_utils.blobToJson(content, content_type) as content"
        in rejected_query.sql_text
    )


def test_datapump_raw_and_rejected_queries_preserve_table_rows():
    window_start = datetime(2026, 4, 1, 0, 0, tzinfo=timezone.utc)
    window_end = datetime(2026, 4, 2, 0, 0, tzinfo=timezone.utc)

    raw_query = build_dataset_query(
        "raw", window_start, window_end, export_format="datapump"
    )
    rejected_query = build_dataset_query(
        "rejected", window_start, window_end, export_format="datapump"
    )

    assert raw_query.sql_text.startswith("select *")
    assert "from raw_data" in raw_query.sql_text
    assert "blobToJson" not in raw_query.sql_text

    assert rejected_query.sql_text.startswith("select *")
    assert "from rejected_data" in rejected_query.sql_text
    assert "blobToJson" not in rejected_query.sql_text


def test_parquet_historized_query_remains_explicit_and_json_friendly():
    window_start = datetime(2026, 4, 1, 0, 0, tzinfo=timezone.utc)
    window_end = datetime(2026, 4, 2, 0, 0, tzinfo=timezone.utc)

    historized_query = build_dataset_query(
        "historized", window_start, window_end, export_format="parquet"
    )

    assert historized_query.sql_text.startswith("select")
    assert (
        "json_serialize(value returning varchar2(32767)) as value_json"
        in historized_query.sql_text
    )
    assert "from historized_data" in historized_query.sql_text
    assert "time_observed >= :window_start" in historized_query.sql_text
    assert "time_observed < :window_end" in historized_query.sql_text


def test_bulk_export_request_inlines_window_literals_for_dbms_cloud():
    window_start = datetime(2026, 4, 1, 0, 0, tzinfo=timezone.utc)
    window_end = datetime(2026, 4, 2, 0, 0, tzinfo=timezone.utc)

    _query, _statement, binds = build_bulk_export_request(
        dataset="raw",
        window_start=window_start,
        window_end=window_end,
        credential_name="archive_credential",
        file_uri_list="https://object.example/exports/raw",
        export_format="parquet",
    )

    assert set(binds) == {
        "credential_name",
        "export_format",
        "file_uri_list",
        "query_text",
    }
    assert binds["export_format"] == "parquet"
    assert ":window_start" not in binds["query_text"]
    assert ":window_end" not in binds["query_text"]
    assert "to_timestamp_tz('2026-04-01T00:00:00.000000+00:00'" in binds["query_text"]
    assert "to_timestamp_tz('2026-04-02T00:00:00.000000+00:00'" in binds["query_text"]
    assert (
        "ords_utils.blobToJson(content, content_type) as content" in binds["query_text"]
    )
