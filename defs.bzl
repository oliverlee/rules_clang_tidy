"""
ClangTidy aspect
"""

load("@rules_cc//cc:action_names.bzl", "ACTION_NAMES")
load("@rules_cc//cc:find_cc_toolchain.bzl", "CC_TOOLCHAIN_TYPE")

def _source_files_in(ctx, attr):
    if not hasattr(ctx.rule.attr, attr):
        return []

    files = []
    for f in getattr(ctx.rule.attr, attr):
        files += [g for g in f.files.to_list() if g.is_source]

    return files

def _compilation_ctx_args(compilation_ctx):
    map = lambda f, attr: [
        f(x)
        for x in getattr(compilation_ctx, attr).to_list()
    ]

    prefix = lambda p: lambda s: p + s

    return (
        map(prefix("-D"), "defines") +
        map(prefix("-isystem"), "external_includes") +
        map(prefix("-F"), "framework_includes") +
        map(prefix("-I"), "includes") +
        map(prefix("-D"), "local_defines") +
        map(prefix("-iquote"), "quote_includes") +
        map(prefix("-isystem"), "system_includes")
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
    return [
        "-isystem" + d
        for d in cc_toolchain.built_in_include_directories
    ] + cc_common.get_memory_inefficient_command_line(
        feature_configuration = feature_configuration,
        action_name = ACTION_NAMES.cpp_compile,
        variables = compile_variables,
    )

def _do_tidy(ctx, compilation_ctx, source_file, **kwargs):
    out = ctx.actions.declare_file(source_file.short_path + ".clang-tidy")

    ctx.actions.run_shell(
        inputs = depset(
            direct = [
                ctx.file._config,
                source_file,
            ],
            transitive = [compilation_ctx.headers],
        ),
        outputs = [out],
        arguments = [str(kwargs["suppress_stderr"]).lower()],
        command = """
set -euo pipefail

{binary} \
    --config-file={config} \
    {tidy_options} \
    $(readlink --canonicalize {infile}) \
      -- {compiler_command} 2> log.stderr \
  || (cat log.stderr >&2 && false)

$1 || cat log.stderr

touch {outfile}
""".format(
            binary = "clang-tidy",
            config = ctx.file._config.path,
            tidy_options = " ".join(kwargs["tidy_options"]),
            infile = source_file.path,
            outfile = out.path,
            compiler_command = " ".join(
                ctx.rule.attr.copts +
                _compilation_ctx_args(compilation_ctx) +
                _toolchain_args(ctx),
            ),
        ),
        mnemonic = "ClangTidy",
        progress_message = "Linting {}".format(source_file.short_path),
        execution_requirements = kwargs["execution_requirements"],
    )

    return out

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
        _check_attr(ctx)

        outputs = [
            _do_tidy(
                ctx,
                target[CcInfo].compilation_context,
                source_file,
                **kwargs
            )
            for source_file in (
                _source_files_in(ctx, "hdrs") +
                _source_files_in(ctx, "srcs")
            )
        ]
        return [OutputGroupInfo(report = depset(outputs))]

    return impl

def make_clang_tidy_aspect(
        config = None,
        options = [],
        suppress_stderr = True,
        execution_requirements = None):
    """
    Creates an aspect to run ClangTidy.

    Args:
        config: label; or `None`; default is `None`
            A single file filegroup passed to ClangTidy with `--config-file`.
            If `None`, the config file used by ClangTidy is determined by
            `label_flag` `//:config`.

        options: List of strings; default is []
            A list of options passed to ClangTidy.

        suppress_stderr: `bool`; default is `True`
            Suppress stderr when ClangTidy runs successfully. This is quieter
            than the `--quiet` option and can be used to suppress messages
            about the number of generated warnings.

        execution_requirements: `dict`; or `None`; default is `None`
            Information for scheduling the action.
    """
    return aspect(
        implementation = _clang_tidy_aspect_impl(
            tidy_options = options,
            suppress_stderr = suppress_stderr,
            execution_requirements = execution_requirements,
        ),
        fragments = ["cpp"],
        attrs = {
            "_config": attr.label(
                default = Label(config or "//:config"),
                allow_single_file = True,
            ),
        },
        required_providers = [CcInfo],
        toolchains = [CC_TOOLCHAIN_TYPE],
    )

check_aspect = make_clang_tidy_aspect(
    options = [
        "--use-color",
        "--warnings-as-errors=\"*\"",
    ],
)
