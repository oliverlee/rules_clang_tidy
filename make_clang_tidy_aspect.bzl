"""
make_clang_tidy_aspect is a macro that creates an aspect to run ClangTidy. It
provides attributes to customize options passed to ClangTidy (e.g. with
different configurations or verbosity).
"""

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load("@rules_cc//cc:action_names.bzl", "ACTION_NAMES")
load("@rules_cc//cc:find_cc_toolchain.bzl", "CC_TOOLCHAIN_TYPE")
load("//private:functional.bzl", fn = "functional")

def _source_files_in(ctx, attr):
    if not hasattr(ctx.rule.attr, attr):
        return []

    files = []
    for f in getattr(ctx.rule.attr, attr):
        files += [g for g in f.files.to_list() if g.is_source]

    return files

def _compilation_ctx_args(compilation_ctx):
    prepend = lambda front, attr: fn.map(
        fn.bind_front(fn.add, front),
        getattr(compilation_ctx, attr).to_list(),
    )

    return (
        prepend("-D", "defines") +
        prepend("-isystem", "external_includes") +
        prepend("-F", "framework_includes") +
        prepend("-I", "includes") +
        prepend("-D", "local_defines") +
        prepend("-iquote", "quote_includes") +
        prepend("-isystem", "system_includes")
    )

def _toolchain_args(ctx):
    cc_toolchain = ctx.toolchains[CC_TOOLCHAIN_TYPE].cc

    feature_configuration = cc_common.configure_features(
        ctx = ctx,
        cc_toolchain = cc_toolchain,
    )
    compile_variables = cc_common.create_compile_variables(
        feature_configuration = feature_configuration,
        cc_toolchain = cc_toolchain,
        user_compile_flags = ctx.fragments.cpp.cxxopts + ctx.fragments.cpp.copts,
    )
    return cc_common.get_memory_inefficient_command_line(
        feature_configuration = feature_configuration,
        action_name = ACTION_NAMES.cpp_compile,
        variables = compile_variables,
    )

def _do_tidy(ctx, compilation_ctx, source_file, **kwargs):
    clang_tidy = ctx.attr._clang_tidy.files_to_run.executable

    sanitize = lambda s: "".join(fn.filter(
        lambda c: not c in ["@", "/", ":", "%"],
        s.elems(),
    )).replace(".bzl", "", 1)

    outbase = ".".join([
        source_file.short_path,
        "_".join(fn.map(sanitize, ctx.aspect_ids)),
    ])

    # This output file may be used by clang-apply-replacements which requires a
    # yaml extension.
    fixes = ctx.actions.declare_file(outbase + ".yaml")
    result = ctx.actions.declare_file(outbase + ".result")
    phony = ctx.actions.declare_file(outbase + ".phony")

    # This action should succeed so that the fixes file is generated and cached.
    ctx.actions.run_shell(
        inputs = depset(
            direct = [
                ctx.file._config,
                source_file,
                clang_tidy,
            ],
            transitive = [compilation_ctx.headers],
        ),
        outputs = [fixes, result],
        arguments = [str(not kwargs["display_stderr"]).lower()],
        command = """\
#!/usr/bin/env bash
set -euo pipefail

({clang_tidy} \
    --config-file={config} \
    {tidy_options} \
    {extra_options} \
    --export-fixes="{fixes}" \
    {infile} \
      -- {compiler_command} 2> log.stderr && echo "true" > {result})\
  || (cat log.stderr >&2 && echo "false" > {result})

$1 || cat log.stderr

touch {fixes}

# replace sandbox path prefix from file paths and
# hope `+` isn't used anywhere
sed --in-place --expression "s+$(pwd)+%workspace%+g" {fixes}
        """.format(
            clang_tidy = clang_tidy.path,
            config = ctx.file._config.path,
            tidy_options = " ".join(kwargs["tidy_options"]),
            extra_options = " ".join(ctx.attr._extra_options[BuildSettingInfo].value),
            infile = source_file.path,
            fixes = fixes.path,
            result = result.path,
            compiler_command = " ".join(
                _toolchain_args(ctx) +
                _compilation_ctx_args(compilation_ctx) +
                ctx.rule.attr.copts,
                # TODO add options from cpp fragment
            ),
        ),
        mnemonic = "ClangTidy",
        progress_message = "Linting {}".format(source_file.short_path),
        execution_requirements = kwargs["execution_requirements"],
    )

    # use result to conditionally fail the action
    ctx.actions.run_shell(
        inputs = depset(direct = [result]),
        outputs = [phony],
        command = """\
#!/usr/bin/env bash
set -euo pipefail

bash {result}
touch {phony}
        """.format(
            result = result.path,
            phony = phony.path,
        ),
    )

    return struct(fixes = fixes, phony = phony)

def _check_attr(ctx):
    config_files = ctx.attr._config.files.to_list()

    if len(config_files) != 1:
        fail("{label} may only contain a single file but it has: {files}".format(
            label = ctx.attr._config.label,
            files = config_files,
        ))

    if not config_files[0].is_source:
        fail("{} must be a source file".format(config_files[0]))

def _clang_tidy_aspect_impl(**kwargs):
    def impl(target, ctx):
        # https://github.com/bazelbuild/bazel/issues/19609
        if not CcInfo in target:
            return []

        _check_attr(ctx)

        fixes = []
        phony = []
        for source_file in (
            _source_files_in(ctx, "hdrs") +
            _source_files_in(ctx, "srcs")
        ):
            out = _do_tidy(
                ctx,
                target[CcInfo].compilation_context,
                source_file,
                **kwargs
            )
            fixes.append(out.fixes)
            phony.append(out.phony)

        return [
            OutputGroupInfo(
                report = depset(fixes + phony),
                fixes = depset(fixes),
            ),
        ]

    return impl

def make_clang_tidy_aspect(
        clang_tidy = None,
        config = None,
        options = [],
        display_stderr = False,
        execution_requirements = None):
    """
    Creates an aspect to run ClangTidy.

    Args:
        clang_tidy: `label`; or `None`; default is `None`
            A label specifying a `clang-tidy` binary. If `None`, the binary is
            determined by `label_flag` `//:clang-tidy`. If `//:clang-tidy` is
            not overriden to specify a binary, `clang-tidy` must be available
            in `PATH`.

        config: `label`; or `None`; default is `None`
            A single file filegroup passed to ClangTidy with `--config-file`.
            If `None`, the config file used by ClangTidy is determined by
            `label_flag` `//:config`.

        options: List of strings; default is []
            A list of options passed to ClangTidy.

        display_stderr: `bool`; default is `False`
            Display stderr when ClangTidy runs successfully. Setting this to
            `False` is quieter than the `--quiet` option and can be used to
            suppress messages about the number of generated warnings.

        execution_requirements: `dict`; or `None`; default is `None`
            Information for scheduling the action.
            https://bazel.build/reference/be/common-definitions#common.tags

    The aspect produces a single output file in the `report` output group.
    Options can refer to the output file with `$@`.
    """
    return aspect(
        implementation = _clang_tidy_aspect_impl(
            tidy_options = options,
            display_stderr = display_stderr,
            execution_requirements = execution_requirements,
        ),
        fragments = ["cpp"],
        attrs = {
            "_clang_tidy": attr.label(
                default = Label(clang_tidy or "//:clang-tidy"),
            ),
            "_config": attr.label(
                default = Label(config or "//:config"),
                allow_single_file = True,
            ),
            "_extra_options": attr.label(
                default = Label("//:extra-options"),
            ),
        },
        toolchains = [CC_TOOLCHAIN_TYPE],
    )
