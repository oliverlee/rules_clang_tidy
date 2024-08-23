#!/usr/bin/env bash
set -euxo pipefail

source test/prelude.bash

check_setup example/misc-unused

# This sets a 15 second idle timeout
# https://github.com/bazelbuild/bazel/issues/11062
unset TEST_TMPDIR

bazel \
  --bazelrc="$test_bazelrc" \
  build \
  --config=clang-tidy \
  --@rules_clang_tidy//:extra-options=--enable-check-profile \
  --@rules_clang_tidy//:extra-options=--checks='fuchsia-*' \
  //... 2>&1 | tee "$log" || true

grep "clang-tidy checks profiling" "$log"
grep "error: .*misc-unused-alias-decls" "$log"
grep "error: .*fuchsia-trailing-return" "$log"
