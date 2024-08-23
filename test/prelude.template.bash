#!/usr/bin/env bash
set -euo pipefail

function override_externals
{
  function override_repository
  {
    local external="${1#$BAZEL_EXTERNAL_DIRECTORY/}"
    echo "build --override_repository=$external=$1"
  }

  export -f override_repository

  local bazelrc="$1"
  local output_base="$2"

  mkdir "$output_base/external"

  find "$BAZEL_EXTERNAL_DIRECTORY" -maxdepth 1 -type d \
    | grep -e "$BAZEL_EXTERNAL_DIRECTORY/" \
    | grep -v -e "$BAZEL_EXTERNAL_DIRECTORY/local_" \
    | xargs -n1 bash -c "echo \"\$(override_repository \"\$1\")\" >> $bazelrc" bash
}

function output_base
{
  echo "$TEST_TMPDIR"
}

function common_setup
{
  log=$(mktemp)
  test_bazelrc=$(mktemp)
  output_base="$TEST_TMPDIR"

  cat > $test_bazelrc << EOF
startup --noblock_for_lock
startup --max_idle_secs=1
startup --output_base=$output_base

build --announce_rc
build --color=yes
build --curses=no
build --show_timestamps
build --experimental_convenience_symlinks=ignore
EOF

  override_externals "$test_bazelrc" "$output_base"
}

function check_setup
{
  common_setup

  cd "$BUILD_WORKSPACE_DIRECTORY/$1"
}

function fix_setup
{
  common_setup

  cp -r "$BUILD_WORKSPACE_DIRECTORY/$1" temp

  echo "common --override_repository=rules_clang_tidy=$BUILD_WORKSPACE_DIRECTORY" >> "$test_bazelrc"

  cd temp
}
