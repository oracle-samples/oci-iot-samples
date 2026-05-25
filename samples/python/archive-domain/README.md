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

- `bulk`: database-side export using `DBMS_CLOUD.EXPORT_DATA`; with the distributed config, the run-level `export_format` is `parquet`
- `sql`: legacy/internal fallback path; it does not satisfy the public Parquet run format and should fail fast when used with the default config

For Parquet `raw` and `rejected` exports, the sample emits:

- `content`
- `content_type`
- `content_encoding`
- `content_representation`

Consumers should use `content_encoding` and `content_representation` together
with `content_type` to interpret `content` safely.

Expected combinations are:

- `content_encoding = json`, `content_representation = parsed-json`
- `content_encoding = text`, `content_representation = json-string`
- `content_encoding = base64`, `content_representation = base64-string`

Malformed `application/json` payloads fall back to
`base64` / `base64-string`.

## Install

```sh
python3 -m venv venv
source venv/bin/activate
python -m pip install --upgrade pip
pip install .
```

## Configure

Copy `data/archive_config.distr.yaml` to `data/archive_config.yaml` and fill in
your IoT Domain, direct database, and Object Storage values. The distributed
config defaults `export_format` to `parquet`.

## Usage

```sh
archive-domain --help
archive-domain plan --datasets raw,historized,rejected
archive-domain run --datasets raw,historized --dry-run
```
