"""
macro/rule to test ClangTidy aspects and rules
"""

def tidy_test(
        name = None,
        srcs = None,
        env = {"CC": "clang"},
        tags = {"no-remote": ""},
        deps = [":prelude"],
        timeout = "short",
        size = "small",
        **kwargs):
    if srcs == None:
        srcs = [name + ".bash"]

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
