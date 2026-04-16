from pathlib import Path


def test_readme_mentions_supported_datasets_and_modes():
    readme = (Path(__file__).resolve().parents[1] / "README.md").read_text()

    assert "raw" in readme
    assert "historized" in readme
    assert "rejected" in readme
    assert "bulk" in readme
    assert "sql" in readme
    assert "parquet" in readme
    assert "DBMS_CLOUD.EXPORT_DATA" in readme
    assert "--dry-run" in readme
