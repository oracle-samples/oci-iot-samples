# Archive IoT Domain Data To Object Storage

Sample Python application to plan and run whole-domain archival for OCI IoT
Domain data.

For shared archive-domain background, including the plan/run workflow,
datasets, retention-based archive windows, Object Storage layout, and bucket
access guidance, see [Shared Concepts](../../sql/archive-domain/README.md#shared-concepts)
in the SQL sample README. This README focuses on Python-specific install,
configuration, and execution details.

The CLI currently exposes two commands:

- `archive-domain plan`
- `archive-domain run`

The Python implementation supports the same three datasets:

- `raw`
- `historized`
- `rejected`

The sample supports two execution modes:

- `bulk`: database-side export using `DBMS_CLOUD.EXPORT_DATA`
- `sql`: SQL-based fallback when bulk export is unavailable, writing `jsonl.gz`
  objects to Object Storage

## Install

```sh
python3 -m venv venv
source venv/bin/activate
python -m pip install --upgrade pip
pip install .
```

## Configure

Copy `data/archive_config.distr.yaml` to `data/archive_config.yaml` and fill in
your IoT Domain, direct database, and Object Storage values.

## Usage

```sh
archive-domain --help
archive-domain plan --datasets raw,historized,rejected
archive-domain run --datasets raw,historized --dry-run
```
