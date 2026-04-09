whenever sqlerror exit sql.sqlcode

set serveroutput on size unlimited
set feedback off

declare
  l_chunk_size constant pls_integer := 32767;
  l_result clob;
  l_offset pls_integer := 1;
begin
  archive_domain_pkg.plan(
    p_config_name  => 'default',
    p_dataset_list => 'raw',
    p_result       => l_result
  );

  if json_value(l_result, '$.datasets.raw.window_start') is null then
    raise_application_error(-20000, 'window_start missing');
  end if;

  if json_value(l_result, '$.datasets.raw.window_end') is null then
    raise_application_error(-20001, 'window_end missing');
  end if;

  while l_offset <= dbms_lob.getlength(l_result) loop
    dbms_output.put_line(dbms_lob.substr(l_result, l_chunk_size, l_offset));
    l_offset := l_offset + l_chunk_size;
  end loop;
end;
/
