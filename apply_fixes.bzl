"""
apply_fixes is a rule for running ClangTidy and applying fixes. This avoids
using the `-fix` option of ClangTidy which can mistakenly apply the same fix
multiple times to a header when running on multiple targets.
"""

load("@bazel_skylib//lib:shell.bzl", "shell")
load("@bazel_skylib//lib:versions.bzl", "versions")
load("@local_bazel_version//:bazel_version.bzl", "BAZEL_VERSION")
load(":aspects.bzl", "export_fixes")

def _do_verify_deps(ctx, out):
    label = str(ctx.label).strip("@").removesuffix(".verify")

    query = ctx.actions.declare_file(ctx.label.name + ".query")
    ctx.actions.run_shell(
        inputs = depset(
            transitive = [
                ctx.attr._workspace_directories.files,
                ctx.attr._workspace_status.files,
            ],
        ),
        outputs = [query],
        command = """\
#!/usr/bin/env bash
set -euo pipefail

export $(cat {workspace_directories} | sed -e 's/ //g' | sed -e 's/\"//g')

# set up symlinks for external workspaces

external_opts=$(mktemp)

find "$BAZEL_EXTERNAL_DIRECTORY" -maxdepth 1 -type d \
  | xargs -I % basename % \
  | xargs -I % echo "--override_repository=\"%=$BAZEL_EXTERNAL_DIRECTORY/%\"" \
  > "$external_opts"

# parse dependency_deps pattern

output_base=$(mktemp -d)
query=$(pwd)/{outfile}

cd "$BUILD_WORKSPACE_DIRECTORY"

# TODO avoid Bazel in Bazel
# https://github.com/bazelbuild/bazel/issues/20447
# https://github.com/bazelbuild/bazel/discussions/20464
{bazel} \
  --noblock_for_lock \
  --max_idle_secs=1 \
  --output_base="$output_base" \
  cquery \
  --show_progress=false \
  --ui_event_filters=-info,-debug \
  $(cat "$external_opts") \
  --output=starlark \
  --starlark:expr='{starlark_expr}' \
  -- {pattern} | grep "//" | sort | uniq > "$query"

        """.format(
            bazel = ctx.attr.bazel_bin,
            starlark_expr = (
                'str(target.label).strip("@") ' +
                'if "CcInfo" in providers(target).keys() ' +
                'else ""'
            ),
            pattern = ctx.attr.desired_deps,
            outfile = query.path,
            workspace_directories = ctx.attr._workspace_directories.files.to_list()[0].path,
        ),
        use_default_shell_env = True,
        mnemonic = "QueryDepsForApplyFixes",
        progress_message = "Querying 'desired_deps' attr of '{label}'".format(
            label = label,
        ),
        execution_requirements = {
            # This rule can't run remotely as it should be re-run anytime any
            # build files change in the consumer workspace. Changes in build
            # files can potentially change the expansion of wildcards in the
            # `desired_deps` pattern.
            #
            # Detection of a change in the build files is signaled by
            # `ctx.attr._workspace_status`.
            #
            # This action also depends on the following definitions from
            # `ctx.attr._workspace_directories`:
            # * BAZEL_EXTERNAL_DIRECTORY
            # * BUILD_WORKSPACE_DIRECTORY
            #
            # BUILD_WORKSPACE_DIRECTORY is not defined in env during this
            # action - it is only available when running the outputs of this
            # action.
            #
            # For more infomation see
            # https://github.com/bazelbuild/bazel/issues/3041#issuecomment-627728133
            #
            # this functionality depends only
            # https://github.com/bazelbuild/bazel/issues/20952
            #
            # https://bazel.build/reference/be/common-definitions#common.tags
            "no-remote": "1",
        },
    )

    ctx.actions.run_shell(
        inputs = depset(direct = [query]),
        outputs = [out],
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

if ! cmp --silent {query} "$actual"; then
  >&2 color "31;1"  "ERROR:"
  >&2 echo " 'deps' does not match 'desired_deps' '{pattern}'"
  >&2 echo "Update 'deps' of '{target}' to\n"
  cat {query} | xargs -I % >&2 echo '"%",'
  >&2 echo ""
  exit 1
fi

touch {outfile}
        """.format(
            outfile = out.path,
            query = query.path,
            actual_deps = " ".join([
                shell.quote(str(d.label).strip("@"))
                for d in ctx.attr.deps
            ]),
            pattern = ctx.attr.desired_deps,
            target = str(ctx.label).strip("@"),
        ),
        use_default_shell_env = True,
        mnemonic = "ApplyFixes",
        progress_message = "Verifying deps of '{label}'".format(
            label = label,
        ),
    )

    return [DefaultInfo(files = depset([out]))]

def _skip_verify_deps(ctx, out):
    ctx.actions.write(out, "")
    return [DefaultInfo(files = depset([out]))]

def _verify_deps_impl(ctx):
    if ctx.attr.desired_deps and not versions.is_at_least("7.1.0", BAZEL_VERSION):
        label = str(ctx.label).strip("@").removesuffix(".verify")
        fail(
            "\n\nFor rule '{}', ".format(label) +
            "use of 'desired_deps' requires Bazel 7.1.0 or higher.\n" +
            "Please remove `desired_deps` or use a newer version of Bazel.\n\n",
        )

    out = ctx.actions.declare_file(ctx.label.name + ".deps")
    impl = _do_verify_deps if ctx.attr.desired_deps else _skip_verify_deps
    return impl(ctx, out)

_verify_deps = rule(
    implementation = _verify_deps_impl,
    attrs = {
        "deps": attr.label_list(
            providers = [CcInfo],
        ),
        "desired_deps": attr.string(),
        "bazel_bin": attr.string(
            default = "bazel",
        ),
        "_workspace_directories": attr.label(
            default = Label("@local_workspace_directories//:defs.bzl"),
            allow_files = True,
        ),
        "_workspace_status": attr.label(
            default = Label("@local_clang_tidy_workspace_status//:status"),
            allow_files = True,
        ),
    },
)

def _apply_fixes_impl(ctx):
    apply_bin = ctx.attr._clang_apply_replacements.files_to_run.executable
    depsets = [dep[OutputGroupInfo].report for dep in ctx.attr.deps]
    fixes = [f for dep in depsets for f in dep.to_list()]

    runfiles = ctx.runfiles(
        files = [apply_bin],
        transitive_files = depset(
            transitive = depsets + [ctx.attr.verify.files],
        ),
    )

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

_apply_fixes = rule(
    implementation = _apply_fixes_impl,
    attrs = {
        "verify": attr.label(),
        "deps": attr.label_list(
            aspects = [export_fixes],
            providers = [CcInfo],
            mandatory = True,
        ),
        "_clang_apply_replacements": attr.label(
            default = Label("//:clang-apply-replacements"),
        ),
    },
    executable = True,
)

def apply_fixes(
        name = None,
        deps = None,
        desired_deps = None,
        bazel_bin = "bazel",
        **kwargs):
    """
    Defines an executable rule to run ClangTidy and then apply fixes.

    Args:
        name: `string`
            rule name

        deps: `label_list`
            List of targets to apply fixes to. Fixes are applied to files in
            the `hdrs` or `srcs` attributes.

        desired_deps: `string`; or `None`; default is `None`
            Desired labels to apply fixes to. Allows wildcards. Does not allow
            workspace specification (all labels are within the current
            workspace).

            If the targets specified by this attribute (with a CcInfo provider)
            does not match the deps attribute, this rule will fail with an
            error.

            Use of this attribute runs a child Bazel process (using
            `bazel_bin`), which may not have the same configuration as the
            parent process.

            Note that the following issue is may still present. `.bazelignore`
            can be defined ignore convenience symlinks.
            https://github.com/bazelbuild/bazel/issues/10653

        bazel_bin: `string`; default is `bazel`
            Path of the child Bazel process used to parse `desired deps`.

        **kwargs:
            Other arguments passed to the executable rule.

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
    """
    _verify_deps(
        name = name + ".verify",
        deps = deps,
        desired_deps = desired_deps,
        bazel_bin = bazel_bin,
        visibility = ["//visibility:private"],
    )

    tags = kwargs.pop("tags", [])

    if not "manual" in tags:
        tags.append("manual")

    _apply_fixes(
        name = name,
        verify = name + ".verify",
        deps = deps,
        tags = tags,
        **kwargs
    )
