# Documentation for Packages Used by IoT Explorer SQL Script

## Overview

The iot_explorer.sql script creates the following packages, which are
utilized by the IoT Explorer application to interact with OCI components.

## IOT_APEX Package

The `IOT_APEX` package provides functions for interacting with the IoT
Platform API.

1. `IOT_APEX.compact_number(n number)`
   - Description: Converts a number into a shortened string representation.
   - Parameters:
     - `n` - the number to be converted.
   - Return Value: A string representing the number in a shortened format.
2. `IOT_APEX.clob_to_blob(p_clob clob, p_charset_id number default null)`
   - Description: Converts a CLOB to a BLOB using a specified or default
     charset.
   - Parameters:
     - `p_clob` - the CLOB to be converted.
     - `p_charset_id` - the charset ID (optional, defaults to
       `dbms_lob.default_csid`).
   - Return Value: The BLOB representation of the input CLOB.
3. `IOT_APEX.cred_chk(p_cred_name varchar2, p_region varchar2)`
   - Description: Checks a named Oracle Cloud credential in a given region.
   - Parameters:
     - `p_cred_name` - the name of the credential.
     - `p_region` - the region to check.
   - Return Value: 'GOOD', 'BAD', or an error message.
4. `IOT_APEX.iot_config()`
   - Description: Loads IoT configuration JSON from the database.
   - Parameters: None.
   - Return Value: A JSON object representing the IoT configuration.
5. `IOT_APEX.is_json(p_json clob)`
   - Description: Determines if a provided CLOB is valid JSON.
   - Parameters:
     - `p_json` - the CLOB to be checked.
   - Return Value: 'true' if valid, 'false' otherwise.

### IOT_INFO Package

The `IOT_INFO` package retrieves various types of IoT-related data.

1. `IOT_INFO.get_dom_grp(p_compartment_id VARCHAR2, p_cred_name VARCHAR2,
   p_region VARCHAR2)`
   - Description: Retrieves IoT domain groups.
   - Parameters:
     - `p_compartment_id` - the compartment ID.
     - `p_cred_name` - the credential name.
     - `p_region` - the region.
   - Return Value: A pipelined table of `dom_grp_rec` records.
2. `IOT_INFO.get_dom_grp()`
   - Description: Retrieves all IoT domain groups.
   - Parameters: None.
   - Return Value: A pipelined table of `dom_grp_rec` records.
3. `IOT_INFO.get_dom_grp_conn(p_dom_grp_id VARCHAR2, p_cred_name VARCHAR2,
   p_region VARCHAR2)`
   - Description: Retrieves IoT domain group connections.
   - Parameters:
     - `p_dom_grp_id` - the domain group ID.
     - `p_cred_name` - the credential name.
     - `p_region` - the region.
   - Return Value: A pipelined table of `dom_grp_conn_rec` records.
4. `IOT_INFO.get_dom_conn(p_dom_id VARCHAR2, p_cred_name VARCHAR2,
   p_region VARCHAR2)`
   - Description: Retrieves IoT domain connections.
   - Parameters:
     - `p_dom_id` - the domain ID.
     - `p_cred_name` - the credential name.
     - `p_region` - the region.
   - Return Value: A pipelined table of `dom_conn_rec` records.
5. `IOT_INFO.get_dom(p_compartment_id VARCHAR2, p_cred_name VARCHAR2,
   p_region VARCHAR2)`
   - Description: Retrieves IoT domains.
   - Parameters:
     - `p_compartment_id` - the compartment ID.
     - `p_cred_name` - the credential name.
     - `p_region` - the region.
   - Return Value: A pipelined table of `dom_rec` records.

### IOT_OBJECTS Package

The `IOT_OBJECTS` package provides functions for interacting with the IoT
Platform objects.

1. `IOT_OBJECTS.instance_api_body(p_type varchar2, p_auth_id varchar2,
   p_display_name varchar2 default null, p_description varchar2 default null,
   p_external_key varchar2 default null, p_dt_adapt_ocid varchar2 default null,
   p_freeform_tags varchar2 default null)`
   - Description: Constructs a JSON CLOB for "instance" API requests.
   - Parameters:
     - `p_type` - the type of instance (structured or unstructured).
     - `p_auth_id` - the authentication ID.
     - `p_display_name` - the display name (optional).
     - `p_description` - the description (optional).
     - `p_external_key` - the external key (optional).
     - `p_dt_adapt_ocid` - the digital twin adapter OCID (optional).
     - `p_freeform_tags` - the freeform tags (optional).
   - Return Value: A JSON CLOB representing the instance API body.
2. `IOT_OBJECTS.instance_cli(p_type varchar2, p_auth_id varchar2,
   p_display_name varchar2 default null, p_description varchar2 default null,
   p_external_key varchar2 default null, p_dt_adapt_ocid varchar2 default null,
   p_freeform_tags varchar2 default null)`
   - Description: Builds a CLI command to create a digital twin instance.
   - Parameters:
     - `p_type` - the type of instance (structured or unstructured).
     - `p_auth_id` - the authentication ID.
     - `p_display_name` - the display name (optional).
     - `p_description` - the description (optional).
     - `p_external_key` - the external key (optional).
     - `p_dt_adapt_ocid` - the digital twin adapter OCID (optional).
     - `p_freeform_tags` - the freeform tags (optional).
   - Return Value: A CLOB representing the CLI command.
3. `IOT_OBJECTS.create_instance(p_body clob)`
   - Description: Calls the REST API to create a digital twin instance.
   - Parameters:
     - `p_body` - the JSON CLOB body for the instance creation request.
   - Return Value: The response from the API as a CLOB.
