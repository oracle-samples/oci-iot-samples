--
-- Install the supporting objects for the SQL archive-domain sample.
--
-- Copyright (c) 2026 Oracle and/or its affiliates.
-- Licensed under the Universal Permissive License v 1.0 as shown at
-- https://oss.oracle.com/licenses/upl.
--
-- DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
--

whenever sqlerror exit sql.sqlcode

prompt Creating archive_domain_config table
@@archive_domain_tables.sql

prompt Creating archive_domain_content_utils
@@archive_domain_content_utils.sql

prompt Creating archive_domain_pkg
@@archive_domain_pkg.sql
