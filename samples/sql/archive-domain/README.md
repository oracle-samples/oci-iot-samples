# Archive IoT Domain Data To Object Storage From SQL

Sample SQL/PLSQL implementation of the archive-domain workflow for OCI IoT
telemetry. This variant is intended to run from the database through a package
installed in the `<DomainShortId>__WKSP` schema.

See `samples/script/query-db/README.md` for the direct database and SQLcl
connection flow used to install and run this sample.

The package currently exposes two entry points:

- `archive_domain_pkg.plan`
- `archive_domain_pkg.run`

Use `install.sql` to create the package objects and `teardown.sql` to remove
them.

The `smoke/` directory contains SQLcl scripts for basic package invocation.
