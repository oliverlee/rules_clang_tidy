#!/usr/bin/env bash
set -euxo pipefail

source test/prelude.bash

fix_setup example/misc-unused

# This sets a 15 second idle timeout
# https://github.com/bazelbuild/bazel/issues/11062
unset TEST_TMPDIR

# generate fixes in output base
bazel \
    --bazelrc="$test_bazelrc" \
    build \
    --config=clang-tidy-export-fixes \
    //...

# apply fixes
bazel \
    --bazelrc="$test_bazelrc" \
    run @rules_clang_tidy//:apply-fixes -- \
    $(bazel --bazelrc="$test_bazelrc" info output_base)

diff \
    --color=always \
    --report-identical-files \
    misc-unused-alias-decls.cpp \
    misc-unused-alias-decls.cpp.fixed
