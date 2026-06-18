--
-- Table definitions for the SQL archive-domain sample.
--
-- Copyright (c) 2026 Oracle and/or its affiliates.
-- Licensed under the Universal Permissive License v 1.0 as shown at
-- https://oss.oracle.com/licenses/upl.
--
-- DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
--

whenever sqlerror exit sql.sqlcode

create table archive_domain_config
(
  config_name varchar2(128) not null,
  config_json clob not null check (config_json is json),
  created_at  timestamp with time zone default systimestamp not null,
  updated_at  timestamp with time zone default systimestamp not null,
  constraint archive_domain_config_pk primary key (config_name)
);

create or replace trigger archive_domain_config_ts
before insert or update on archive_domain_config
for each row
begin
  if inserting then
    :new.created_at := systimestamp;
  end if;
  :new.updated_at := systimestamp;
end;
/

show errors;

declare
  l_error_count number;
begin
  select count(*)
    into l_error_count
    from user_errors
   where name = 'ARCHIVE_DOMAIN_CONFIG_TS'
     and type = 'TRIGGER';

  if l_error_count > 0 then
    raise_application_error(-20002, 'archive_domain_config_ts compilation failed');
  end if;
end;
/
