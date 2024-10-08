#!/usr/bin/env bash
set -euxo pipefail

source test/prelude.bash

check_setup example/hermetic-toolchain

# This sets a 15 second idle timeout
# https://github.com/bazelbuild/bazel/issues/11062
unset TEST_TMPDIR

bazel \
  --bazelrc="$test_bazelrc" \
  build \
  --config=clang-tidy \
  --toolchain_resolution_debug="cpp" \
  //... 2>&1 | tee "$log" || true

grep "Selected .*llvm_toolchain" "$log"
grep "error: .*misc-unused-alias-decls" "$log"
