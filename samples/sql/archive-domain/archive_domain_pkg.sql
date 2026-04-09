--
-- SQL/PLSQL package for the DB-driven archive-domain sample.
--
-- Copyright (c) 2026 Oracle and/or its affiliates.
-- Licensed under the Universal Permissive License v 1.0 as shown at
-- https://oss.oracle.com/licenses/upl.
--
-- DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
--

create or replace package archive_domain_pkg as
  procedure plan(
    p_config_name  in varchar2 default 'default',
    p_dataset_list in varchar2 default 'raw,historized,rejected',
    p_start_time   in timestamp with time zone default null,
    p_end_time     in timestamp with time zone default null,
    p_result       out clob
  );

  procedure run(
    p_config_name  in varchar2 default 'default',
    p_dataset_list in varchar2 default 'raw,historized,rejected',
    p_start_time   in timestamp with time zone default null,
    p_end_time     in timestamp with time zone default null,
    p_result       out clob
  );
end archive_domain_pkg;
/

show errors

declare
  l_error_count number;
begin
  select count(*)
    into l_error_count
    from user_errors
   where name = 'ARCHIVE_DOMAIN_PKG'
     and type = 'PACKAGE';

  if l_error_count > 0 then
    raise_application_error(-20000, 'archive_domain_pkg spec compilation failed');
  end if;
end;
/

create or replace package body archive_domain_pkg as
  function build_stub_result(
    p_action       in varchar2,
    p_config_name  in varchar2,
    p_dataset_list in varchar2
  ) return clob
  is
    l_result clob;
  begin
    select json_serialize(
             json_object(
               'status' value 'stub',
               'action' value p_action,
               'config_name' value p_config_name,
               'datasets' value json_array(p_dataset_list)
             )
             returning clob pretty
           )
      into l_result
      from dual;

    return l_result;
  end build_stub_result;

  function load_config(
    p_config_name in varchar2 default 'default'
  ) return clob
  is
    l_config clob;
  begin
    select config_json
      into l_config
      from archive_domain_config
     where config_name = p_config_name;

    return l_config;
  exception
    when no_data_found then
      raise_application_error(-20010, 'archive_domain_config missing config: ' || p_config_name);
  end load_config;

  procedure plan(
    p_config_name  in varchar2 default 'default',
    p_dataset_list in varchar2 default 'raw,historized,rejected',
    p_start_time   in timestamp with time zone default null,
    p_end_time     in timestamp with time zone default null,
    p_result       out clob
  )
  is
  begin
    p_result := build_stub_result(
      p_action       => 'plan',
      p_config_name  => p_config_name,
      p_dataset_list => p_dataset_list
    );
  end plan;

  procedure run(
    p_config_name  in varchar2 default 'default',
    p_dataset_list in varchar2 default 'raw,historized,rejected',
    p_start_time   in timestamp with time zone default null,
    p_end_time     in timestamp with time zone default null,
    p_result       out clob
  )
  is
  begin
    p_result := build_stub_result(
      p_action       => 'run',
      p_config_name  => p_config_name,
      p_dataset_list => p_dataset_list
    );
  end run;
end archive_domain_pkg;
/

show errors

declare
  l_error_count number;
begin
  select count(*)
    into l_error_count
    from user_errors
   where name = 'ARCHIVE_DOMAIN_PKG'
     and type = 'PACKAGE BODY';

  if l_error_count > 0 then
    raise_application_error(-20001, 'archive_domain_pkg body compilation failed');
  end if;
end;
/
