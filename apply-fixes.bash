#!/usr/bin/env bash

set -euo pipefail

apply_bin="$1"
output_path="$2"

if [ "$(uname)" == "Darwin" ]; then
  SED_INPLACE="-i''"
else
  SED_INPLACE="-i"
fi

find "$output_path" -type f -name "*.yaml" \
  | xargs sed "$SED_INPLACE" -e "s+%workspace%+$BUILD_WORKSPACE_DIRECTORY+g"

"$apply_bin" "$output_path"
