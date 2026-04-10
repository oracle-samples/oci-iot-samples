# Archive IoT Domain Data To Object Storage From SQL

This DB-driven sample lets you plan and run the archive-domain workflow entirely from the database using `archive_domain_pkg.plan` and `archive_domain_pkg.run`. The package lives in the `<DomainShortId>__WKSP` schema, reads configuration from `archive_domain_config`, and writes datasets to Object Storage with `DBMS_CLOUD` APIs.

The current DB-driven format choices are:

- `historized` exports as Parquet
- `raw` exports as Data Pump
- `rejected` exports as Data Pump

That is the current preferred choice. After `DATA_PUMP_DIR` access was enabled for the `__WKSP` execution path, a query-based `DBMS_CLOUD.EXPORT_DATA(... type='datapump' ...)` probe succeeded against `KBCB5B66BKIW6__IOT.RAW_DATA`. That means the DB-driven sample can keep the bronze datasets on a fidelity-preserving Data Pump export path instead of falling back to text encodings.

Non-Data Pump bronze options considered:

- JSONL with `content_base64` and `content_encoding = 'base64'`:
  viable fallback if `DATA_PUMP_DIR` access is unavailable.
- Separate payload-object archive plus metadata sidecar:
  viable, but more moving parts than this sample needs in v1.
- Best-effort text casting of `BLOB` content:
  rejected, because it is not reliably reversible for mixed or binary payloads.

## Prerequisites

- An IoT Domain (for example `ocid1.iotdomain.oc1..example`) and the `__IOT` schema populated with telemetry tables.
- A workspace database user configured to connect with `WKSP_PROXY_USER` (see [samples/script/query-db/README.md](../../script/query-db/README.md) for the connection flow used here).
- A `DBMS_CLOUD` credential that can write to the archive bucket. The sample uses the placeholder name `DOMAIN_ARCHIVE_TEST` (the same name referenced from the sample config). Create it with `DBMS_CLOUD.CREATE_CREDENTIAL` before calling the package routines.
- Object Storage namespace/bucket for checkpoints and manifests. The config row seeds `prefix` values such as `<bucket>/<prefix>` and `_state/checkpoint.json`.

## Install / Teardown

1. From the workspace schema, run:
   ```sh
   sql "jdbc:oracle:thin:[${WKSP_PROXY_USER}]/@${IOT_DB_CONNECT_STRING}&TOKEN_AUTH=OCI_TOKEN" @samples/sql/archive-domain/install.sql
   ```
   This pulls in `archive_domain_tables.sql`, installs `archive_domain_config`, and creates the `archive_domain_pkg`.
2. When you are finished, drop the package and helper tables with:
   ```sh
   sql "jdbc:oracle:thin:[${WKSP_PROXY_USER}]/@${IOT_DB_CONNECT_STRING}&TOKEN_AUTH=OCI_TOKEN" @samples/sql/archive-domain/teardown.sql
   ```

## Configuration

The package reads every runtime setting from `archive_domain_config`:

| Column | Purpose |
| --- | --- |
| `config_name` | Logical identifier, defaults to `default`. |
| `config_json` | JSON payload that points to domain IDs, bucket/namespace/prefix, checkpoint object, DBMS_CLOUD credential name, retention days per dataset, and bootstrap lookback. |

Seed the row with `samples/sql/archive-domain/smoke/seed_config.sql`. The example JSON references `DOMAIN_ARCHIVE_TEST` as `dbms_cloud_credential_name`, `archive/_manifests` as `manifest_prefix`, and `archive/_state/checkpoint.json` for checkpoint persistence. Adjust those values to match your archive bucket and credential names.

## Planning With `archive_domain_pkg.plan`

The plan procedure inspects the retention policy, checkpoint state, and (optionally) explicit `start`/`end` times before returning a JSON payload of proposed windows for each dataset. Call it manually or via `samples/sql/archive-domain/smoke/plan.sql`:

```sql
set serveroutput on size unlimited
declare
  l_result clob;
begin
  archive_domain_pkg.plan(
    p_config_name  => 'default',
    p_dataset_list => 'raw,historized',
    p_result       => l_result
  );
  dbms_output.put_line(l_result);
end;
/
```

Inspect `$.datasets.<name>.window_start` / `window_end` plus `checkpoint_before` to validate the plan and decide which datasets to run.

## Running With `archive_domain_pkg.run`

`archive_domain_pkg.run` exports `historized` as Parquet and `raw` / `rejected` as Data Pump through `DBMS_CLOUD.EXPORT_DATA`, writes a JSON manifest under `<prefix>/_manifests/run_id=<...>.json`, and advances the checkpoint at `<prefix>/_state/checkpoint.json` only after all exports succeed. Use the smoke scripts such as `samples/sql/archive-domain/smoke/run_raw_small_window.sql` (which also prints the manifest) or invoke the package directly:

```sql
set serveroutput on size unlimited
declare
  l_result clob;
begin
  archive_domain_pkg.run(
    p_config_name  => 'default',
    p_dataset_list => 'raw',
    p_result       => l_result
  );
  dbms_output.put_line(l_result);
end;
/
```

The returned JSON includes per-dataset statuses and the manifest path. Re-run with a different `p_dataset_list` or `p_end_time` to export additional windows.

For bronze datasets, the archive now preserves the database rows through Data Pump rather than rewriting the `BLOB` payloads into text.

## Manual Validation & Object Storage Verification

1. Confirm the config row exists: `select config_json from archive_domain_config where config_name = 'default';`
2. Run the plan script and check that `checkpoint_before` equals the last checkpoint in Object Storage.
3. After running `archive_domain_pkg.run`, list objects under `oci os object list --namespace <namespace> --bucket <bucket> --prefix <prefix>` and verify:
   - A manifest JSON appears under `_manifests/run_id=<run-id>.json`.
   - The checkpoint JSON at `_state/checkpoint.json` reflects the new `last_successful_run_at`.
   - Dataset exports land under `zone=bronze` / `zone=silver` paths with `dataset=<name>` segments.
   - `raw` and `rejected` exports are written as `.dmp` objects.
   - `historized` exports continue to use Parquet.
4. Re-run `archive_domain_pkg.plan` to ensure the next window uses the updated checkpoint.

## Smoke Scripts

- `smoke/seed_config.sql`: populates `archive_domain_config` with a `default` row that uses `DOMAIN_ARCHIVE_TEST`.
- `smoke/plan.sql`: exercises `archive_domain_pkg.plan`.
- `smoke/run_raw_small_window.sql`, `run_historized_small_window.sql`, `run_rejected_small_window.sql`: export the three datasets individually using the configuration metadata.

Each smoke script expects the supporting objects to exist and prints JSON output so you can verify returned manifests without wiring a scheduler.
