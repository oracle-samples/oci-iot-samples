from archive_domain.db import choose_execution_mode


def test_choose_execution_mode_uses_sql_when_bulk_mode_is_unavailable():
    mode = choose_execution_mode(
        requested_mode="bulk",
        dbms_cloud_available=False,
        has_db_export_credentials=True,
    )

    assert mode == "sql"


def test_choose_execution_mode_retains_bulk_when_prerequisites_exist():
    mode = choose_execution_mode(
        requested_mode="bulk",
        dbms_cloud_available=True,
        has_db_export_credentials=True,
    )

    assert mode == "bulk"
