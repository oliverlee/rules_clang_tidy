"""
Rules for defining aspects to run ClangTidy and to apply fixes.
"""

load(":apply_fixes.bzl", _apply_fixes = "apply_fixes")
load(":make_clang_tidy_aspect.bzl", _make_clang_tidy_aspect = "make_clang_tidy_aspect")

make_clang_tidy_aspect = _make_clang_tidy_aspect

apply_fixes = _apply_fixes
