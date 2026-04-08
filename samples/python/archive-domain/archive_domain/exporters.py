"""Export strategy helpers for archive-domain."""

from .sql import DatasetQuery, build_dataset_query, build_dbms_cloud_export_statement


def export_format_for_dataset(dataset: str) -> str:
    """Return the export format for a dataset."""
    if dataset in {"raw", "rejected"}:
        return "datapump"
    if dataset == "historized":
        return "parquet"
    raise ValueError(f"Unsupported dataset: {dataset}")


def dataset_zone(dataset: str) -> str:
    """Return the archive zone for a dataset."""
    if dataset in {"raw", "rejected"}:
        return "bronze"
    if dataset == "historized":
        return "silver"
    raise ValueError(f"Unsupported dataset: {dataset}")


def build_bulk_export_request(
    dataset: str,
    window_start,
    window_end,
    credential_name: str,
    file_uri_list: str,
) -> tuple[DatasetQuery, str, dict]:
    """Build the dataset query and DBMS_CLOUD export statement."""
    dataset_query = build_dataset_query(dataset, window_start, window_end)
    statement, binds = build_dbms_cloud_export_statement(
        dataset_query=dataset_query,
        credential_name=credential_name,
        file_uri_list=file_uri_list,
        export_format=export_format_for_dataset(dataset),
    )
    return dataset_query, statement, binds
