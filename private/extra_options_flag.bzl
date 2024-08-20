"""
Defines a repeatable options flag.
"""

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")

def _impl(ctx):
    return [
        BuildSettingInfo(value = ctx.build_setting_value),
    ]

extra_options_flag = rule(
    implementation = _impl,
    build_setting = config.string_list(
        flag = True,
        repeatable = True,
    ),
)
