"""
Determines paths to local workspace directories.
"""

def _local_workspace_directories_impl(rctx):
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
exports_files(["defs.bzl"])
        """,
        executable = False,
    )

    rctx.file(
        "defs.bzl",
        content = """
BAZEL_EXTERNAL_DIRECTORY = "{external_dir}"
BUILD_WORKSPACE_DIRECTORY = "{workspace_root}"
""".format(
            external_dir = str(rctx.path(".").realpath).removesuffix("/" + rctx.name),
            workspace_root = rctx.workspace_root,
        ),
        executable = False,
    )

local_workspace_directories = repository_rule(
    implementation = _local_workspace_directories_impl,
    local = True,
)
