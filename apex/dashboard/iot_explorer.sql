--
-- This script grants supporting objects for the IoT Platform Explorer.
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

--combines stats contained in the iot_msg_stats materialized view with records that occurred after the last materialized view update.
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
                          from    ( select 'Instances' as data_type, to_timestamp(i.data.timeCreated) as timecreated from instances_syn i 
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

--hierarchical view of models, adapters, and instances 
create or replace view iot_hierarchy 
  as
  with models as 
  ( select  /*+ MATERIALIZE */
            i.data."_id".string() as id,
            null as parent_id,
            i.data."displayName".string() as display_name,
            'model' as iot_element,
            i.data as json_data,
            i.data.lifecycleState.string() as lifecycleState,
            'oj-ux-ico-business-model' as icon
    from    models_syn i
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
              i.data."_id".string() as id,
              i.data.digitalTwinModelId.string() as parent_id,
              i.data.displayName.string() as display_name,
              'adapter' as iot_element,
              i.data,
              i.data.lifecycleState.string() as lifecycleState,
              'oj-ux-ico-processes' as icon
    from      adapters_syn i
    where    i.data.digitalTwinModelId.string() is not null
    union all
    select    'unstructuredAdapter' as id,
              'unstructuredModel' as parent_id,
              'Unstructured' as display_name,
              'adapter' as iot_element,
              null as json_data,
              'ACTIVE' as lifecycleState,
              'oj-ux-ico-processes' as icon
    from      dual ),
  instances as 
  ( select    /*+ MATERIALIZE */
              i.data."_id".string() as id,
              nvl(i.data.digitalTwinAdapterId.string(),'unstructuredAdapter') as parent_id,
              i.data.displayName.string() as display_name,
              'instance' as iot_element,
              i.data,
              i.data.lifecycleState.string() as lifecycleState,
              'oj-ux-ico-radio' as icon
      from    instances_syn i ),
  all_data as 
  ( select * from models
    union all 
    select * from adapters
    union all
    select * from instances
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


--Create table IOT_CONFIG to hold JSON configuration data
create table if not exists "IOT_CONFIG"(
  "JSON_TOPIC"    varchar2(50) not null,
  "JSON_CONTENT"  clob,
  constraint is_json_clob check ( "JSON_CONTENT" is json )
);


-- Inserts record into "IOT_CONFIG" if it does not exist containing basic json data
declare
  record_exists number;
  begin
    select  count(*) 
    into    record_exists
    from    iot_config 
    where   json_topic = 'IOT_CONFIG';
    
    if record_exists = 0 then
      insert into iot_config(json_topic,json_content)
      values('IOT_CONFIG','{
          "credentials":null,
          "tenancy_ocid":null,
          "tenancy_name":null,
          "tenancy_region":null,
          "iot_compartment":null,
          "vault_ocid":null,
          "vault_master_key":null,
          "certificate_authority":null}'
      );
      commit;
    end if;
end;
/


create or replace package "IOT_APEX" as
  function clob_to_blob(p_clob clob, p_charset_id  number default null) return blob;

  function cred_chk( p_cred_name varchar2 ) return varchar2;

  function iot_config return json_object_t;

end "IOT_APEX";
/

create or replace package body "IOT_APEX" as

  function "CLOB_TO_BLOB"(p_clob clob, p_charset_id  number default null) 
    return blob 
    is
      v_blob blob;
      v_offset number := 1;
      v_amount number;
      v_charset_id number := nvl(p_charset_id, dbms_lob.default_csid);
      v_lang_context number := 0;
      v_warning number;
    BEGIN
      v_amount := dbms_lob.getlength(p_clob);
      dbms_lob.createtemporary(v_blob, TRUE);
      dbms_lob.converttoblob(v_blob, p_clob, v_amount, v_offset, v_offset, v_charset_id, v_lang_context, v_warning);
      RETURN v_blob;
  end;


  function "CRED_CHK"( p_cred_name varchar2 )
    return varchar2
    is
    v_return DBMS_CLOUD_TYPES.resp;
    begin 
    v_return := DBMS_CLOUD.SEND_REQUEST(
              credential_name    => p_cred_name,
              uri                => 'https://identity.eu-frankfurt-1.oci.oraclecloud.com/20160918/regions',
              method             => 'GET');
    return 'GOOD';
    EXCEPTION
      WHEN OTHERS THEN
        IF SQLCODE = -20401 THEN
          return 'BAD';
        ELSE
           return 'Error: ' || SQLERRM;
        END IF;
  end;


  function "IOT_CONFIG" 
    return json_object_t
    is
    v_return json_object_t;
    v_clob clob;
    begin
      select  i.json_content
      into    v_clob
      from    iot_config i
      where   json_topic = 'IOT_CONFIG';

      v_return := json_object_t.parse(v_clob);

      return v_return;

    exception
      when others then
        dbms_output.put_line('Error: ' || SQLERRM);

  end;

end "IOT_APEX";
/

-- Create or replace the IOT_INFO package
CREATE OR REPLACE PACKAGE "IOT_INFO" AS

  /*
    This code is a package that provides a set of functions to interact with the 
    OcI IoT Platform API. The functions retrieve various types of IoT-related data, 
    such as domain groups, domain group connections, domain connections, and domains. 
    The data is retrieved using the DBMS_CLOUD.SEND_REQUEST function, which sends a 
    GET request to the OcI IoT Platform API. The response is then parsed using the 
    JSON_TABLE function, and the results are piped to the caller. The package also 
    includes overloaded functions that retrieve data without requiring the caller to 
    specify the compartment ID, credential name, and region. These functions retrieve 
    the required information from the IOT_CONFIG table.
  */

  -- Define a record type to hold IoT domain group information
  TYPE dom_grp_rec IS RECORD(
      id VARCHAR2(200), 
      compartmentId VARCHAR2(300), 
      displayName VARCHAR2(300), 
      grp_description VARCHAR2(300), 
      lifecycleState VARCHAR2(50), 
      timeCreated VARCHAR2(50), 
      timeUpdated VARCHAR2(50)
  );

  -- Define a table type to hold a collection of dom_grp_rec records
  TYPE dom_grp_tbl IS TABLE OF dom_grp_rec;

  -- Define a record type to hold IoT domain group connection information
  TYPE dom_grp_conn_rec IS RECORD(
      id VARCHAR2(200), 
      compartmentId VARCHAR2(300), 
      displayName VARCHAR2(300), 
      lifecycleState VARCHAR2(50), 
      datahost VARCHAR2(300), 
      dbConnectionString VARCHAR2(300), 
      dbTokenScope VARCHAR2(300), 
      timeCreated VARCHAR2(50), 
      timeUpdated VARCHAR2(50)
  );

  -- Define a table type to hold a collection of dom_grp_conn_rec records
  TYPE dom_grp_conn_tbl IS TABLE OF dom_grp_conn_rec;

  -- Define a record type to hold IoT domain connection information
  TYPE dom_conn_rec IS RECORD(
      id VARCHAR2(200), 
      compartmentId VARCHAR2(300), 
      displayName VARCHAR2(300), 
      lifecycleState VARCHAR2(50), 
      deviceHost VARCHAR2(300), 
      iotDomainGroupId VARCHAR2(300), 
      retentRawData number,
      retentRejectedData number,
      retentHistorizedData number,
      retentRawCommandData number,
      timeCreated VARCHAR2(50), 
      timeUpdated VARCHAR2(50)
  );

  -- Define a table type to hold a collection of dom_conn_rec records
  TYPE dom_conn_tbl IS TABLE OF dom_conn_rec;

  -- Define a record type to hold IoT domain information
  TYPE dom_rec IS RECORD(
      id VARCHAR2(200), 
      iotDomainGroupId VARCHAR2(300), 
      compartmentId VARCHAR2(300), 
      displayName VARCHAR2(300), 
      dom_desc VARCHAR2(300), 
      lifecycleState VARCHAR2(50),
      timeCreated VARCHAR2(50), 
      timeUpdated VARCHAR2(50)
  );

  -- Define a table type to hold a collection of dom_rec records
  TYPE dom_tbl IS TABLE OF dom_rec;

  -- Function to retrieve IoT domain groups with specified compartment ID, credential name, and region
  FUNCTION get_dom_grp(p_compartment_id VARCHAR2, p_cred_name VARCHAR2, p_region VARCHAR2) RETURN dom_grp_tbl PIPELINED;

  -- Function to retrieve all IoT domain groups
  FUNCTION get_dom_grp RETURN dom_grp_tbl PIPELINED;

  -- Function to retrieve IoT domain group connections with specified domain group ID, credential name, and region
  FUNCTION get_dom_grp_conn(p_dom_grp_id VARCHAR2, p_cred_name VARCHAR2, p_region VARCHAR2) RETURN dom_grp_conn_tbl PIPELINED;

  -- Function to retrieve all IoT domain group connections
  FUNCTION get_dom_grp_conn RETURN dom_grp_conn_tbl PIPELINED;

  -- Function to retrieve IoT domain connections with specified domain ID, credential name, and region
  FUNCTION get_dom_conn(p_dom_id VARCHAR2, p_cred_name VARCHAR2, p_region VARCHAR2) RETURN dom_conn_tbl PIPELINED;

  -- Function to retrieve all IoT domain connections
  FUNCTION get_dom_conn RETURN dom_conn_tbl PIPELINED;

  -- Function to retrieve IoT domains with specified compartment ID, credential name, and region
  FUNCTION get_dom(p_compartment_id VARCHAR2, p_cred_name VARCHAR2, p_region VARCHAR2) RETURN dom_tbl PIPELINED;

  -- Function to retrieve all IoT domains
  FUNCTION get_dom RETURN dom_tbl PIPELINED;

END;
/

-- Create or replace the IOT_INFO package body
CREATE OR REPLACE PACKAGE BODY "IOT_INFO" AS

  -- Function to retrieve IoT domain groups with specified compartment ID, credential name, and region
  FUNCTION get_dom_grp(p_compartment_id VARCHAR2, p_cred_name VARCHAR2, p_region VARCHAR2)
    RETURN dom_grp_tbl
    PIPELINED IS

    -- Variables to hold the response from the DBMS_CLOUD.SEND_REQUEST function
    v_return DBMS_CLOUD_TYPES.resp;
    v_clob CLOB;
    v_json JSON;

    BEGIN

      -- Send a GET request to the OcI IoT Cloud API to retrieve IoT domain groups
      v_return := DBMS_CLOUD.SEND_REQUEST(
          credential_name    => p_cred_name,
          uri                => 'https://iot.'||p_region||'.oci.oraclecloud.com/20250531/iotDomainGroups?compartmentId='||p_compartment_id|| '&limit=100',
          method             => 'GET'
      );

      -- Get the response text from the v_return object
      v_clob := DBMS_CLOUD.GET_RESPONSE_TEXT(resp => v_return);

      -- Parse the JSON response and pipe the results to the caller
            FOR json_rec IN (
          SELECT 
              a.dom_grp_ocid, 
              a.compartmentId, 
              a.displayName, 
              a.dom_grp_desc, 
              a.lifecycleState, 
              a.timeCreated, 
              a.timeUpdated
          FROM 
              JSON_TABLE(
                  v_clob,
                  '$.items[*]' COLUMNS (
                      dom_grp_ocid VARCHAR PATH '$.id',
                      compartmentId VARCHAR PATH '$.compartmentId',
                      displayName VARCHAR PATH '$.displayName',
                      dom_grp_desc VARCHAR PATH '$.description',
                      lifecycleState VARCHAR PATH '$.lifecycleState',
                      timeCreated VARCHAR PATH '$.timeCreated',
                      timeUpdated VARCHAR PATH '$.timeUpdated'
                  )
              ) a
      ) LOOP 
          PIPE ROW (dom_grp_rec(json_rec.dom_grp_ocid, json_rec.compartmentId, json_rec.displayName, json_rec.dom_grp_desc, json_rec.lifecycleState,json_rec.timeCreated, json_rec.timeUpdated));
      END LOOP;

      RETURN;

    EXCEPTION
      WHEN OTHERS THEN
          -- Log any errors that occur during the execution of this function
          DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);

  END;

  -- Function to retrieve all IoT domain groups
  FUNCTION get_dom_grp
    RETURN dom_grp_tbl
    PIPELINED IS

    -- Variables to hold the response from the DBMS_CLOUD.SEND_REQUEST function
    v_return DBMS_CLOUD_TYPES.resp;
    v_clob CLOB;
    v_json JSON;
    v_config json_object_t;

    BEGIN

      -- Retrieve the compartment ID, credential name, and region from the IOT_CONFIG table
      v_config := iot_apex.iot_config;
      
      -- Send a GET request to the OcI IoT Cloud API to retrieve IoT domain groups
      v_return := DBMS_CLOUD.SEND_REQUEST(
          credential_name    => v_config.get_string('credentials'),
          uri                => 'https://iot.'||v_config.get_string('tenancy_region')||'.oci.oraclecloud.com/20250531/iotDomainGroups?compartmentId='||v_config.get_string('iot_compartment'),
          method             => 'GET'
      );

      -- Get the response text from the v_return object
      v_clob := DBMS_CLOUD.GET_RESPONSE_TEXT(resp => v_return);

      -- Parse the JSON response and pipe the results to the caller
      FOR json_rec IN (
          SELECT 
              a.dom_grp_ocid, 
              a.compartmentId, 
              a.displayName, 
              a.dom_grp_desc, 
              a.lifecycleState, 
              a.timeCreated, 
              a.timeUpdated
          FROM 
              JSON_TABLE(
                  v_clob,
                  '$.items[*]' COLUMNS (
                      dom_grp_ocid VARCHAR PATH '$.id',
                      compartmentId VARCHAR PATH '$.compartmentId',
                      displayName VARCHAR PATH '$.displayName',
                      dom_grp_desc VARCHAR PATH '$.description',
                      lifecycleState VARCHAR PATH '$.lifecycleState',
                      timeCreated VARCHAR PATH '$.timeCreated',
                      timeUpdated VARCHAR PATH '$.timeUpdated'
                  )
              ) a
      ) LOOP 
          PIPE ROW (dom_grp_rec(json_rec.dom_grp_ocid, json_rec.compartmentId, json_rec.displayName, json_rec.dom_grp_desc, json_rec.lifecycleState, json_rec.timeCreated, json_rec.timeUpdated));
      END LOOP;

      RETURN;

    EXCEPTION
      WHEN OTHERS THEN
          -- Log any errors that occur during the execution of this function
          DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);

  END;

  -- Other functions are implemented similarly...

  FUNCTION get_dom_grp_conn(p_dom_grp_id varchar2, p_cred_name varchar2, p_region varchar2)
    RETURN dom_grp_conn_tbl
    PIPELINED IS

    v_return DBMS_CLOUD_TYPES.resp;
    v_clob clob;
    v_json json;

    BEGIN

      v_return := DBMS_CLOUD.SEND_REQUEST(
          credential_name    => p_cred_name,
          uri                => 'https://iot.'||p_region||'.oci.oraclecloud.com/20250531/iotDomainGroups/'||p_dom_grp_id,
          method             => 'GET');

      v_clob := 
          DBMS_CLOUD.GET_RESPONSE_TEXT(
              resp          => v_return );

      for json_rec in (
          SELECT A.dom_grp_ocid, A.compartmentId, A.displayName, A.lifecycleState, A.datahost, A.dbConnectionString, A.dbTokenScope, A.timeCreated, A.timeUpdated
          FROM JSON_TABLE(
              v_clob
              , '$' COLUMNS (
                  dom_grp_ocid VARCHAR PATH '$.id',
                  compartmentId VARCHAR PATH '$.compartmentId',
                  displayName VARCHAR PATH '$.displayName',
                  lifecycleState VARCHAR PATH '$.lifecycleState',
                  datahost VARCHAR PATH '$.dataHost',
                  dbConnectionString VARCHAR PATH '$.dbConnectionString',
                  dbTokenScope VARCHAR PATH '$.dbTokenScope',
                  timeCreated VARCHAR PATH '$.timeCreated',
                  timeUpdated VARCHAR PATH '$.timeUpdated'
              )
          ) A
      ) loop 
          pipe row (dom_grp_conn_rec(json_rec.dom_grp_ocid,json_rec.compartmentId,json_rec.displayName,json_rec.lifecycleState,json_rec.datahost,json_rec.dbConnectionString,json_rec.dbTokenScope,json_rec.timeCreated,json_rec.timeUpdated));
      end loop;

      RETURN;

      EXCEPTION
      WHEN OTHERS THEN
          DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);

  END;

  FUNCTION get_dom_grp_conn
    RETURN dom_grp_conn_tbl
    PIPELINED IS

    v_return DBMS_CLOUD_TYPES.resp;
    v_clob clob;
    v_json json;
    v_config json_object_t;

    BEGIN

      v_config := iot_apex.iot_config;

      for rec in (select * from table(iot_info.get_dom_grp)) loop
          v_return := DBMS_CLOUD.SEND_REQUEST(
              credential_name    => v_config.get_string('credentials'),
              uri                => 'https://iot.'||v_config.get_string('tenancy_region')|| '.oci.oraclecloud.com/20250531/iotDomainGroups/'||rec.id,
              method             => 'GET');

          v_clob := 
              DBMS_CLOUD.GET_RESPONSE_TEXT(
                  resp          => v_return );

          for json_rec in (
              SELECT A.dom_grp_ocid, A.compartmentId, A.displayName, A.lifecycleState, A.datahost, A.dbConnectionString, A.dbTokenScope, A.timeCreated, A.timeUpdated
              FROM JSON_TABLE(
                  v_clob
                  , '$' COLUMNS (
                      dom_grp_ocid VARCHAR PATH '$.id',
                      compartmentId VARCHAR PATH '$.compartmentId',
                      displayName VARCHAR PATH '$.displayName',
                      lifecycleState VARCHAR PATH '$.lifecycleState',
                      datahost VARCHAR PATH '$.dataHost',
                      dbConnectionString VARCHAR PATH '$.dbConnectionString',
                      dbTokenScope VARCHAR PATH '$.dbTokenScope',
                      timeCreated VARCHAR PATH '$.timeCreated',
                      timeUpdated VARCHAR PATH '$.timeUpdated'
                  )
              ) A
          ) loop 
              pipe row (dom_grp_conn_rec(json_rec.dom_grp_ocid,json_rec.compartmentId,json_rec.displayName,json_rec.lifecycleState,json_rec.datahost,json_rec.dbConnectionString,json_rec.dbTokenScope,json_rec.timeCreated,json_rec.timeUpdated));
          end loop;

      end loop;

      RETURN;

      EXCEPTION
      WHEN OTHERS THEN
          DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);

  END;

  FUNCTION get_dom_conn(p_dom_id varchar2, p_cred_name varchar2, p_region varchar2 )
    RETURN dom_conn_tbl
    PIPELINED IS

    v_return DBMS_CLOUD_TYPES.resp;
    v_clob clob;

    BEGIN

      v_return := DBMS_CLOUD.SEND_REQUEST(
          credential_name    => p_cred_name,
          uri                => 'https://iot.'||p_region||'.oci.oraclecloud.com/20250531/iotDomains/'||p_dom_id,
          method             => 'GET');

      v_clob := 
          DBMS_CLOUD.GET_RESPONSE_TEXT(
              resp          => v_return );

      for json_rec in (
              select a.dom_ocid, a.iotDomainGroupId, a.compartmentId, a.displayName, a.lifecycleState, a.deviceHost, a.timeCreated, a.timeUpdated
              from json_table(
                  v_clob
                  , '$' COLUMNS (
                      dom_ocid VARCHAR PATH '$.id',
                      compartmentId VARCHAR PATH '$.compartmentId',
                      displayName VARCHAR PATH '$.displayName',
                      lifecycleState VARCHAR PATH '$.lifecycleState',
                      deviceHost VARCHAR PATH '$.deviceHost',
                      iotDomainGroupId VARCHAR PATH '$.iotDomainGroupId',
                      timeCreated VARCHAR PATH '$.timeCreated',
                      timeUpdated VARCHAR PATH '$.timeUpdated'
                  )
              ) A
          ) loop 
              pipe row (dom_conn_rec(json_rec.dom_ocid,json_rec.compartmentId,json_rec.displayName,json_rec.lifecycleState,json_rec.deviceHost,json_rec.iotDomainGroupId,json_rec.timeCreated,json_rec.timeUpdated));
          end loop;

      RETURN;

      EXCEPTION
      WHEN OTHERS THEN
          DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);

  END;

  FUNCTION get_dom_conn
    RETURN dom_conn_tbl
    PIPELINED IS

    v_return DBMS_CLOUD_TYPES.resp;
    v_clob clob;
    v_config json_object_t;

    BEGIN

      v_config := iot_apex.iot_config;

      for rec in ( select * from table(iot_info.get_dom) ) loop

          v_return := DBMS_CLOUD.SEND_REQUEST(
              credential_name    => v_config.get_string('credentials'),
              uri                => 'https://iot.'||v_config.get_string('tenancy_region')|| '.oci.oraclecloud.com/20250531/iotDomains/'||rec.id,
              method             => 'GET');

          v_clob := 
              DBMS_CLOUD.GET_RESPONSE_TEXT(
                  resp          => v_return );

          for json_rec in (
              select a.dom_ocid, a.iotDomainGroupId, a.compartmentId, a.displayName, a.lifecycleState, a.deviceHost,a.retentRawData, a.retentRejectedData, a.retentHistorizedData, a.retentRawCommandData, a.timeCreated, a.timeUpdated
              from json_table(
                  v_clob
                  , '$' COLUMNS (
                      dom_ocid VARCHAR PATH '$.id',
                      compartmentId VARCHAR PATH '$.compartmentId',
                      displayName VARCHAR PATH '$.displayName',
                      lifecycleState VARCHAR PATH '$.lifecycleState',
                      deviceHost VARCHAR PATH '$.deviceHost',
                      iotDomainGroupId VARCHAR PATH '$.iotDomainGroupId',
                      retentRawData number PATH '$.dataRetentionPeriodsInDays.rawData',
                      retentRejectedData number PATH '$.dataRetentionPeriodsInDays.rejectedData',
                      retentHistorizedData number PATH '$.dataRetentionPeriodsInDays.historizedData',
                      retentRawCommandData number PATH '$.dataRetentionPeriodsInDays.rawCommandData',
                      timeCreated VARCHAR PATH '$.timeCreated',
                      timeUpdated VARCHAR PATH '$.timeUpdated'
                  )
              ) A
          ) loop 
              pipe row (dom_conn_rec(json_rec.dom_ocid,json_rec.compartmentId,json_rec.displayName,json_rec.lifecycleState,json_rec.deviceHost,json_rec.iotDomainGroupId,json_rec.retentRawData,json_rec.retentRejectedData,json_rec.retentHistorizedData,json_rec.retentRawCommandData,json_rec.timeCreated,json_rec.timeUpdated));
          end loop;

      end loop;

      RETURN;

      EXCEPTION
      WHEN OTHERS THEN
          DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);

  END;

  FUNCTION get_dom(p_compartment_id varchar2, p_cred_name varchar2, p_region varchar2)
    RETURN dom_tbl
    PIPELINED IS

    v_return DBMS_CLOUD_TYPES.resp;
    v_clob clob;
    v_json json;

    BEGIN

      v_return := DBMS_CLOUD.SEND_REQUEST(
          credential_name    => p_cred_name,
          uri                => 'https://iot.'||p_region||'.oci.oraclecloud.com/20250531/iotDomains?compartmentId='||p_compartment_id,
          method             => 'GET');

      v_clob := 
          DBMS_CLOUD.GET_RESPONSE_TEXT(resp          => v_return );

      for json_rec in (
          SELECT a.dom_ocid, a.iotDomainGroupId, a.compartmentId, a.displayName, a.dom_desc, a.lifecycleState,  a.timeCreated, a.timeUpdated
          FROM JSON_TABLE(
              v_clob
              , '$.items[*]' COLUMNS (
                  dom_ocid VARCHAR PATH '$.id',
                  iotDomainGroupId VARCHAR PATH '$.iotDomainGroupId',
                  compartmentId VARCHAR PATH '$.compartmentId',
                  displayName VARCHAR PATH '$.displayName',
                  dom_desc varchar2 path '$.description',
                  lifecycleState VARCHAR PATH '$.lifecycleState',
                  timeCreated VARCHAR PATH '$.timeCreated',
                  timeUpdated VARCHAR PATH '$.timeUpdated'
              )
          ) A 
      ) loop 
          pipe row (dom_rec(json_rec.dom_ocid,json_rec.iotDomainGroupId,json_rec.compartmentId,json_rec.displayName,json_rec.dom_desc,json_rec.lifecycleState,json_rec.timeCreated,json_rec.timeUpdated));
      end loop;

      RETURN;

      EXCEPTION
      WHEN OTHERS THEN
          DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);

  END;

  FUNCTION get_dom
    RETURN dom_tbl
    PIPELINED IS

    v_return DBMS_CLOUD_TYPES.resp;
    v_clob clob;
    v_json json;
    v_config json_object_t;

    BEGIN

      v_config := iot_apex.iot_config;

      v_return := DBMS_CLOUD.SEND_REQUEST(
            credential_name    => v_config.get_string('credentials'),
            uri                => 'https://iot.'||v_config.get_string('tenancy_region')|| '.oci.oraclecloud.com/20250531/iotDomains?compartmentId='||v_config.get_string('iot_compartment'),
            method             => 'GET');

        v_clob := DBMS_CLOUD.GET_RESPONSE_TEXT(resp=> v_return );

        for json_rec in (
            SELECT a.dom_ocid, a.iotDomainGroupId, a.compartmentId, a.displayName, a.dom_desc, a.lifecycleState, a.timeCreated, a.timeUpdated
            FROM JSON_TABLE(
                v_clob
                , '$.items[*]' COLUMNS (
                    dom_ocid VARCHAR PATH '$.id',
                    iotDomainGroupId VARCHAR PATH '$.iotDomainGroupId',
                    compartmentId VARCHAR PATH '$.compartmentId',
                    displayName VARCHAR PATH '$.displayName',
                    dom_desc varchar2 path '$.description',
                    lifecycleState VARCHAR PATH '$.lifecycleState',
                    timeCreated VARCHAR PATH '$.timeCreated',
                    timeUpdated VARCHAR PATH '$.timeUpdated'
                )
            ) A 
        ) loop 
            pipe row (dom_rec(json_rec.dom_ocid,json_rec.iotDomainGroupId,json_rec.compartmentId,json_rec.displayName,json_rec.dom_desc,json_rec.lifecycleState,json_rec.timeCreated,json_rec.timeUpdated));
        end loop;

        RETURN;

        EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);

    END;

END;
/
