--
-- Seed script for the SQL archive-domain sample.
--
-- Copyright (c) 2026 Oracle and/or its affiliates.
-- Licensed under the Universal Permissive License v 1.0 as shown at
-- https://oss.oracle.com/licenses/upl.
--
-- DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
--

whenever sqlerror exit sql.sqlcode

set serveroutput on size unlimited
set feedback off

declare
  l_config_json clob := json_serialize(
    json_object(
      'domain_id' value 'ocid1.iotdomain.oc1..example',
      'domain_short_name' value 'iot-domain',
      'bucket_name' value 'sample-bucket',
      'namespace' value 'sample-namespace',
      'prefix' value 'archive',
      'manifest_prefix' value 'archive/_manifests',
      'checkpoint_object' value 'archive/_state/checkpoint.json',
      'dbms_cloud_credential_name' value 'CRED_OBJ',
      'retention_days' value json_object(
        'raw' value 16,
        'historized' value 30,
        'rejected' value 16
      ),
      'bootstrap_lookback_days' value 7
    )
    returning clob pretty
  );
begin
  merge into archive_domain_config tgt
  using (select 'default' as config_name from dual) src
  on (tgt.config_name = src.config_name)
  when matched then
    update set config_json = l_config_json
  when not matched then
    insert (config_name, config_json)
    values (src.config_name, l_config_json);

  dbms_output.put_line('seeded default config');

  declare
    l_result clob;
  begin
    select config_json
      into l_result
      from archive_domain_config
     where config_name = 'default';

    dbms_output.put_line(l_result);
  end;
end;
/
