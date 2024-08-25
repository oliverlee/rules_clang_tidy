#!/usr/bin/env bash
set -euxo pipefail

source test/prelude.bash

fix_setup example/misc-unused

# This sets a 15 second idle timeout
# https://github.com/bazelbuild/bazel/issues/11062
unset TEST_TMPDIR

cat "$test_bazelrc" >> .bazelrc

# build everything
bazel \
  build \
  //...

# apply fixes target not run
! cmp \
  misc-unused-alias-decls.cpp \
  misc-unused-alias-decls.cpp.fixed

# linting delayed until this binary is explicitly built/run
bazel \
  run \
  //:apply-fixes | tee "$log"

grep "error: .*misc-unused-alias-decls" "$log"

diff \
  --color=always \
  --report-identical-files \
  misc-unused-alias-decls.cpp \
  misc-unused-alias-decls.cpp.fixed
