--
-- This script grates supporting objects for the IoT Platform Explorer.
--
-- Copyright (c) 2025 Oracle and/or its affiliates.
-- Licensed under the Universal Permissive License v 1.0 as shown at
-- https://oss.oracle.com/licenses/upl.
--
-- DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
--

--Function that changes a number into a shortened string representation
create or replace function compact_number (n number)
  return varchar2
  is 
    begin
      if n = 0 then 
          return '0';
      else
          return round((n/power(1000,trunc(log(1000,trunc(abs(n)))))),1) || ltrim(substr(' KMBT',trunc(log(1000,trunc(abs(n)))) + 1,1));
      end if;
      exception
        when others then
          DBMS_OUTPUT.PUT_LINE('Failure in compact_number(). Error: ' || SQLERRM);
end;
/

--Creates the synonyms in the __wksp schema for the views in the __iot schema 
declare
  cursor rec_cur is
    select  'create or replace synonym '||lower(replace(view_name,'DIGITAL_TWIN_',''))||'_syn for '||lower(owner)||'.'||lower(view_name) as statement
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

--Materialized view for counting messages received.
create materialized view iot_msg_stats
  build immediate
  refresh complete on demand
  as
  with recs as (
    select  'Raw Messages' as data_type, time_received as time_recorded from raw_data_syn
    union all
    select  'Rejected Messages' as data_type, time_received as time_recorded from rejected_data_syn
    union all
    select  'Historized Records' as data_type, time_observed as time_recorded from historized_data_syn
    union all 
    select  'Command Records' as data_type, time_created as time_recorded from raw_command_data_syn
  )
    select  data_type ,
            recorded_year,
            recorded_week,
            first_recorded_at,
            last_recorded_at,
            total_count,
            week_count,
            sum(week_count) over ( partition by data_type order by recorded_year, recorded_week ) as week_running_count,
            row_id,
            last_date
  from      (
              select  data_type,
                      extract( year from time_recorded) as recorded_year,
                      to_number(to_char(trunc(time_recorded,'DD'),'IW')) as recorded_week,
                      min(time_recorded) over( partition by data_type) as first_recorded_at,
                      max(time_recorded) over( partition by data_type) as last_recorded_at,
                      count(*) over( partition by data_type) as total_count,
                      count(*) over ( partition by data_type, extract( year from time_recorded), to_number(to_char(trunc(time_recorded,'DD'),'IW')) ) as week_count,
                      sum(1) over (  partition by data_type, extract( year from time_recorded), to_number(to_char(trunc(time_recorded,'DD'),'IW'))  order by rownum) as row_id,
                      max(time_recorded) over ( partition by data_type ) as last_date
              from    recs )
  where   row_id = 1 
;

--scheduled task to update materialized view
declare
  l_job_exists number;
  begin
    select  count(*) into l_job_exists
    from    user_scheduler_jobs
    where   job_name = 'REFRESH_MVIEW_IOT_MSG_STATS';

    if l_job_exists = 1 then
      dbms_scheduler.drop_job(job_name => 'REFRESH_MVIEW_IOT_MSG_STATS');
    end if;

    DBMS_SCHEDULER.CREATE_JOB(
      JOB_NAME            => 'REFRESH_MVIEW_IOT_MSG_STATS',
      JOB_TYPE            => 'PLSQL_BLOCK',
      JOB_ACTION          => 'BEGIN DBMS_MVIEW.REFRESH(''IOT_MSG_STATS''); END;',
      START_DATE          => sysdate,
      REPEAT_INTERVAL     => 'FREQ=DAILY; Interval=1;BYHOUR=1;ByMinute=0',
      ENABLED             => TRUE,
      auto_drop           => FALSE,
      COMMENTS            => 'Refresh iot_msg_stats'
    );

  exception
    when others then
      DBMS_OUTPUT.PUT_LINE('Failed to create scheduled task for updating materialized view iot_msg_stats. Error: ' || SQLERRM);

end;
/

