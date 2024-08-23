#!/usr/bin/env bash
set -euxo pipefail

source test/prelude.bash

check_setup example/dep-cc_test

# This sets a 15 second idle timeout
# https://github.com/bazelbuild/bazel/issues/11062
unset TEST_TMPDIR

bazel \
  --bazelrc="$test_bazelrc" \
  build \
  //pass:build_pass

bazel \
  --bazelrc="$test_bazelrc" \
  build \
  //fail/... 2>&1 | tee "$log" || true

grep "no such target '//:baz'" "$log"
