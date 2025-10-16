# IoT from scratch - Terraform Edition

## Overview

This sample Terraform script demonstrates how to set up an OCI IoT Platform environment
from scratch.

The table below summarizes the resources created by the script and the privileges required.

| Resource                         | Defined in file | Privileges required | Notes |
|----------------------------------|:---------------:|---------------------|-------|
| Service policy for the Certificate Authority Service| identity.tf     | manage policies in compartment | Optional, alternatively, policy must be created by an administrator|
| Service policy for the IoT Platform| identity.tf     | manage policies in compartment | Optional; alternatively, the policy must be created by an administrator|
| Compartment for all IoT resources| identity.tf     | manage compartments in compartment | Optional; alternatively, resources will be created in the provided compartment |
| Vault                            | vault.tf        | manage vaults in compartment / manage keys in compartment / manage secret-family in compartment| |
| Secrets                          | vault.tf        | | Optional; pre-creates secrets for sample Digital Twins |
| Root and Subordinate CA          | certificates.tf | manage certificate-authority-family | |
| Certificates                     | certificates.tf | | Optional; pre-creates certificates for sample Digital Twins |
| IoT Domain Group                 | iot.tf          | manage iot-domain-group-family in compartment ||
| IoT Domain                       | iot.tf          | manage iot-domain-family in compartment ||
| IoT Digital Twins                | iot.tf          | manage iot-digital-twin-family in compartment | Optional; creates sample Digital Twins|
| IoT Data Access - APEX           | iot.tf          | | Optional|
| IoT Data Access - ORDS           | iot.tf          | read domains in tenancy | Optional |
| IoT Data Access - Database       | iot.tf          | | Optional|
| Confidential Application         | identity.tf     | _Identity Domain Application Administrator_ / _Identity Domain Administrator_ role | Optional, alternatively request the application creation to an administrator.|

If the Terraform user has all the privileges listed, the script will be able to scaffold
a complete IoT environment. If the user is missing privileges for optional resources,
assistance from an administrator will be required.

## Prerequisites

### Policies

The Terraform user must have the following privileges granted:

```text
allow group MyTerraformGroup to manage vaults in compartment MyIoTCompartment
allow group MyTerraformGroup to manage keys in compartment MyIoTCompartment
allow group MyTerraformGroup to use key-delegate in compartment MyIoTCompartment
allow group MyTerraformGroup to manage secret-family in compartment MyIoTCompartment
allow group MyTerraformGroup to manage certificate-authority-family in compartment MyIoTCompartment
allow group MyTerraformGroup to manage iot-family in compartment MyIoTCompartment
```

The following optional policies will facilitate the deployment:

- To create a sub-compartment for all resources in the provided compartment:

  ```text
  allow group MyTerraformGroup to manage compartments in compartment MyIoTCompartment
  ```

- To create the required service policies for both the Certificate Authority Service and
the IoT Platform:

  ```text
  allow group MyTerraformGroup to manage policies in compartment MyIoTCompartment
  ```

  Alternatively, an administrator will need to create the following policy:

  ```text
  allow any-user to use keys in compartment MyIoTCompartment where request.principal.type = 'certificateauthority'
  allow any-user to manage objects in compartment MyIoTCompartment where request.principal.type = 'certificateauthority'
  allow any-user to {SECRET_BUNDLE_READ, SECRET_READ} in compartment MyIoTCompartment where request.principal.type = 'iotdomain'
  allow any-user to {CERTIFICATE_BUNDLE_READ, CERTIFICATE_READ} in compartment MyIoTCompartment where request.principal.type = 'iotdomain'
  allow any-user to {CERTIFICATE_AUTHORITY_BUNDLE_READ, CERTIFICATE_AUTHORITY_READ} in compartment MyIoTCompartment where request.principal.type = 'iotdomain'
  allow any-user to {CABUNDLE_READ} in compartment MyIoTCompartment where request.principal.type = 'iotdomain'
  ```

- To retrieve the Identity Domain endpoint (needed for ORDS data access):

  ```text
  allow group MyTerraformGroup to read domains in tenancy
  ```

  Alternatively, get the endpoint from an administrator.

### ORDS data access

An Identity Domain is required in which a Confidential Application can be created to provide
OAuth authentication for the ORDS API.
In most cases, the Default Identity Domain can be used.
However, if it is a Lightweight Identity Domain, a new Free Identity Domain must be
created.
You can choose to use that Identity Domain only for OAuth or for your entire
IoT Platform environment.

To create the Confidential Application, the Terraform user must have the
_Identity Domain Application Administrator_ role for that Identity Domain.
Alternatively, the script will display the commands to be executed by an
administrator.

Similarly, the Identity Domain must have `Configure client access` enabled,
which requires the _Identity Domain Administrator_ role.

### Direct database access

