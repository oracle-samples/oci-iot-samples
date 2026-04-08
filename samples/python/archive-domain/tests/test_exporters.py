from datetime import datetime, timezone

from archive_domain.exporters import export_format_for_dataset
from archive_domain.sql import build_dataset_query


def test_export_format_for_dataset_uses_mixed_strategy():
    assert export_format_for_dataset("raw") == "datapump"
    assert export_format_for_dataset("rejected") == "datapump"
    assert export_format_for_dataset("historized") == "parquet"


def test_dataset_queries_use_the_expected_time_column():
    window_start = datetime(2026, 4, 1, 0, 0, tzinfo=timezone.utc)
    window_end = datetime(2026, 4, 2, 0, 0, tzinfo=timezone.utc)

    raw_query = build_dataset_query("raw", window_start, window_end)
    historized_query = build_dataset_query("historized", window_start, window_end)

    assert "time_received >= :window_start" in raw_query.sql_text
    assert "time_received < :window_end" in raw_query.sql_text
    assert "time_observed >= :window_start" in historized_query.sql_text
    assert "time_observed < :window_end" in historized_query.sql_text
