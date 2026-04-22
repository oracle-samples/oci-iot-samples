--
-- Content conversion utilities for the SQL archive-domain sample.
--
-- Copyright (c) 2026 Oracle and/or its affiliates.
-- Licensed under the Universal Permissive License v 1.0 as shown at
-- https://oss.oracle.com/licenses/upl.
--
-- DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
--

create or replace package archive_domain_content_utils authid definer as
  function blob_to_json(
    p_blob         in blob,
    p_content_type in varchar2
  ) return json;

  function clob_to_json(
    p_clob         in clob,
    p_content_type in varchar2,
    p_data_format  in varchar2 default null
  ) return json;
end archive_domain_content_utils;
/

show errors

declare
  l_error_count number;
begin
  select count(*)
    into l_error_count
    from user_errors
   where name = 'ARCHIVE_DOMAIN_CONTENT_UTILS'
     and type = 'PACKAGE';

  if l_error_count > 0 then
    raise_application_error(-20030, 'archive_domain_content_utils spec compilation failed');
  end if;
end;
/

create or replace package body archive_domain_content_utils as
  function normalize_content_type(
    p_content_type in varchar2
  ) return varchar2
  is
  begin
    if p_content_type is null then
      return null;
    end if;

    return lower(trim(regexp_substr(p_content_type, '^[^;]+')));
  end normalize_content_type;

  function blob_to_base64(
    p_blob in blob
  ) return clob
  is
    l_chunk_size constant pls_integer := trunc(2000 / 3) * 3;
    l_blob_length pls_integer;
    l_clob clob;
    l_blob_offset pls_integer := 1;
    l_read_length pls_integer;
    l_raw raw(2000);
    l_base64 varchar2(32767);
  begin
    if p_blob is null then
      return null;
    end if;

    l_blob_length := dbms_lob.getlength(p_blob);
    dbms_lob.createtemporary(l_clob, true, dbms_lob.session);

    while l_blob_offset <= l_blob_length loop
      l_read_length := least(l_chunk_size, l_blob_length - l_blob_offset + 1);
      l_raw := dbms_lob.substr(p_blob, l_read_length, l_blob_offset);

      exit when l_raw is null or l_read_length = 0;

      l_base64 := replace(
                    replace(
                      utl_raw.cast_to_varchar2(utl_encode.base64_encode(l_raw)),
                      chr(10),
                      ''
                    ),
                    chr(13),
                    ''
                  );

      dbms_lob.writeappend(l_clob, length(l_base64), l_base64);
      l_blob_offset := l_blob_offset + l_read_length;
    end loop;

    return l_clob;
  end blob_to_base64;

  function blob_to_clob_utf8(
    p_blob in blob
  ) return clob
  is
    l_result clob;
    l_dest_offset integer := 1;
    l_src_offset integer := 1;
    l_lang_context integer := dbms_lob.default_lang_ctx;
    l_warning integer;
  begin
    if p_blob is null then
      return null;
    end if;

    dbms_lob.createtemporary(l_result, true, dbms_lob.session);
    dbms_lob.converttoclob(
      dest_lob     => l_result,
      src_blob     => p_blob,
      amount       => dbms_lob.lobmaxsize,
      dest_offset  => l_dest_offset,
      src_offset   => l_src_offset,
      blob_csid    => nls_charset_id('AL32UTF8'),
      lang_context => l_lang_context,
      warning      => l_warning
    );
    return l_result;
  end blob_to_clob_utf8;

  function escape_json_string(
    p_clob in clob
  ) return clob
  is
    l_clob_length pls_integer;
    l_index pls_integer := 1;
    l_chr varchar2(4);
    l_code pls_integer;
    l_escaped_clob clob;
  begin
    if p_clob is null then
      return null;
    end if;

    l_clob_length := dbms_lob.getlength(p_clob);
    dbms_lob.createtemporary(l_escaped_clob, true, dbms_lob.session);

    while l_index <= l_clob_length loop
      l_chr := dbms_lob.substr(p_clob, 1, l_index);
      l_code := ascii(l_chr);

      case l_chr
        when '"' then
          dbms_lob.writeappend(l_escaped_clob, 2, '\"');
        when chr(92) then
          dbms_lob.writeappend(l_escaped_clob, 2, '\\');
        when chr(8) then
          dbms_lob.writeappend(l_escaped_clob, 2, '\b');
        when chr(9) then
          dbms_lob.writeappend(l_escaped_clob, 2, '\t');
        when chr(10) then
          dbms_lob.writeappend(l_escaped_clob, 2, '\n');
        when chr(12) then
          dbms_lob.writeappend(l_escaped_clob, 2, '\f');
        when chr(13) then
          dbms_lob.writeappend(l_escaped_clob, 2, '\r');
        else
          if l_code < 32 then
            dbms_lob.writeappend(
              l_escaped_clob,
              6,
              '\u' || to_char(l_code, 'FM000X')
            );
          else
            dbms_lob.writeappend(l_escaped_clob, length(l_chr), l_chr);
          end if;
      end case;

      l_index := l_index + 1;
    end loop;

    return l_escaped_clob;
  end escape_json_string;

  function clob_to_json(
    p_clob         in clob,
    p_content_type in varchar2,
    p_data_format  in varchar2 default null
  ) return json
  is
    l_content_type varchar2(4000);
    l_data_format varchar2(4000);
  begin
    if p_clob is null then
      return null;
    end if;

    l_content_type := normalize_content_type(p_content_type);
    l_data_format := lower(trim(p_data_format));

    if (l_content_type is null and l_data_format is null)
        or instr(nvl(l_content_type, ''), 'json') > 0
        or l_data_format = 'json' then
      begin
        return json(p_clob);
      exception
        when others then
          return json('"' || escape_json_string(p_clob) || '"');
      end;
    end if;

    return json('"' || escape_json_string(p_clob) || '"');
  end clob_to_json;

  function blob_to_json(
    p_blob         in blob,
    p_content_type in varchar2
  ) return json
  is
    l_content_type varchar2(4000);
    l_clob clob;
  begin
    if p_blob is null then
      return null;
    end if;

    l_content_type := normalize_content_type(p_content_type);

    if l_content_type like 'text/%' then
      l_clob := blob_to_clob_utf8(p_blob);
      return json('"' || escape_json_string(l_clob) || '"');
    end if;

    if l_content_type is null or instr(l_content_type, 'json') > 0 then
      begin
        l_clob := blob_to_clob_utf8(p_blob);
        return json(l_clob);
      exception
        when others then
          return json('"' || blob_to_base64(p_blob) || '"');
      end;
    end if;

    return json('"' || blob_to_base64(p_blob) || '"');
  end blob_to_json;
end archive_domain_content_utils;
/

show errors

declare
  l_error_count number;
begin
  select count(*)
    into l_error_count
    from user_errors
   where name = 'ARCHIVE_DOMAIN_CONTENT_UTILS'
     and type = 'PACKAGE BODY';

  if l_error_count > 0 then
    raise_application_error(-20031, 'archive_domain_content_utils body compilation failed');
  end if;
end;
/
