--
-- This script creates supporting objects for the IoT Platform Explorer.
--
-- Copyright (c) 2025 Oracle and/or its affiliates.
-- Licensed under the Universal Permissive License v 1.0 as shown at
-- https://oss.oracle.com/licenses/upl.
--
-- DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
--

--Creates the synonyms in the __wksp schema for the views in the __iot schema
declare
  cursor rec_cur is
    select  'create or replace synonym '||
            lower(replace(view_name,'DIGITAL_TWIN_',''))||
            '_syn for '||
            lower(owner)||
            '.'||lower(view_name) as statement
    from    all_views
    where   upper(owner) = replace( sys_context( 'userenv', 'current_schema' ), '__WKSP', '__IOT' )
    and     view_name not like 'AQ$%';
  begin

  for rec in rec_cur loop

    begin

      execute immediate rec.statement;
      dbms_output.put_line('Successfully executed: ' || rec.statement);

    exception
      when others then
        dbms_output.put_line('Failed to execute: ' || rec.statement || '. Error: ' || sqlerrm);

    end;

  end loop;

end;
/

--Drop materialized view if exist
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
    select  'Raw Messages' as data_type,
            time_received as time_recorded
    from    raw_data_syn
    union all
    select  'Rejected Messages' as data_type,
            time_received as time_recorded
    from    rejected_data_syn
    union all
    select  'Historized Records' as data_type,
            time_observed as time_recorded
    from    historized_data_syn
    union all
    select  'Command Records' as data_type,
            time_created as time_recorded
    from    raw_command_data_syn
  )
    select  data_type ,
            recorded_year,
            recorded_week,
            first_recorded_at,
            last_recorded_at,
            total_count,
            week_count,
            sum(week_count) over (
              partition by data_type
              order by recorded_year,
                       recorded_week
            ) as week_running_count,
            row_id,
            last_date
    from    (
              select  data_type,
                      extract( year from time_recorded) as recorded_year,
                      to_number(to_char(trunc(time_recorded,'DD'),'IW')) as recorded_week,
                      min(time_recorded) over( partition by data_type) as first_recorded_at,
                      max(time_recorded) over( partition by data_type) as last_recorded_at,
                      count(*) over( partition by data_type) as total_count,
                      count(*) over (
                        partition by data_type,
                                     extract( year from time_recorded),
                                     to_number(to_char(trunc(time_recorded,'DD'),'IW'))
                      ) as week_count,
                      sum(1) over (
                        partition by data_type,
                                     extract( year from time_recorded),
                                     to_number(to_char(trunc(time_recorded,'DD'),'IW'))
                        order by rownum
                      ) as row_id,
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

    dbms_scheduler.create_job(
      job_name            => 'REFRESH_MVIEW_IOT_MSG_STATS',
      job_type            => 'PLSQL_BLOCK',
      job_action          => 'begin DBMS_MVIEW.REFRESH(''IOT_MSG_STATS''); end;',
      start_date          => sysdate,
      repeat_interval     => 'FREQ=DAILY; Interval=1;BYHOUR=1;ByMinute=0',
      enabled             => true,
      auto_drop           => false,
      comments            => 'Refresh iot_msg_stats'
    );

  exception
    when others then
      dbms_output.put_line('Failed to create scheduled task for updating materialized view iot_msg_stats. Error: ' || sqlerrm);

end;
/

--combines stats contained in the iot_msg_stats materialized
--view with records that occurred after the last materialized view update.
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
            sum(week_count) over (
              partition by data_type
              order by recorded_year,
                       recorded_week ) as week_running_count,
            row_id,
            last_date
  from      (
              select  data_type,
                      extract( year from time_recorded) as recorded_year,
                      to_number(to_char(trunc(time_recorded,'DD'),'IW')) as recorded_week,
                      min(time_recorded) over( partition by data_type) as first_recorded_at,
                      max(time_recorded) over( partition by data_type) as last_recorded_at,
                      count(*) over( partition by data_type) as total_count,
                      count(*) over (
                        partition by data_type,
                        extract(year from time_recorded),
                        to_number(to_char(trunc(time_recorded,'DD'),'IW'))
                        ) as week_count,
                      sum(1) over (
                        partition by data_type,
                        extract(year from time_recorded),
                        to_number(to_char(trunc(time_recorded,'DD'),'IW')) order by rownum
                        ) as row_id,
                      max(time_recorded) over ( partition by data_type ) as last_date
              from    ( select  'Raw Messages' as data_type,
                                time_received as time_recorded
                        from    raw_data_syn
                        where   time_received > (select max(last_date)
                                                 from iot_msg_stats
                                                 where data_type = 'Raw Messages')
                        union all
                        select  'Rejected Messages' as data_type,
                                time_received as time_recorded
                        from    rejected_data_syn
                        where   time_received > (select max(last_date)
                                                 from   iot_msg_stats
                                                 where  data_type = 'Rejected Messages')
                        union all
                        select  'Historized Records' as data_type,
                                time_observed as time_recorded
                        from    historized_data_syn
                        where   time_observed > (select max(last_date)
                                                 from   iot_msg_stats
                                                 where  data_type = 'Historized Records')
                        union all
                        select  'Command Records' as data_type,
                                time_created as time_recorded
                        from    raw_command_data_syn
                        where   time_created > (select max(last_date)
                                                from   iot_msg_stats
                                                where   data_type = 'Command Records')
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
                      sum(week_count) over (
                        partition by data_type
                        order by recorded_year,
                                 recorded_week ) as week_running_count,
                      row_id,
                      last_date
              from    (
                        select  data_type,
                                extract( year from timecreated) as recorded_year,
                                to_number(to_char(trunc(timecreated,'DD'),'IW')) as recorded_week,
                                min(timecreated) over( partition by data_type) as first_recorded_at,
                                max(timecreated) over( partition by data_type) as last_recorded_at,
                                count(*) over( partition by data_type) as total_count,
                                count(*) over (
                                  partition by data_type,
                                               extract( year from timecreated),
                                               to_number(to_char(trunc(timecreated,'DD'),'IW'))
                                  ) as week_count,
                                sum(1) over (
                                  partition by data_type,
                                               extract( year from timecreated),
                                               to_number(to_char(trunc(timecreated,'DD'),'IW'))
                                  order by rownum) as row_id,
                                null as last_date
                        from    ( select  'Instances' as data_type,
                                          to_timestamp(i.data.timeCreated) as timecreated
                                  from    instances_syn i
                                  where   i.data."lifecycleState" = 'ACTIVE'
                                  union all
                                  select  'Adaptors' as data_type,
                                          to_timestamp(ads.data.timeCreated) as timecreated
                                  from    adapters_syn ads
                                  where   ads.data."lifecycleState" = 'ACTIVE'
                                  union all
                                  select  'Models' as data_type,
                                          to_timestamp(ms.data.timeCreated) as timecreated
                                  from    models_syn ms
                                  where   ms.data."lifecycleState" = 'ACTIVE'
                                )
                      )
              where   row_id = 1
          )
  group by data_type,
          recorded_year,
          recorded_week
;

--hierarchical view of models, adapters, and instances
create or replace view iot_hierarchy as
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
          rpad('.', (level-1)*2, '.') || id as tree,
          level as tree_level,
          parent_id,
          connect_by_root id as root_id,
          ltrim(sys_connect_by_path(id, '|'), '|') as path,
          json_data
  from    all_data
  start with parent_id is null
  connect by parent_id = prior id
;


--Create table IOT_CONFIG to hold JSON configuration data
create table if not exists iot_config(
  json_topic    varchar2(50) not null,
  json_content  clob,
  constraint is_json_clob check ( json_content is json )
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




-- Create iot_apex package
create or replace package iot_apex as
  function clob_to_blob(
    p_clob clob,
    p_charset_id number default null) return blob;

  function cred_chk(
    p_cred_name varchar2,
    p_region varchar2 ) return varchar2;

  function iot_config return json_object_t;

  function is_json(p_json clob) return varchar2;

  function compact_number(n number) return varchar2;
end iot_apex;
/

-- Create iot_apex package body
create or replace package body iot_apex as
  -- Converts a clob to a BLOB, using a specified or default charset
  function clob_to_blob(p_clob clob, p_charset_id number default null)
    return blob
    is
      v_blob blob;
      v_offset number := 1;
      v_amount number;
      v_charset_id number := nvl(p_charset_id, dbms_lob.default_csid);
      v_lang_context number := 0;
      v_warning number;
    begin
      v_amount := dbms_lob.getlength(p_clob); -- Get length of the clob
      dbms_lob.createtemporary(v_blob, true); -- Create a temporary BLOB
      -- Convert clob to BLOB using DBMS_LOB package
      dbms_lob.converttoblob(
        v_blob,
        p_clob,
        v_amount,
        v_offset,
        v_offset,
        v_charset_id,
        v_lang_context,
        v_warning);
      return v_blob;

      exception
        when others then
          return null;
  end;

  -- Checks a named Oracle Cloud credential in a given region by calling OCI Identity endpoint
  function cred_chk(p_cred_name varchar2, p_region varchar2)
    return varchar2
    is
    v_return dbms_cloud_types.resp;
    begin
    v_return := dbms_cloud.send_request(
              credential_name    => p_cred_name,
              uri                => 'https://identity.' ||
                                    p_region ||
                                    '.oci.oraclecloud.com/20160918/regions',
              method             => 'GET'); -- Perform REST GET request
    return 'GOOD'; -- Success if no error
    exception
      when others then
        if sqlcode = -20401 then
          return 'BAD'; -- Credential is invalid / region not reachable
        else
           return 'Error: ' || sqlerrm; -- Return other errors as text
        end if;
  end;

  -- Loads IOT configuration JSON from database, parses it, and returns as JSON object
  function iot_config
    return json_object_t
    is
    v_return json_object_t;
    v_clob clob;
    begin
      select  i.json_content
      into    v_clob
      from    iot_config i
      where   json_topic = 'IOT_CONFIG'; -- Pull config for IOT_CONFIG topic

      v_return := json_object_t.parse(v_clob); -- Parse the JSON clob

      return v_return;

    exception
      when others then
        dbms_output.put_line('Error: ' || sqlerrm); -- Log error
        return null;
  end;

  -- Determines if provided clob is valid JSON using SQL IS JSON STRICT predicate
  function is_json(p_json clob)
    return varchar2
    is
    v_json_string clob := p_json;
    v_is_json number;
    begin
      EXECUTE IMMEDIATE
        'select case when :1 is json strict then 1 else 0 end from dual'
        into v_is_json
        using v_json_string;

      if v_is_json = 1 then
          return 'true'; -- JSON is valid
      else
          return 'false'; -- JSON is invalid
      end if;
      exception
        when others
          then return 'false'; -- Exception treated as invalid JSON
  end;

  -- Converts a number into a string consisting of 1-999.9 followed by a unit ex: K = 1000's
  function compact_number(n number)
    return varchar2
    is
    begin
      if n = 0 then
          return '0';
      else
          return round((n/power(1000,trunc(log(1000,trunc(abs(n)))))),1) ||
                 ltrim(substr(' KMBT',trunc(log(1000,trunc(abs(n)))) + 1,1));
      end if;
      exception
        when others then
          return 'Failure in compact_number(). Error: ' || sqlerrm;
  end;
end iot_apex;
/




-- Create iot_info package
create or replace package iot_info as

  /*
    This code is a package that provides a set of functions to interact with the
    Oracle IoT Platform API. The functions retrieve various types of IoT-related data,
    such as domain groups, domain group connections, domain connections, and domains.
    The data is retrieved using the DBMS_CLOUD.SEND_REQUEST function, which sends a
    GET request to the Oracle IoT Platform API. The response is then parsed using the
    json_table function, and the results are piped to the caller. The package also
    includes overloaded functions that retrieve data without requiring the caller to
    specify the compartment ID, credential name, and region. These functions retrieve
    the required information from the IOT_CONFIG table.
  */

  -- Define a record type to hold IoT domain group information
  type dom_grp_rec is record(
      id varchar2(200),
      compartmentid varchar2(300),
      displayname varchar2(300),
      grp_description varchar2(300),
      lifecyclestate varchar2(50),
      timecreated varchar2(50),
      timeupdated varchar2(50)
  );

  -- Define a table type to hold a collection of dom_grp_rec records
  type dom_grp_tbl is table of dom_grp_rec;

  -- Define a record type to hold IoT domain group connection information
  type dom_grp_conn_rec is record(
      id varchar2(200),
      compartmentId varchar2(300),
      displayName varchar2(300),
      lifecycleState varchar2(50),
      datahost varchar2(300),
      dbConnectionString varchar2(300),
      dbTokenScope varchar2(300),
      timeCreated varchar2(50),
      timeUpdated varchar2(50)
  );

  -- Define a table type to hold a collection of dom_grp_conn_rec records
  type dom_grp_conn_tbl is table of dom_grp_conn_rec;

  -- Define a record type to hold IoT domain connection information
  type dom_conn_rec is record(
      id varchar2(200),
      compartmentId varchar2(300),
      displayName varchar2(300),
      lifecycleState varchar2(50),
      deviceHost varchar2(300),
      iotDomainGroupId varchar2(300),
      retentRawData number,
      retentRejectedData number,
      retentHistorizedData number,
      retentRawCommandData number,
      timeCreated varchar2(50),
      timeUpdated varchar2(50)
  );

  -- Define a table type to hold a collection of dom_conn_rec records
  type dom_conn_tbl is table of dom_conn_rec;

  -- Define a record type to hold IoT domain information
  type dom_rec is record(
      id varchar2(200),
      iotDomainGroupId varchar2(300),
      compartmentId varchar2(300),
      displayName varchar2(300),
      dom_desc varchar2(300),
      lifecycleState varchar2(50),
      timeCreated varchar2(50),
      timeUpdated varchar2(50)
  );

  -- Define a table type to hold a collection of dom_rec records
  type dom_tbl is table of dom_rec;

  -- Function to retrieve IoT domain groups with specified compartment ID, credential name, and region
  function get_dom_grp(p_compartment_id varchar2, p_cred_name varchar2, p_region varchar2) return dom_grp_tbl pipelined;

  -- Function to retrieve all IoT domain groups
  function get_dom_grp return dom_grp_tbl pipelined;

  -- Function to retrieve IoT domain group connections with specified domain group ID, credential name, and region
  function get_dom_grp_conn(p_dom_grp_id varchar2, p_cred_name varchar2, p_region varchar2) return dom_grp_conn_tbl pipelined;

  -- Function to retrieve all IoT domain group connections
  function get_dom_grp_conn return dom_grp_conn_tbl pipelined;

  -- Function to retrieve IoT domain connections with specified domain ID, credential name, and region
  function get_dom_conn(p_dom_id varchar2, p_cred_name varchar2, p_region varchar2) return dom_conn_tbl pipelined;

  -- Function to retrieve all IoT domain connections
  function get_dom_conn return dom_conn_tbl pipelined;

  -- Function to retrieve IoT domains with specified compartment ID, credential name, and region
  function get_dom(p_compartment_id varchar2, p_cred_name varchar2, p_region varchar2) return dom_tbl pipelined;

  -- Function to retrieve all IoT domains
  function get_dom return dom_tbl pipelined;

end;
/

-- Create iot_info package body
create or replace package body iot_info as

  -- Function to retrieve IoT domain groups with specified compartment ID, credential name, and region
  function get_dom_grp(p_compartment_id varchar2, p_cred_name varchar2, p_region varchar2)
    return dom_grp_tbl
    pipelined is

    -- Variables to hold the response from the DBMS_CLOUD.SEND_REQUEST function
    v_return dbms_cloud_types.resp;  -- Response object from DBMS_CLOUD.SEND_REQUEST
    v_clob clob;                     -- clob to store the response text

    begin

      -- Send a GET request to the Oracle IoT Cloud API to retrieve IoT domain groups
      -- The request is constructed using the provided compartment ID, credential name, and region
      v_return := dbms_cloud.send_request(
          credential_name    => p_cred_name, -- Credential name for authentication
          uri                => 'https://iot.'||
                                p_region||
                                '.oci.oraclecloud.com/20250531/iotDomainGroups?compartmentId='||
                                p_compartment_id||
                                '&limit=100', -- URI for the IoT domain groups API
          method             => 'GET'         -- HTTP method (GET)
      );

      -- Get the response text from the v_return object
      v_clob := dbms_cloud.get_response_text(resp => v_return);

      -- Parse the JSON response and pipe the results to the caller
      -- The json_table function is used to parse the JSON response and extract relevant columns
      for json_rec in (
          select
              a.dom_grp_ocid,
              a.compartmentId,
              a.displayName,
              a.dom_grp_desc,
              a.lifecycleState,
              a.timeCreated,
              a.timeUpdated
          from
              json_table(
                  v_clob, -- JSON clob to parse
                  '$.items[*]' columns (  -- Path to the items array in the JSON response
                      dom_grp_ocid varchar path '$.id', -- Column definitions for the json_table function
                      compartmentId varchar path '$.compartmentId',
                      displayName varchar path '$.displayName',
                      dom_grp_desc varchar path '$.description',
                      lifecycleState varchar path '$.lifecycleState',
                      timeCreated varchar path '$.timeCreated',
                      timeUpdated varchar path '$.timeUpdated'
                  )
              ) a
      ) loop
          -- Pipe each row to the caller as a dom_grp_rec object
          pipe row (
            dom_grp_rec(
              json_rec.dom_grp_ocid,
              json_rec.compartmentId,
              json_rec.displayName,
              json_rec.dom_grp_desc,
              json_rec.lifecycleState,
              json_rec.timeCreated,
              json_rec.timeUpdated)
          );
      end loop;

      return;

    exception
      when others then
          -- Log any errors that occur during the execution of this function
          dbms_output.put_line( 'Error: ' || sqlerrm );

  end;

  -- Function to retrieve all IoT domain groups (overload without parameters)
  function get_dom_grp
    return dom_grp_tbl
    pipelined is

    -- Variables to hold the response from the DBMS_CLOUD.SEND_REQUEST function
    v_return dbms_cloud_types.resp;  -- Response object from DBMS_CLOUD.SEND_REQUEST
    v_clob clob;                     -- clob to store the response text
    v_config json_object_t;          -- JSON object to store configuration settings

    begin

      -- Retrieve the compartment ID, credential name, and region from the IOT_CONFIG table
      v_config := iot_apex.iot_config;

      -- Send a GET request to the Oracle IoT Cloud API to retrieve IoT domain groups
      -- The request is constructed using the configuration settings retrieved above
      v_return := dbms_cloud.send_request(
          credential_name    => v_config.get_string('credentials'), -- Credential name from the configuration
          uri                => 'https://iot.'||
                                v_config.get_string('tenancy_region')||
                                '.oci.oraclecloud.com/20250531/iotDomainGroups?compartmentId='||
                                v_config.get_string('iot_compartment'), -- URI for the IoT domain groups API
          method             => 'GET'         -- HTTP method (GET)
      );

      -- Get the response text from the v_return object
      v_clob := dbms_cloud.get_response_text(resp => v_return);

      -- Parse the JSON response and pipe the results to the caller
      -- The json_table function is used to parse the JSON response and extract relevant columns
      for json_rec in (
          select
              a.dom_grp_ocid,
              a.compartmentId,
              a.displayName,
              a.dom_grp_desc,
              a.lifecycleState,
              a.timeCreated,
              a.timeUpdated
          from
              json_table(
                  v_clob, -- JSON clob to parse
                  '$.items[*]' columns (  -- Path to the items array in the JSON response
                      dom_grp_ocid varchar path '$.id', -- Column definitions for the json_table function
                      compartmentId varchar path '$.compartmentId',
                      displayName varchar path '$.displayName',
                      dom_grp_desc varchar path '$.description',
                      lifecycleState varchar path '$.lifecycleState',
                      timeCreated varchar path '$.timeCreated',
                      timeUpdated varchar path '$.timeUpdated'
                  )
              ) a
      ) loop
          -- Pipe each row to the caller as a dom_grp_rec object
          pipe row (
            dom_grp_rec(
              json_rec.dom_grp_ocid,
              json_rec.compartmentId,
              json_rec.displayName,
              json_rec.dom_grp_desc,
              json_rec.lifecycleState,
              json_rec.timeCreated,
              json_rec.timeUpdated)
          );
      end loop;

      return;

    exception
      when others then
          -- Log any errors that occur during the execution of this function
          dbms_output.put_line( 'Error: ' || sqlerrm );
  end;

  -- Function to retrieve IoT domain group connections with specified domain group ID, credential name, and region
  function get_dom_grp_conn(p_dom_grp_id varchar2, p_cred_name varchar2, p_region varchar2)
    return dom_grp_conn_tbl
    pipelined is

    v_return dbms_cloud_types.resp;  -- Response object from dbms_cloud.send_request
    v_clob clob;                     -- clob to store the response text

    begin

      -- Send a GET request to the Oracle IoT Cloud API to retrieve the IoT domain group connection
      v_return := dbms_cloud.send_request(
          credential_name    => p_cred_name, -- Credential name for authentication
          uri                => 'https://iot.'||
                                p_region||
                                '.oci.oraclecloud.com/20250531/iotDomainGroups/'||
                                p_dom_grp_id, -- URI for the IoT domain group connection API
          method             => 'GET'         -- HTTP method (GET)
      );

      -- Get the response text from the v_return object
      v_clob :=
          dbms_cloud.get_response_text(
              resp          => v_return );

      -- Parse the JSON response and pipe the results to the caller
      for json_rec in (
          select  a.dom_grp_ocid,
                  a.compartmentId,
                  a.displayName,
                  a.lifecycleState,
                  a.datahost,
                  a.dbConnectionString,
                  a.dbTokenScope,
                  a.timeCreated,
                  a.timeUpdated
          from    json_table(
                    v_clob, -- JSON clob to parse
                    '$' columns (  -- Path to the root object in the JSON response
                      dom_grp_ocid varchar path '$.id', -- Column definitions for the json_table function
                      compartmentId varchar path '$.compartmentId',
                      displayName varchar path '$.displayName',
                      lifecycleState varchar path '$.lifecycleState',
                      datahost varchar path '$.dataHost',
                      dbConnectionString varchar path '$.dbConnectionString',
                      dbTokenScope varchar path '$.dbTokenScope',
                      timeCreated varchar path '$.timeCreated',
                      timeUpdated varchar path '$.timeUpdated'
                    )
                  ) a
      ) loop
          -- Pipe each row to the caller as a dom_grp_conn_rec object
          pipe row (
            dom_grp_conn_rec(
              json_rec.dom_grp_ocid,
              json_rec.compartmentId,
              json_rec.displayName,
              json_rec.lifecycleState,
              json_rec.datahost,
              json_rec.dbConnectionString,
              json_rec.dbTokenScope,
              json_rec.timeCreated,
              json_rec.timeUpdated
            )
          );
      end loop;

      return;

    exception
      when others then
          -- Log any errors that occur during the execution of this function
          dbms_output.put_line( 'Error: ' || sqlerrm );
  end;

  -- Function to retrieve all IoT domain group connections (overload without parameters)
  function get_dom_grp_conn
    return dom_grp_conn_tbl
    pipelined is

    v_return dbms_cloud_types.resp;  -- Response object from DBMS_CLOUD.SEND_REQUEST
    v_clob clob;                     -- clob to store the response text
    v_config json_object_t;          -- JSON object to store configuration settings

    begin

      -- Retrieve the configuration settings from the IOT_CONFIG table
      v_config := iot_apex.iot_config;

      -- Loop through each IoT domain group retrieved by the get_dom_grp function
      for rec in (select * from table(iot_info.get_dom_grp)) loop
          -- Send a GET request to the Oracle IoT Cloud API to retrieve the IoT domain group connection
          v_return := dbms_cloud.send_request(
              credential_name    => v_config.get_string('credentials'), -- Credential name from the configuration
              uri                => 'https://iot.'||v_config.get_string('tenancy_region')|| '.oci.oraclecloud.com/20250531/iotDomainGroups/'||rec.id, -- URI for the IoT domain group connection API
              method             => 'GET'         -- HTTP method (GET)
          );

          -- Get the response text from the v_return object
          v_clob :=
              dbms_cloud.get_response_text(
                  resp          => v_return );

          -- Parse the JSON response and pipe the results to the caller
          for json_rec in (
              select  a.dom_grp_ocid,
                      a.compartmentId,
                      a.displayName,
                      a.lifecycleState,
                      a.datahost,
                      a.dbConnectionString,
                      a.dbTokenScope,
                      a.timeCreated,
                      a.timeUpdated
              from    json_table(
                        v_clob, -- JSON clob to parse
                        '$' columns (  -- Path to the root object in the JSON response
                          dom_grp_ocid varchar path '$.id', -- Column definitions for the json_table function
                          compartmentId varchar path '$.compartmentId',
                          displayName varchar path '$.displayName',
                          lifecycleState varchar path '$.lifecycleState',
                          datahost varchar path '$.dataHost',
                          dbConnectionString varchar path '$.dbConnectionString',
                          dbTokenScope varchar path '$.dbTokenScope',
                          timeCreated varchar path '$.timeCreated',
                          timeUpdated varchar path '$.timeUpdated'
                        )
                      ) a
          ) loop
              -- Pipe each row to the caller as a dom_grp_conn_rec object
              pipe row (
                dom_grp_conn_rec(
                  json_rec.dom_grp_ocid,
                  json_rec.compartmentId,
                  json_rec.displayName,
                  json_rec.lifecycleState,
                  json_rec.datahost,
                  json_rec.dbConnectionString,
                  json_rec.dbTokenScope,
                  json_rec.timeCreated,
                  json_rec.timeUpdated
                )
              );
          end loop;

      end loop;

      return;

    exception
      when others then
          -- Log any errors that occur during the execution of this function
          dbms_output.put_line( 'Error: ' || sqlerrm );

  end;

  -- Function to retrieve IoT domain connections with specified domain ID, credential name, and region
  function get_dom_conn(p_dom_id varchar2, p_cred_name varchar2, p_region varchar2)
    return dom_conn_tbl
    pipelined IS

    v_return dbms_cloud_types.resp;  -- Response object from DBMS_CLOUD.SEND_REQUEST
    v_clob clob;                     -- clob to store the response text

    begin

      -- Send a GET request to the Oracle IoT Cloud API to retrieve the IoT domain connection
      v_return := dbms_cloud.send_request(
          credential_name    => p_cred_name, -- Credential name for authentication
          uri                => 'https://iot.'||
                                p_region||
                                '.oci.oraclecloud.com/20250531/iotDomains/'||
                                p_dom_id, -- URI for the IoT domain connection API
          method             => 'GET'         -- HTTP method (GET)
      );

      -- Get the response text from the v_return object
      v_clob :=
          dbms_cloud.get_response_text(
              resp          => v_return );

      -- Parse the JSON response and pipe the results to the caller
      for json_rec in (
              select  a.dom_ocid,
                      a.iotdomaingroupid,
                      a.compartmentid,
                      a.displayname,
                      a.lifecyclestate,
                      a.devicehost,
                      a.timecreated,
                      a.timeupdated
              from    json_table(
                        v_clob, -- JSON clob to parse
                        '$' columns (  -- Path to the root object in the JSON response
                          dom_ocid varchar path '$.id', -- Column definitions for the json_table function
                          compartmentid varchar path '$.compartmentId',
                          displayname varchar path '$.displayName',
                          lifecyclestate varchar path '$.lifecycleState',
                          devicehost varchar path '$.deviceHost',
                          iotdomaingroupid varchar path '$.iotDomainGroupId',
                          timecreated varchar path '$.timeCreated',
                          timeupdated varchar path '$.timeUpdated'
                        )
                      ) a
          ) loop
              -- Pipe each row to the caller as a dom_conn_rec object
              pipe row (
                dom_conn_rec(
                  json_rec.dom_ocid,
                  json_rec.compartmentid,
                  json_rec.displayname,
                  json_rec.lifecyclestate,
                  json_rec.devicehost,
                  json_rec.iotdomaingroupid,
                  json_rec.timecreated,
                  json_rec.timeupdated
                )
              );
          end loop;

      return;

    exception
      when others then
          -- Log any errors that occur during the execution of this function
          dbms_output.put_line( 'Error: ' || sqlerrm );

  end;

  -- Function to retrieve all IoT domain connections (overload without parameters)
  function get_dom_conn
    return dom_conn_tbl
    pipelined is

    v_return dbms_cloud_types.resp;  -- Response object from DBMS_CLOUD.SEND_REQUEST
    v_clob clob;                     -- clob to store the response text
    v_config json_object_t;          -- JSON object to store configuration settings

    begin

      -- Retrieve the configuration settings from the IOT_CONFIG table
      v_config := iot_apex.iot_config;

      -- Loop through each IoT domain retrieved by the get_dom function
      for rec in (select * from table(iot_info.get_dom)) loop

          -- Send a GET request to the Oracle IoT Cloud API to retrieve the IoT domain connection
          v_return := dbms_cloud.send_request(
              credential_name    => v_config.get_string('credentials'), -- Credential name from the configuration
              uri                => 'https://iot.'||
                                    v_config.get_string('tenancy_region')||
                                    '.oci.oraclecloud.com/20250531/iotDomains/'||
                                    rec.id, -- URI for the IoT domain connection API
              method             => 'GET'         -- HTTP method (GET)
          );

          -- Get the response text from the v_return object
          v_clob :=
            dbms_cloud.get_response_text(
              resp => v_return
            );

          -- Parse the JSON response and pipe the results to the caller
          for json_rec in (
              select  a.dom_ocid,
                      a.iotdomaingroupid,
                      a.compartmentid,
                      a.displayname,
                      a.lifecyclestate,
                      a.devicehost,
                      a.retentrawdata,
                      a.retentrejecteddata,
                      a.retenthistorizeddata,
                      a.retentrawcommanddata,
                      a.timecreated,
                      a.timeupdated
              from json_table(
                  v_clob, -- JSON clob to parse
                  '$' columns (  -- Path to the root object in the JSON response
                      dom_ocid varchar path '$.id', -- Column definitions for the json_table function
                      compartmentid varchar path '$.compartmentId',
                      displayname varchar path '$.displayName',
                      lifecyclestate varchar path '$.lifecycleState',
                      devicehost varchar path '$.deviceHost',
                      iotdomaingroupid varchar path '$.iotDomainGroupId',
                      retentrawdata number path '$.dataRetentionPeriodsInDays.rawData',
                      retentrejecteddata number path '$.dataRetentionPeriodsInDays.rejectedData',
                      retenthistorizeddata number path '$.dataRetentionPeriodsInDays.historizedData',
                      retentrawcommanddata number path '$.dataRetentionPeriodsInDays.rawCommandData',
                      timecreated varchar path '$.timeCreated',
                      timeupdated varchar path '$.timeUpdated'
                  )
              ) A
          ) loop
              -- Pipe each row to the caller as a dom_conn_rec object
              pipe row (
                dom_conn_rec(
                  json_rec.dom_ocid,
                  json_rec.compartmentid,
                  json_rec.displayname,
                  json_rec.lifecyclestate,
                  json_rec.devicehost,
                  json_rec.iotdomaingroupid,
                  json_rec.retentrawdata,
                  json_rec.retentrejecteddata,
                  json_rec.retenthistorizeddata,
                  json_rec.retentrawcommanddata,
                  json_rec.timecreated,
                  json_rec.timeupdated
                )
              );
          end loop;

      end loop;

      return;

    exception
      when others then
          -- Log any errors that occur during the execution of this function
          dbms_output.put_line( 'Error: ' || sqlerrm );
  end;

  -- Function to retrieve IoT domains with specified compartment ID, credential name, and region
  function get_dom(p_compartment_id varchar2, p_cred_name varchar2, p_region varchar2)
    return dom_tbl
    pipelined is

    v_return dbms_cloud_types.resp;  -- Response object from DBMS_CLOUD.SEND_REQUEST
    v_clob clob;                     -- clob to store the response text

    begin

      -- Send a GET request to the Oracle IoT Cloud API to retrieve IoT domains
      v_return := dbms_cloud.send_request(
          credential_name    => p_cred_name, -- Credential name for authentication
          uri                => 'https://iot.'||
                                p_region||
                                '.oci.oraclecloud.com/20250531/iotDomains?compartmentId='||
                                p_compartment_id, -- URI for the IoT domains API
          method             => 'GET'         -- HTTP method (GET)
      );

      -- Get the response text from the v_return object
      v_clob :=
          dbms_cloud.get_response_text(resp          => v_return );

      -- Parse the JSON response and pipe the results to the caller
      for json_rec in (
          select  a.dom_ocid,
                  a.iotdomaingroupid,
                  a.compartmentid,
                  a.displayname,
                  a.dom_desc,
                  a.lifecyclestate,
                  a.timecreated,
                  a.timeupdated
          from json_table(
              v_clob, -- JSON clob to parse
              '$.items[*]' columns (  -- Path to the items array in the JSON response
                  dom_ocid varchar path '$.id', -- Column definitions for the json_table function
                  iotdomaingroupid varchar path '$.iotDomainGroupId',
                  compartmentid varchar path '$.compartmentId',
                  displayname varchar path '$.displayName',
                  dom_desc varchar2 path '$.description',
                  lifecyclestate varchar path '$.lifecycleState',
                  timecreated varchar path '$.timeCreated',
                  timeupdated varchar path '$.timeUpdated'
              )
          ) a
      ) loop
          -- Pipe each row to the caller as a dom_rec object
          pipe row (
            dom_rec(
              json_rec.dom_ocid,
              json_rec.iotdomaingroupid,
              json_rec.compartmentid,
              json_rec.displayname,
              json_rec.dom_desc,
              json_rec.lifecyclestate,
              json_rec.timecreated,
              json_rec.timeupdated));
      end loop;

      return;

    exception
      when others then
          -- Log any errors that occur during the execution of this function
          dbms_output.put_line( 'Error: ' || sqlerrm );
  end;

  -- Function to retrieve all IoT domains (overload without parameters)
  function get_dom
    return dom_tbl
    pipelined is

    v_return dbms_cloud_types.resp;  -- Response object from DBMS_CLOUD.SEND_REQUEST
    v_clob clob;                     -- clob to store the response text
    v_config json_object_t;          -- JSON object to store configuration settings

    begin

      -- Retrieve the configuration settings from the IOT_CONFIG table
      v_config := iot_apex.iot_config;

      -- Send a GET request to the Oracle IoT Cloud API to retrieve IoT domains
      v_return := dbms_cloud.send_request(
            credential_name    => v_config.get_string('credentials'), -- Credential name from the configuration
            uri                => 'https://iot.'||
                                  v_config.get_string('tenancy_region')||
                                  '.oci.oraclecloud.com/20250531/iotDomains?compartmentId='||
                                  v_config.get_string('iot_compartment'), -- URI for the IoT domains API
            method             => 'GET'         -- HTTP method (GET)
      );

      -- Get the response text from the v_return object
      v_clob :=
          dbms_cloud.get_response_text(resp          => v_return );

      -- Parse the JSON response and pipe the results to the caller
      for json_rec in (
          select  a.dom_ocid,
                  a.iotdomaingroupid,
                  a.compartmentid,
                  a.displayname,
                  a.dom_desc,
                  a.lifecyclestate,
                  a.timecreated,
                  a.timeupdated
          from json_table(
              v_clob, -- JSON clob to parse
              '$.items[*]' columns (  -- Path to the items array in the JSON response
                  dom_ocid varchar path '$.id', -- Column definitions for the json_table function
                  iotdomaingroupid varchar path '$.iotDomainGroupId',
                  compartmentid varchar path '$.compartmentId',
                  displayname varchar path '$.displayName',
                  dom_desc varchar2 path '$.description',
                  lifecyclestate varchar path '$.lifecycleState',
                  timecreated varchar path '$.timeCreated',
                  timeupdated varchar path '$.timeUpdated'
              )
          ) a
      ) loop
          -- Pipe each row to the caller as a dom_rec object
          pipe row (
            dom_rec(
              json_rec.dom_ocid,
              json_rec.iotdomaingroupid,
              json_rec.compartmentid,
              json_rec.displayname,
              json_rec.dom_desc,
              json_rec.lifecyclestate,
              json_rec.timecreated,
              json_rec.timeupdated));
      end loop;

      return;

    exception
      when others then
          -- Log any errors that occur during the execution of this function
          dbms_output.put_line( 'Error: ' || sqlerrm );

  end;
end;
/




-- Create iot_objects package
create or replace package iot_objects as 
  -- Constructs a JSON clob for "instance" API requests using supplied parameters 
  function instance_api_body( 
    p_type varchar2 /* structured or unstructured */,
    p_iot_domain_ocid varchar2 default null, /*only needed on create request*/
    p_auth_id varchar2, 
    p_display_name varchar2 default null, 
    p_description varchar2 default null, 
    p_external_key varchar2 default null, 
    p_dt_adapt_ocid varchar2 default null, 
    p_freeform_tags varchar2 default null,
    p_ocid varchar2 default null --identity of object for update and delete
  ) return clob; 

  -- Builds CLI command to create a digital twin instance from parameters 
  function instance_cli( 
    p_type varchar2, /* structured or unstructured */
    p_iot_domain_ocid varchar2 default null,
    p_auth_id varchar2, 
    p_display_name varchar2 default null, 
    p_description varchar2 default null, 
    p_external_key varchar2 default null, 
    p_dt_adapt_ocid varchar2 default null, 
    p_freeform_tags varchar2 default null,
    p_action varchar2 default 'create', /* create or update or delete */
    p_ocid varchar2 default null --identity of object for update and delete
  ) return clob; 

  -- Calls REST API to create a digital twin instance, given a JSON clob body 
  function create_instance(p_body clob) return clob; 

  -- Calls REST API to update a digital twin instance, given the ocid of the 
  -- instance to be updated and JSON clob body 
  function update_instance(p_ocid varchar2, p_body clob) return clob;

  -- Constructs the API JSON body to create a digital twin model 
  function model_api_body(
    p_iot_domain_ocid varchar2 default null, /*only needed on create request*/
    p_display_name varchar2,
    p_description varchar2 default null, 
    p_context varchar2, 
    p_contents clob, 
    p_freeform_tags clob default null, 
    p_dtdl_id varchar2 default null,
    p_ocid varchar2 default null --identity of object for update and delete
  ) return clob; 

  -- Builds CLI command to create a digital twin model 
 function model_cli(
    p_iot_domain_ocid varchar2 default null,
    p_display_name varchar2,
    p_description varchar2 default null, 
    p_context varchar2, /* expects comma seperated list */
    p_contents clob,  /* expects json format */
    p_freeform_tags clob default null, /* json object format { "key":"value","key":"value" } */
    p_dtdl_id varchar2 default null,
    p_action varchar2 default 'create', /* create or update or delete */ 
    p_ocid varchar2 default null --used to identify model for update or delete
  ) return clob; 

  -- Calls REST API to create a digital twin model 
  function create_model(p_body clob) return clob; 

  -- Calls REST API to update a digital twin model, given the ocid of the 
  -- model to be updated and JSON clob body 
  function update_model(p_ocid varchar2, p_body clob) return clob; 

  -- Constructs JSON API payload for digital twin adapter creation 
  function adapter_api_body(
    p_iot_domain_ocid varchar2 default null, /*only needed on create request*/
    p_dt_model_ocid varchar2 default null, 
    p_display_name varchar2, 
    p_description varchar2 default null,
    p_ocid varchar2 default null --used to identify adapter for update or delete
  ) return clob; 

  -- Composes CLI command for digital twin adapter creation 
  function adapter_cli( 
    p_iot_domain_ocid varchar2 default null, /*only needed on create request*/
    p_dt_model_ocid varchar2, 
    p_display_name varchar2, 
    p_description varchar2 default null,
    p_action varchar2 default 'create', /* create or update or delete */
    p_ocid varchar2 default null 
  ) return clob; 

  -- Calls REST API to create a digital twin adapter 
  function create_adapter(p_body clob) return clob; 

  -- Calls REST API to update a digital twin adapter, given the ocid of the 
  -- adapter to be updated and JSON clob body 
  function update_adapter(p_ocid varchar2, p_body clob) return clob; 

  -- Calls REST API to delete a digital twin model, adapter, or instance, 
  -- depending on OCID type inferred from its prefix pattern 
  function delete_object(p_object_ocid varchar2) return clob; 
end iot_objects;
/

-- Create iot_objects package body
create or replace package body iot_objects as
  -- Constructs a JSON clob for "instance" API requests using supplied parameters
  function instance_api_body( 
    p_type varchar2 /* structured or unstructured */,
    p_iot_domain_ocid varchar2 default null, /*only needed on create request*/
    p_auth_id varchar2, 
    p_display_name varchar2 default null, 
    p_description varchar2 default null, 
    p_external_key varchar2 default null, 
    p_dt_adapt_ocid varchar2 default null, 
    p_freeform_tags varchar2 default null,
    p_ocid varchar2 default null --identity of object for update and delete
    ) 
    return clob is 
      v_domain_ocid varchar2(255); 
      json_main json_object_t; 
      json_obj json_object_t; 
    begin 

      json_main := json_object_t(); 

      -- Conditionally populate JSON keys if params present
      if p_iot_domain_ocid is not null then json_main.put('iotDomainId',p_iot_domain_ocid); end if;
      if p_auth_id is not null then json_main.put('authId',p_auth_id); end if; 
      if p_display_name is not null then json_main.put('displayName',p_display_name); end if; 
      if p_description is not null then json_main.put('description',p_description); end if; 
      if p_external_key is not null then json_main.put('externalKey',p_external_key); end if; 

      -- Add digitalTwinAdapterId for type "structured" 
      if lower(p_type) = 'structured' then 
        if p_dt_adapt_ocid is not null then 
          json_main.put('digitalTwinAdapterId',p_dt_adapt_ocid); 
        end if; 
      end if; 

      -- If freeform tags are supplied, add as JSON object 
      if p_freeform_tags is not null then 
        json_obj := json_object_t(); 
        json_obj := json_object_t( p_freeform_tags ); 
        json_main.put('freeformTags',json_obj); 
      end if; 

    return  json_main.to_clob; -- Return the assembled JSON as clob 

    exception 
      when others then 
        return 'Error: ' || sqlerrm; -- On error, return error text 
  end; 


  -- Builds CLI command to create, update, or delete a digital twin instance
  function instance_cli(
    p_type varchar2, /* structured or unstructured */
    p_iot_domain_ocid varchar2 default null,
    p_auth_id varchar2, 
    p_display_name varchar2 default null, 
    p_description varchar2 default null, 
    p_external_key varchar2 default null, 
    p_dt_adapt_ocid varchar2 default null, 
    p_freeform_tags varchar2 default null,
    p_action varchar2 default 'create', /* create or update or delete */
    p_ocid varchar2 default null --identity of object for update and delete
    ) 
    return clob is
      json_main json_object_t; 
      json_obj json_object_t; 
      v_return clob; 
      v_auth_id varchar2(300);
      p_iot_domain_ocid varchar2(300);
      v_display_name varchar2(100); 
      v_description varchar2(500); 
      v_iot_domain_ocid varchar2(300); 
      v_external_key varchar2(100); 
      v_dt_adapt_ocid varchar2(300); 
      v_freeform_tags varchar2(500);
      v_ocid varchar2(300);
    begin

      -- Build CLI parameter portions only if inputs provided
      v_display_name := nvl2(p_display_name,
                             '--display-name "'|| p_display_name ||'" ',
                             null);

      v_description := nvl2(p_description,
                            '--description "'|| p_description ||'" ',
                            null);
      v_iot_domain_ocid := nvl2(p_iot_domain_ocid, 
                            '--iotDomainId "'|| p_iot_domain_ocid ||'" ', 
                            null); 

      -- For structured type, add adapter id param
      if lower(p_type) = 'structured' then
        v_domain_ocid := nvl2(p_description,
                              '--digital-twin-adapter-id "'|| p_dt_adapt_ocid ||'" ',
                              null);
      end if;

      -- Optional params
      v_external_key := nvl2(p_external_key, 
                             '--external-key "' || p_external_key || '" ', 
                             null); 
      v_auth_id := nvl2(p_auth_id, 
                              '--auth-id "' || p_auth_id || '" ', 
                              null); 
      v_freeform_tags := nvl2(p_freeform_tags, 
                              '--freeform-tags '''|| p_freeform_tags ||''' ', 
                              null);
      v_ocid := nvl2(p_ocid, 
                      '--digital-twin-instance-id "'|| p_ocid ||'" ', 
                      null);

      -- Compose entire CLI command
      if lower(p_action) = 'create' then
        v_return := 'oci iot digital-twin-instance '|| lower(p_action) ||' '||
                    v_iot_domain_ocid||
                    v_display_name|| 
                    v_description||  
                    v_external_key|| 
                    v_freeform_tags||
                    v_dt_adapt_ocid||
                    v_auth_id;
      elsif lower(p_action) = 'update' and v_ocid is not null then
        v_return := 'oci iot digital-twin-instance '|| lower(p_action) ||' '||
                    v_display_name|| 
                    v_description|| 
                    v_external_key|| 
                    v_freeform_tags||
                    v_dt_adapt_ocid||
                    v_auth_id||
                    v_ocid;
      elsif lower(p_action) = 'delete' and v_ocid is not null then
        v_return := 'oci iot digital-twin-instance '|| lower(p_action) ||' '|| 
                    v_ocid;
      end if;

    return  v_return;

    exception
      when others then
        return 'Error: ' || sqlerrm;
  end;


  -- Calls REST API to create a digital twin instance, given a JSON clob body
  function create_instance(p_body clob)
    return clob
    as
    response dbms_cloud_types.resp;
    v_return clob;
    v_config json_object_t;
    v_blob blob;
    v_uri varchar2(500);
    begin

      v_config := iot_apex.iot_config; -- Load config

      v_blob := iot_apex.clob_to_blob(p_body); -- Convert JSON body to BLOB

          response := dbms_cloud.send_request(
              credential_name    => v_config.get_string('credentials'),
              uri                => 'https://iot.'||
                                    v_config.get_string('tenancy_region')||
                                    '.oci.oraclecloud.com/20250531/digitalTwinInstances',
              method             => 'POST',
              body               => v_blob );

          -- Read and return response text
          v_return :=
              dbms_cloud.get_response_text(
                  resp          => response );

    return v_return;

    exception
      when others then
          -- Log any errors that occur during the execution of this function
          return 'Error: ' || sqlerrm;
  end;


  -- Calls REST API to update a digital twin instance, given a JSON clob body 
  function update_instance(p_ocid varchar2, p_body clob) 
    return clob 
    as 
    response dbms_cloud_types.resp; 
    v_return clob; 
    v_config json_object_t; 
    v_blob blob; 
    v_uri varchar2(500); 
    begin 

      v_config := iot_apex.iot_config; -- Load config 

      v_blob := iot_apex.clob_to_blob(p_body); -- Convert JSON body to BLOB 

      response := dbms_cloud.send_request( 
          credential_name    => v_config.get_string('credentials'), 
          uri                => 'https://iot.'|| 
                                v_config.get_string('tenancy_region')|| 
                                '.oci.oraclecloud.com/20250531/digitalTwinInstances/'||p_ocid, 
          method             => 'PUT', 
          body               => v_blob ); 

      -- Read and return response text 
      v_return := 
          dbms_cloud.get_response_text( 
              resp          => response ); 

    return v_return; 

    exception 
      when others then 
          -- Log any errors that occur during the execution of this function 
          return 'Error: ' || sqlerrm; 

  end; 


  -- Constructs the API JSON body to create a digital twin model
  function model_api_body(
    p_iot_domain_ocid varchar2 default null, /*only needed on create request*/
    p_display_name varchar2,
    p_description varchar2 default null,  
    p_context varchar2, 
    p_contents clob, 
    p_freeform_tags clob default null, 
    p_dtdl_id varchar2 default null,
    p_ocid varchar2 default null --identity of object for update and delete
    ) 
    return clob
    is
      v_return clob;
      v_domain_ocid varchar2(255);
      v_element varchar2(255);
      json_main json_object_t;
      json_spec json_object_t;
      json_obj json_object_t;
      json_array json_array_t;
    begin
      json_main := json_object_t();

      if p_iot_domain_ocid is not null then 
        json_main.put('iotDomainId',p_iot_domain_ocid); 
      end if; 

      if p_display_name is not null then
        json_main.put('displayName',p_display_name);
      end if;

      if p_description is not null then
        json_main.put('description',p_description);
      end if;

      -- Attach freeformTags JSON object if present and valid
      if p_freeform_tags is not null and iot_apex.is_json( p_freeform_tags ) = 'true' then
        json_obj := json_object_t();
        json_obj := json_object_t( p_freeform_tags );
        json_main.put('freeformTags',json_obj);
      end if;

      json_spec := json_object_t();

      if p_display_name is not null then
        json_spec.put('displayName',p_display_name);
      end if;

      if p_dtdl_id is not null then
        json_spec.put('@id',p_dtdl_id);
      end if;

      if p_description is not null then
        json_spec.put('description',p_description);
      end if;

      json_spec.put('@type','Interface'); -- Always "Interface"

      -- Build @context as JSON array if provided (comma separated context)
      if p_context is not null then
        json_array := json_array_t();
        for i in 1..regexp_count(p_context, '[^,]+') loop
            -- Process the element
            v_element := trim( regexp_substr(p_context, '[^,]+', 1, i) );
            json_array.append( v_element );
        end loop;
        json_spec.put('@context',json_array);
      end if;

      -- Attach contents as array, if valid JSON clob provided
      if p_contents is not null and iot_apex.is_json( p_contents ) = 'true' then
        json_array := json_array_t(p_contents);
        json_spec.put('contents',json_array);
      end if;

      json_main.put( 'spec', json_spec );

      return  json_main.to_clob;

      exception
        when others then
          return 'Error: ' || sqlerrm;
  end;


  -- Builds CLI command to create a digital twin model
  function model_cli(
    p_iot_domain_ocid varchar2 default null,
    p_display_name varchar2,
    p_description varchar2 default null, 
    p_context varchar2, /* expects comma seperated list */
    p_contents clob,  /* expects json format */
    p_freeform_tags clob default null, /* json object format { "key":"value","key":"value" } */
    p_dtdl_id varchar2 default null,
    p_action varchar2 default 'create', /* create or update or delete */ 
    p_ocid varchar2 default null --used to identify model for update or delete
    ) 
    return clob
    is
      v_return clob; 
      v_result clob; 
      v_json_src json_object_t; 
      v_json_spec json_object_t; 
      v_iot_domain_ocid varchar2(300); 
      v_display_name varchar2(300); 
      v_description varchar2(500); 
      v_context varchar2(300); 
      v_contents clob; 
      v_freeform_tags clob;
      v_ocid varchar2(255);
    begin
      -- Build CLI parameter strings
      v_iot_domain_ocid := nvl2(p_iot_domain_ocid, 
            '--iot-domain-id "'|| p_iot_domain_ocid ||'" ', 
            null);
      v_display_name := nvl2(p_display_name, 
            '--display-name "'|| p_display_name ||'" ', 
            null); 
      v_description := nvl2(p_description, 
            '--description "'|| p_description ||'" ', 
            null); 
      v_freeform_tags := nvl2(p_freeform_tags, 
            '--freeform-tags "'|| p_freeform_tags ||'" ', 
            null);
      v_ocid := nvl2(p_ocid, 
            '--digital-twin-model-id "'|| p_ocid ||'" ', 
            null);

      v_result := iot_objects.model_api_body(
        p_iot_domain_ocid => p_iot_domain_ocid,
        p_display_name => p_display_name,
        p_description => p_description,
        p_context => p_context,
        p_contents => p_contents,
        p_freeform_tags => p_freeform_tags,
        p_dtdl_id => p_dtdl_id,
        p_ocid => v_ocid );

      v_json_src := json_object_t.parse(v_result);
      v_json_spec := json_object_t();

      -- Extract and reconstruct "spec" for CLI argument
      v_json_spec.put('@context', treat(
                                    treat(
                                      v_json_src.get('spec') as json_object_t
                                    ).get('@context') as json_array_t
                                  )
                                );
      v_json_spec.put('@id', treat(
                               v_json_src.get('spec') as json_object_t
                             ).get('@id')
                           );
      v_json_spec.put('@type','Interface');
      v_json_spec.put('contents', treat(
                                    treat(
                                      v_json_src.get('spec') as json_object_t
                                    ).get('contents') as json_array_t
                                  )
                                );

      -- Build CLI invocation string 
      if lower(p_action) = 'delete' and v_ocid is not null then
        v_return := 'oci iot digital-twin-model '|| p_action ||' '|| v_ocid;
      elsif lower(p_action) = 'update' and v_ocid is not null then
        v_return := 'oci iot digital-twin-model '|| p_action ||' '|| 
                    v_iot_domain_ocid|| 
                    v_ocid||
                    v_display_name|| 
                    v_description|| 
                    v_freeform_tags|| 
                    '--spec "'||v_json_spec.to_clob||'"'; 
      elsif lower(p_action) = 'create' then 
        v_return := 'oci iot digital-twin-model '|| p_action ||' '|| 
                    v_iot_domain_ocid|| 
                    v_display_name|| 
                    v_description|| 
                    v_freeform_tags|| 
                    '--spec "'||v_json_spec.to_clob||'"'; 
      end if;

      return v_return;

      exception
        when others then
          return 'Error: ' || sqlerrm;
  end;


  -- Calls REST API to create a digital twin model
  function create_model(p_body clob)
    return clob
    is
    response dbms_cloud_types.resp;
    v_return clob;
    v_blob blob;
    v_config json_object_t;
    begin

      v_config := iot_apex.iot_config; -- Load settings

      if iot_apex.is_json(p_body) = 'false' then
        raise_application_error(-20001, 'Improper JSON.'); -- Validate JSON
      end if;

      v_blob := iot_apex.clob_to_blob(p_body); -- Prepare HTTP body

      response := dbms_cloud.send_request(
          credential_name    => v_config.get_string('credentials'),
          uri                => 'https://iot.'||
                                v_config.get_string('tenancy_region')||
                                '.oci.oraclecloud.com/20250531/digitalTwinModels',
          method             => 'POST',
          body               => v_blob );

      v_return :=
          dbms_cloud.get_response_text(
              resp          => response );

      return v_return;

      exception
        when others then
          return 'Error: ' || sqlerrm;
  end;


  -- Calls REST API to create a update twin model 
  function update_model(p_ocid varchar2, p_body clob) 
    return clob 
    is 
    response dbms_cloud_types.resp; 
    v_return clob; 
    v_blob blob; 
    v_config json_object_t;
    v_json_body json_object_t;
    v_body clob;
    begin 

      v_config := iot_apex.iot_config; -- Load settings 

      if iot_apex.is_json(p_body) = 'false' then 
        raise_application_error(-20001, 'Improper JSON.'); -- Validate JSON 
      end if; 

      v_json_body := json_object_t.parse(p_body);
      v_json_body.remove('spec');
      v_body := v_json_body.to_clob;

      v_blob := iot_apex.clob_to_blob(v_body); -- Prepare HTTP body 

          response := dbms_cloud.send_request( 
              credential_name    => v_config.get_string('credentials'), 
              uri                => 'https://iot.'|| 
                                    v_config.get_string('tenancy_region')|| 
                                    '.oci.oraclecloud.com/20250531/digitalTwinModels/'||p_ocid, 
              method             => 'PUT', 
              body               => v_blob ); 

          v_return := 
              dbms_cloud.get_response_text( 
                  resp          => response ); 

      return v_return; 

      exception 
        when others then 
          return 'Error: ' || sqlerrm; 
  end; 


  -- Constructs JSON API payload for digital twin adapter creation
  function adapter_api_body(
    p_iot_domain_ocid varchar2 default null, /*only needed on create request*/
    p_dt_model_ocid varchar2 default null, 
    p_display_name varchar2, 
    p_description varchar2 default null,
    p_ocid varchar2 default null ) 
    return clob
    is
    v_domain_ocid varchar2(255);
    json_main json_object_t;
    begin
      json_main := json_object_t();

      if p_iot_domain_ocid is not null then 
        json_main.put('iotDomainId',p_iot_domain_ocid); 
      end if; 
      if p_dt_model_ocid is not null then 
        json_main.put('digitalTwinModelId',p_dt_model_ocid); 
      end if; 
      if p_display_name is not null then 
        json_main.put('displayName',p_display_name); 
      end if; 
      if p_description is not null then 
        json_main.put('description',p_description); 
      end if; 
      if p_ocid is not null then 
        json_main.put('digitalTwinAdapterId',p_ocid); 
      end if; 

      return  json_main.to_clob; 

      exception 
        when others then 
          return 'Error: ' || sqlerrm; 
  end; 


  -- Composes CLI command for digital twin adapter creation
  function adapter_cli(
    p_iot_domain_ocid varchar2 default null, /*only needed on create request*/
    p_dt_model_ocid varchar2, 
    p_display_name varchar2, 
    p_description varchar2 default null,
    p_action varchar2 default 'create', /* create or update or delete */
    p_ocid varchar2 default null ) 
    return clob
    is
      v_domain_ocid varchar2(255); 
      v_return clob; 
      v_dt_model_ocid varchar2(300); 
      v_display_name varchar2(100); 
      v_description varchar2(500);
      v_ocid varchar2(300);
    begin
      v_display_name := nvl2(p_display_name, 
        '--display-name "'|| p_display_name || '" ', 
        null); 
      v_description := nvl2(p_description, 
        '--description "'|| p_description ||'" ', 
        null); 
      v_dt_model_ocid := nvl2(p_dt_model_ocid, 
        '--digital-twin-model-id "'|| p_dt_model_ocid ||'" ', 
        null);
      v_ocid := nvl2(p_ocid, 
        '--digital-twin-adapter-id "'|| p_ocid ||'" ', 
        null); 

      select  '--iot-domain-id "'|| id  ||'" '
      into    v_domain_ocid
      from    table( iot_info.get_dom );

      if lower(p_action) = 'create' then
        v_return := 'oci iot digital-twin-adapter '|| p_action ||' '|| 
                    v_domain_ocid||
                    v_display_name|| 
                    v_description|| 
                    v_dt_model_ocid;
      elsif lower(p_action) = 'update' and v_ocid is not null then
        v_return := 'oci iot digital-twin-adapter '|| p_action ||' '||
                    v_ocid||
                    v_display_name|| 
                    v_description|| 
                    v_dt_model_ocid;
      elsif lower(p_action) = 'delete' and v_ocid is not null then
        v_return := 'oci iot digital-twin-adapter '|| p_action ||' '||
                    v_ocid;
      end if;

      return  v_return;

      exception
        when others then
          return 'Error: ' || sqlerrm;
  end;


  -- Calls REST API to create a digital twin adapter
  function create_adapter(p_body clob)
    return clob
    is
    response dbms_cloud_types.resp;
      v_return clob;
      v_blob blob;
      v_config json_object_t;

    begin

      v_config := iot_apex.iot_config; -- Load settings

      v_blob := iot_apex.clob_to_blob(p_body);

      response := dbms_cloud.send_request(
          credential_name    => v_config.get_string('credentials'),
          uri                => 'https://iot.'||
                                v_config.get_string('tenancy_region')||
                                '.oci.oraclecloud.com/20250531/digitalTwinAdapters',
          method             => 'POST',
          body               => v_blob );

      v_return :=
          dbms_cloud.get_response_text(
              resp          => response );

    return v_return;

    exception
      when others then
          -- Log any errors that occur during the execution of this function
          return 'Error: ' || sqlerrm;
  end;

  -- Calls REST API to update a digital twin adapter 
  function update_adapter(p_ocid varchar2, p_body clob) 
    return clob 
    is 
    response dbms_cloud_types.resp; 
      v_return clob; 
      v_blob blob; 
      v_config json_object_t; 

    begin 

      v_config := iot_apex.iot_config; -- Load settings 

      v_blob := iot_apex.clob_to_blob(p_body); 

      response := dbms_cloud.send_request( 
          credential_name    => v_config.get_string('credentials'), 
          uri                => 'https://iot.'|| 
                                v_config.get_string('tenancy_region')|| 
                                '.oci.oraclecloud.com/20250531/digitalTwinAdapters/'||p_ocid, 
          method             => 'PUT', 
          body               => v_blob ); 

      v_return := 
          dbms_cloud.get_response_text( 
              resp          => response ); 

    return v_return; 

    exception 
      when others then 
          -- Log any errors that occur during the execution of this function 
          return 'Error: ' || sqlerrm; 
  end; 

  -- Calls REST API to delete a digital twin model, adapter, or instance,
  -- depending on OCID type inferred from its prefix pattern
  function delete_object(p_object_ocid varchar2)
    return clob
    as
      response dbms_cloud_types.resp;
      v_return clob;
      v_config json_object_t;
      v_uri varchar2(500);
    begin
      v_config := iot_apex.iot_config;

      v_uri := 'https://iot.'||v_config.get_string('tenancy_region');

      -- Decide URI suffix by OCID prefix
      if instr(p_object_ocid,'.iotdigitaltwinmodel.') > 0 then
        v_uri := v_uri || '.oci.oraclecloud.com/20250531/digitalTwinModels/'||p_object_ocid;
      elsif instr(p_object_ocid,'.iotdigitaltwinadapter.') > 0 then
        v_uri := v_uri || '.oci.oraclecloud.com/20250531/digitalTwinAdapters/'||p_object_ocid;
      elsif instr(p_object_ocid,'.iotdigitaltwininstance.') > 0 then
        v_uri := v_uri || '.oci.oraclecloud.com/20250531/digitalTwinInstances/'||p_object_ocid;
      else
        raise_application_error(-20001, 'OCID prefix not recognised as an IoT Object type.');
      end if;

      response := dbms_cloud.send_request(
        credential_name    => v_config.get_string('credentials'),
        uri                => v_uri,
        method             => 'DELETE'
      );

      v_return :=
          dbms_cloud.get_response_text(
              resp          => response );

    return v_return||'success';

    exception
      when others then
          -- Log any errors that occur during the execution of this function
          return 'Error: ' || sqlerrm;
  end;
end iot_objects;
/




-- Create iot_oci package
create or replace package iot_oci as
  function pretty(p_json_clob clob) return clob;

  function get_secret(p_secret_ocid varchar2) return clob;

  function create_secret(
    p_secret_name varchar2,
    secret_content varchar2 default null,
    secret_char number default 24) return clob;

  function delete_secret(p_secret_name varchar2) return clob;

  function get_all_secrets return clob;

  function get_all_cas return clob;

  function get_all_certs return clob; --LIST_CERTIFICATES

  function create_cert( p_cert_name varchar2, p_cert_auth_ocid varchar2 ) return clob;

  function delete_cert( p_cert_ocid varchar2 ) return clob;

  function get_cert( p_cert_ocid varchar2 ) return clob;

end iot_oci;
/

-- Create iot_oci package body
create or replace package body iot_oci as

  -- Function to pretty-print a JSON clob
  function pretty(p_json_clob clob)
      return clob is
      js json; -- Holds parsed input JSON from clob
      v_clob clob; -- Will receive the pretty-printed JSON output
    begin
      -- Parse the input clob string into a JSON object using the JSON constructor
      js := json(p_json_clob); -- Create a JSON object from the input clob

      -- Serialize the JSON object to a clob with PRETTY formatting using json_serialize
      select json_serialize(js returning clob pretty) -- Pretty-print the JSON object
      into v_clob; -- Store the formatted JSON in v_clob

      -- Return the formatted JSON string
      return v_clob; -- Return the pretty-printed JSON clob

    exception
      when others then
          -- Output any error that occurs during execution to the Oracle buffer for debugging
          return 'Error: ' || sqlerrm; -- Log the error message

  end;

  -- Function to retrieve a secret from OCI Vault given a secret OCID
  function get_secret(p_secret_ocid varchar2)
      return clob is
      results dbms_cloud_oci_sc_secrets_get_secret_bundle_response_t; -- For secret bundle API response
      v_config json_object_t; -- OCI config pulled from app-owned table
      v_return clob; -- Decoded secret string to return
    begin

      -- Fetch the OCI configuration (compartment, credentials, etc.) from the app-owned table
      v_config := iot_apex.iot_config; -- Get the OCI configuration

      -- Call the OCI SDK package to retrieve the secret bundle by secret OCID
      results := dbms_cloud_oci_sc_secrets.get_secret_bundle(
          secret_id => p_secret_ocid, -- Secret OCID to retrieve
          -- vault_id => v_config.get_string('iot_vault_ocid'), -- Not used in this call
          region => v_config.get_string('tenancy_region'), -- Region where the secret is stored
          credential_name => v_config.get_string('credentials') -- Credential name for authentication
      ); -- Get the secret bundle

      -- Decode the base64 secret content from the API response and convert it to a string
      v_return := utl_raw.cast_to_varchar2(
                    utl_encode.base64_decode(
                      utl_raw.cast_to_raw(
                        treat(
                          treat(
                            results.response_body as dbms_cloud_oci_secrets_secret_bundle_t
                          ).secret_bundle_content as dbms_cloud_oci_secrets_base64_secret_bundle_content_details_t
                        ).content -- Extract the secret content
                      )
                    )
                  ); -- Decode the base64 secret content

      -- Return the decoded secret string
      return v_return; -- Return the decoded secret

    exception
      when others then
          -- Log any error that occurs during execution
          return 'Error: ' || sqlerrm; -- Log the error message

  end;

  -- Function to create a new secret in OCI Vault
  function create_secret(
    p_secret_name varchar2,
    secret_content varchar2 default null,
    secret_char number default 24)
    return clob
    is
      v_config json_object_t; -- Config params from APEX
      secret_text varchar2(100); -- Plain text secret to be stored
      secret_content_details dbms_cloud_oci_vault_base64_secret_content_details_t; -- Secret data in base64
      secret_details dbms_cloud_oci_vault_create_secret_details_t; -- All secret params for OCI
      results dbms_cloud_oci_vt_vaults_create_secret_response_t; -- API response
      content_exception exception; -- Custom exception placeholder
      v_return json_object_t; -- JSON output for status/OCID
    begin

      -- Use the provided secret content or generate a random string if not supplied
      if secret_content is not null then
        secret_text := secret_content; -- Use the provided secret content
      else
        -- Generate a random string of the specified length (default 24 characters)
        secret_text := dbms_random.string( opt => 'a', len => nvl( secret_char, 24 ) ); -- Generate a random string
      end if;

      -- Fetch the OCI configuration from the app-owned table
      v_config := iot_apex.iot_config; -- Get the OCI configuration

      -- Prepare the secret content for OCI by base64 encoding it
      secret_content_details := dbms_cloud_oci_vault_base64_secret_content_details_t(); -- Create a new secret content details object
      secret_content_details.content_type := 'BASE64'; -- Specify the content type as base64
      secret_content_details.stage := 'CURRENT'; -- Set the stage to CURRENT
      -- Base64 encode the secret text and store it in the content attribute
      secret_content_details.content := utl_raw.cast_to_varchar2(
                                          utl_encode.base64_encode(
                                            utl_raw.cast_to_raw(secret_text)
                                          )
                                        ); -- Base64 encode the secret text

      -- Set all required secret data for the OCI API call
      secret_details := dbms_cloud_oci_vault_create_secret_details_t(); -- Create a new secret details object
      secret_details.compartment_id := v_config.get_string('iot_compartment'); -- Compartment ID where the secret will be stored
      secret_details.description := 'This is a secret generated from the PL/SQL SDK'; -- Description of the secret
      secret_details.key_id := v_config.get_string('vault_master_key'); -- KMS master key ID
      secret_details.secret_content := secret_content_details; -- Secret content details
      secret_details.secret_name := p_secret_name; -- Name of the secret
      secret_details.vault_id := v_config.get_string('iot_vault_ocid'); -- Vault ID where the secret will be stored

      -- Call the OCI API to create the secret
      results := dbms_cloud_oci_vt_vaults.create_secret (
                      create_secret_details => secret_details, -- Secret details for creation
                      opc_request_id  => null, -- Optional request ID
                      opc_retry_token  => null, -- Optional retry token
                      region => v_config.get_string('tenancy_region'), -- Region where the secret will be stored
                      endpoint  => null, -- Optional endpoint
                      credential_name => v_config.get_string('credentials') -- Credential name for authentication
                      ); -- Create the secret

      -- Package the result for output as a JSON clob
      v_return := json_object_t(); -- Create a new JSON object
      v_return.put('status',results.status_code); -- Status code of the API response
      v_return.put('secret_ocid',treat(results.response_body as dbms_cloud_oci_vault_secret_t).id); -- OCID of the created secret

      -- Return the result as a JSON clob
      return v_return.to_clob; -- Return the result as a JSON clob

    exception
      when content_exception then
        -- Log any error that occurs during execution
        return 'Error: ' || sqlerrm; -- Log the error message
      when others then
        -- Log any other error that occurs during execution
        return 'Error: ' || sqlerrm; -- Log the error message

  end;

  -- Function to schedule deletion of a secret
  function delete_secret( p_secret_name varchar2)
    return clob
    is
      v_config json_object_t; -- Config
      delete_schedue dbms_cloud_oci_vault_schedule_secret_deletion_details_t; -- Deletion details incl. time
      delete_timestamp timestamp; -- Scheduled deletion time
      results dbms_cloud_oci_vt_vaults_schedule_secret_deletion_response_t; -- API response
      v_return json_object_t; -- Output
    begin

      -- Fetch the OCI configuration from the app-owned table
      v_config := iot_apex.iot_config; -- Get the OCI configuration

      -- Calculate the scheduled deletion time (1 week from now)
      delete_timestamp := systimestamp + interval '7' day; -- Schedule deletion 1 week from now

      -- Prepare the deletion request with the specified time
      delete_schedue := dbms_cloud_oci_vault_schedule_secret_deletion_details_t (
          time_of_deletion => delete_timestamp -- Scheduled deletion time
        ); -- Create a new deletion details object

      -- Call the OCI API to schedule the deletion of the secret (needs OCID of secret)
      results := dbms_cloud_oci_vt_vaults.schedule_secret_deletion (
          secret_id => json_object_t.parse(iot_oci.get_secret(p_secret_name)).get_string('secret_ocid'), -- OCID of the secret to be deleted
          schedule_secret_deletion_details => delete_schedue, -- Deletion details
          if_match => null, -- Optional if-match header
          opc_request_id => null, -- Optional request ID
          region => v_config.get_string('tenancy_region'), -- Region where the secret is stored
          endpoint => null, -- Optional endpoint
          credential_name => v_config.get_string('credentials') -- Credential name for authentication
        ); -- Schedule the deletion

      -- Package the result for output as a JSON clob
      v_return := json_object_t(); -- Create a new JSON object
      v_return.put('status',results.status_code); -- Status code of the API response

      -- Return the result as a JSON clob
      return v_return.to_clob; -- Return the result as a JSON clob

    exception
      when others then
          -- Log any error that occurs during execution
          return 'Error: ' || sqlerrm; -- Log the error message
  end;

  -- Function to list all secrets in OCI Vault
  function get_all_secrets
    return clob
    is
      v_config json_object_t; -- Config
      v_return json_object_t; -- Return value
      json_obj json_object_t; -- Element in secrets array
      json_arr json_array_t; -- Array of secrets info

      get_response dbms_cloud_oci_vt_vaults_list_secrets_response_t; -- API response
      get_response_body dbms_cloud_oci_vault_secret_summary_tbl; -- Listing table from response
    begin

      -- Fetch the OCI configuration from the app-owned table
      v_config := iot_apex.iot_config; -- Get the OCI configuration

      -- Get the list of secrets for the given compartment
      get_response := dbms_cloud_oci_vt_vaults.list_secrets (
                              compartment_id => v_config.get_string('iot_compartment'), -- Compartment ID
                              region => v_config.get_string('tenancy_region'), -- Region
                              credential_name => v_config.get_string('credentials') -- Credential name
                              ); -- Get the list of secrets

      -- Get the response body
      get_response_body := get_response.response_body; -- Get the response body

      -- Create a new JSON object to store the result
      v_return := json_object_t(); -- Create a new JSON object
      v_return.put('status', get_response.status_code); -- Status code of the API response

      -- Create a new JSON array to store the secrets info
      json_arr := json_array_t(); -- Create a new JSON array
      for i in 1 .. get_response_body.count loop

          -- Build JSON per secret
          json_obj := json_object_t(); -- Create a new JSON object
          json_obj.put('name',get_response_body(i).secret_name); -- Secret name
          json_obj.put('ocid',get_response_body(i).id); -- Secret OCID
          json_obj.put('description',get_response_body(i).description); -- Secret description
          json_obj.put('lifecycle_state',get_response_body(i).lifecycle_state); -- Secret lifecycle state
          json_obj.put('master_key_id',get_response_body(i).key_id); -- Master key ID
          json_arr.append(json_obj); -- Append the JSON object to the array

      end loop;

      -- Add the secrets array to the result JSON object
      v_return.put('secrets',json_arr); -- Add the secrets array to the result

      -- Return the result as a JSON clob
      return v_return.to_clob; -- Return the result as a JSON clob

    exception
    when others then
        -- Log any error that occurs during execution
        return 'Error: ' || sqlerrm; -- Log the error message
  end;

  -- Function to list all certificate authorities
  function get_all_cas
    return clob
    is
      v_config json_object_t; -- Config

      get_response dbms_cloud_oci_certm_certificates_management_list_certificate_authorities_response_t; -- API response
      get_response_body dbms_cloud_oci_certificates_management_certificate_authority_collection_t; -- Response body
      response_items dbms_cloud_oci_certificates_management_certificate_authority_summary_tbl; -- Items in response
      v_return json_object_t; -- Return value
      json_obj json_object_t; -- Element in CAs array
      json_arr json_array_t; -- Array of CAs info
    begin

      -- Fetch the OCI configuration from the app-owned table
      v_config := iot_apex.iot_config; -- Get the OCI configuration

      -- Get the list of certificate authorities
      get_response := dbms_cloud_oci_certm_certificates_management.list_certificate_authorities (
                              compartment_id => v_config.get_string('iot_compartment'), -- Compartment ID
                              region => v_config.get_string('tenancy_region'), -- Region
                              credential_name => v_config.get_string('credentials') -- Credential name
                              ); -- Get the list of CAs

      -- Get the response body and items
      get_response_body := get_response.response_body; -- Get the response body
      response_items := get_response_body.items; -- Get the items in the response

      -- Create a new JSON object to store the result
      v_return := json_object_t(); -- Create a new JSON object
      v_return.put('status', get_response.status_code); -- Status code of the API response
      json_arr := json_array_t(); -- Create a new JSON array

      -- Build JSON array output
      for i in 1 .. response_items.count loop
        json_obj := json_object_t(); -- Create a new JSON object
        json_obj.put('name',response_items(i).name); -- CA name
        json_obj.put('ocid',response_items(i).id); -- CA OCID
        json_obj.put('lifecycle_state',response_items(i).lifecycle_state); -- CA lifecycle state
        json_obj.put('compartment_id',response_items(i).compartment_id); -- Compartment ID
        json_arr.append(json_obj); -- Append the JSON object to the array
      end loop;

      -- Add the CAs array to the result JSON object
      v_return.put('cas',json_arr); -- Add the CAs array to the result

      -- Return the result as a JSON clob
      return v_return.to_clob; -- Return the result as a JSON clob

    exception
    when others then
        -- Log any error that occurs during execution
        return 'Error: ' || sqlerrm; -- Log the error message
  end;

  -- Function to list all certificates in the vault
  function get_all_certs
    return clob
    is
      v_config json_object_t; -- Config
      get_response dbms_cloud_oci_certm_certificates_management_list_certificates_response_t; -- API response
      get_response_body dbms_cloud_oci_certificates_management_certificate_collection_t; -- Response body
      response_items dbms_cloud_oci_certificates_management_certificate_summary_tbl; -- Items in response
      v_return json_object_t; -- Return value
      v_obj json_object_t; -- Element in certs array
      v_arr json_array_t; -- Array of certs info
    begin

      -- Fetch the OCI configuration from the app-owned table
      v_config := iot_apex.iot_config; -- Get the OCI configuration

      -- Request OCI for all certificates
      get_response := dbms_cloud_oci_certm_certificates_management.list_certificates (
                                compartment_id => v_config.get_string('iot_compartment'), -- Compartment ID
                                region => v_config.get_string('tenancy_region'), -- Region
                                credential_name => v_config.get_string('credentials') -- Credential name
                                ); -- Get the list of certificates

      -- Get the response body and items
      get_response_body := get_response.response_body; -- Get the response body
      response_items := get_response_body.items; -- Get the items in the response

      -- Create a new JSON object to store the result
      v_return := json_object_t(); -- Create a new JSON object
      v_return.put('status', get_response.status_code); -- Status code of the API response

      -- Create a new JSON array to store the certificates info
      v_arr := json_array_t(); -- Create a new JSON array

      -- Build JSON array output
      for i in 1 .. response_items.count loop
        v_obj := json_object_t(); -- Create a new JSON object
        v_obj.put('name',response_items(i).name); -- Certificate name
        v_obj.put('ocid',response_items(i).id); -- Certificate OCID
        v_obj.put('ca_ocid',response_items(i).issuer_certificate_authority_id); -- CA OCID
        v_obj.put('lifecycle_state',response_items(i).lifecycle_state); -- Certificate lifecycle state
        v_obj.put('compartment_id',response_items(i).compartment_id); -- Compartment ID
        v_arr.append(v_obj); -- Append the JSON object to the array
      end loop;

      -- Add the certificates array to the result JSON object
      v_return.put('certs',v_arr); -- Add the certificates array to the result

      -- Return the result as a JSON clob
      return v_return.to_clob; -- Return the result as a JSON clob

    exception
      when others then
        -- Log any error that occurs during execution
        dbms_output.put_line('Error: ' || sqlerrm); -- Log the error message
  end;

  -- Function to create a new certificate issued by given certificate authority
  function create_cert(p_cert_name varchar2, p_cert_auth_ocid varchar2)
    return clob
    is
      v_config json_object_t; -- Config
      cert_config_subject dbms_cloud_oci_certificates_management_certificate_subject_t; -- X.509 subject
      cert_config dbms_cloud_oci_certificates_management_create_certificate_details_t; -- High-level cert config
      results dbms_cloud_oci_certm_certificates_management_create_certificate_response_t; -- API response
      certificate_config_details dbms_cloud_oci_certificates_management_create_certificate_config_details_t; -- Certificate config details
      certificate_config_details_internal_ca dbms_cloud_oci_certificates_management_create_certificate_issued_by_internal_ca_config_details_t; -- Certificate config details for internal CA
      content_exception exception; -- Custom exception placeholder
      v_return json_object_t; -- JSON output for status/OCID
    begin

      -- Fetch the OCI configuration from the app-owned table
      v_config := iot_apex.iot_config; -- Get the OCI configuration

      -- Initialize the certificate subject (CN etc.)
      cert_config_subject := dbms_cloud_oci_certificates_management_certificate_subject_t(); -- Create a new certificate subject
      cert_config_subject.common_name := p_cert_name; -- Set the common name

      -- Specify internal CA as issuer and configuration for new cert
      certificate_config_details_internal_ca := dbms_cloud_oci_certificates_management_create_certificate_issued_by_internal_ca_config_details_t(); -- Create a new certificate config details object for internal CA
      certificate_config_details_internal_ca.version_name := null; -- Version name (not used)
      certificate_config_details_internal_ca.certificate_profile_type := 'TLS_SERVER_OR_CLIENT'; -- Certificate profile type
      certificate_config_details_internal_ca.issuer_certificate_authority_id := p_cert_auth_ocid; -- Issuer CA OCID
      certificate_config_details_internal_ca.subject := cert_config_subject; -- Certificate subject

      -- Set the certificate config details
      certificate_config_details := certificate_config_details_internal_ca; -- Set the certificate config details

      -- Fill overall certificate details
      cert_config := dbms_cloud_oci_certificates_management_create_certificate_details_t(); -- Create a new certificate details object
      cert_config.name := p_cert_name; -- Certificate name
      cert_config.compartment_id := v_config.get_string('iot_compartment'); -- Compartment ID
      cert_config.certificate_config := certificate_config_details; -- Certificate config details

      -- Call the OCI API to create the certificate
      results := dbms_cloud_oci_certm_certificates_management.create_certificate(
          create_certificate_details => cert_config, -- Certificate details for creation
          region => v_config.get_string('tenancy_region'), -- Region
          credential_name => v_config.get_string('credentials') -- Credential name
      ); -- Create the certificate

      -- Package the result for output as a JSON clob
      v_return := json_object_t(); -- Create a new JSON object
      v_return.put('status',results.status_code); -- Status code of the API response
      v_return.put('cert_ocid',treat(results.response_body as dbms_cloud_oci_certificates_management_certificate_t).id); -- OCID of the created certificate

      -- Return the result as a JSON clob
      return v_return.to_clob; -- Return the result as a JSON clob

    exception
      when others then
        -- Return an error message if an exception occurs
        return 'Error: executing iot_oci.create_cert: ' || sqlerrm; -- Return the error message
  end;

  -- Function to schedule certificate deletion
  function delete_cert( p_cert_ocid varchar2 )
    return clob
    is
    v_config json_object_t; -- Config
    v_return json_object_t; -- JSON output for status
    cert_delete_time dbms_cloud_oci_certificates_management_schedule_certificate_deletion_details_t; -- Deletion details
    results dbms_cloud_oci_certm_certificates_management_schedule_certificate_deletion_response_t; -- API response
    begin

      -- Fetch the OCI configuration from the app-owned table
      v_config := iot_apex.iot_config; -- Get the OCI configuration

      -- Create a new deletion details object
      cert_delete_time := dbms_cloud_oci_certificates_management_schedule_certificate_deletion_details_t(); -- Create a new deletion details object
     -- cert_delete_time.time_of_deletion := (systimestamp + interval '5'); -- Scheduled deletion time (not set)

      -- Call the OCI API to schedule the deletion of the certificate
      results := dbms_cloud_oci_certm_certificates_management.schedule_certificate_deletion (
        certificate_id => p_cert_ocid, -- Certificate OCID to be deleted
        schedule_certificate_deletion_details => cert_delete_time, -- Deletion details
        region => v_config.get_string('tenancy_region'), -- Region
        credential_name => v_config.get_string('credentials') -- Credential name
      ); -- Schedule the deletion

      -- Package the result for output as a JSON clob
      v_return := json_object_t(); -- Create a new JSON object
      v_return.put('status',results.status_code); -- Status code of the API response

      -- Return the result as a JSON clob
      return v_return.to_clob; -- Return the result as a JSON clob

    exception
      when others then
          -- Log any error that occurs during execution
          return 'Error: executing iot_oci.delete_cert: ' || sqlerrm; -- Log the error message

  end;

  -- Function to fetch PEM/chain/private key for one cert by OCID
  function get_cert( p_cert_ocid varchar2 )
    return clob
    is
    v_config json_object_t; -- Config
    v_return json_object_t; -- JSON output for status/PEM/chain/private
    results dbms_cloud_oci_cert_certificates_get_certificate_bundle_response_t; -- API response
    get_cert_results dbms_cloud_oci_certm_certificates_management_get_certificate_response_t;
    cert_cn varchar2(100); -- store common name of certificate
    begin

      -- Fetch the OCI configuration from the app-owned table
      v_config := iot_apex.iot_config; -- Get the OCI configuration

      get_cert_results := dbms_cloud_oci_certm_certificates_management.get_certificate(
        certificate_id => p_cert_ocid, -- Certificate OCID 
        region => v_config.get_string('tenancy_region'), -- Region 
        credential_name => v_config.get_string('credentials') -- Credential name
      );

      -- Call the OCI API to get the certificate bundle
      results := dbms_cloud_oci_cert_certificates.get_certificate_bundle(
        certificate_id => p_cert_ocid, -- Certificate OCID
        certificate_bundle_type => 'CERTIFICATE_CONTENT_WITH_PRIVATE_KEY', -- Certificate bundle type
        region => v_config.get_string('tenancy_region'), -- Region
        credential_name => v_config.get_string('credentials') -- Credential name
      ); -- Get the certificate bundle

      if get_cert_results.status_code = '200' then -- check for success of get_certificate
        cert_cn := treat(
                      treat(
                        get_cert_results.response_body as dbms_cloud_oci_certificates_management_certificate_t
                      ).subject as dbms_cloud_oci_certificates_management_certificate_subject_t
                    ).common_name;
      end if;

      -- Package the result for output as a JSON clob
      v_return := json_object_t(); -- Create a new JSON object
      v_return.put('status',results.status_code); -- Status code of the API response
      v_return.put('common_name',cert_cn); -- common name of the cert 
      v_return.put('cert_pem',
                    treat(
                      results.response_body as dbms_cloud_oci_certificates_certificate_bundle_t
                    ).certificate_pem); -- Certificate PEM

      v_return.put('cert_chain_pem',
                    treat(
                      results.response_body as dbms_cloud_oci_certificates_certificate_bundle_t
                    ).cert_chain_pem); -- Certificate chain PEM

      v_return.put('private_pem',
                    treat(
                      results.response_body as dbms_cloud_oci_certificates_certificate_bundle_with_private_key_t
                    ).private_key_pem ); -- Private key PEM

      -- Return the result as a JSON clob
      return v_return.to_clob; -- Return the result as a JSON clob

    exception
      when others then
          -- Return an error message if an exception occurs
          return 'Error: executing IOT_OCI.GET_CERT: ' || sqlerrm; -- Return the error message
  end;

end iot_oci;
/




--create auth_view which list all certs and secrets accessable to IoT and there lifecycle state
create or replace view auth_view as
  (
    -- Select columns for unified auth objects (certs and secrets)
    select  auth_type,ocid,auth_name,lifecycle_state
    from    (
              -- First subquery: All certificates from OCI
              select  'cert' as auth_type,       -- Mark type as 'cert'
                      ocid,                      -- Certificate OCID
                      auth_name,                 -- Certificate name
                      lifecycle_state            -- Certificate lifecycle state
              from    json_table(
                        iot_oci.get_all_certs,   -- Call to function returning certs JSON
                        '$.certs[*]'             -- For each certificate item in the array
                        columns (
                            ocid varchar2(255) path '$.ocid',                  -- Extract certificate OCID
                            auth_name varchar2(100) path '$.name',              -- Extract certificate name
                            lifecycle_state varchar2(255) path '$.lifecycle_state' -- Extract certificate state
                        )
                      ) jt
              union all
              -- Second subquery: All secrets from OCI
              select  'secret' as auth_type,     -- Mark type as 'secret'
                      ocid,                      -- Secret OCID
                      auth_name,                 -- Secret name
                      lifecycle_state            -- Secret lifecycle state
              from    json_table(
                        iot_oci.get_all_secrets, -- Call to function returning secrets JSON
                        '$.secrets[*]'           -- For each secret item in the array
                        columns (
                            ocid varchar2(255) path '$.ocid',                  -- Extract secret OCID
                            auth_name varchar2(100) path '$.name',              -- Extract secret name
                            lifecycle_state varchar2(255) path '$.lifecycle_state' -- Extract secret state
                        )
                      ) jt
            )
);


--create view that shows detailed information about the certs available to IoT including name, location, status, and pem
create or replace view iot_certs as
  select  a.name,
          a.ocid,
          a.ca_ocid,
          a.lifecycle_state,
          a.compartment_id,
          iot_oci.get_cert( a.ocid )  pem
   from    json_table(
                      iot_oci.get_all_certs,
                      '$.certs[*]' columns (
                          name varchar path '$.name',
                          ocid varchar path '$.ocid',
                          ca_ocid varchar path '$.ca_ocid',
                          lifecycle_state varchar path '$.lifecycle_state',
                          compartment_id varchar path '$.compartment_id'
                      )
) a;


--create view for showing detailed information about passwords stored in vault including unencrypted password
create or replace view iot_passwords as
  select  a.name,
          a.ocid,
          a.description,
          a.lifecycle_state,
          a.master_key_id,
          iot_oci.get_secret( a.ocid )  as password
   from    json_table(
                      iot_oci.get_all_secrets,
                      '$.secrets[*]' columns (
                          name varchar path '$.name',
                          ocid varchar path '$.ocid',
                          description varchar path '$.description',
                          lifecycle_state varchar path '$.lifecycle_state',
                          master_key_id varchar path '$.master_key_id'
                      )
) a;