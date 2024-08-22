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

# add a new target
echo 'cc_library(name = "a")' >> BUILD.bazel

# rebuild detects stale deps attr
bazel \
    build \
    //... 2>&1 | tee log || true

grep "ERROR.* 'deps' does not match 'desired_deps'" log
