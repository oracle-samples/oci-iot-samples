import importlib.util
from pathlib import Path


def _load_sql_config_module():
    module_path = (
        Path(__file__).resolve().parents[3]
        / "sql"
        / "archive-domain"
        / "load_config.py"
    )
    spec = importlib.util.spec_from_file_location(
        "archive_sql_load_config", module_path
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class _FakeCursor:
    def __init__(self):
        self.statements = []

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb):
        return False

    def execute(self, statement, **binds):
        self.statements.append((statement, binds))


class _FakeConnection:
    def __init__(self):
        self.cursor_obj = _FakeCursor()
        self.committed = False

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb):
        return False

    def cursor(self):
        return self.cursor_obj

    def commit(self):
        self.committed = True


def test_sql_load_config_commits_successful_upsert(tmp_path, monkeypatch):
    module = _load_sql_config_module()
    config_path = tmp_path / "archive_config.json"
    config_path.write_text('{"export_format":"parquet"}', encoding="utf-8")
    connection = _FakeConnection()

    monkeypatch.setattr(module, "connect", lambda _args: connection)
    monkeypatch.setattr(
        module,
        "parse_args",
        lambda: module.argparse.Namespace(
            config_file=config_path,
            config_name="default",
            proxy_user="KBCB5B66BKIW6__WKSP",
            connect_string="tcps:adb.example.com:1521/service",
            token_scope="urn:oracle:db::id::*",
            auth_type="InstancePrincipal",
            profile="DEFAULT",
        ),
    )

    module.main()

    assert connection.committed is True
