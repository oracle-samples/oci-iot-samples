"""SQL builders for archive-domain.

Copyright (c) 2026 Oracle and/or its affiliates.
Licensed under the Universal Permissive License v 1.0 as shown at
https://oss.oracle.com/licenses/upl

DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone

from .models import EXPORT_FORMAT_DATAPUMP, EXPORT_FORMAT_PARQUET, VALID_EXPORT_FORMATS


@dataclass(frozen=True)
class DatasetQuery:
    """A query and its bind values."""

    dataset: str
    sql_text: str
    binds: dict[str, datetime]
    time_column: str


def dataset_time_column(dataset: str) -> str:
    """Return the purge-relevant time column for a dataset."""
    if dataset == "historized":
        return "time_observed"
    return "time_received"


def _normalized_content_type_sql() -> str:
    return "lower(trim(regexp_substr(content_type, '^[^;]+')))"


def _json_candidate_sql() -> str:
    return "to_clob(utl_raw.cast_to_varchar2(dbms_lob.substr(content, 32767, 1)))"


def _content_encoding_sql() -> str:
    content_type_expr = _normalized_content_type_sql()
    json_candidate_expr = _json_candidate_sql()
    return (
        "case "
        f"when {content_type_expr} like 'text/%' then 'text' "
        f"when {content_type_expr} is null or instr({content_type_expr}, 'json') > 0 then "
        f"  case when {json_candidate_expr} is json strict then 'json' else 'base64' end "
        "else 'base64' "
        "end"
    )


def _content_representation_sql() -> str:
    content_type_expr = _normalized_content_type_sql()
    json_candidate_expr = _json_candidate_sql()
    return (
        "case "
        f"when {content_type_expr} like 'text/%' then 'json-string' "
        f"when {content_type_expr} is null or instr({content_type_expr}, 'json') > 0 then "
        f"  case when {json_candidate_expr} is json strict then 'parsed-json' else 'base64-string' end "
        "else 'base64-string' "
        "end"
    )


def build_dataset_query(
    dataset: str,
    window_start: datetime,
    window_end: datetime,
    domain_short_name: str | None = None,
    export_format: str = EXPORT_FORMAT_PARQUET,
) -> DatasetQuery:
    """Build the dataset-specific SQL query."""
    normalized_export_format = export_format.lower()
    if normalized_export_format not in VALID_EXPORT_FORMATS:
        raise ValueError(f"Unsupported export format: {export_format}")

    if dataset == "raw" and normalized_export_format == EXPORT_FORMAT_PARQUET:
        content_encoding_expr = _content_encoding_sql()
        content_representation_expr = _content_representation_sql()
        blob_to_json_expr = _blob_to_json_expr()
        sql_text = """
            select
                id,
                digital_twin_instance_id,
                endpoint,
                time_received,
                content_type,
                {content_encoding_expr} as content_encoding,
                {content_representation_expr} as content_representation,
                {blob_to_json_expr} as content
            from raw_data
            where time_received >= :window_start
              and time_received < :window_end
            order by time_received, id
        """.strip().format(
            content_encoding_expr=content_encoding_expr,
            content_representation_expr=content_representation_expr,
            blob_to_json_expr=blob_to_json_expr,
        )
        time_column = "time_received"
    elif dataset == "raw" and normalized_export_format == EXPORT_FORMAT_DATAPUMP:
        sql_text = """
            select *
            from raw_data
            where time_received >= :window_start
              and time_received < :window_end
            order by time_received, id
        """.strip()
        time_column = "time_received"
    elif dataset == "historized" and normalized_export_format == EXPORT_FORMAT_PARQUET:
        sql_text = """
            select
                id,
                digital_twin_instance_id,
                content_path,
                time_observed,
                json_serialize(value returning varchar2(32767)) as value_json,
                json_value(value, '$' returning number null on error) as value_number,
                json_value(value, '$' returning varchar2(32767) null on error) as value_text
            from historized_data
            where time_observed >= :window_start
              and time_observed < :window_end
            order by time_observed, id
        """.strip()
        time_column = "time_observed"
    elif dataset == "historized" and normalized_export_format == EXPORT_FORMAT_DATAPUMP:
        sql_text = """
            select *
            from historized_data
            where time_observed >= :window_start
              and time_observed < :window_end
            order by time_observed, id
        """.strip()
        time_column = "time_observed"
    elif dataset == "rejected" and normalized_export_format == EXPORT_FORMAT_PARQUET:
        content_encoding_expr = _content_encoding_sql()
        content_representation_expr = _content_representation_sql()
        blob_to_json_expr = _blob_to_json_expr()
        sql_text = """
            select
                id,
                digital_twin_instance_id,
                endpoint,
                time_received,
                reason_code,
                reason_message,
                content_type,
                {content_encoding_expr} as content_encoding,
                {content_representation_expr} as content_representation,
                {blob_to_json_expr} as content
            from rejected_data
            where time_received >= :window_start
              and time_received < :window_end
            order by time_received, id
        """.strip().format(
            content_encoding_expr=content_encoding_expr,
            content_representation_expr=content_representation_expr,
            blob_to_json_expr=blob_to_json_expr,
        )
        time_column = "time_received"
    elif dataset == "rejected" and normalized_export_format == EXPORT_FORMAT_DATAPUMP:
        sql_text = """
            select *
            from rejected_data
            where time_received >= :window_start
              and time_received < :window_end
            order by time_received, id
        """.strip()
        time_column = "time_received"
    else:
        raise ValueError(
            f"Unsupported dataset/export_format combination: {dataset}/{export_format}"
        )

    return DatasetQuery(
        dataset=dataset,
        sql_text=sql_text,
        binds={"window_start": window_start, "window_end": window_end},
        time_column=time_column,
    )


def _blob_to_json_expr() -> str:
    return "blob_to_json(content, content_type)"


def build_dbms_cloud_export_statement(
    dataset_query: DatasetQuery,
    credential_name: str,
    file_uri_list: str,
    export_format: str,
) -> tuple[str, dict[str, str | datetime]]:
    """Build the PL/SQL block for DBMS_CLOUD.EXPORT_DATA."""
    statement = """
        begin
          dbms_cloud.export_data(
            credential_name => :credential_name,
            file_uri_list   => :file_uri_list,
            format          => json_object('type' value :export_format),
            query           => :query_text
          );
        end;
    """.strip()
    binds: dict[str, str | datetime] = {
        "credential_name": credential_name,
        "file_uri_list": file_uri_list,
        "export_format": export_format,
        "query_text": _render_dbms_cloud_query_text(dataset_query),
    }
    return statement, binds


def _render_dbms_cloud_query_text(dataset_query: DatasetQuery) -> str:
    """Inline timestamp literals because DBMS_CLOUD receives the query as a string."""
    query_text = dataset_query.sql_text
    for bind_name, bind_value in dataset_query.binds.items():
        query_text = query_text.replace(
            f":{bind_name}", _oracle_timestamp_tz_literal(bind_value)
        )
    return query_text


def _oracle_timestamp_tz_literal(value: datetime) -> str:
    """Render a timezone-aware datetime as an Oracle TIMESTAMP WITH TIME ZONE literal."""
    if value.tzinfo is None:
        raise ValueError("Timezone-aware timestamps are required for archive queries")

    normalized = value.astimezone(timezone.utc).isoformat(timespec="microseconds")
    return (
        "to_timestamp_tz("
        f"'{normalized}', "
        "'YYYY-MM-DD\"T\"HH24:MI:SS.FF6TZH:TZM'"
        ")"
    )
