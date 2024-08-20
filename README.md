# rules_clang_tidy

Run `clang-tidy` on Bazel C++ targets. This project is heavily inspired by
[bazel_clang_tidy](https://github.com/erenon/bazel_clang_tidy) but has changes
made to better fit my workflow.

## usage

```Starlark
# //:WORKSPACE.bazel
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_repository")

RULES_CLANG_TIDY_COMMIT = ...

http_repository(
    name = "rules_clang_tidy",
    integrity = ...,
    strip_prefix = "rules_clang_tidy-{commit}".format(
        commit = RULES_CLANG_TIDY_COMMIT,
    ),
    url = "https://github.com/oliverlee/rules_clang_tidy/archive/{commit}.tar.gz".format(
        commit = RULES_CLANG_TIDY_COMMIT,
    ),
)

load("@rules_clang_tidy//:dependencies.bzl", "rules_clang_tidy_dependencies")

rules_clang_tidy_dependencies()
```

```Starlark
# //:.bazelrc
build:clang-tidy --aspects=@rules_clang_tidy//:aspects.bzl%check
build:clang-tidy --output_groups=report
build:clang-tidy --keep_going
```

Perform static analysis with

```sh
bazel build //... --config=clang-tidy
```

This will use `clang-tidy` in your `PATH` and [`.clang-tidy`](.clang_tidy)
defined in this repository.

### using a hermetic toolchain

<details><summary></summary>

To specify a specific binary (e.g. `clang-tidy` is specified by a hermetic
toolchain like [this](https://github.com/bazel-contrib/toolchains_llvm)), update
the build setting in `.bazelrc`.

```Starlark
# //:.bazelrc

build --@rules_clang_tidy//:clang-tidy=@llvm18//:clang-tidy

build:clang-tidy --aspects=@rules_clang_tidy//:aspects.bzl%check
build:clang-tidy --output_groups=report
build:clang-tidy --keep_going
```

</details>

### specifying `.clang-tidy`

<details><summary></summary>

To override the default `.clang-tidy`, define a `filegroup` containing the
replacement config and update build setting in `.bazelrc`.

```Starlark
# //:BUILD.bazel

filegroup(
    name = "clang-tidy-config",
    srcs = [".clang-tidy"],
    visibility = ["//visibility:public"],
)
```

```Starlark
# //:.bazelrc

build --@rules_clang_tidy//:config=//:clang-tidy-config

build:clang-tidy --aspects=@rules_clang_tidy//:aspects.bzl%check
build:clang-tidy --output_groups=report
build:clang-tidy --keep_going
```

</details>

### applying fixes

<details><summary></summary>

To apply fixes, generate the exported fixes with the `export_fixes` aspect.

```Starlark
# //:.bazelrc

build:clang-tidy-export-fixes --aspects=@rules_clang_tidy//:aspects.bzl%export_fixes
build:clang-tidy-export-fixes --output_groups=report
build:clang-tidy-export-fixes --remote_download_outputs=toplevel
```

```sh
bazel build //... --config=clang-tidy-export-fixes
```

If only a subset of checks needs to be run, those can be specified with `extra-options`.

```sh
bazel build //... --config=clang-tidy-export-fixes \
  --@rules_clang_tidy//:extra-options="--checks=-*,misc-unused-alias-decls"
```

Then apply the exported fixes with

```sh
bazel run @rules_clang_tidy//:apply-fixes -- $(bazel info output_path)
```

Alternatively, use rule `apply_fixes` and specify the dependencies for the
target.

```Starlark
load("@rules_clang_tidy//:defs.bzl", "apply_fixes")

apply_fixes(
    name = "apply-fixes",
    deps = [
        ...
    ],
    desired_deps = "//...", # requires Bazel 7.1.0
    testonly = True, # if deps includes cc_test targets
)
```

and run the `apply_fixes` target

```sh
bazel run //:apply-fixes

bazel run //:apply-fixes \
  --@rules_clang_tidy//:extra-options="--checks=-*,misc-unused-alias-decls*"
```

Both the `apply-fixes` executable target and the `apply_fixes` rule use the
binary specified with `--@rules_clang_tidy//:clang-apply-replacements`. If not
set, `clang-apply-replacements` must be in `PATH`. Similarly to
`--@rules_clang_tidy//:clang-tidy`, it's convenient to define the value in
`.bazelrc`.

</details>

## Requirements

- Bazel 5.x
- ClangTidy ??