4. `IOT_OBJECTS.model_api_body(p_description varchar2 default null,
   p_display_name varchar2, p_context varchar2, p_contents clob,
   p_freeform_tags clob default null, p_dtdl_id varchar2 default null)`
   - Description: Constructs the API JSON body to create a digital twin model.
   - Parameters:
     - `p_description` - the description (optional).
     - `p_display_name` - the display name.
     - `p_context` - the context.
     - `p_contents` - the contents.
     - `p_freeform_tags` - the freeform tags (optional).
     - `p_dtdl_id` - the DTDL ID (optional).
   - Return Value: A JSON CLOB representing the model API body.
5. `IOT_OBJECTS.model_cli(p_description varchar2 default null,
    p_display_name varchar2, p_context varchar2, p_contents clob,
    p_freeform_tags clob default null, p_dtdl_id varchar2 default null)`
    - Description: Builds a CLI command to create a digital twin model.
    - Parameters:
      - `p_description` - the description (optional).
      - `p_display_name` - the display name.
      - `p_context` - the context.
      - `p_contents` - the contents.
      - `p_freeform_tags` - the freeform tags (optional).
      - `p_dtdl_id` - the DTDL ID (optional).
    - Return Value: A CLOB representing the CLI command.
6. `IOT_OBJECTS.create_model(p_body clob)`
    - Description: Calls the REST API to create a digital twin model.
    - Parameters:
      - `p_body` - the JSON CLOB body for the model creation request.
    - Return Value: The response from the API as a CLOB.
7. `IOT_OBJECTS.adapter_api_body(p_dt_model_ocid varchar2, p_display_name
    varchar2, p_description varchar2 default null)`
    - Description: Constructs a JSON API payload for digital twin adapter
      creation.
    - Parameters:
      - `p_dt_model_ocid` - the digital twin model OCID.
      - `p_display_name` - the display name.
      - `p_description` - the description (optional).
    - Return Value: A JSON CLOB representing the adapter API body.
8. `IOT_OBJECTS.adapter_cli(p_dt_model_ocid varchar2, p_display_name varchar2,
    p_description varchar2 default null)`
    - Description: Composes a CLI command for digital twin adapter creation.
    - Parameters:
      - `p_dt_model_ocid` - the digital twin model OCID.
      - `p_display_name` - the display name.
      - `p_description` - the description (optional).
    - Return Value: A CLOB representing the CLI command.
9. `IOT_OBJECTS.create_adapter(p_body clob)`
    - Description: Calls the REST API to create a digital twin adapter.
    - Parameters:
      - `p_body` - the JSON CLOB body for the adapter creation request.
    - Return Value: The response from the API as a CLOB.
10. `IOT_OBJECTS.delete_object(p_object_ocid varchar2)`
    - Description: Calls the REST API to delete a digital twin object.
    - Parameters:
      - `p_object_ocid` - the OCID of the object to be deleted.
    - Return Value: The response from the API as a CLOB.

### IOT_OCI Package

The `IOT_OCI` package provides functions for interacting with OCI services.

1. `IOT_OCI.pretty(p_json_clob clob)`
   - Description: Pretty-prints a JSON CLOB.
   - Parameters:
     - `p_json_clob` - the JSON CLOB to be formatted.
   - Return Value: A formatted JSON CLOB.
2. `IOT_OCI.get_secret(p_secret_ocid VARCHAR2)`
   - Description: Retrieves a secret from OCI Vault.
   - Parameters:
     - `p_secret_ocid` - the OCID of the secret.
   - Return Value: The decoded secret as a CLOB.
3. `IOT_OCI.create_secret(p_secret_name varchar2, secret_content varchar2
   default null, secret_char number default 24)`
   - Description: Creates a new secret in OCI Vault.
   - Parameters:
     - `p_secret_name` - the name of the secret.
     - `secret_content` - the content of the secret (optional).
     - `secret_char` - the number of characters for the generated secret
       (optional, defaults to 24).
   - Return Value: A JSON CLOB containing the status and OCID of the created
     secret.
4. `IOT_OCI.get_all_secrets()`
   - Description: Lists all secrets in OCI Vault.
   - Parameters: None.
   - Return Value: A JSON CLOB containing information about all secrets.
5. `IOT_OCI.get_all_cas()`
   - Description: Lists all certificate authorities.
   - Parameters: None.
   - Return Value: A JSON CLOB containing information about all certificate
     authorities.
6. `IOT_OCI.get_all_certs()`
   - Description: Lists all certificates in the vault.
   - Parameters: None.
   - Return Value: A JSON CLOB containing information about all certificates.
7. `IOT_OCI.create_cert(p_cert_name varchar2, p_cert_auth_ocid varchar2)`
   - Description: Creates a new certificate issued by a given certificate
     authority.
   - Parameters:
     - `p_cert_name` - the name of the certificate.
     - `p_cert_auth_ocid` - the OCID of the certificate authority.
   - Return Value: A JSON CLOB containing the status and OCID of the created
     certificate.
8. `IOT_OCI.delete_cert(p_cert_ocid varchar2)`
   - Description: Schedules deletion of a certificate.
   - Parameters:
     - `p_cert_ocid` - the OCID of the certificate to be deleted.
   - Return Value: A JSON CLOB containing the status of the deletion request.
9. `IOT_OCI.get_cert(p_cert_ocid varchar2)`
   - Description: Fetches PEM/chain/private key for a certificate by OCID.
   - Parameters:
     - `p_cert_ocid` - the OCID of the certificate.
   - Return Value: A JSON CLOB containing the certificate details.
