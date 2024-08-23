#!/usr/bin/env bash
set -euxo pipefail

source test/prelude.bash

fix_setup example/hermetic-toolchain

# This sets a 15 second idle timeout
# https://github.com/bazelbuild/bazel/issues/11062
unset TEST_TMPDIR

bazel \
  --bazelrc="$test_bazelrc" \
  run \
  //:apply-fixes | tee "$log"

grep "warning: .*misc-unused-alias-decls" "$log"

diff \
  --color=always \
  --report-identical-files \
  misc-unused-alias-decls.cpp \
  misc-unused-alias-decls.cpp.fixed
