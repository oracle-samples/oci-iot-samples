#!/usr/bin/env python3
"""Load archive-domain JSON configuration into archive_domain_config.

Copyright (c) 2026 Oracle and/or its affiliates.
Licensed under the Universal Permissive License v 1.0 as shown at
https://oss.oracle.com/licenses/upl

DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from types import SimpleNamespace

import oracledb
import oracledb.plugins.oci_tokens  # noqa: F401


def build_dsn(connect_string: str) -> str:
    """Convert the IoT DB connect string into an Oracle DSN."""
    match = re.match(r"tcps:(.*):(\d+)/([^?]*)(\?.*)?", connect_string)
    if not match:
        raise ValueError("Invalid connect string")

    hostname, port, service, _ = match.groups()
    return f"""
        (DESCRIPTION =
            (ADDRESS=(PROTOCOL=TCPS)(PORT={port})(HOST={hostname}))
            (CONNECT_DATA=(SERVICE_NAME={service}))
        )"""


def connect(args: argparse.Namespace):
    """Connect to the workspace schema using OCI token-based auth."""
    extra_auth_params = {
        "auth_type": args.auth_type,
        "scope": args.token_scope,
    }
    if args.auth_type == "ConfigFileAuthentication":
        extra_auth_params["profile"] = args.profile

    return oracledb.connect(
        dsn=build_dsn(args.connect_string),
        proxy_user=args.proxy_user,
        extra_auth_params=extra_auth_params,
    )


def load_json_file(path: Path) -> str:
    """Load and validate the JSON config payload."""
    payload = json.loads(path.read_text(encoding="utf-8"))
    return json.dumps(payload, indent=2)


def parse_args() -> argparse.Namespace:
    """Parse CLI arguments."""
    parser = argparse.ArgumentParser(
        description="Load archive-domain JSON config into archive_domain_config."
    )
    parser.add_argument(
        "--config-file",
        required=True,
        type=Path,
        help="Path to archive_config.json.",
    )
    parser.add_argument(
        "--config-name",
        default="default",
        help="Logical config_name value in archive_domain_config.",
    )
    parser.add_argument(
        "--proxy-user",
        required=True,
        help="Workspace proxy user such as KBCB5B66BKIW6__WKSP.",
    )
    parser.add_argument(
        "--connect-string",
        required=True,
        help="IoT DB connect string in tcps:host:port/service form.",
    )
    parser.add_argument(
        "--token-scope",
        required=True,
        help="OCI IAM DB token scope for the IoT domain group.",
    )
    parser.add_argument(
        "--auth-type",
        choices=["InstancePrincipal", "ConfigFileAuthentication"],
        default="InstancePrincipal",
        help="Token-auth mode to use for the database connection.",
    )
    parser.add_argument(
        "--profile",
        default="DEFAULT",
        help="OCI profile used when auth-type is ConfigFileAuthentication.",
    )
    return parser.parse_args()


def main() -> None:
    """Upsert the JSON payload into archive_domain_config."""
    args = parse_args()
    config_json = load_json_file(args.config_file)

    with connect(args) as conn:
        with conn.cursor() as cur:
            cur.execute(
                "delete from archive_domain_config where config_name = :config_name",
                config_name=args.config_name,
            )
            cur.execute(
                """
                insert into archive_domain_config(config_name, config_json)
                values (:config_name, :config_json)
                """,
                config_name=args.config_name,
                config_json=config_json,
            )

    print(f"loaded config '{args.config_name}' from {args.config_file}")


if __name__ == "__main__":
    main()
