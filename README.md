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
```

```Starlark
# //:.bazelrc
build:clang-tidy --aspects=@rules_clang_tidy//:defs.bzl%check_aspect
build:clang-tidy --output_groups=report
build:clang-tidy --keep_going
```

Perform static analysis with

```sh
bazel build //... --config=clang-tidy
```

This will use `clang-tidy` in your `PATH` and pick up a `.clang-tidy` file
defined in your repository.

## Requirements

- Bazel 5.x
- ClangTidy ??
