#!/usr/bin/env bash
set -euxo pipefail

source test/prelude.bash

fix_setup example/shared-source

# This sets a 15 second idle timeout
# https://github.com/bazelbuild/bazel/issues/11062
unset TEST_TMPDIR

cat "$test_bazelrc" >> .bazelrc

# build everything
bazel run //:c
