# OCI IoT Platform Explorer

This APEX application serves as a dashboard for monitoring IoT devices and messages.

## Upgrading

If you are upgrading follow the instructions in Part One of Setup. The new version
of iot_explorer.sql and iot_explorer.app.sql can be installed in the same schema as
the exising version. No settings will be lost during the upgrade process.

## Prerequisites

1. Setup of IoT Platform. [IoT Platform Getting Started](https://docs.oracle.com/en-us/iaas/Content/internet-of-things/overview.htm)
2. Allow access to APEX. [APEX Setup](https://docs.oracle.com/en-us/iaas/Content/internet-of-things/connect-iot-apex.htm)
3. Create an APEX user to install and access the application.
[APEX Administration Guide](https://docs.oracle.com/en/database/oracle/apex/24.2/aeadm/managing-users-across-an-application-express-instance.html#GUID-CE23292D-05D1-4E79-BF40-8BC31E74E6C8).

### Enabling Optional Features

The application includes the following optional features that require OCI
credentials to function.

1. Creation, updating, and deletion of models, adapters, and instances.
2. Creation of certificates and passwords for instances created in the
   application.
3. Retrieval of certificate private key, certificate (pem), and certificate
   chain (pem) stored in a OCI compartment.
4. Retrieval of passwords stored in a vault and private keys of certificates to
   facilitate device setup.
5. Retrieval of IoT Domain Group and IoT Domain information where the
   application is running.

>[!WARNING]
>Providing these settings gives a group access to your IoT domain group(s),
>the IoT domain(s) they contain, as well as certificates, private keys, and
>other Vault secrets.
>
>**All users with access to the IoT Platform Explorer application will be able
>to view this sensitive information**.
>
>This application is for demonstration purposes only and you should carefully
>consider the access it provides, should you decide to configure these
>settings.

In order to mitigate some risk it is **recommended** that you create a
dedicated OCI user and group that OCI IoT Explorer can use to access OCI REST
APIs.

1. Begin by creating an OCI user group.
2. Next, create a user with an API Key assigned to that group.

Then, as the admin-level user, create a new policy and set the policy
statements appropriate for you.

- Allow access read IoT Domain Group and Domain information

  ```text
  Allow group <grp_name> to read iot-family in compartment <cmp_name>
  ```

- Allow group members to create IoT objects. (models, adapters, instances,
relationships )

  ```text
  Allow group <grp_name> to manage iot-digital-twin-family in compartment
  <cmp_name>
  ```

- Allow group members access, create, and read secrets stored in a vault.

  ```text
  Allow group <grp_name> to use vaults in compartment <cmp_name>
  Allow group <grp_name> to manage secret-family in compartment <cmp_name>
  Allow group <grp_name> to use keys in compartment <cmp_name>
  ```

- Allow group members to access and read certificate authority information and;
  access, read, and create certificates.

  ```text
  Allow group <grp_name> to read certificate-authority-family in compartment
  <cmp_name>
  Allow group <grp_name> to use certificate-authority-delegate in compartment
  <cmp_name>
  Allow group <grp_name> to manage leaf-certificate-family in compartment
  <cmp_name>
  Allow group <grp_name> to use key-delegate in compartment <cmp_name>
  ```

## Setup

After completing your IoT Platform setup, you should be able to access your
APEX instance with the user you created in the prerequisites. Log in to your
instance and complete the following tasks to install the dashboard.

### Part One

There are several database objects that need to be created that are
prerequisites for the IoT Explorer. The iot_explorer.sql file is a creation
script for creating the following objects.

- Synonyms
  - A synonym will be created in the *__wksp schema for each of the views in
    the \*__iot schema. The synonym names are derived by removing
    'DIGITAL_TWIN_' from the view name (if present) and appending '_syn'.

- Views
  - iot_stats - merges messages/records that have occurred after the last
    refresh of iot_msg_stats to report basic stats for all data.
  - iot_hierarchy - a hierarchy view of models -> adapters -> instances.
  - auth_view - lists certs and secrets accessible to IoT.
  - iot_certs - detailed information about certs available to IoT.
  - iot_passwords - detailed information about passwords stored in the vault.
  - iot_model_view - json model information in table format via json_table.
  - iot_adapter_view - json adapter information in table format via json_table.
  - iot_instance_view - json instance information in table format via json_table.

- Materialized Views
  - iot_msg_stats - computes basic stats on raw messages, rejected messages,
    historized records, and command records.

- Scheduled Tasks
  - REFRESH_MVIEW_IOT_MSG_STATS - task is executed daily at 01:00 (1:00 am) and
    updates the iot_msg_stats materialized view.

- Packages
  - See [iot_explorer_packages.md](iot_explorer_packages.md)

#### Instructions

1. Click "SQL Workshop" located on the top menu bar.
2. Click "SQL Scripts" from the five options at the top of the page.
3. Click the "Upload" button on the right.
4. Select the "iot_explorer.sql" file and click "Upload".
5. Click "Run" in the far-right column of the row containing the script.
6. Click APEX logo at the top left of the page to return to the APEX home page.

### Part Two

The following will walk you through the installation of the IoT Explorer
application.

1. Click "Import".
2. Select the iot_explorer.app.sql file.
3. Click the "Next" button.
4. Set the "Parsing Schema" to your workspace (e.g., ****************__wksp).
5. You may either reuse the application number or allow APEX to auto-assign a new
application number.
6. Click "Install Application".

## Running the Application

The application is accessible through any standard web browser via a URL. To
obtain that URL use the instructions below.

1. From the APEX home screen, click "App Builder".
2. Then click "OCI IoT Platform Explorer".
3. Then, click the "Run" button located at the top right of the page below your
username.
4. Copy and save / bookmark the URL.

The application uses an APEX user account for authorization.

## Usage

Navigation is accessible from the top left of the page via the hamburger menu.

The application allows viewing of IoT objects (models, adapters, and digital twins)
as well as telemetry sent to the platform (raw, rejected, and historized data).

The "IoT Tree" page organizes the IoT objects and telemetry received by each object
in a hierarchy starting with models, next adapters, then digital twins.

The 'Settings' page allows you to enter a user's credentials and information
about your tenancy.  This information, along with OCI policies allows the
application to make the REST API calls to the IoT service. Any features requiring
a value that has not been set will display a message to that effect.

## Removal

To remove the OCI IoT Explorer:

1. Select the application from the APEX Application Builder and click "Delete
Application" on the left.
2. Load iot_explorer_teardown.sql into APEX SQL Workshop -> Scripts and run.