To configure direct database access, you will need to provide the VCN OCIDs from
which you will connect to the database, as well as the (Dynamic) Identity Groups allowed
to connect.

The [Network configuration](../../script/iot-from-scratch/database-access.md#network-configuration)
and [Compute instance](../../script/iot-from-scratch/database-access.md#compute-instance)
sections of the
[Direct database access](../../script/iot-from-scratch/database-access.md)
document describe a sample VCN configuration.

## Creating Digital Twin Instances

You can optionally create sample Digital Twin Instances using basic or certificate authentication.
The definitions are aligned with the other samples of this repository.
See the configuration file for more details.

## Configuring and Running the Terraform Script

Follow the steps below to configure and deploy the IoT Platform resources with Terraform:

### Install and configure Terraform

- **Terraform CLI**: Download and install Terraform from
  [developer.hashicorp.com/terraform/install](https://developer.hashicorp.com/terraform/install)
- **Configure the Terraform OCI provider**: Configure the provider as documented in
  [Configuring the Provider](https://docs.oracle.com/en-us/iaas/Content/dev/terraform/configuring.htm).
  We recommend using environment variables instead of editing the `provider.tf` file.

### Install and configure the OCI CLI

As of today, Terraform cannot directly configure data access for IoT resources.
As a workaround, Terraform uses `local-exec` to invoke the OCI Command Line Interface (CLI)
for these operations.  
Ensure the OCI CLI is
[installed and configured](https://docs.oracle.com/en-us/iaas/Content/API/Concepts/cliconcepts.htm)
using the same authentication as the one configured for Terraform.

Set [environment variables](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/clienvironmentvariables.htm)
to specify non-default settings—especially:

- `OCI_CLI_PROFILE` if you use a non-default profile with API-key authentication
- `OCI_CLI_AUTH` if you do not use API-key authentication (e.g., Instance Principal)

### Configure Input Variables

The sample provides a `terraform.distr.tfvars` file with example values. To configure
the deployment:

```sh
cp terraform.distr.tfvars terraform.tfvars
```

Edit the newly created `terraform.tfvars` file to specify values appropriate for your
target OCI tenancy, compartment, region, etc.

### Initialize the Terraform Project

In the repository directory (where the `.tf` files are located), run:

```sh
terraform init
```

This command will initialize Terraform and download the required provider plugins.

### Review and Apply the Plan

Review the changes Terraform will make:

```sh
terraform plan
```

To deploy the resources:

```sh
terraform apply
```

Confirm the prompt to proceed.

### Additional Notes

- If some resources fail to create due to insufficient permissions or pre-existing
  configuration, refer to the "Privileges required" table above and consult with your
  OCI administrator.
- Due to the grace period imposed by OCI when deleting secrets and certificates,
  Terraform won't be able to delete all resources in one go when running `terraform destroy`.
- For more details about variable options and output values, review the `variables.tf` and
  `outputs.tf` files.

## Retrieving secrets and certificates from OCI

If you chose to create sample Digital Twin Instances with this script, secrets
will be downloaded to `data/iot-device-secrets-<environment>.json`. This file
contains a map of user ID and password for your devices.

The Terraform OCI provider does not allow to extract the generated certificates
and keys; the `data/iot-device-cert-id-<environment>.json` file contains a map
of certificate Common Name and certificate OCID for these devices.
A sample python script
(`[download-certificates.py](./download-certs/download-certificates.py)`)
is provided to retrieve the certificate and key files to install on your devices.

You need Python 3 and the required packages.
From the [`download-certs`](./download-certs/) directory, install the dependencies with:

```sh
pip install -r requirements.txt
```

Running the script (basic usage):

```sh
./download-certificates.py ../data/iot-device-cert-id-<environment>.json <output-dir>
```

To encrypt the private keys:

```sh
./download-certificates.py ../data/iot-device-cert-id-<environment>.json <output-dir> \
    --key-password YourKeyPassword
```

To also generate PFX bundles (a PKCS#12 archive is a standardized file format used to
store cryptographic objects in a single secure container):

```sh
./download-certificates.py ../data/iot-device-cert-id-<environment>.json <output-dir> \
    --key-password YourKeyPassword \
    --pfx-password YourPfxPassword
```

Where `<output-dir>` is a directory where the resulting PEM/chain/PFX files will be
saved (it will be created if it does not exist).

For each device certificate, the following files are generated in `<output-dir>`:

- `<CN>.cert.pem`  — Device certificate
- `<CN>.key.pem`   — Private key (optionally encrypted)
- `<CN>.chain.pem` — CA certificate chain
- `<CN>.pfx`       — PKCS#12 bundle containing key + cert + chain (if `--pfx-password`
  specified)

The script uses your local OCI profile (CONFIG file or environment) for authentication.

For troubleshooting or advanced usage, see the comments in the script file.
