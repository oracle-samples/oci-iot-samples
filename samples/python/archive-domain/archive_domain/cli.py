"""CLI for the archive-domain sample.

Copyright (c) 2026 Oracle and/or its affiliates.
Licensed under the Universal Permissive License v 1.0 as shown at
https://oss.oracle.com/licenses/upl

DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
"""

from __future__ import annotations

import os
from datetime import datetime, timezone

import click

from .service import build_service


def _format_timestamp(value: datetime | None) -> str:
    if value is None:
        return "none"
    return value.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def _parse_timestamp(_ctx: click.Context, _param: click.Parameter, value: str | None):
    if value is None:
        return None
    normalized = value.replace("Z", "+00:00")
    return datetime.fromisoformat(normalized)


@click.group()
@click.option(
    "--config",
    "config_path",
    default="samples/python/archive-domain/data/archive_config.yaml",
    show_default=True,
    help="Path to the archive-domain YAML config file.",
)
@click.option(
    "--profile",
    default=os.getenv("OCI_CLI_PROFILE", "DEFAULT"),
    show_default=True,
    help="OCI config profile name.",
)
@click.option(
    "--auth",
    type=click.Choice(
        ["api_key", "instance_principal", "resource_principal", "security_token"]
    ),
    default=os.getenv("OCI_CLI_AUTH", "api_key"),
    show_default=True,
    help="OCI authentication type.",
)
@click.pass_context
def cli(ctx: click.Context, config_path: str, profile: str, auth: str):
    """Archive IoT Domain telemetry."""
    ctx.ensure_object(dict)
    ctx.obj["config_path"] = config_path
    ctx.obj["profile"] = profile
    ctx.obj["auth"] = auth


@cli.command()
@click.option(
    "--datasets",
    default="raw,historized,rejected",
    show_default=True,
    help="Comma-separated dataset list.",
)
@click.option(
    "--start-time",
    callback=_parse_timestamp,
    help="Explicit archive window start in ISO-8601 format.",
)
@click.option(
    "--end-time",
    callback=_parse_timestamp,
    help="Explicit archive window end in ISO-8601 format.",
)
@click.pass_context
def plan(
    ctx: click.Context,
    datasets: str,
    start_time: datetime | None,
    end_time: datetime | None,
):
    """Plan archive work."""
    service = build_service(
        ctx.obj["config_path"], profile=ctx.obj["profile"], auth=ctx.obj["auth"]
    )
    plan_result = service.plan(
        datasets=datasets, start_time=start_time, end_time=end_time
    )

    click.echo(
        f"Checkpoint: {_format_timestamp(plan_result.checkpoint.last_successful_run_at)}"
    )
    for dataset in plan_result.plan.selected_datasets:
        dataset_plan = plan_result.plan.datasets[dataset]
        click.echo(
            f"{dataset}: {_format_timestamp(dataset_plan.window_start)} -> "
            f"{_format_timestamp(dataset_plan.window_end)} "
            f"(retention={dataset_plan.retention_days}d)"
        )


@cli.command()
@click.option(
    "--datasets",
    default="raw,historized,rejected",
    show_default=True,
    help="Comma-separated dataset list.",
)
@click.option(
    "--mode",
    type=click.Choice(["bulk", "sql"]),
    default="bulk",
    show_default=True,
    help="Preferred archive execution mode.",
)
@click.option(
    "--dry-run",
    is_flag=True,
    help="Plan and print pending archive actions without exporting data.",
)
@click.option(
    "--start-time",
    callback=_parse_timestamp,
    help="Explicit archive window start in ISO-8601 format.",
)
@click.option(
    "--end-time",
    callback=_parse_timestamp,
    help="Explicit archive window end in ISO-8601 format.",
)
@click.pass_context
def run(
    ctx: click.Context,
    datasets: str,
    mode: str,
    dry_run: bool,
    start_time: datetime | None,
    end_time: datetime | None,
):
    """Run archive work."""
    service = build_service(
        ctx.obj["config_path"], profile=ctx.obj["profile"], auth=ctx.obj["auth"]
    )
    run_result = service.run(
        datasets=datasets,
        mode=mode,
        dry_run=dry_run,
        start_time=start_time,
        end_time=end_time,
    )

    click.echo(f"Run ID: {run_result.run_id}")
    click.echo(f"Mode: {run_result.mode}")
    if dry_run:
        click.echo("Dry run only; no data exported.")
    for dataset_result in run_result.dataset_results:
        click.echo(
            f"{dataset_result.name}: {dataset_result.status} "
            f"({dataset_result.export_mode}, {dataset_result.export_format})"
        )
    click.echo(
        f"Checkpoint advanced: {'yes' if run_result.checkpoint_advanced else 'no'}"
    )
    failed_results = [
        result for result in run_result.dataset_results if result.status == "failed"
    ]
    if failed_results:
        details = "; ".join(
            f"{result.name}: {result.error_message or 'export failed'}"
            for result in failed_results
        )
        raise click.ClickException(f"One or more dataset exports failed: {details}")
