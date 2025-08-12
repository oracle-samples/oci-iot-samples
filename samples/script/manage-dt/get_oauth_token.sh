#!/usr/bin/env bash
#
# Retrieve auth token for the data API.
#
# Copyright (c) 2025 Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at
# https://oss.oracle.com/licenses/upl.
#
# DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
#

PGM=$(basename "$0")
readonly PGM
PGM_DIR=$( cd "$(dirname "$0")" && pwd -P )
readonly PGM_DIR

# shellcheck disable=SC1091
source "${PGM_DIR}/environ.sh"

# Only refresh if token is about to expire
if [[ -f "${PGM_DIR}/token.sh" ]]; then
  if [[ $(uname -s) == "Darwin" ]]; then
    gnu_stat="gstat"
  else
    gnu_stat="stat"
  fi
  token_age=$(( $(date +%s) - $(${gnu_stat} -L --format %Y "${PGM_DIR}/token.sh") ))
  if [[ ${token_age} -lt 1500 ]]; then
    echo "${PGM}: Data token valid"
    exit
  fi
fi

echo "${PGM}: Refreshing data token"
api_data_token=$(curl -s --location "${OAUTH_ENDPOINT}" \
  --header 'Content-Type: application/x-www-form-urlencoded' \
  --user "${IAM_APP_CLIENT_ID}:${IAM_APP_CLIENT_SECRET}" \
  --data-urlencode "scope=/${DOMAIN_GROUP_SHORT_ID}/iot/${DOMAIN_SHORT_ID}" \
  --data-urlencode "grant_type=password" \
  --data-urlencode "username=${IAM_USER}" \
  --data-urlencode "password=${IAM_PASSWORD}" | jq -r .access_token)

cat > "${PGM_DIR}/token.sh" <<EOF
#!/usr/bin/env bash
# Token generated on $(date)

# shellcheck disable=SC2034

API_DATA_TOKEN="${api_data_token}"
EOF
