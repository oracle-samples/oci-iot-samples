from click.testing import CliRunner

from archive_domain.cli import cli


def test_cli_lists_plan_and_run_commands():
    runner = CliRunner()

    result = runner.invoke(cli, ["--help"])

    assert result.exit_code == 0
    assert "plan" in result.output
    assert "run" in result.output
