--
-- This script removes supporting objects for the IoT Platform Explorer.
--
-- Copyright (c) 2025 Oracle and/or its affiliates.
-- Licensed under the Universal Permissive License v 1.0 as shown at
-- https://oss.oracle.com/licenses/upl.
--
-- DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
--

drop view iot_model_view;
drop view iot_adapter_view;
drop view iot_instance_view;
drop view iot_passwords;
drop view iot_certs;
drop view auth_view;
drop package iot_oci;
drop package iot_objects;
drop package iot_info;
drop package iot_apex;
drop table iot_config;
drop view iot_hierarchy;
drop view iot_stats;
declare
  l_job_exists number;
  begin
    select  count(*) into l_job_exists
    from    user_scheduler_jobs
    where   job_name = 'REFRESH_MVIEW_IOT_MSG_STATS';

    if l_job_exists = 1 then
      dbms_scheduler.drop_job(job_name => 'REFRESH_MVIEW_IOT_MSG_STATS');
    end if;
end;
/
declare
    count_mv number;
  begin
    select count(*) into count_mv
    from all_mviews
    where mview_name = 'IOT_MSG_STATS';

    if count_mv > 0 then
        execute immediate 'drop materialized view iot_msg_stats';
    end if;
end;
/
declare
  cursor rec_cur is
    select  'drop synonym '||lower(replace(view_name,'DIGITAL_TWIN_',''))||'_syn' as statement
    from    all_views
    where   upper(owner) = replace( sys_context( 'userenv', 'current_schema' ), '__WKSP', '__IOT' )
    and     view_name not like 'AQ$%';
  begin

  for rec in rec_cur loop

    begin

      execute immediate rec.statement;
      DBMS_OUTPUT.PUT_LINE('Successfully executed: ' || rec.statement);

    exception
      when others then
        DBMS_OUTPUT.PUT_LINE('Failed to execute: ' || rec.statement || '. Error: ' || SQLERRM);

    end;

  end loop;

end;
/