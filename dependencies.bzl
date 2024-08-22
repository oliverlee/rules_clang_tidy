"""
User setup functions for dependencies
"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("//private:local_bazel_version.bzl", "local_bazel_version")
load("//private:local_workspace_directories.bzl", "local_workspace_directories")
load("//private:local_workspace_status.bzl", "local_workspace_status")

def rules_clang_tidy_dependencies():
    maybe(
        http_archive,
        name = "bazel_skylib",
        urls = [
            "https://mirror.bazel.build/github.com/bazelbuild/bazel-skylib/releases/download/1.7.1/bazel-skylib-1.7.1.tar.gz",
            "https://github.com/bazelbuild/bazel-skylib/releases/download/1.7.1/bazel-skylib-1.7.1.tar.gz",
        ],
        sha256 = "bc283cdfcd526a52c3201279cda4bc298652efa898b10b4db0837dc51652756f",
    )

    local_bazel_version(
        name = "local_bazel_version",
    )

    local_workspace_directories(
        name = "local_workspace_directories",
    )

    local_workspace_status(
        name = "local_clang_tidy_workspace_status",
    )
