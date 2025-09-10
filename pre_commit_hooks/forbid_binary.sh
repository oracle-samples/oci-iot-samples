#!/usr/bin/env bash
#
# forbid_binary.sh: Forbid binary files
#
# Copyright (c) 2022 Oracle and/or its affiliates.
#
# Description:
#   pre-commit hook to prevent binary file commit unless it is flagged as LFS

set -e

rc=0
for file in "${@}"; do
  lfs=$(git lfs ls-files -n -I "/${file}")
  if [[ -z ${lfs} ]]; then
    echo "[ERROR] ${file} appears to be a non-LFS binary file"
    rc=1
  fi
done
exit ${rc}
