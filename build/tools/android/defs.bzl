"""Project Android rule wrappers with repo defaults."""

load(
    "@rules_android//rules:rules.bzl",
    _android_binary = "android_binary",
    _android_local_test = "android_local_test",
)

_DEFAULT_DEBUG_SIGNING_KEYS = ["//build/signing/android/debug:debug.keystore"]
_DEFAULT_MIN_SDK_VERSION = "23"
_DEFAULT_PROGUARD_SPECS = ["//build/tools/android:proguard-rules.pro"]
_DEFAULT_TARGET_SDK_VERSION = "36"
_DEFAULT_VERSION_CODE = "1"
_DEFAULT_VERSION_NAME = "1"
_OPT_COMPILATION_MODE = "//build/tools/android:compilation_mode_opt"

def _select_for_opt(opt_value, default_value):
    return select({
        _OPT_COMPILATION_MODE: opt_value,
        "//conditions:default": default_value,
    })

def _with_default_manifest_values(manifest_values):
    values = {
        "minSdkVersion": _DEFAULT_MIN_SDK_VERSION,
        "targetSdkVersion": _DEFAULT_TARGET_SDK_VERSION,
        "versionCode": _DEFAULT_VERSION_CODE,
        "versionName": _DEFAULT_VERSION_NAME,
    }
    if manifest_values != None:
        values.update(manifest_values)
    return values

def android_binary(name, debug_signing_keys = None, manifest_values = None, proguard_specs = None, **kwargs):
    """android_binary with repo-wide defaults and -c opt-only shrinking."""
    if debug_signing_keys == None:
        debug_signing_keys = _DEFAULT_DEBUG_SIGNING_KEYS
    if proguard_specs == None:
        proguard_specs = _DEFAULT_PROGUARD_SPECS
    if type(proguard_specs) == "select" or proguard_specs:
        if "shrink_resources" in kwargs:
            fail("android_binary cannot set both proguard_specs and shrink_resources")
        kwargs["proguard_specs"] = _select_for_opt(proguard_specs, [])
        kwargs["shrink_resources"] = _select_for_opt(1, 0)
    _android_binary(
        name = name,
        debug_signing_keys = debug_signing_keys,
        manifest_values = _with_default_manifest_values(manifest_values),
        **kwargs
    )

def android_local_test(name, **kwargs):
    """Pass-through for android_local_test for a single import surface."""
    _android_local_test(
        name = name,
        **kwargs
    )
