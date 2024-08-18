#!/usr/bin/env bash

set -euo pipefail

find "$1" -type f -name "*.clang-tidy.yaml" | \
    xargs sed -i -e "s+%workspace%+$BUILD_WORKSPACE_DIRECTORY+g"

clang-apply-replacements "$1"
