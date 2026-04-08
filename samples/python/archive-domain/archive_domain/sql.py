"""SQL builders for archive-domain."""

from dataclasses import dataclass
from datetime import datetime


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


def build_dataset_query(
    dataset: str, window_start: datetime, window_end: datetime
) -> DatasetQuery:
    """Build the dataset-specific SQL query."""
    if dataset == "raw":
        sql_text = """
            select
                id,
                digital_twin_instance_id,
                endpoint,
                time_received,
                content
            from raw_data
            where time_received >= :window_start
              and time_received < :window_end
            order by time_received, id
        """.strip()
        time_column = "time_received"
    elif dataset == "historized":
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
    elif dataset == "rejected":
        sql_text = """
            select
                id,
                digital_twin_instance_id,
                endpoint,
                time_received,
                reason_code,
                reason_message,
                content
            from rejected_data
            where time_received >= :window_start
              and time_received < :window_end
            order by time_received, id
        """.strip()
        time_column = "time_received"
    else:
        raise ValueError(f"Unsupported dataset: {dataset}")

    return DatasetQuery(
        dataset=dataset,
        sql_text=sql_text,
        binds={"window_start": window_start, "window_end": window_end},
        time_column=time_column,
    )


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
        "query_text": dataset_query.sql_text,
    }
    binds.update(dataset_query.binds)
    return statement, binds

