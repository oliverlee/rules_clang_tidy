"""
Determines the workspace status used as an input to `apply_fixes` rules.
"""

def _local_workspace_status_impl(rctx):
    rctx.file(
        "WORKSPACE.bazel",
        content = """\
workspace(name = {name})
        """.format(name = rctx.name),
        executable = False,
    )

    # TODO handle < Bazel 7.1.0
    # https://github.com/bazelbuild/bazel/issues/20952
    # https://github.com/bazelbuild/bazel/issues/20363
    rctx.watch_tree(rctx.workspace_root)

    rctx.file(
        "BUILD.bazel",
        content = """\
exports_files(["config.bzl", "status"])
        """,
        executable = False,
    )

    rctx.file(
        "workspace-status.bash",
        content = r"""#!/usr/bin/env bash
set -euo pipefail

build_files=$(find {workspace} \
  $(cat "$workspace/.bazelignore" 2> /dev/null | xargs -I % echo "-not ( -path {workspace}/% -prune )") \
  -type f \( \
    -name "BUILD" -o \
    -name "BUILD.bazel" -o \
    -name "WORKSPACE" -o \
    -name "WORKSPACE.bazel" \
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

local_workspace_status = repository_rule(
    implementation = _local_workspace_status_impl,
    local = True,
)
