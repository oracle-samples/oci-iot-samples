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
  type t_dataset_list is table of varchar2(30) index by pls_integer;
  type t_seen_map is table of pls_integer index by varchar2(30);

  function format_timestamp(
    p_value in timestamp with time zone
  ) return varchar2
  is
  begin
    return to_char(
      p_value at time zone 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.FF3"Z"'
    );
  end format_timestamp;

  function parse_timestamp(
    p_value in varchar2
  ) return timestamp with time zone
  is
    l_value varchar2(128);
    l_has_fraction boolean;
  begin
    if p_value is null then
      return null;
    end if;

    l_value := trim(p_value);
    if substr(l_value, -1) = 'Z' then
      l_value := substr(l_value, 1, length(l_value) - 1) || '+00:00';
    end if;

    l_has_fraction := instr(l_value, '.') > 0;

    if l_has_fraction then
      return to_timestamp_tz(
        l_value,
        'YYYY-MM-DD"T"HH24:MI:SS.FFTZH:TZM'
      );
    end if;

    return to_timestamp_tz(
      l_value,
      'YYYY-MM-DD"T"HH24:MI:SSTZH:TZM'
    );
  exception
    when others then
      raise_application_error(-20018, 'invalid checkpoint timestamp: ' || p_value);
  end parse_timestamp;

  function blob_to_clob(
    p_value in blob
  ) return clob
  is
    l_result clob;
    l_dest_offset integer := 1;
    l_src_offset integer := 1;
    l_lang_context integer := dbms_lob.default_lang_ctx;
    l_warning integer;
  begin
    if p_value is null then
      return null;
    end if;

    dbms_lob.createtemporary(l_result, true);
    dbms_lob.converttoclob(
      dest_lob     => l_result,
      src_blob     => p_value,
      amount       => dbms_lob.lobmaxsize,
      dest_offset  => l_dest_offset,
      src_offset   => l_src_offset,
      blob_csid    => nls_charset_id('AL32UTF8'),
      lang_context => l_lang_context,
      warning      => l_warning
    );
    return l_result;
  end blob_to_clob;

  function is_not_found_error(
    p_error_code in number
  ) return boolean
  begin
    return p_error_code = -20404;
  end is_not_found_error;

  function parse_datasets(
    p_dataset_list in varchar2
  ) return t_dataset_list
  is
    l_result t_dataset_list;
    l_seen t_seen_map;
    l_token varchar2(128);
    l_dataset varchar2(30);
    l_index pls_integer := 1;
    l_count pls_integer := 0;
  begin
    if trim(p_dataset_list) is null then
      raise_application_error(-20011, 'dataset list cannot be empty');
    end if;

    loop
      l_token := regexp_substr(p_dataset_list, '[^,]+', 1, l_index);
      exit when l_token is null;
      l_dataset := lower(trim(l_token));

      if l_dataset not in ('raw', 'historized', 'rejected') then
        raise_application_error(-20012, 'unsupported dataset: ' || l_dataset);
      end if;

      if not l_seen.exists(l_dataset) then
        l_count := l_count + 1;
        l_result(l_count) := l_dataset;
        l_seen(l_dataset) := 1;
      end if;

      l_index := l_index + 1;
    end loop;

    if l_count = 0 then
      raise_application_error(-20011, 'dataset list cannot be empty');
    end if;

    return l_result;
  end parse_datasets;

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

  function resolve_retention_days(
    p_config  in clob,
    p_dataset in varchar2
  ) return pls_integer
  is
    l_config_obj json_object_t;
    l_retention_obj json_object_t;
    l_retention_days pls_integer;
  begin
    l_config_obj := json_object_t.parse(p_config);
    l_retention_obj := l_config_obj.get_object('retention_days');

    if l_retention_obj is null or not l_retention_obj.has(p_dataset) then
      raise_application_error(-20014, 'missing or invalid retention_days.' || p_dataset);
    end if;

    l_retention_days := l_retention_obj.get_number(p_dataset);

    if l_retention_days < 0 then
      raise_application_error(-20013, 'retention_days.' || p_dataset || ' must be >= 0');
    end if;

    return l_retention_days;
  exception
    when value_error then
      raise_application_error(-20014, 'missing or invalid retention_days.' || p_dataset);
    when no_data_found then
      raise_application_error(-20014, 'missing or invalid retention_days.' || p_dataset);
    when others then
      if sqlcode = -20013 then
        raise;
      end if;
      raise_application_error(-20014, 'missing or invalid retention_days.' || p_dataset);
  end resolve_retention_days;

  function load_checkpoint(
    p_config in clob
  ) return timestamp with time zone
  is
    l_credential_name varchar2(128);
    l_namespace varchar2(256);
    l_bucket_name varchar2(256);
    l_checkpoint_object varchar2(1024);
    l_region varchar2(128);
    l_uri varchar2(4000);
    l_checkpoint_blob blob;
    l_checkpoint_json clob;
    l_timestamp_text varchar2(128);
    l_loaded boolean := false;
  begin
    select json_value(p_config, '$.dbms_cloud_credential_name' returning varchar2(128) error on error),
           json_value(p_config, '$.namespace' returning varchar2(256) error on error),
           json_value(p_config, '$.bucket_name' returning varchar2(256) error on error),
           json_value(p_config, '$.checkpoint_object' returning varchar2(1024) error on error)
      into l_credential_name, l_namespace, l_bucket_name, l_checkpoint_object
      from dual;

    select coalesce(
             json_value(p_config, '$.region' returning varchar2(128) null on error),
             sys_context('USERENV', 'CLOUD_REGION')
           )
      into l_region
      from dual;

    if l_region is null then
      return null;
    end if;

    l_uri := 'https://objectstorage.' || l_region || '.oraclecloud.com/n/'
             || l_namespace || '/b/' || l_bucket_name || '/o/' || l_checkpoint_object;

    begin
      execute immediate
        q'[begin
              :result := dbms_cloud.get_object(
                credential_name => :credential_name,
                object_uri      => :object_uri
              );
            end;]'
        using out l_checkpoint_blob, in l_credential_name, in l_uri;
      l_checkpoint_json := blob_to_clob(l_checkpoint_blob);
      l_loaded := true;
    exception
      when others then
        if is_not_found_error(sqlcode) then
          return null;
        end if;
    end;

    if not l_loaded then
      execute immediate
        q'[begin
              :result := dbms_cloud.get_object(
                credential_name => :credential_name,
                object_uri      => :object_uri
              );
            end;]'
        using out l_checkpoint_json, in l_credential_name, in l_uri;
    end if;

    select json_value(
             l_checkpoint_json,
             '$.last_successful_run_at'
             returning varchar2(128)
             null on empty
             error on error
           )
      into l_timestamp_text
      from dual;

    return parse_timestamp(l_timestamp_text);
  exception
    when others then
      if is_not_found_error(sqlcode) then
        return null;
      end if;
      raise;
  end load_checkpoint;

  procedure plan(
    p_config_name  in varchar2 default 'default',
    p_dataset_list in varchar2 default 'raw,historized,rejected',
    p_start_time   in timestamp with time zone default null,
    p_end_time     in timestamp with time zone default null,
    p_result       out clob
  )
  is
    l_config clob;
    l_now timestamp with time zone := systimestamp;
    l_checkpoint_before timestamp with time zone;
    l_bootstrap_lookback_days pls_integer;
    l_datasets t_dataset_list;
    l_result_obj json_object_t := json_object_t();
    l_datasets_obj json_object_t := json_object_t();
    l_dataset_obj json_object_t;
    l_dataset varchar2(30);
    l_retention_days pls_integer;
    l_purge_boundary timestamp with time zone;
    l_window_start timestamp with time zone;
    l_window_end timestamp with time zone;
  begin
    l_config := load_config(p_config_name => p_config_name);
    l_datasets := parse_datasets(p_dataset_list => p_dataset_list);
    l_checkpoint_before := load_checkpoint(p_config => l_config);

    begin
      select json_value(
               l_config,
               '$.bootstrap_lookback_days'
               returning number
               error on error
             )
        into l_bootstrap_lookback_days
        from dual;
    exception
      when others then
        raise_application_error(-20017, 'missing or invalid bootstrap_lookback_days');
    end;

    if l_bootstrap_lookback_days < 0 then
      raise_application_error(-20016, 'bootstrap_lookback_days must be >= 0');
    end if;

    l_result_obj.put('now', format_timestamp(l_now));
    if l_checkpoint_before is null then
      l_result_obj.put_null('checkpoint_before');
    else
      l_result_obj.put('checkpoint_before', format_timestamp(l_checkpoint_before));
    end if;

    for l_index in 1 .. l_datasets.count loop
      l_dataset := l_datasets(l_index);
      l_retention_days := resolve_retention_days(
        p_config  => l_config,
        p_dataset => l_dataset
      );
      l_purge_boundary := l_now - numtodsinterval(l_retention_days, 'DAY');
      l_window_end := coalesce(p_end_time, l_purge_boundary);

      if p_start_time is not null then
        l_window_start := p_start_time;
      elsif l_checkpoint_before is not null then
        l_window_start := l_checkpoint_before - numtodsinterval(l_retention_days, 'DAY');
      else
        l_window_start := l_purge_boundary - numtodsinterval(l_bootstrap_lookback_days, 'DAY');
      end if;

      l_dataset_obj := json_object_t();
      l_dataset_obj.put('retention_days', l_retention_days);
      l_dataset_obj.put('purge_boundary', format_timestamp(l_purge_boundary));
      l_dataset_obj.put('window_start', format_timestamp(l_window_start));
      l_dataset_obj.put('window_end', format_timestamp(l_window_end));
      l_datasets_obj.put(l_dataset, l_dataset_obj);
    end loop;

    l_result_obj.put('datasets', l_datasets_obj);
    p_result := l_result_obj.to_clob();
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
