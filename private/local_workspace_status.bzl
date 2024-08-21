"""
Determines the workspace status used as an input to `apply_fixes` rules.
"""

# we can't load @bazel_skylib yet since this bzl file is loaded in
# dependencies.bzl (which is responsible for loading @bazel_skylib)

# https://github.com/bazelbuild/bazel-skylib/blob/652c8f0b2817daaa2570b7a3b2147643210f7dc7/lib/versions.bzl

def _extract_version_number(bazel_version):
    """Extracts the semantic version number from a version string

    Args:
      bazel_version: the version string that begins with the semantic version
        e.g. "1.2.3rc1 abc1234" where "abc1234" is a commit hash.

    Returns:
      The semantic version string, like "1.2.3".
    """
    for i in range(len(bazel_version)):
        c = bazel_version[i]
        if not (c.isdigit() or c == "."):
            return bazel_version[:i]
    return bazel_version

# Parse the bazel version string from `native.bazel_version`.
# e.g.
# "0.10.0rc1 abc123d" => (0, 10, 0)
# "0.3.0" => (0, 3, 0)
def _parse_bazel_version(bazel_version):
    """Parses a version string into a 3-tuple of ints

    int tuples can be compared directly using binary operators (<, >).

    For a development build of Bazel, this returns an unspecified version tuple
    that compares higher than any released version.

    Args:
      bazel_version: the Bazel version string

    Returns:
      An int 3-tuple of a (major, minor, patch) version.
    """

    version = _extract_version_number(bazel_version)
    if not version:
        return (999999, 999999, 999999)
    return tuple([int(n) for n in version.split(".")])

def _setup_status_file(rctx):
    """
    Setup the workspace status file.

    Stores a hash value for the build files of the root workspace (i.e.
    consumer of @bazel-clang-tidy) in a status file.

    This status file is updated whenever any build files change.
    """

    # https://github.com/bazelbuild/bazel/issues/20952
    # https://github.com/bazelbuild/bazel/issues/20363
    rctx.watch_tree(rctx.workspace_root)

    rctx.file(
        "workspace-status.bash",
        content = r"""#!/usr/bin/env bash
set -euo pipefail

build_files=$(find {workspace} \
  $(cat "{workspace}/.bazelignore" 2> /dev/null | xargs -I % echo "-not ( -path {workspace}/% -prune )") \
  -type f \( \
    -name "BUILD" -o \
    -name "BUILD.bazel" \
  \) \
  | sort \
)

echo "$build_files" | xargs -I % cat % | md5sum
        """.format(
            workspace = rctx.workspace_root,
        ),
        executable = True,
    )

    result = rctx.execute(
        ["./workspace-status.bash"],
        timeout = 5,
    )
    if result.return_code != 0:
        fail(result.stderr)

    result = rctx.file(
        "status",
        content = result.stdout,
        executable = False,
    )

def _local_workspace_status_impl(rctx):
    rctx.file(
        "WORKSPACE.bazel",
        content = """\
workspace(name = {name})
        """.format(name = rctx.name),
        executable = False,
    )

    rctx.file(
        "BUILD.bazel",
        content = """\
exports_files(["config.bzl", "status"])
        """,
        executable = False,
    )

    rctx.file(
        "config.bzl",
        content = """
BAZEL_EXTERNAL_DIRECTORY = "{external_dir}"
BUILD_WORKSPACE_DIRECTORY = "{workspace_root}"
""".format(
            external_dir = str(rctx.path(".").realpath).removesuffix("/" + rctx.name),
            workspace_root = rctx.workspace_root,
        ),
        executable = False,
    )

    if _parse_bazel_version(native.bazel_version) >= _parse_bazel_version("7.1.0"):
        _setup_status_file(rctx)
    else:
        rctx.file(
            "status",
            content = "",
            executable = False,
        )

local_workspace_status = repository_rule(
    implementation = _local_workspace_status_impl,
    local = True,
)
