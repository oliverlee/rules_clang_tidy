#!/usr/bin/env bash

set -euo pipefail

apply_bin="$1"
output_path="$2"

find "$output_path" -type f -name "*.yaml" \
  | xargs sed -i -e "s+%workspace%+$BUILD_WORKSPACE_DIRECTORY+g"

"$apply_bin" "$output_path"
