whenever sqlerror exit sql.sqlcode

set serveroutput on size unlimited
set feedback off

declare
  l_config_json clob;
  l_result clob;
begin
  select json_serialize(
           json_mergepatch(
             config_json,
             json_object('export_format' value 'datapump')
           )
           returning clob pretty
         )
    into l_config_json
    from archive_domain_config
   where config_name = 'default';

  merge into archive_domain_config tgt
  using (select 'datapump_blocked' as config_name from dual) src
  on (tgt.config_name = src.config_name)
  when matched then
    update set config_json = l_config_json
  when not matched then
    insert (config_name, config_json)
    values (src.config_name, l_config_json);

  begin
    archive_domain_pkg.plan(
      p_config_name  => 'datapump_blocked',
      p_dataset_list => 'raw',
      p_result       => l_result
    );
    raise_application_error(-20090, 'datapump blocked check did not fail');
  exception
    when others then
      if sqlcode != -20025 then
        raise;
      end if;
      dbms_output.put_line('BLOCKED_OK');
  end;

  delete from archive_domain_config
   where config_name = 'datapump_blocked';
exception
  when others then
    delete from archive_domain_config
     where config_name = 'datapump_blocked';
    raise;
end;
/
