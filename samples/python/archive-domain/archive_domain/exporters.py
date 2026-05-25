"""Export strategy helpers for archive-domain.

Copyright (c) 2026 Oracle and/or its affiliates.
Licensed under the Universal Permissive License v 1.0 as shown at
https://oss.oracle.com/licenses/upl

DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
"""

from .models import VALID_EXPORT_FORMATS
from .sql import DatasetQuery, build_dataset_query, build_dbms_cloud_export_statement


def export_format_for_dataset(dataset: str, run_export_format: str = "parquet") -> str:
    """Return the configured run format for a dataset."""
    _ = dataset
    export_format = run_export_format.lower()
    if export_format not in VALID_EXPORT_FORMATS:
        raise ValueError(f"Unsupported export format: {run_export_format}")
    return export_format


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
    domain_short_name: str,
    export_format: str = "parquet",
) -> tuple[DatasetQuery, str, dict]:
    """Build the dataset query and DBMS_CLOUD export statement."""
    dataset_query = build_dataset_query(
        dataset,
        window_start,
        window_end,
        domain_short_name=domain_short_name,
        export_format=export_format,
    )
    statement, binds = build_dbms_cloud_export_statement(
        dataset_query=dataset_query,
        credential_name=credential_name,
        file_uri_list=file_uri_list,
        export_format=export_format_for_dataset(dataset, export_format),
    )
    return dataset_query, statement, binds
