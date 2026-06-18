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

  function clob_to_blob(
    p_value in clob
  ) return blob
  is
    l_result blob;
    l_dest_offset integer := 1;
    l_src_offset integer := 1;
    l_lang_context integer := dbms_lob.default_lang_ctx;
    l_warning integer;
  begin
    if p_value is null then
      return null;
    end if;

    dbms_lob.createtemporary(l_result, true);
    dbms_lob.converttoblob(
      dest_lob     => l_result,
      src_clob     => p_value,
      amount       => dbms_lob.lobmaxsize,
      dest_offset  => l_dest_offset,
      src_offset   => l_src_offset,
      blob_csid    => nls_charset_id('AL32UTF8'),
      lang_context => l_lang_context,
      warning      => l_warning
    );
    return l_result;
  end clob_to_blob;

  function is_not_found_error(
    p_error_code in number
  ) return boolean
  is
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

  function resolve_region(
    p_config in clob
  ) return varchar2
  is
    l_region varchar2(128);
  begin
    select coalesce(
             json_value(p_config, '$.region' returning varchar2(128) null on error),
             sys_context('USERENV', 'CLOUD_REGION')
           )
      into l_region
      from dual;

    return l_region;
  end resolve_region;

  function resolve_export_format(
    p_config in clob
  ) return varchar2
  is
    l_export_format varchar2(30);
  begin
    select lower(
             coalesce(
               json_value(p_config, '$.export_format' returning varchar2(30) null on error),
               'parquet'
             )
           )
      into l_export_format
      from dual;

    if l_export_format not in ('parquet', 'datapump') then
      raise_application_error(-20024, 'unsupported export_format: ' || l_export_format);
    end if;

    return l_export_format;
  end resolve_export_format;

  procedure validate_export_request(
    p_export_format in varchar2,
    p_datasets      in t_dataset_list
  )
  is
  begin
    if p_export_format != 'datapump' then
      return;
    end if;

    if p_datasets.count != 1 then
      raise_application_error(-20026, 'datapump export format requires exactly one dataset per run');
    end if;
  end validate_export_request;

  function trim_slashes(
    p_value in varchar2
  ) return varchar2
  is
  begin
    return regexp_replace(nvl(trim(p_value), ''), '^/+|/+$', '');
  end trim_slashes;

  function build_object_uri(
    p_region      in varchar2,
    p_namespace   in varchar2,
    p_bucket_name in varchar2,
    p_object_name in varchar2
  ) return varchar2
  is
  begin
    return 'https://objectstorage.' || p_region || '.oraclecloud.com/n/'
           || p_namespace || '/b/' || p_bucket_name || '/o/' || p_object_name;
  end build_object_uri;

  function build_run_id(
    p_run_at in timestamp with time zone
  ) return varchar2
  is
  begin
    return to_char(p_run_at at time zone 'UTC', 'YYYYMMDD"T"HH24MISS"Z"');
  end build_run_id;

  function resolve_zone(
    p_dataset in varchar2
  ) return varchar2
  is
  begin
    case p_dataset
      when 'historized' then
        return 'silver';
      when 'raw' then
        return 'bronze';
      when 'rejected' then
        return 'bronze';
      else
        raise_application_error(-20021, 'unsupported dataset for zone mapping: ' || p_dataset);
    end case;
  end resolve_zone;

  function build_dataset_object_prefix(
    p_prefix            in varchar2,
    p_domain_short_name in varchar2,
    p_dataset           in varchar2,
    p_run_id            in varchar2,
    p_run_at            in timestamp with time zone
  ) return varchar2
  is
    l_prefix varchar2(1024);
    l_run_at_utc timestamp with time zone;
    l_zone varchar2(30);
  begin
    l_prefix := trim_slashes(p_prefix);
    l_run_at_utc := p_run_at at time zone 'UTC';
    l_zone := resolve_zone(p_dataset);
    return l_prefix
           || '/domain=' || p_domain_short_name
           || '/zone=' || l_zone || '/dataset=' || p_dataset
           || '/year=' || to_char(l_run_at_utc, 'YYYY')
           || '/month=' || to_char(l_run_at_utc, 'MM')
           || '/day=' || to_char(l_run_at_utc, 'DD')
           || '/hour=' || to_char(l_run_at_utc, 'HH24')
           || '/run_id=' || p_run_id;
  end build_dataset_object_prefix;

  function build_manifest_object_name(
    p_manifest_prefix in varchar2,
    p_run_id          in varchar2
  ) return varchar2
  is
  begin
    return trim_slashes(p_manifest_prefix) || '/run_id=' || p_run_id || '.json';
  end build_manifest_object_name;

  function to_sql_timestamp_tz_literal(
    p_value in timestamp with time zone
  ) return varchar2
  is
  begin
    return 'to_timestamp_tz('''
           || to_char(p_value at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.FF3TZH:TZM')
           || ''',''YYYY-MM-DD"T"HH24:MI:SS.FF3TZH:TZM'')';
  end to_sql_timestamp_tz_literal;

  function normalized_content_type_sql return varchar2
  is
  begin
    return 'lower(trim(regexp_substr(content_type, ''^[^;]+'')))';
  end normalized_content_type_sql;

  function json_candidate_sql return varchar2
  is
  begin
    return 'to_clob(utl_raw.cast_to_varchar2(dbms_lob.substr(content, 32767, 1)))';
  end json_candidate_sql;

  function content_encoding_sql return varchar2
  is
    l_content_type_expr varchar2(4000);
    l_json_candidate_expr varchar2(4000);
  begin
    l_content_type_expr := normalized_content_type_sql();
    l_json_candidate_expr := json_candidate_sql();
    return 'case '
           || 'when ' || l_content_type_expr || ' like ''text/%'' then ''text'' '
           || 'when ' || l_content_type_expr || ' is null or instr(' || l_content_type_expr || ', ''json'') > 0 then '
           || 'case when ' || l_json_candidate_expr || ' is json strict then ''json'' else ''base64'' end '
           || 'else ''base64'' '
           || 'end';
  end content_encoding_sql;

  function content_representation_sql return varchar2
  is
    l_content_type_expr varchar2(4000);
    l_json_candidate_expr varchar2(4000);
  begin
    l_content_type_expr := normalized_content_type_sql();
    l_json_candidate_expr := json_candidate_sql();
    return 'case '
           || 'when ' || l_content_type_expr || ' like ''text/%'' then ''json-string'' '
           || 'when ' || l_content_type_expr || ' is null or instr(' || l_content_type_expr || ', ''json'') > 0 then '
           || 'case when ' || l_json_candidate_expr || ' is json strict then ''parsed-json'' else ''base64-string'' end '
           || 'else ''base64-string'' '
           || 'end';
  end content_representation_sql;

  function build_raw_query(
    p_domain_short_name in varchar2,
    p_export_format     in varchar2,
    p_window_start      in timestamp with time zone,
    p_window_end        in timestamp with time zone
  ) return clob
  is
    l_iot_schema varchar2(261);
  begin
    l_iot_schema := dbms_assert.simple_sql_name(
      upper(trim(p_domain_short_name)) || '__IOT'
    );

    if p_export_format = 'datapump' then
      return 'select * '
             || 'from ' || l_iot_schema || '.raw_data '
             || 'where time_received >= ' || to_sql_timestamp_tz_literal(p_window_start) || ' '
             || 'and time_received < ' || to_sql_timestamp_tz_literal(p_window_end) || ' '
             || 'order by time_received, id';
    end if;

    return 'select '
           || 'id, digital_twin_instance_id, endpoint, time_received, content_type, '
           || content_encoding_sql() || ' as content_encoding, '
           || content_representation_sql() || ' as content_representation, '
           || 'blob_to_json(content, content_type) as content '
           || 'from ' || l_iot_schema || '.raw_data '
           || 'where time_received >= ' || to_sql_timestamp_tz_literal(p_window_start) || ' '
           || 'and time_received < ' || to_sql_timestamp_tz_literal(p_window_end) || ' '
           || 'order by time_received, id';
  end build_raw_query;

  function build_historized_query(
    p_domain_short_name in varchar2,
    p_export_format     in varchar2,
    p_window_start      in timestamp with time zone,
    p_window_end        in timestamp with time zone
  ) return clob
  is
    l_iot_schema varchar2(261);
  begin
    l_iot_schema := dbms_assert.simple_sql_name(
      upper(trim(p_domain_short_name)) || '__IOT'
    );

    if p_export_format = 'datapump' then
      return 'select * '
             || 'from ' || l_iot_schema || '.historized_data '
             || 'where time_observed >= ' || to_sql_timestamp_tz_literal(p_window_start) || ' '
             || 'and time_observed < ' || to_sql_timestamp_tz_literal(p_window_end) || ' '
             || 'order by time_observed, id';
    end if;

    return 'select '
           || 'id, digital_twin_instance_id, content_path, time_observed, '
           || 'json_serialize(value returning varchar2(32767)) as value_json, '
           || 'json_value(value, ''$'' returning number null on error) as value_number, '
           || 'json_value(value, ''$'' returning varchar2(32767) null on error) as value_text '
           || 'from ' || l_iot_schema || '.historized_data '
           || 'where time_observed >= ' || to_sql_timestamp_tz_literal(p_window_start) || ' '
           || 'and time_observed < ' || to_sql_timestamp_tz_literal(p_window_end) || ' '
           || 'order by time_observed, id';
  end build_historized_query;

  function build_rejected_query(
    p_domain_short_name in varchar2,
    p_export_format     in varchar2,
    p_window_start      in timestamp with time zone,
    p_window_end        in timestamp with time zone
  ) return clob
  is
    l_iot_schema varchar2(261);
  begin
    l_iot_schema := dbms_assert.simple_sql_name(
      upper(trim(p_domain_short_name)) || '__IOT'
    );

    if p_export_format = 'datapump' then
      return 'select * '
             || 'from ' || l_iot_schema || '.rejected_data '
             || 'where time_received >= ' || to_sql_timestamp_tz_literal(p_window_start) || ' '
             || 'and time_received < ' || to_sql_timestamp_tz_literal(p_window_end) || ' '
             || 'order by time_received, id';
    end if;

    return 'select '
           || 'id, digital_twin_instance_id, endpoint, time_received, '
           || 'reason_code, reason_message, content_type, '
           || content_encoding_sql() || ' as content_encoding, '
           || content_representation_sql() || ' as content_representation, '
           || 'blob_to_json(content, content_type) as content '
           || 'from ' || l_iot_schema || '.rejected_data '
           || 'where time_received >= ' || to_sql_timestamp_tz_literal(p_window_start) || ' '
           || 'and time_received < ' || to_sql_timestamp_tz_literal(p_window_end) || ' '
           || 'order by time_received, id';
  end build_rejected_query;

  procedure put_json_object(
    p_credential_name in varchar2,
    p_object_uri      in varchar2,
    p_payload         in clob
  )
  is
    l_payload_blob blob;
  begin
    l_payload_blob := clob_to_blob(p_payload);

    dbms_cloud.put_object(
      credential_name => p_credential_name,
      object_uri      => p_object_uri,
      contents        => l_payload_blob
    );
  end put_json_object;

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
    l_export_format varchar2(30);
    l_retention_days pls_integer;
    l_purge_boundary timestamp with time zone;
    l_window_start timestamp with time zone;
    l_window_end timestamp with time zone;
  begin
    l_config := load_config(p_config_name => p_config_name);
    l_datasets := parse_datasets(p_dataset_list => p_dataset_list);
    l_export_format := resolve_export_format(p_config => l_config);
    validate_export_request(
      p_export_format => l_export_format,
      p_datasets      => l_datasets
    );
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
    l_result_obj.put('export_format', l_export_format);
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
    l_config clob;
    l_datasets t_dataset_list;
    l_plan_result clob;
    l_plan_obj json_object_t;
    l_plan_datasets_obj json_object_t;
    l_plan_dataset_obj json_object_t;
    l_checkpoint_before_element json_element_t;
    l_run_at timestamp with time zone;
    l_window_start timestamp with time zone;
    l_window_end timestamp with time zone;
    l_region varchar2(128);
    l_domain_short_name varchar2(128);
    l_namespace varchar2(256);
    l_bucket_name varchar2(256);
    l_prefix varchar2(1024);
    l_manifest_prefix varchar2(1024);
    l_checkpoint_object varchar2(1024);
    l_credential_name varchar2(128);
    l_checkpoint_before varchar2(128);
    l_dataset varchar2(30);
    l_run_id varchar2(64);
    l_dataset_object_prefix varchar2(2048);
    l_dataset_file_uri_list varchar2(4000);
    l_dataset_query clob;
    l_dataset_export_format varchar2(30);
    l_dataset_status varchar2(32);
    l_dataset_error_message varchar2(4000);
    l_all_succeeded boolean := true;
    l_selected_datasets json_array_t := json_array_t();
    l_manifest_dataset_results json_array_t := json_array_t();
    l_result_datasets_obj json_object_t := json_object_t();
    l_manifest_dataset_obj json_object_t;
    l_result_dataset_obj json_object_t;
    l_manifest_obj json_object_t := json_object_t();
    l_result_obj json_object_t := json_object_t();
    l_manifest_object_name varchar2(2048);
    l_manifest_uri varchar2(4000);
    l_manifest_json clob;
    l_checkpoint_uri varchar2(4000);
    l_checkpoint_json clob;
    l_export_format varchar2(30);
  begin
    l_config := load_config(p_config_name => p_config_name);
    l_datasets := parse_datasets(p_dataset_list => p_dataset_list);

    plan(
      p_config_name  => p_config_name,
      p_dataset_list => p_dataset_list,
      p_start_time   => p_start_time,
      p_end_time     => p_end_time,
      p_result       => l_plan_result
    );

    l_plan_obj := json_object_t.parse(l_plan_result);
    l_run_at := parse_timestamp(l_plan_obj.get_string('now'));
    l_export_format := l_plan_obj.get_string('export_format');
    l_plan_datasets_obj := l_plan_obj.get_object('datasets');
    l_checkpoint_before_element := l_plan_obj.get('checkpoint_before');
    if l_checkpoint_before_element is not null and not l_checkpoint_before_element.is_null then
      l_checkpoint_before := l_plan_obj.get_string('checkpoint_before');
    end if;

    select json_value(l_config, '$.domain_short_name' returning varchar2(128) error on error),
           json_value(l_config, '$.namespace' returning varchar2(256) error on error),
           json_value(l_config, '$.bucket_name' returning varchar2(256) error on error),
           json_value(l_config, '$.prefix' returning varchar2(1024) error on error),
           json_value(l_config, '$.manifest_prefix' returning varchar2(1024) error on error),
           json_value(l_config, '$.checkpoint_object' returning varchar2(1024) error on error),
           json_value(l_config, '$.dbms_cloud_credential_name' returning varchar2(128) error on error)
      into l_domain_short_name, l_namespace, l_bucket_name, l_prefix, l_manifest_prefix,
           l_checkpoint_object, l_credential_name
      from dual;

    l_region := resolve_region(l_config);
    if l_region is null then
      raise_application_error(-20020, 'missing region and CLOUD_REGION context');
    end if;

    l_run_id := build_run_id(l_run_at);
    for l_index in 1 .. l_datasets.count loop
      l_dataset := l_datasets(l_index);
      l_selected_datasets.append(l_dataset);

      l_plan_dataset_obj := l_plan_datasets_obj.get_object(l_dataset);
      l_window_start := parse_timestamp(l_plan_dataset_obj.get_string('window_start'));
      l_window_end := parse_timestamp(l_plan_dataset_obj.get_string('window_end'));

      l_dataset_object_prefix := build_dataset_object_prefix(
        p_prefix            => l_prefix,
        p_domain_short_name => l_domain_short_name,
        p_dataset           => l_dataset,
        p_run_id            => l_run_id,
        p_run_at            => l_run_at
      );

      case l_dataset
        when 'raw' then
          l_dataset_query := build_raw_query(
            p_domain_short_name => l_domain_short_name,
            p_export_format     => l_export_format,
            p_window_start      => l_window_start,
            p_window_end        => l_window_end
          );
          l_dataset_export_format := l_export_format;
          if l_export_format = 'datapump' then
            l_dataset_file_uri_list := build_object_uri(
              p_region      => l_region,
              p_namespace   => l_namespace,
              p_bucket_name => l_bucket_name,
              p_object_name => l_dataset_object_prefix || '/raw_01.dmp'
            );
          else
            l_dataset_file_uri_list := build_object_uri(
              p_region      => l_region,
              p_namespace   => l_namespace,
              p_bucket_name => l_bucket_name,
              p_object_name => l_dataset_object_prefix || '/' || l_dataset
            );
          end if;
        when 'historized' then
          l_dataset_query := build_historized_query(
            p_domain_short_name => l_domain_short_name,
            p_export_format     => l_export_format,
            p_window_start      => l_window_start,
            p_window_end        => l_window_end
          );
          l_dataset_export_format := l_export_format;
          if l_export_format = 'datapump' then
            l_dataset_file_uri_list := build_object_uri(
              p_region      => l_region,
              p_namespace   => l_namespace,
              p_bucket_name => l_bucket_name,
              p_object_name => l_dataset_object_prefix || '/historized_01.dmp'
            );
          else
            l_dataset_file_uri_list := build_object_uri(
              p_region      => l_region,
              p_namespace   => l_namespace,
              p_bucket_name => l_bucket_name,
              p_object_name => l_dataset_object_prefix || '/' || l_dataset
            );
          end if;
        when 'rejected' then
          l_dataset_query := build_rejected_query(
            p_domain_short_name => l_domain_short_name,
            p_export_format     => l_export_format,
            p_window_start      => l_window_start,
            p_window_end        => l_window_end
          );
          l_dataset_export_format := l_export_format;
          if l_export_format = 'datapump' then
            l_dataset_file_uri_list := build_object_uri(
              p_region      => l_region,
              p_namespace   => l_namespace,
              p_bucket_name => l_bucket_name,
              p_object_name => l_dataset_object_prefix || '/rejected_01.dmp'
            );
          else
            l_dataset_file_uri_list := build_object_uri(
              p_region      => l_region,
              p_namespace   => l_namespace,
              p_bucket_name => l_bucket_name,
              p_object_name => l_dataset_object_prefix || '/' || l_dataset
            );
          end if;
      end case;

      l_dataset_status := 'planned';
      l_dataset_error_message := null;

      begin
        if l_dataset_export_format = 'datapump' then
          dbms_cloud.export_data(
            credential_name => l_credential_name,
            file_uri_list   => l_dataset_file_uri_list,
            format          => json_object(
                                 'type' value 'datapump',
                                 'compression' value 'HIGH',
                                 'version' value 'LATEST'
                               ),
            query           => l_dataset_query
          );
        else
          dbms_cloud.export_data(
            credential_name => l_credential_name,
            file_uri_list   => l_dataset_file_uri_list,
            format          => '{"type":"' || l_dataset_export_format || '"}',
            query           => l_dataset_query
          );
        end if;
        l_dataset_status := 'succeeded';
      exception
        when others then
          l_dataset_status := 'failed';
          l_dataset_error_message := substr(sqlerrm, 1, 4000);
      end;

      if l_dataset_status <> 'succeeded' then
        l_all_succeeded := false;
      end if;

      l_manifest_dataset_obj := json_object_t();
      l_manifest_dataset_obj.put('name', l_dataset);
      l_manifest_dataset_obj.put('status', l_dataset_status);
      l_manifest_dataset_obj.put('export_mode', 'bulk');
      l_manifest_dataset_obj.put('export_format', l_dataset_export_format);
      l_manifest_dataset_obj.put('object_prefix', l_dataset_object_prefix);
      if l_dataset_error_message is null then
        l_manifest_dataset_obj.put_null('error_message');
      else
        l_manifest_dataset_obj.put('error_message', l_dataset_error_message);
      end if;
      l_manifest_dataset_results.append(l_manifest_dataset_obj);

      l_result_dataset_obj := json_object_t();
      l_result_dataset_obj.put('status', l_dataset_status);
      l_result_dataset_obj.put('export_format', l_dataset_export_format);
      l_result_dataset_obj.put('object_prefix', l_dataset_object_prefix);
      l_result_dataset_obj.put('file_uri_list', l_dataset_file_uri_list);
      if l_dataset_error_message is null then
        l_result_dataset_obj.put_null('error_message');
      else
        l_result_dataset_obj.put('error_message', l_dataset_error_message);
      end if;
      l_result_datasets_obj.put(l_dataset, l_result_dataset_obj);
    end loop;

    l_manifest_object_name := build_manifest_object_name(
      p_manifest_prefix => l_manifest_prefix,
      p_run_id          => l_run_id
    );
    l_manifest_uri := build_object_uri(
      p_region      => l_region,
      p_namespace   => l_namespace,
      p_bucket_name => l_bucket_name,
      p_object_name => l_manifest_object_name
    );

    l_manifest_obj.put('run_id', l_run_id);
    l_manifest_obj.put('selected_datasets', l_selected_datasets);
    if l_checkpoint_before is null then
      l_manifest_obj.put_null('checkpoint_before');
    else
      l_manifest_obj.put('checkpoint_before', l_checkpoint_before);
    end if;
    l_manifest_obj.put('dataset_results', l_manifest_dataset_results);
    l_manifest_json := l_manifest_obj.to_clob();

    put_json_object(
      p_credential_name => l_credential_name,
      p_object_uri      => l_manifest_uri,
      p_payload         => l_manifest_json
    );

    if l_all_succeeded then
      l_checkpoint_uri := build_object_uri(
        p_region      => l_region,
        p_namespace   => l_namespace,
        p_bucket_name => l_bucket_name,
        p_object_name => l_checkpoint_object
      );

      l_result_dataset_obj := json_object_t();
      l_result_dataset_obj.put('last_successful_run_at', format_timestamp(l_run_at));
      l_checkpoint_json := l_result_dataset_obj.to_clob();

      put_json_object(
        p_credential_name => l_credential_name,
        p_object_uri      => l_checkpoint_uri,
        p_payload         => l_checkpoint_json
      );
    end if;

    l_result_obj.put('run_id', l_run_id);
    l_result_obj.put('export_format', l_export_format);
    l_result_obj.put('datasets', l_result_datasets_obj);
    l_result_obj.put('manifest_object_name', l_manifest_object_name);
    l_result_obj.put('checkpoint_advanced', l_all_succeeded);
    p_result := l_result_obj.to_clob();
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
