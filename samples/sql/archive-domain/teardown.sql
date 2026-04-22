--
-- Remove supporting objects for the SQL archive-domain sample.
--
-- Copyright (c) 2026 Oracle and/or its affiliates.
-- Licensed under the Universal Permissive License v 1.0 as shown at
-- https://oss.oracle.com/licenses/upl.
--
-- DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
--

whenever sqlerror exit sql.sqlcode

declare
  l_package_exists number;
begin
  select count(*)
    into l_package_exists
    from user_objects
   where object_name = 'ARCHIVE_DOMAIN_PKG'
     and object_type in ('PACKAGE', 'PACKAGE BODY');

  if l_package_exists > 0 then
    execute immediate 'drop package archive_domain_pkg';
  end if;
end;
/

declare
  l_package_exists number;
begin
  select count(*)
    into l_package_exists
    from user_objects
   where object_name = 'ARCHIVE_DOMAIN_CONTENT_UTILS'
     and object_type in ('PACKAGE', 'PACKAGE BODY');

  if l_package_exists > 0 then
    execute immediate 'drop package archive_domain_content_utils';
  end if;
end;
/

declare
  l_trigger_exists number;
begin
  select count(*)
    into l_trigger_exists
    from user_objects
   where object_name = 'ARCHIVE_DOMAIN_CONFIG_TS'
     and object_type = 'TRIGGER';

  if l_trigger_exists > 0 then
    execute immediate 'drop trigger archive_domain_config_ts';
  end if;
end;
/

declare
  l_table_exists number;
begin
  select count(*)
    into l_table_exists
    from user_objects
   where object_name = 'ARCHIVE_DOMAIN_CONFIG'
     and object_type = 'TABLE';

  if l_table_exists > 0 then
    execute immediate 'drop table archive_domain_config';
  end if;
end;
/
