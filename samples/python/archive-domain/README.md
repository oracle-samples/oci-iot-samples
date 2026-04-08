# Archive IoT Domain Data To Object Storage

Sample Python application to plan and run whole-domain archival for OCI IoT
telemetry that is approaching retention-based purge windows.

The sample is intentionally separate from `manage-dt` because it focuses on:

- domain-wide archival rather than single Digital Twins
- direct database access rather than ORDS
- Object Storage manifests and checkpoints

The CLI currently exposes two commands:

- `archive-domain plan`
- `archive-domain run`

The implementation supports three datasets:

- `raw`
- `historized`
- `rejected`

The sample supports two execution modes:

- `bulk`: database-side export using `DBMS_CLOUD.EXPORT_DATA`
- `sql`: SQL-based fallback when bulk export is unavailable

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

