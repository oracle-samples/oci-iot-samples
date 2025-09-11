# IoT from scratch

## Foreword

This document demonstrates how to set up an OCI IoT Platform environment from scratch
within a given compartment.
Although the operations can be completed via the OCI Console, this document primarily
employs the OCI CLI due to its scriptability.

When creating resources with the OCI CLI, always capture the resource ID (OCID) of the
created resources, as they are typically needed in further steps!

## Prerequisites

### Tenancy and Identity Domain considerations

An Identity Domain is required where a Confidential Application can be created to provide
OAuth authentication for the ORDS API.
In most cases, the Default Identity Domain can be used.
However, if it is a Lightweight Identity Domain, a new Free Identity Domain must be
created.
You can choose to use that Identity Domain only for OAuth or for your entire
IoT Platform environment.

During the setup of your environment, you will need to provide the endpoint URL or
hostname of your chosen Identity Domain. You can retrieve the Identity Domain endpoint URL
with:

```bash
compartment_id=
oci iam domain list -c ${compartment_id} \
    --query 'data[].["display-name", url]'
```

Here, `compartment_id` should be the tenancy OCID for the Default Identity Domain,
or the OCID of the compartment containing your Identity Domain.

### Policies

To set up an OCI IoT Platform environment, the following policy statements are required:

