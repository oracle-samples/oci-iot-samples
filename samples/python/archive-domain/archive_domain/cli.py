"""CLI for the archive-domain sample."""

import click


@click.group()
def cli():
    """Archive IoT Domain telemetry."""


@cli.command()
def plan():
    """Plan archive work."""


@cli.command()
def run():
    """Run archive work."""

