"""
apply_fixes is a rule for running ClangTidy and applying fixes. This avoids
using the `-fix` option of ClangTidy which can mistakenly apply the same fix
multiple times to a header when running on multiple targets.
"""

load("@bazel_skylib//lib:shell.bzl", "shell")
load(":aspects.bzl", "export_fixes")

def _apply_fixes_impl(ctx):
    desired_deps = ctx.actions.declare_file(ctx.label.name + ".desired_deps")

    ctx.actions.run_shell(
        outputs = [desired_deps],
        arguments = [ctx.attr.desired_deps],
        command = """\
#!/usr/bin/env bash
set -euo pipefail
set -x

output_base="$(pwd)/../.."

# set up symlinks for external workspaces

external_opts=$(mktemp)

find "$output_base/external" -maxdepth 1 -type d \
  | xargs -I % basename % \
  | xargs -I % echo "--override_repository=\"%=$output_base/external/%\"" \
  > "$external_opts"

# determine workspace path

if [ -f "{package}/BUILD" ]; then
  build_file="{package}/BUILD"
else
  build_file="{package}/BUILD.bazel"
fi

package_build_file_path="$(readlink -f $build_file)"
workspace_path="${{package_build_file_path%$build_file}}"

cd "$workspace_path"

# TODO avoid Bazel in Bazel
# https://github.com/bazelbuild/bazel/issues/20447
# https://github.com/bazelbuild/bazel/discussions/20464
{bazel} \
  --noblock_for_lock \
  --max_idle_secs=1 \
  --output_base="$(mktemp -d)" \
  cquery \
  $(cat "$external_opts") \
  --output=starlark \
  --starlark:expr='{starlark_expr}' \
  -- {pattern} | grep "//" | sort | uniq > {outfile}

        """.format(
            package = ctx.label.package,
            bazel = ctx.attr.bazel_bin,
            starlark_expr = (
                'str(target.label).strip("@") ' +
                'if "CcInfo" in providers(target).keys() ' +
                'else ""'
            ),
            pattern = ctx.attr.desired_deps,
            outfile = desired_deps.path,
        ),
        use_default_shell_env = True,
        mnemonic = "ParseDepsForApplyFixes",
        progress_message = "Parsing 'desired_deps' attr of '{}'".format(
            str(ctx.label).strip("@"),
        ),
        execution_requirements = {
            # https://github.com/bazelbuild/bazel/issues/21587
            # https://github.com/bazelbuild/bazel/issues/15516
            "no-cache": "1",
            "local": "1",
            # FIXME
            # This doesn't re-run if the output is in the action cache
        },
    )

    verify_file = ctx.actions.declare_file(ctx.label.name + ".verify")
    ctx.actions.run_shell(
        inputs = depset(direct = [desired_deps]),
        outputs = [verify_file],
        command = """\
#!/usr/bin/env bash
set -euo pipefail

# https://github.com/bazelbuild/bazel/blob/master/scripts/packages/bazel.sh
function color() {{
      # Usage: color "31;5" "string"
      # Some valid values for color:
      # - 5 blink, 1 strong, 4 underlined
      # - fg: 31 red,  32 green, 33 yellow, 34 blue, 35 purple, 36 cyan, 37 white
      # - bg: 40 black, 41 red, 44 blue, 45 purple
      printf '\033[%sm%s\033[0m' "$@"
}}

actual=$(mktemp)

$(for d in {actual_deps}; do echo "$d"; done | sort | uniq > "$actual")

if ! cmp --silent {desired} "$actual"; then
  >&2 color "31;1"  "ERROR:"
  >&2 echo " 'deps' does not match 'desired_deps' '{pattern}'"
  >&2 echo "Update 'deps' of '{target}' to\n"
  cat {desired} | xargs -I % >&2 echo '"%",'
  >&2 echo ""
  exit 1
fi

touch {verify_file}
        """.format(
            verify_file = verify_file.path,
            desired = desired_deps.path,
            actual_deps = " ".join([
                shell.quote(str(d.label).strip("@"))
                for d in ctx.attr.deps
            ]),
            pattern = ctx.attr.desired_deps,
            target = str(ctx.label).strip("@"),
        ),
        use_default_shell_env = True,
        mnemonic = "ApplyFixes",
        progress_message = "Verifying deps of {}".format(ctx.label),
    )

    apply_bin = ctx.attr._clang_apply_replacements.files_to_run.executable
    depsets = [dep[OutputGroupInfo].report for dep in ctx.attr.deps]
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

    runfiles = ctx.runfiles(
        files = [apply_bin, verify_file],
        transitive_files = depset(transitive = depsets),
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
            doc = """
            Targets to apply fixes to. Fixes are not applied to files in
            transitive dependencies.
            """,
        ),
        "desired_deps": attr.string(),
        "bazel_bin": attr.string(
            default = "bazel",
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

    desired_deps: `string`; or `None`; default is `None`
       Desired labels to apply fixes to. Allows wildcards. Does not allow
       workspace specification (all labels are within the current workspace).

       If the targets specified by this attribute (with a CcInfo provider)
       does not match the deps attribute, this rule will fail with an error.

       Bazel 7.1.0 may be required for some wildcards although there is a
       workaround for older versions.
       https://github.com/bazelbuild/bazel/issues/10653
       https://github.com/bazelbuild/bazel/issues/10653#issuecomment-694230015

    bazel_bin: `string`; default is `bazel`
      Path of the child Bazel process used to parse `desired deps`.

```bzl
load("@rules_clang_tidy//:defs.bzl", "apply_fixes")

apply_fixes(
    name = "apply-fixes",
    deps = [
        ...
    ],
    desired_deps = "//...",
)
```
    """,
)
