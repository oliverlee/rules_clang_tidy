"""
Defines a binary target for a binary in PATH.
"""

load("@bazel_skylib//rules:write_file.bzl", "write_file")

def path_binary_wrapper(
        name = None,
        binary = None):
    write_file(
        name = "gen-" + name,
        out = name + ".bash",
        content = [
            "#!/usr/bin/env bash",
            "set -euo pipefail",
            "exec {} \"$@\"".format(binary),
            "",
        ],
        is_executable = True,
        tags = ["manual"],
        visibility = ["//visibility:private"],
    )

    native.sh_binary(
        name = name,
        srcs = ["gen-" + name],
    )
