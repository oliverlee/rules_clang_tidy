"""
macro/rule to test ClangTidy aspects and rules
"""

def tidy_test(
        name = None,
        srcs = None,
        example_external = None,
        env = {"CC": "clang"},
        tags = {"no-remote": ""},
        deps = [":prelude"],
        timeout = "short",
        size = "small",
        **kwargs):
    if srcs == None:
        srcs = [name + ".bash"]

    # Manually add runfile dependencies. These can't be tracked by Bazel.
    kwargs["data"] = [
        # This example is excluded from the workspace by .bazelignore
        "@local_example_{external}//:status".format(
            external = example_external,
        ),
        # The example external may depend on the filegroups below
        "//:files",
        "//private:files",
    ] + kwargs.setdefault("data", [])

    native.sh_test(
        name = name,
        srcs = srcs,
        env = env,
        tags = tags,
        deps = deps,
        timeout = timeout,
        size = size,
        **kwargs
    )
