whenever sqlerror exit sql.sqlcode

set serveroutput on size unlimited
set feedback off

declare
  l_chunk_size constant pls_integer := 32767;
  l_export_format varchar2(32);
  l_file_uri_list varchar2(4000);
  l_result clob;
  l_offset pls_integer := 1;
  l_status varchar2(32);
  l_checkpoint_advanced varchar2(10);
  l_manifest_object_name varchar2(2048);
  l_config clob;
  l_credential_name varchar2(128);
  l_namespace varchar2(256);
  l_bucket_name varchar2(256);
  l_checkpoint_object varchar2(1024);
  l_region varchar2(128);
  l_manifest_uri varchar2(4000);
  l_checkpoint_uri varchar2(4000);
  l_manifest_blob blob;
  l_checkpoint_blob blob;
  l_manifest_clob clob;
  l_checkpoint_clob clob;

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
begin
  archive_domain_pkg.run(
    p_config_name  => 'default',
    p_dataset_list => 'raw',
    p_start_time   => systimestamp - numtodsinterval(5, 'MINUTE'),
    p_end_time     => systimestamp,
    p_result       => l_result
  );

  select json_value(l_result, '$.datasets.raw.status' returning varchar2(32))
    into l_status
    from dual;

  if l_status is null or l_status != 'succeeded' then
    raise_application_error(-20010, 'raw export did not succeed');
  end if;

  select json_value(l_result, '$.manifest_object_name' returning varchar2(2048))
    into l_manifest_object_name
    from dual;

  if l_manifest_object_name is null then
    raise_application_error(-20011, 'manifest_object_name missing');
  end if;

  select json_value(l_result, '$.datasets.raw.export_format' returning varchar2(32)),
         json_value(l_result, '$.datasets.raw.file_uri_list' returning varchar2(4000))
    into l_export_format, l_file_uri_list
    from dual;

  if l_export_format is null or l_export_format != 'datapump' then
    raise_application_error(-20016, 'raw export_format was not datapump');
  end if;

  if l_file_uri_list is null or l_file_uri_list not like '%.dmp' then
    raise_application_error(-20017, 'raw file_uri_list did not point to a dmp object');
  end if;

  select json_value(l_result, '$.checkpoint_advanced' returning varchar2(10))
    into l_checkpoint_advanced
    from dual;

  if l_checkpoint_advanced is null or l_checkpoint_advanced != 'true' then
    raise_application_error(-20012, 'checkpoint_advanced was not true');
  end if;

  select config_json
    into l_config
    from archive_domain_config
   where config_name = 'default';

  select json_value(l_config, '$.dbms_cloud_credential_name' returning varchar2(128) error on error),
         json_value(l_config, '$.namespace' returning varchar2(256) error on error),
         json_value(l_config, '$.bucket_name' returning varchar2(256) error on error),
         json_value(l_config, '$.checkpoint_object' returning varchar2(1024) error on error),
         coalesce(
           json_value(l_config, '$.region' returning varchar2(128) null on error),
           sys_context('USERENV', 'CLOUD_REGION')
         )
    into l_credential_name, l_namespace, l_bucket_name, l_checkpoint_object, l_region
    from dual;

  l_manifest_uri := build_object_uri(l_region, l_namespace, l_bucket_name, l_manifest_object_name);
  l_checkpoint_uri := build_object_uri(l_region, l_namespace, l_bucket_name, l_checkpoint_object);

  execute immediate
    q'[begin
          :result := dbms_cloud.get_object(
            credential_name => :credential_name,
            object_uri      => :object_uri
          );
        end;]'
    using out l_manifest_blob, in l_credential_name, in l_manifest_uri;

  l_manifest_clob := blob_to_clob(l_manifest_blob);
  if l_manifest_clob is null then
    raise_application_error(-20013, 'manifest object was not readable');
  end if;

  execute immediate
    q'[begin
          :result := dbms_cloud.get_object(
            credential_name => :credential_name,
            object_uri      => :object_uri
          );
        end;]'
    using out l_checkpoint_blob, in l_credential_name, in l_checkpoint_uri;

  l_checkpoint_clob := blob_to_clob(l_checkpoint_blob);
  if l_checkpoint_clob is null then
    raise_application_error(-20014, 'checkpoint object was not readable');
  end if;

  if json_value(l_checkpoint_clob, '$.last_successful_run_at' returning varchar2(128) null on empty) is null then
    raise_application_error(-20015, 'checkpoint did not include last_successful_run_at');
  end if;

  while l_offset <= dbms_lob.getlength(l_result) loop
    dbms_output.put_line(dbms_lob.substr(l_result, l_chunk_size, l_offset));
    l_offset := l_offset + l_chunk_size;
  end loop;
end;
/
