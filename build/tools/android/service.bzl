"""Android service endpoint build settings."""

AndroidStringFlagInfo = provider(fields = ["value"])

def _string_flag_impl(ctx):
    return [AndroidStringFlagInfo(value = ctx.build_setting_value)]

_service_url_profile = rule(
    implementation = _string_flag_impl,
    build_setting = config.string(flag = True),
)

_deploy_service_url = rule(
    implementation = _string_flag_impl,
    build_setting = config.string(flag = True),
)

def android_service_url_settings():
    """Declares Android service URL build settings in the current package."""
    _service_url_profile(
        name = "android_service_url_profile",
        build_setting_default = "local",
        visibility = ["//visibility:public"],
    )

    native.config_setting(
        name = "android_service_url_profile_deploy",
        flag_values = {
            ":android_service_url_profile": "deploy",
        },
        visibility = ["//visibility:public"],
    )

    _deploy_service_url(
        name = "android_deploy_service_url",
        build_setting_default = "",
        visibility = ["//visibility:public"],
    )