- [Vault secrets](https://docs.oracle.com/en-us/iaas/Content/Identity/Reference/keypolicyreference.htm)
  (to store Digital Twin secrets and the Certificate Authority key):
  - manage secret-family in compartment
- [Certificate Service](https://docs.oracle.com/en-us/iaas/Content/Identity/Reference/certificatespolicyreference.htm)
  (to store Digital Twin certificates):
  - manage certificate-authority-family in compartment
  - manage leaf-certificate-family in compartment
- [Core Services](https://docs.oracle.com/en-us/iaas/Content/Identity/Reference/corepolicyreference.htm)
  (Network configuration and compute instance for direct database connection):
  - manage virtual-network-family in compartment
  - manage instance-family in compartment
- IoT Platform:
  - manage iot-family in compartment
  - manage iot-domain-family in compartment
  - manage iot-digital-twin-family in compartment

Additionally:

- The user setting up the IoT Platform environment must be an Application Administrator
  in the selected Identity Domain to manage the Confidential Application (or request
  support from an Identity Domain administrator).
- Service policies must be defined for the IoT Platform and Certificate Service, which
  typically require administrator privileges in the tenancy.

#### OCI IoT Platform policies

The following policy statements allow the OCI IoT Platform to access your vault secrets and
certificates. They must be
[created](https://docs.oracle.com/en-us/iaas/tools/oci-cli/3.65.0/oci_cli_docs/cmdref/iam/policy/create.html)
in the root compartment:

```bash
home_region=
tenancy_id=
compartment_id=
iot_platform_tenancy_id=
iot_plc_display_name=
statements=$(cat <<EOF
[
  "define tenancy iot_tenancy as ${iot_platform_tenancy_id}",
  "admit any-user of tenancy iot_tenancy to {SECRET_BUNDLE_READ, SECRET_READ} in compartment id ${compartment_id} where all {request.principal.type = 'iotdomain', request.principal.compartment.id = target.compartment.id}",
  "admit any-user of tenancy iot_tenancy to {CERTIFICATE_BUNDLE_READ, CERTIFICATE_READ, CERTIFICATE_ASSOCIATION_READ} in compartment id ${compartment_id} where all {request.principal.type = 'iotdomain', request.principal.compartment.id = target.compartment.id}",
  "admit any-user of tenancy iot_tenancy to {CERTIFICATE_AUTHORITY_BUNDLE_READ, CERTIFICATE_AUTHORITY_READ, CERTIFICATE_AUTHORITY_ASSOCIATION_READ} in compartment id ${compartment_id} where all {request.principal.type = 'iotdomain', request.principal.compartment.id = target.compartment.id}",
  "admit any-user of tenancy iot_tenancy to {CABUNDLE_READ} in compartment id ${compartment_id} where all {request.principal.type = 'iotdomain', request.principal.compartment.id = target.compartment.id}",
  "admit any-user of tenancy iot_tenancy to {CERTIFICATE_VERSION_READ} in compartment id ${compartment_id} where all {request.principal.type = 'iotdomain', request.principal.compartment.id = target.compartment.id}",
]
EOF
)
oci --region ${home_region} iam policy create \
    --compartment-id ${tenancy_id} \
    --name ${iot_plc_display_name} \
    --description "IoT Platform policies" \
    --statements "${statements}"
```

#### Certificate Service policies

The Certificate Authority service needs to access the Vault RSA key. This is done through
a Dynamic Group and policies; see
[Required IAM Policy](https://docs.oracle.com/en-us/iaas/Content/certificates/managing-certificate-authorities.htm#CA_required_iam_policy).

[Create Dynamic Group](https://docs.oracle.com/en-us/iaas/tools/oci-cli/3.65.0/oci_cli_docs/cmdref/identity-domains/dynamic-resource-group/create.html):

```bash
identity_endpoint=
crt_dg_display_name=
oci identity-domains dynamic-resource-group create \
    --display-name ${crt_dg_display_name} \
    --endpoint ${identity_endpoint} \
    --matching-rule "resource.type='certificateauthority'" \
    --schemas '["urn:ietf:params:scim:schemas:oracle:idcs:DynamicResourceGroup"]'
```

[Create policy](https://docs.oracle.com/en-us/iaas/tools/oci-cli/3.65.0/oci_cli_docs/cmdref/iam/policy/create.html):

```bash
home_region=
compartment_id=
crt_plc_display_name=
# If the Dynamic Group is not in the Default Identity Domain, it must be prefixed
# by the Identity Domain name. Eg.: "IdentityDomainName/IdentityGroupName"
crt_dynamic_group=
oci --region ${home_region} iam policy create \
    --compartment-id ${compartment_id} \
    --name ${crt_plc_display_name} \
    --description "Vault access for the Certificate Authority service" \
    --statements '[
        "allow dynamic-group '${crt_dynamic_group}' to use keys in compartment id '${compartment_id}'",
        "allow dynamic-group '${crt_dynamic_group}' to manage objects in compartment id '${compartment_id}'"
    ]'
```

### Create a Vault and Keys

[Create vault](https://docs.oracle.com/en-us/iaas/tools/oci-cli/3.65.0/oci_cli_docs/cmdref/kms/management/vault/create.html):

```bash
compartment_id=
vlt_display_name=
oci kms management vault create \
    --compartment-id ${compartment_id} \
    --display-name ${vlt_display_name} \
    --vault-type DEFAULT \
    --wait-for-state ACTIVE
```

Capture the `management-endpoint` returned.

We need an RSA key for certificates and an AES key for vault secrets—
[create keys](https://docs.oracle.com/en-us/iaas/tools/oci-cli/3.65.0/oci_cli_docs/cmdref/kms/management/key/create.html):

```bash
compartment_id=
vault_management_endpoint=
aes_kms_key_display_name=
rsa_kms_key_display_name=
oci kms management key create \
    --compartment-id ${compartment_id} \
    --display-name ${aes_kms_key_display_name} \
    --key-shape '{"algorithm": "AES", "length": 16}' \
    --endpoint ${vault_management_endpoint} \
    --wait-for-state ENABLED
oci kms management key create \
    --compartment-id ${compartment_id} \
    --display-name ${rsa_kms_key_display_name} \
    --key-shape '{"algorithm": "RSA", "length": 256}' \
    --endpoint ${vault_management_endpoint} \
    --wait-for-state ENABLED
```

Capture the AES and RSA key IDs returned.

You can now
[create secrets](https://docs.oracle.com/en-us/iaas/tools/oci-cli/3.65.0/oci_cli_docs/cmdref/vault/secret/create-base64.html)
for your Digital Twins. For example:

```bash
compartment_id=
vault_id=
aes_kms_key_id=
dt_secret_name=
dt_secret_content=
oci vault secret create-base64 \
    --compartment-id ${compartment_id} \
    --vault-id ${vault_id} \
    --key-id ${aes_kms_key_id} \
    --secret-name ${dt_secret_name} \
    --secret-content-content $(echo -n "${dt_secret_content}" | base64) \
    --wait-for-state ACTIVE --wait-for-state FAILED
```

### Certificate Authority

We create a root and a subordinate Certificate Authority.

[Create Root Certificate Authority](https://docs.oracle.com/en-us/iaas/tools/oci-cli/3.65.0/oci_cli_docs/cmdref/certs-mgmt/certificate-authority/create-root-ca-by-generating-config-details.html):

Notes:

- In this example, we do not manage revocation.
- We extend the maximum validity of certificates to 1 year (default is 90 days).
- The `timeOfValidityNotAfter` must be in the form `"2035-08-31T00:00:00.000Z"`
  (the generated JSON sample template is incorrect).

```bash
compartment_id=
root_ca_display_name=
root_ca_common_name=
rsa_kms_key_id=
# Use "gdate" on macOS
date_cmd=$(command -v gdate || echo date)
oci certs-mgmt certificate-authority create-root-ca-by-generating-config-details \
    --compartment-id ${compartment_id} \
    --name ${root_ca_display_name} \
    --description "Root Certificate Authority" \
    --kms-key-id ${rsa_kms_key_id} \
    --subject '{ "commonName": "'${root_ca_common_name}'", "country": "US" }' \
    --signing-algorithm "SHA256_WITH_RSA" \
    --validity '{ "timeOfValidityNotAfter": "'$(${date_cmd} -u -d "+10 year" +"%Y-%m-%dT%H:%M:%S.%3NZ")'" }' \
    --certificate-authority-rules '[{
      "ruleType": "CERTIFICATE_AUTHORITY_ISSUANCE_EXPIRY_RULE",
      "certificateAuthorityMaxValidityDuration": "P3650D",
      "leafCertificateMaxValidityDuration": "P365D"
    }]' \
    --wait-for-state ACTIVE --wait-for-state FAILED
```

[Create Subordinate Certificate Authority](https://docs.oracle.com/en-us/iaas/tools/oci-cli/3.65.0/oci_cli_docs/cmdref/certs-mgmt/certificate-authority/create-subordinate-ca-issued-by-internal-ca.html):

```bash
compartment_id=
root_ca_id=
sub_ca_display_name=
sub_ca_common_name=
rsa_kms_key_id=
date_cmd=$(command -v gdate || echo date)
oci certs-mgmt certificate-authority create-subordinate-ca-issued-by-internal-ca \
    --compartment-id ${compartment_id} \
    --name ${sub_ca_display_name} \
    --description "Subordinate Certificate Authority" \
    --issuer-certificate-authority-id ${root_ca_id} \
    --kms-key-id ${rsa_kms_key_id} \
    --subject '{ "commonName": "'${sub_ca_common_name}'", "country": "US" }' \
    --signing-algorithm "SHA256_WITH_RSA" \
    --validity '{ "timeOfValidityNotAfter": "'$(${date_cmd} -u -d "+5 year" +"%Y-%m-%dT%H:%M:%S.%3NZ")'" }' \
    --certificate-authority-rules '[{
      "ruleType": "CERTIFICATE_AUTHORITY_ISSUANCE_EXPIRY_RULE",
      "certificateAuthorityMaxValidityDuration": "P1824D",
      "leafCertificateMaxValidityDuration": "P365D"
    }]' \
    --wait-for-state ACTIVE --wait-for-state FAILED
```

You can now
[create certificates](https://docs.oracle.com/en-us/iaas/tools/oci-cli/3.65.0/oci_cli_docs/cmdref/certs-mgmt/certificate/create-certificate-issued-by-internal-ca.html)
for a Digital Twin. For example:

```bash
compartment_id=
sub_ca_id=
dt_cert_display_name=
dt_cert_common_name=
date_cmd=$(command -v gdate || echo date)
oci certs-mgmt certificate create-certificate-issued-by-internal-ca \
    --compartment-id ${compartment_id} \
    --name ${dt_cert_display_name} \
    --certificate-profile-type TLS_CLIENT \
    --issuer-certificate-authority-id ${sub_ca_id} \
    --subject '{ "dt_cert_common_name": "'${common_name}'", "country": "US" }' \
    --validity '{ "timeOfValidityNotAfter": "'$(${date_cmd} -u -d "+1 year" +"%Y-%m-%dT%H:%M:%S.%3NZ")'" }' \
    --certificate-rules '[{
      "ruleType": "CERTIFICATE_RENEWAL_RULE",
      "renewalInterval": "P364D",
      "advanceRenewalPeriod": "P30D"
    }]' \
    --wait-for-state ACTIVE --wait-for-state FAILED
```

Certificates can be
[retrieved](https://docs.oracle.com/en-us/iaas/tools/oci-cli/3.65.0/oci_cli_docs/cmdref/certs-mgmt/ca-bundle/get.html)
with:

```bash
certificate_id=
oci certificates certificate-bundle get \
   --certificate-id ${certificate_id} \
   --bundle-type CERTIFICATE_CONTENT_WITH_PRIVATE_KEY |
   jq -r '.data."certificate-pem"','.data."private-key-pem"' > client_certificate_bundle.pem
```

## IoT Domain Group and Domain

Now that everything is in place, these steps are straightforward.

### IoT Domain Group

Be patient, IoT Domain Group creation can take quite some time!

```bash
compartment_id=
iot_domain_group_display_name=
oci iot domain-group create \
    --compartment-id ${compartment_id} \
    --display-name ${iot_domain_group_display_name} \
    --wait-for-state SUCCEEDED --wait-for-state FAILED
```

### IoT Domain

```bash
compartment_id=
iot_domain_display_name=
iot_domain_group_id=
oci iot domain create \
    --compartment-id ${compartment_id} \
    --display-name ${iot_domain_display_name} \
    --iot-domain-group-id ${iot_domain_group_id} \
    --wait-for-state SUCCEEDED --wait-for-state FAILED
```

## Configuring data access

There are three types of data access that can be configured. All are optional, but you
will need at least one to be able to query your data.

1. Via the Oracle Application Express (APEX) web-based interface
2. Using the Oracle REST Data Services (ORDS) API
3. Using a direct database connection

### APEX data access

Note that the initial password must be at least 12 characters.

```bash
iot_domain_id=
apex_initial_password=
oci iot domain configure-apex-data-access \
    --iot-domain-id ${iot_domain_id} \
    --db-workspace-admin-initial-password "${apex_initial_password}" \
    --wait-for-state SUCCEEDED --wait-for-state FAILED
```

That should give you access to the APEX environment. If you didn't save the details when
creating the IoT Domain Group and Domain, you can retrieve the URL and account information:

```bash
iot_domain_group_id=
iot_domain_id=
iot_data_host=$(oci iot domain-group get --iot-domain-group-id ${iot_domain_group_id} --query 'data."data-host"' --raw-output)
iot_device_host=$(oci iot domain get --iot-domain-id ${iot_domain_id} --query 'data."device-host"' --raw-output)
echo "APEX URL.     : https://${iot_data_host}/ords/apex"
echo "Workspace/User: ${iot_device_host/.*}__wksp"
```

### ORDS data access

The ORDS API uses OAuth tokens as an authentication mechanism. A Confidential Application
must be created as the OAuth provider.

First, ensure that Signing certificate client access is enabled at the Identity Domain
level ([setting get](https://docs.oracle.com/en-us/iaas/tools/oci-cli/3.65.0/oci_cli_docs/cmdref/identity-domains/setting/get.html)):

```bash
identity_endpoint=
oci identity-domains setting get \
    --setting-id Settings \
    --endpoint ${identity_endpoint} \
    --query 'data."signing-cert-public-access"'
```

If the above request returns `false`, enable access with
([setting patch](https://docs.oracle.com/en-us/iaas/tools/oci-cli/3.65.0/oci_cli_docs/cmdref/identity-domains/setting/patch.html)):

```bash
oci identity-domains setting patch \
    --setting-id Settings \
    --endpoint ${identity_endpoint} \
    --operations '[{"op": "replace", "path": "SigningCertPublicAccess", "value": true}]' \
    --schemas '["urn:ietf:params:scim:api:messages:2.0:PatchOp"]'
```

Create the Confidential Application
([app create](https://docs.oracle.com/en-us/iaas/tools/oci-cli/3.65.0/oci_cli_docs/cmdref/identity-domains/app/create.html)):

```bash
identity_endpoint=
app_display_name=
iot_domain_display_name=
iot_domain_group_id=
iot_domain_id=
#
iot_data_host=$(oci iot domain-group get --iot-domain-group-id ${iot_domain_group_id} --query 'data."data-host"' --raw-output)
iot_device_host=$(oci iot domain get --iot-domain-id ${iot_domain_id} --query 'data."device-host"' --raw-output)
#
oci identity-domains app create \
  --endpoint "${identity_endpoint}" \
  --display-name "${app_display_name}" \
  --based-on-template '{
      "$ref": "'${identity_endpoint}'/admin/v1/AppTemplates/CustomWebAppTemplateId",
      "value": "CustomWebAppTemplateId",
      "well-known-id": "CustomWebAppTemplateId"
  }' \
  --schemas '[
      "urn:ietf:params:scim:schemas:oracle:idcs:App",
      "urn:ietf:params:scim:schemas:oracle:idcs:extension:OCITags"
  ]' \
  --access-token-expiry 3600 \
  --active true \
  --allowed-grants '[
      "refresh_token",
      "password",
      "client_credentials",
      "urn:ietf:params:oauth:grant-type:jwt-bearer"
  ]' \
  --audience "/${iot_data_host/.*}" \
  --client-type confidential \
  --description "${app_display_name}" \
  --is-login-target true \
  --is-o-auth-client true \
  --is-o-auth-resource true \
  --scopes '[{
    "description": "'${iot_domain_display_name}'",
    "displayName": "'${iot_domain_display_name}'",
    "fqs": "/'${iot_data_host/.*}'/iot/'${iot_device_host/.*}'",
    "readOnly": null,
    "requiresConsent": null,
    "value": "/iot/'${iot_device_host/.*}'"
  }]'
```

From the command output, capture the following; these are needed to retrieve API tokens:

- Client Id: `data.name`
- Client Secret: `data.client-secret`

In addition, you need to grant application access to the users, either directly or via a
group.

With the Confidential Application in place, you can now configure the ORDS Data Access in
the IoT Platform. The Identity Domain Host is the Identity Endpoint previously retrieved,
without the `https://` prefix and the `:443` suffix.

```bash
iot_domain_id=
identity_endpoint=
identity_domain_host=${identity_endpoint#https://}
identity_domain_host=${identity_domain_host%:443}
oci iot domain configure-ords-data-access \
    --iot-domain-id ${iot_domain_id} \
    --db-allowed-identity-domain-host "${identity_domain_host}" \
    --wait-for-state SUCCEEDED --wait-for-state FAILED
```

Use of the ORDS data access API is demonstrated in the [Manage Digital Twins sample](../manage-dt/README.md).

### Direct database access

This is described in [Direct database access](database-access.md).
