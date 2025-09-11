# Direct database access

## Network configuration

For security reasons, direct access to the IoT Platform database is only possible from OCI
using a [Service Gateway](https://docs.oracle.com/en-us/iaas/Content/Network/Tasks/servicegateway.htm).

A typical network configuration is described in
[Overview of Service Gateways](https://docs.oracle.com/en-us/iaas/Content/Network/Tasks/servicegateway.htm#overview)
and covers the needs of a production environment.

It highlights the fact that you cannot have both an Internet Gateway and a Service Gateway
attached to a subnet. In other words, the Compute Instance connecting to the database
must be in a private subnet and can only be accessed through a Bastion:  
![Network diagram](./iot-db-bastion.png)  
This is described in the OCI IoT Platform documentation:
[Connecting Directly to the IoT Database](https://docs.oracle.com/en-us/iaas/Content/internet-of-things/connect-database.htm).

This document describes a simpler setup which can be used for testing and development by
creating a Compute Instance attached to both the public and the private subnets:  
![Network diagram](./iot-db.png)

In this configuration, there is no need for a NAT Gateway, but it is not an issue if you
have one. The easiest way to create such a configuration is to use the
[Virtual Networking Wizard - Create a VCN with Internet Connectivity](https://docs.oracle.com/en-us/iaas/Content/Network/Tasks/quickstartnetworking.htm#VCN_with_Internet_Connectivity).

## Compute instance

Create an Oracle Linux 9 Compute Instance in that VCN, using the public subnet as the
primary VNIC.

[Create and attach a secondary VNIC](https://docs.oracle.com/en-us/iaas/compute-cloud-at-customer/topics/network/creating-and-attaching-a-secondary-vnic.htm)
to the instance; this time, select the private subnet (do not configure the instance as
suggested on the linked page, see below).

While the recommended way to configure the secondary VNIC is
[`oci-network-config`](https://docs.oracle.com/en-us/iaas/oracle-linux/oci-utils/index.htm#oci-network-config),
this approach doesn't use NetworkManager, which is not ideal for configuring a static
route. We are going to use NetworkManager as described for
[Enterprise Linux](https://docs.oracle.com/en-us/iaas/Content/Network/Tasks/managingVNICs.htm#Linux):

```shell
# Run as root
dnf -y install NetworkManager-config-server
dnf -y install NetworkManager-cloud-setup
mkdir -p /etc/systemd/system/nm-cloud-setup.service.d
cat >/etc/systemd/system/nm-cloud-setup.service.d/oci.conf <<EOF
[Service]
Environment=NM_CLOUD_SETUP_OCI=yes
Environment=NM_CLOUD_SETUP_LOG=TRACE
EOF
systemctl daemon-reload
systemctl enable --now nm-cloud-setup
```

Add a static route to the Autonomous Database service to use the private subnet:

```text
# # Retrieve the IP of the Autonomous Database service in the region
# dig +short adb.eu-frankfurt-1.oraclecloud.com
adb.eu-frankfurt-1.oci.oraclecloud.com.
138.1.3.227
# # Find the Network Manager connection name for the private subnet
# nmcli -g GENERAL.CONNECTION,GENERAL.DEVICE,IP4.ADDRESS device show
Wired Connection
enp0s6
172.16.0.223/24

Wired connection 1
enp1s0
172.16.1.12/24

lo
lo
127.0.0.1/8 
# # The private subnet VNIC is attached as "Wired connection 1"
# # Add a static route for the database (IP address retrieved above)
# # The gateway is always the first IP in the subnet IP range
# nmcli connection modify "Wired connection 1" +ipv4.routes "138.1.3.227/32 172.16.1.1"
# # Activate the changes
# nmcli connection up "Wired connection 1"
Connection successfully activated (D-Bus active path: /org/freedesktop/NetworkManager/ActiveConnection/6)
# # Verify the route table
# ip route
default via 172.16.0.1 dev enp0s6 proto dhcp src 172.16.0.223 metric 100 
138.1.3.227/32 via 172.16.1.1 dev enp1s0 proto static metric 101 
169.254.0.0/16 dev enp0s6 proto dhcp scope link src 172.16.0.223 metric 100 
172.16.0.0/24 dev enp0s6 proto kernel scope link src 172.16.0.223 metric 100 
172.16.1.0/24 dev enp1s0 proto kernel scope link src 172.16.1.12 metric 101 
```

The instance is now ready. We can proceed to the configuration of the IoT Platform.

## Configuring the IoT Platform

When everything is in place, configuring the IoT Platform is straightforward and requires
two steps:

1. Allowlist the VCN to access the database. This is done at the IoT Domain Group level
   and is thus common for all IoT Domains in the IoT Domain Group.
2. Specify which OCI Groups or Dynamic Groups are allowed to connect to the database. This
   is done at the IoT Domain level, as it governs the privileges to the IoT database schemas
   for that IoT Domain.

### Configure the IoT Domain Group

```bash
iot_domain_group_id=
# List of VCN IDs to allowlist
# This is a bash array -- e.g.: ( "ocid1.vcn...." "ocid1.vcn...." )
vcn_ids=( )
#
vcn_list=$(printf '"%s", ' "${vcn_ids[@]}")
vcn_list=${vcn_list%, }
oci iot domain-group configure-data-access \
    --iot-domain-group-id ${iot_domain_group_id} \
    --db-allow-listed-vcn-ids '['"${vcn_list}"']' \
    --wait-for-state SUCCEEDED --wait-for-state FAILED
```

### Configure the IoT Domain

Database authentication is done through an
[IAM `db-token`](https://docs.oracle.com/en-us/iaas/tools/oci-cli/3.65.1/oci_cli_docs/cmdref/iam/db-token/get.html).
To retrieve a token, the user or application needs to authenticate with OCI, either with
an API key or through _principals_. For our use case, using an Instance Principal is
attractive as it doesn't require storing credentials on the Compute Instance.

[Create a Dynamic Group](https://docs.oracle.com/en-us/iaas/tools/oci-cli/3.65.0/oci_cli_docs/cmdref/identity-domains/dynamic-resource-group/create.html)
for the compute instance.
This step is optional if you prefer to authenticate with an API key.

```bash
identity_endpoint=
ci_dg_display_name=
instance_id=
oci identity-domains dynamic-resource-group create \
    --display-name ${ci_dg_display_name} \
    --endpoint ${identity_endpoint} \
    --matching-rule "instance.id = '${instance_id}'" \
    --schemas '["urn:ietf:params:scim:schemas:oracle:idcs:DynamicResourceGroup"]'
```

(See [IoT from scratch](./README.md#tenancy-and-identity-domain-considerations) for how to
retrieve the Identity Endpoint.)

This Dynamic Group will contain only this Compute Instance; you can potentially address a
broader scope with, e.g., `instance.compartment.id = '<compartment-ocid>'`.

No additional policy is required to retrieve the token, but you might want to give access
to the IoT Platform. In that case, create the following policy:

```bash
home_region=
compartment_id=
ci_plc_display_name=
# If the Dynamic Group is not in the Default Identity Domain, it must be prefixed
# by the Identity Domain name. Eg.: "IdentityDomainName/IdentityGroupName"
ci_dynamic_group=
oci --region ${home_region} iam policy create \
    --compartment-id ${compartment_id} \
    --name ${ci_plc_display_name} \
    --description "IoT Platform access for Compute Instances" \
    --statements '[
        "allow dynamic-group '${ci_dynamic_group}' to use iot-family in compartment id '${compartment_id}'",
        "allow dynamic-group '${ci_dynamic_group}' to use iot-domain-family in compartment id '${compartment_id}'",
        "allow dynamic-group '${ci_dynamic_group}' to use iot-digital-twin-family in compartment id '${compartment_id}'"
    ]'
```

Grant access to the user groups and/or the dynamic groups to the IoT Domain schemas:

```bash
tenancy_id=
iot_domain_id=
# List of Identity Groups to allowlist
# If the (Dynamic) Group is not in the Default Identity Domain, it must be prefixed
# by the Identity Domain name. Eg.: "IdentityDomainName/IdentityGroupName"
# This is a bash array -- e.g.: ( "Group1" "Group2" )
identity_groups=()
# 
group_list=$(printf '"'${tenancy_id}':%s", ' "${identity_groups[@]}")
group_list=${group_list%, }
oci iot domain configure-direct-data-access \
    --iot-domain-id ${iot_domain_id} \
    --db-allow-listed-identity-group-names '['"${group_list}"']' \
    --wait-for-state SUCCEEDED --wait-for-state FAILED
```

You should now be able to connect to the database as described in direct database
connection ([command line](../query-db/README.md) or [Python](../../python/query-db/)).

## Connecting to the database from outside OCI

While not recommended from a security standpoint, it might be desirable to connect to the
IoT Platform database from a workstation for development purposes.

Using the above setup, you can tunnel SQLNet through an `ssh` connection.

Alias the Autonomous Database IP to localhost on your workstation—for example, in
`/etc/hosts`:

```text
127.0.0.1       adb.eu-frankfurt-1.oraclecloud.com
```

Establish an ssh tunnel redirecting your local SQLNet port to the ADB service:

```shell
ssh -L 1521:adb.eu-frankfurt-1.oraclecloud.com:1521 opc@<compute instance>
```

You can now transparently request an IAM `db-token` and connect to the IoT Platform
database from your workstation as long as the `ssh` session remains open.
Note that in this case, your OCI user must be a member of an allowlisted group.