--combines stats contained in the iot_msg_stats materialized view with records that occured after the last materialized view update.
create or replace view iot_stats
  as
  with recs as (
    select  data_type ,
            recorded_year,
            recorded_week,
            first_recorded_at,
            last_recorded_at,
            total_count,
            week_count,
            sum(week_count) over ( partition by data_type order by recorded_year, recorded_week ) as week_running_count,
            row_id,
            last_date
  from      (
              select  data_type,
                      extract( year from time_recorded) as recorded_year,
                      to_number(to_char(trunc(time_recorded,'DD'),'IW')) as recorded_week,
                      min(time_recorded) over( partition by data_type) as first_recorded_at,
                      max(time_recorded) over( partition by data_type) as last_recorded_at,
                      count(*) over( partition by data_type) as total_count,
                      count(*) over ( partition by data_type, extract( year from time_recorded), to_number(to_char(trunc(time_recorded,'DD'),'IW')) ) as week_count,
                      sum(1) over (  partition by data_type, extract( year from time_recorded), to_number(to_char(trunc(time_recorded,'DD'),'IW'))  order by rownum) as row_id,
                      max(time_recorded) over ( partition by data_type ) as last_date
              from    ( select 'Raw Messages' as data_type, time_received as time_recorded from raw_data_syn where time_received > (select max(last_date) from iot_msg_stats where data_type = 'Raw Messages')
                        union all
                        select 'Rejected Messages' as data_type, time_received as time_recorded from rejected_data_syn where time_received > (select max(last_date) from iot_msg_stats where data_type = 'Rejected Messages')
                        union all
                        select 'Historized Records' as data_type, time_observed as time_recorded from historized_data_syn where time_observed > (select max(last_date) from iot_msg_stats where data_type = 'Historized Records')
                        union all
                        select 'Command Records' as data_type, time_created as time_recorded from raw_command_data_syn where time_created > (select max(last_date) from iot_msg_stats where data_type = 'Command Records')
                      )
            ) 
  where   row_id = 1 
  )
  select  data_type,
          recorded_year,
          recorded_week,
          min(first_recorded_at) as first_recorded_at,
          max(last_recorded_at) as last_recorded_at,
          sum(total_count) as total_count,
          sum(week_count) as week_count,
          sum(week_running_count) as week_running_count
  from    (
              select * from recs
              union all
              select * from iot_msg_stats
              union all
              select  data_type ,
                      recorded_year,
                      recorded_week,
                      first_recorded_at,
                      last_recorded_at,
                      total_count,
                      week_count,
                      sum(week_count) over ( partition by data_type order by recorded_year, recorded_week ) as week_running_count,
                      row_id,
                      last_date
              from    (
                        select  data_type,
                                  extract( year from timecreated) as recorded_year,
                                  to_number(to_char(trunc(timecreated,'DD'),'IW')) as recorded_week,
                                  min(timecreated) over( partition by data_type) as first_recorded_at,
                                  max(timecreated) over( partition by data_type) as last_recorded_at,
                                  count(*) over( partition by data_type) as total_count,
                                  count(*) over ( partition by data_type, extract( year from timecreated), to_number(to_char(trunc(timecreated,'DD'),'IW')) ) as week_count,
                                  sum(1) over (  partition by data_type, extract( year from timecreated), to_number(to_char(trunc(timecreated,'DD'),'IW'))  order by rownum) as row_id,
                                  null as last_date
                          from    ( select 'Devices' as data_type, to_timestamp(i.data.timeCreated) as timecreated from instances_syn i 
                                    union all
                                    select 'Adaptors' as data_type, to_timestamp(ads.data.timeCreated) as timecreated from adapters_syn ads
                                    union all
                                    select 'Models' as data_type, to_timestamp(ms.data.timeCreated) as timecreated from models_syn ms
                                  )
                        )
              where   row_id = 1
          )
  group by data_type,
          recorded_year,
          recorded_week
;

--hierarchical view of models, adaptors, and instances 
create or replace view iot_hierarchy 
  as
  with models as 
  ( select  /*+ MATERIALIZE */
            i.data."id".string() as id,
            null as parent_id,
            i.data."displayName".string() as display_name,
            'model' as iot_element,
            i.data as json_data,
            i.data.lifecycleState.string() as lifecycleState,
            'oj-ux-ico-business-model' as icon
    from    models_syn i
    where   i.data."id".string() in (  select  i.data.digitalTwinModelId.string() 
                                        from    adapters_syn i )
    union all
    select  'unstructuredModel' as id,
            null as parent_id,
            'Unstructured' as display_name,
            'model' as iot_element,
            null as json_data,
            'ACTIVE' as lifecycleState,
            'oj-ux-ico-business-model' as icon
    from    dual ),
  adapters as 
  ( select    /*+ MATERIALIZE */
              i.data."id".string() as id,
              i.data.digitalTwinModelId.string() as parent_id,
              i.data.displayName.string() as display_name,
              'adapter' as iot_element,
              i.data,
              i.data.lifecycleState.string() as lifecycleState,
              'oj-ux-ico-processes' as icon
    from      adapters_syn i
    where    i.data.digitalTwinModelId.string() is not null
    and      i.data."id".string() in (  select  i.data.digitalTwinAdapterId.string() 
                                          from    instances_syn i )
    union all
    select    'unstructuredAdapter' as id,
              'unstructuredModel' as parent_id,
              'Unstructured' as display_name,
              'adapter' as iot_element,
              null as json_data,
              'ACTIVE' as lifecycleState,
              'oj-ux-ico-processes' as icon
    from      dual ),
  devices as 
  ( select    /*+ MATERIALIZE */
              i.data.id.string() as id,
              nvl(i.data.digitalTwinAdapterId.string(),'unstructuredAdapter') as parent_id,
              i.data.displayName.string() as display_name,
              'device' as iot_element,
              i.data,
              i.data.lifecycleState.string() as lifecycleState,
              'oj-ux-ico-radio' as icon
      from    instances_syn i ),
  all_data as 
  ( select * from models
    union all 
    select * from adapters
    union all
    select * from devices
  )

  select  id,
          apex_util.url_encode (id) as link_id,
          display_name,
          iot_element,
          lifecycleState,
          display_name||' ('||id||')' as page_label,
          icon,
          RPAD('.', (level-1)*2, '.') || id as tree,
          level as tree_level,
          parent_id,
          connect_by_root id as root_id,
          ltrim(sys_connect_by_path(id, '|'), '|') as path,
          json_data
  from    all_data 
  start with parent_id is null
  connect BY parent_id = prior id
;