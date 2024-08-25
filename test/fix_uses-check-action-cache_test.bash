#!/usr/bin/env bash
set -euxo pipefail

source test/prelude.bash

orig="$(mktemp)"

fix_setup example/misc-unused

# This sets a 15 second idle timeout
# https://github.com/bazelbuild/bazel/issues/11062
unset TEST_TMPDIR

cat "$test_bazelrc" >> .bazelrc

# run check, generating fixes in cache
bazel build --config=clang-tidy //... | tee "$log" || true

grep "error: .*misc-unused-alias-decls" "$log"

bazel run //:apply-fixes 2>&1 | tee "$log"

[ 0 -eq $(grep -c "error: .*misc-unused-alias-decls" "$log") ]
