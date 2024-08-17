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
            direct = [source_file],
            transitive = [compilation_ctx.headers],
        ),
        outputs = [out],
        command = """
set -euo pipefail

{binary} {tidy_options} $(readlink --canonicalize {infile}) -- {compiler_command} {suppress_stderr}

touch {outfile}
""".format(
            binary = "clang-tidy",
            tidy_options = " ".join(kwargs["tidy_options"]),
            infile = source_file.path,
            outfile = out.path,
            compiler_command = " ".join(
                ctx.rule.attr.copts +
                _compilation_ctx_args(compilation_ctx) +
                _toolchain_args(ctx),
            ),
            suppress_stderr = "2> /dev/null" if kwargs["suppress_stderr"] else "",
        ),
        mnemonic = "ClangTidy",
        progress_message = "Linting {}".format(source_file.short_path),
        execution_requirements = kwargs["execution_requirements"],
    )

    return out

def _clang_tidy_aspect_impl(**kwargs):
    def impl(target, ctx):
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
        options = None,
        suppress_stderr = True,
        execution_requirements = None):
    return aspect(
        implementation = _clang_tidy_aspect_impl(
            tidy_options = options or [],
            suppress_stderr = suppress_stderr,
            execution_requirements = execution_requirements,
        ),
        fragments = ["cpp"],
        required_providers = [CcInfo],
        toolchains = [CC_TOOLCHAIN_TYPE],
    )

check_aspect = make_clang_tidy_aspect(
    options = [
        "--use-color",
    ],
)
