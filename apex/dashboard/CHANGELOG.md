<!-- markdownlint-disable MD024 -->
# IoT Explorer - Release Notes

## December 16th, 2025

### New Features

- Added Current Instance Content to the Instance Detail page.

### Changes

- Created Relationships page.
- Cleaned up command report on Instance Detail page.
- Add display name to the top of Adapter and Incatance detail pages.

## December 16th, 2025

### New Features

- Altered report layout to better reflect OCI Console design.
- Fixed spelling errors.
- Implemented version number on Apex pages.

### Changes

- functions in iot_objects package was changed to make them
more versatile

## November 20th, 2025

### New Features

- Added new views that transform model, adapter, and instance
data from json to table structure.
- Models, Adapters, and Instances can be updated through the
application. This includes an option to create new versions
of models if needed.

### Changes

- functions in iot_objects package was changed to make them
more versatile

## November 7th, 2025

### New Features

- Added ability to update objects to iot_objects package.

### Changes

- Functions in the iot_objects package must now be passed the
IoT Domain ocid when needed

## October 17th, 2025

### New Features

- Creation and deletion available for models, adapters, and instances.
- Secrets and certificates can be created as part of the instance
  creation form.

### Changes

- DTDL Model D in Adapter and Instance reports links to Model Detail and
Usage page.

### Bug Fixes

- Report column names and order consistency

## September 16th, 2025

### New Features

- Inclusion of command data throughout the application
- Copy button added to OCIDs
- Settings page added for user tenancy information
- IoT Platform domain group and domain information added

### Changes

- Direct link from OCI IoT Platform object listings to recent activity

### Bug Fixes

- Report column names and order consistency

## August 25th, 2025

### Initial Release

Features

- Traffic monitoring dashboard
- Listing of OCI IoT Platform objects (models, adapters, and instances)
- Reports of Raw Data, Errors, and Historized data
- Dynamic tree structure of OCI IoT Platform objects, their relationships, and
  most recent data collected
