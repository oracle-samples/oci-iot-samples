
# OCI IoT Platform Explorer

This APEX application serves as a dashboard for monitoring IoT devices and messages.

## Prerequisites

1. Complete setup of Iot Platform including access to APEX:
2. Create an APEX user to install and access the application.

Documentation about creating APEX users can be found in the
[APEX Administration Guide](https://docs.oracle.com/en/database/oracle/apex/24.2/aeadm/managing-users-across-an-application-express-instance.html#GUID-CE23292D-05D1-4E79-BF40-8BC31E74E6C8).

### Optional

It is recommended that you create an OCI user and group that OCI IoT Explorer can use to
access OCI REST APIs. However, any user with sufficient access will suffice.

1. Begin by creating an OCI user group.  
2. Next, create a user with an API Key assigned to that group.

Then, as the admin-level user, create a new policy and set the following.

```text
Allow group <grp_name> to manage iot-family in compartment <cmp_name>
Allow group <grp_name> to manage iot-domain-family in compartment <cmp_name>
Allow group <grp_name> to manage iot-digital-twin-family in compartment <cmp_name>
```

## Setup

After completing your IoT Platform setup, you should be able to access your APEX
instance with the user you created in the prerequisites. Log in to your instance and
complete the following tasks to install the dashboard.

### Part One

There are several database objects that need to be created that are
prerequisites for the IoT Explorer. The iot_explorer.sql file is a creation script
for creating the following objects.

* Synonyms
  * A synonym will be created in the *__wksp schema for each of the views in the
  *__iot schema. The synonym names are derived by removing 'DIGITAL_TWIN_' from the
  view name (if present) and appending '_syn'.
* Views
  * iot_stats - merges messages/records that have occured after the last refresh of
  iot_msg_stats to report basic stats for all data.
  * iot_hierarchy - a hierarchy view of models -> adapters -> instances.
* Materialized Views
  * iot_msg_stats - computes basic stats on raw messages, rejected messages,
  historized records, and command records.
* Scheduled Tasks
  * REFRESH_MVIEW_IOT_MSG_STATS - task is executed daily at 01:00 (1:00 am) and
  updates the iot_msg_stats materialized view.
* Functions
  * compact_number( n number ) - accepts a number and returns a shorter string
  representation of that number.

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

The application is accessable through any standard web browser via a url. To
obtain that url use the instructions below.

1. From the APEX home screen, click "App Builder".
2. Then click "OCI IoT Platform Explorer".
3. Then, click the "Run" button located at the top right of the page below your
username.
4. Copy and save / bookmark the url.

The application uses APEX user account for authorization.

## Usage

Navigation is accessible from the top left of the page via the hamburger menu.

The application allows viewing of IoT objects (models, adapters, and digital twins)
as well as telemetry sent to the platform (raw, rejected, and historized data).

The "IoT Tree" page organizes the IoT objects and telemetry received by each object
in a hierarchy starting with models, next adapters, then digital twins.

The 'Settings' page allows you to enter a user's credentials and information
about your tenancy.  This information, along with OCI policies allows the
application to make the REST API calls to the IoT service. Any features requiring a
value that has not been set will display a message to that effect.

## Removal

To remove the OCI IoT Explorer:

1. Select the application from the APEX Application Builder and click "Delete
Application" on the left.
2. Load iot_explorer_teardown.sql into APEX SQL Workshop -> Scripts and run.
