"""
Writes the Bazel version to file.

https://github.com/bazelbuild/bazel/issues/8305#issuecomment-1954690199
"""

def _impl(rctx):
    rctx.file(
        "WORKSPACE.bazel",
        content = """\
workspace(name = {name})
        """.format(name = rctx.name),
        executable = False,
    )

    rctx.file(
        "BUILD.bazel",
        content = "",
        executable = False,
    )

    rctx.file(
        "bazel_version.bzl",
        content = """
BAZEL_VERSION = "{version}"
""".format(
            version = native.bazel_version,
        ),
        executable = False,
    )

local_bazel_version = repository_rule(
    implementation = _impl,
    local = True,
)
