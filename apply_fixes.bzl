"""
apply_fixes is a rule for running ClangTidy and applying fixes. This avoids
using the `-fix` option of ClangTidy which can mistakenly apply the same fix
multiple times to a header when running on multiple targets.
"""

load("@bazel_skylib//lib:shell.bzl", "shell")
load(":aspects.bzl", "export_fixes")

def _apply_fixes_impl(ctx):
    apply_bin = ctx.attr._clang_apply_replacements.files_to_run.executable
    depsets = [dep[OutputGroupInfo].report for dep in ctx.attr.deps]

    runfiles = ctx.runfiles(
        files = [apply_bin],
        transitive_files = depset(transitive = depsets),
    )
    fixes = [f for dep in depsets for f in dep.to_list()]
    out = ctx.actions.declare_file(ctx.label.name + ".bash")

    ctx.actions.write(
        output = out,
        content = """\
#!/usr/bin/env bash
set -euo pipefail

fixes={fixes}

for src in "${{fixes[@]}}"; do
  dst="updated-fixes/$src"
  mkdir -p $(dirname "$dst")
  sed -e "s+%workspace%+$BUILD_WORKSPACE_DIRECTORY+" "$src" > "$dst"
done

{apply_bin} updated-fixes 2> >(tee -a log.stderr >&2)

[ $(grep --max-count=1 --count "doesn't exist" log.stderr) -eq 0 ]
        """.format(
            apply_bin = apply_bin.short_path,
            fixes = shell.array_literal([
                f.short_path
                for f in fixes
            ]),
        ),
        is_executable = True,
    )

    return [DefaultInfo(
        runfiles = runfiles,
        executable = out,
    )]

apply_fixes = rule(
    implementation = _apply_fixes_impl,
    attrs = {
        "deps": attr.label_list(
            aspects = [export_fixes],
            providers = [CcInfo],
        ),
        "_clang_apply_replacements": attr.label(
            default = Label("//:clang-apply-replacements"),
        ),
    },
    executable = True,
    doc = """\
Defines an executable rule to run ClangTidy and then apply fixes.

Args:
    name: `string`
        rule name

    deps: `label_list`
        List of targets to apply fixes to. Fixes are applied to files in
        the `hdrs` or `srcs` attributes.

```bzl
load("@rules_clang_tidy//:defs.bzl", "apply_fixes")

apply_fixes(
    name = "apply-fixes",
    deps = [
        ...
    ],
)
```
    """,
)
