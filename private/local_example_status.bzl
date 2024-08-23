"""
Defines a status file for an example directory.
"""

load(":local_workspace_status.bzl", "local_workspace_status")

def local_example_status(
        name = None):
    local_workspace_status(
        name = "local_example_{name}".format(
            name = name,
        ),
        root_relpath = "example/" + name,
        # changes to any file in the example directory will trigger a retest
        find_expr = "-type f",
    )
