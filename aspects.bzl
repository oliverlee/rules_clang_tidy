"""
Preconfigured aspects for running ClangTidy.
"""

load(":make_clang_tidy_aspect.bzl", "make_clang_tidy_aspect")

check = make_clang_tidy_aspect(
    options = [
        "--use-color",
        "--warnings-as-errors='*'",
    ],
)
