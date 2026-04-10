# Archive IoT Domain Data To Object Storage From SQL

This DB-driven sample lets you plan and run the archive-domain workflow entirely from the database using `archive_domain_pkg.plan` and `archive_domain_pkg.run`. The package lives in the `<DomainShortId>__WKSP` schema, reads configuration from `archive_domain_config`, and writes datasets to Object Storage with `DBMS_CLOUD` APIs.

The DB-driven format choices are:

- `historized` exports as Parquet
- `raw` exports as Data Pump
- `rejected` exports as Data Pump

## Prerequisites

- An IoT Domain (for example `ocid1.iotdomain.oc1..example`) and the `__IOT` schema populated with telemetry tables.
- A workspace database user configured to connect with `WKSP_PROXY_USER` (see [samples/script/query-db/README.md](../../script/query-db/README.md) for the connection flow used here).
- A `DBMS_CLOUD` credential that can write to the archive bucket. The sample uses the placeholder name `DOMAIN_ARCHIVE_TEST` (the same name referenced from the sample config). Create it with `DBMS_CLOUD.CREATE_CREDENTIAL` before calling the package routines.
- Object Storage namespace/bucket for checkpoints and manifests. The config row seeds `prefix` values such as `<bucket>/<prefix>` and `_state/checkpoint.json`.

## Bucket Access Guidance

There are two separate OCI access paths to keep in mind:

- The OCI principal behind the `DBMS_CLOUD` credential.
- The compute or operator principal you might use for manual validation outside the database.

For the SQL sample itself, the important path is the `DBMS_CLOUD` credential. The OCI user or group behind that credential must be able to:

- read bucket metadata for the target bucket
- create objects in the target bucket
- overwrite objects in the target bucket when rerunning the same checkpoint or manifest object names
- read objects again if you want the smoke scripts to validate manifests and checkpoint files

In same-tenancy setups, the broad pattern is:

```text
Allow <group-or-user-scope> to read buckets in compartment <bucket_compartment>
  where target.bucket.name = '<bucket_name>'

Allow <group-or-user-scope> to manage objects in compartment <bucket_compartment>
  where target.bucket.name = '<bucket_name>'
```

If the credential user is in a different tenancy from the bucket, you need the usual OCI cross-tenancy `Define` / `Endorse` / `Admit` policy pattern instead of same-tenancy bucket policies.

If you also use the compute-host or Python workflows, the compute instance principal or dynamic group needs its own Object Storage policy. That access path is separate from the `DBMS_CLOUD` credential user.

For the bronze Data Pump exports (`raw` and `rejected`), this managed database also needed database-side access to `DATA_PUMP_DIR`. In practice that means the execution schema needs the necessary directory privileges before query-based `DBMS_CLOUD.EXPORT_DATA(... type='datapump' ...)` will work.

## Install / Teardown

1. To install, run:
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

For normal setup, copy:

```text
samples/sql/archive-domain/data/archive_config.distr.json
```

to:

```text
samples/sql/archive-domain/data/archive_config.json
```

Edit the JSON file with your real values, then load it into
`archive_domain_config` with:

```sh
python3 samples/sql/archive-domain/load_config.py \
  --config-file samples/sql/archive-domain/data/archive_config.json \
  --config-name default \
  --proxy-user "${WKSP_PROXY_USER}" \
  --connect-string "${IOT_DB_CONNECT_STRING}" \
  --token-scope "${IOT_DB_TOKEN_SCOPE}" \
  --auth-type InstancePrincipal
```

On a workstation using a config-file-backed OCI identity instead of instance
principal, use:

```sh
python3 samples/sql/archive-domain/load_config.py \
  --config-file samples/sql/archive-domain/data/archive_config.json \
  --config-name default \
  --proxy-user "${WKSP_PROXY_USER}" \
  --connect-string "${IOT_DB_CONNECT_STRING}" \
  --token-scope "${IOT_DB_TOKEN_SCOPE}" \
  --auth-type ConfigFileAuthentication \
  --profile "${OCI_CLI_PROFILE:-DEFAULT}"
```

The distributed JSON template includes placeholders for the bucket layout and
`dbms_cloud_credential_name`, and is the recommended starting point for
operator-managed configuration. `smoke/seed_config.sql` remains available as a
test helper, but it is not the primary setup path.

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

The IoT Platform purges data according to dataset-specific retention periods.
For this SQL sample, those retention values are supplied in
`archive_domain_config.config_json` under `retention_days`. The code uses them
to compute the purge boundary for each dataset (`now - retention_days`) and
then derives the newly at-risk archive window from either:

- the explicit `p_start_time` / `p_end_time`
- the last successful checkpoint in Object Storage
- or the configured bootstrap lookback when no checkpoint exists yet

`archive_domain_pkg.plan` triggers these steps:

1. Load the named config row from `archive_domain_config`.
2. Parse and validate the requested dataset list.
3. Read the checkpoint object from Object Storage when it exists.
4. Resolve per-dataset retention values from `config_json`.
5. Compute the effective archive window for each dataset:
   - `window_start`
   - `window_end`
   - `purge_boundary`
6. Return the plan as JSON.

`plan` does **not** export data, write manifests, or advance the checkpoint.

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

`archive_domain_pkg.run` triggers these steps:

1. Load the named config row from `archive_domain_config`.
2. Reuse the same planning logic as `archive_domain_pkg.plan` to determine the archive window.
3. Build a `run_id` and dataset-specific object prefixes.
4. For each selected dataset:
   - build the dataset query
   - export `historized` with Parquet
   - export `raw` / `rejected` with Data Pump
5. Write a manifest JSON object to Object Storage.
6. Write the checkpoint JSON only if every selected dataset succeeded.
7. Return the run result as JSON, including per-dataset statuses and the manifest object name.

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
   - `historized` exports use Parquet.
4. Re-run `archive_domain_pkg.plan` to ensure the next window uses the updated checkpoint.

## Smoke Scripts

- `smoke/seed_config.sql`: populates `archive_domain_config` with a `default` row that uses `DOMAIN_ARCHIVE_TEST`.
- `load_config.py`: loads `data/archive_config.json` into `archive_domain_config`.
- `smoke/plan.sql`: exercises `archive_domain_pkg.plan`.
- `smoke/run_raw_small_window.sql`, `run_historized_small_window.sql`, `run_rejected_small_window.sql`: export the three datasets individually using the configuration metadata.

Each smoke script expects the supporting objects to exist and prints JSON output so you can verify returned manifests without wiring a scheduler.
