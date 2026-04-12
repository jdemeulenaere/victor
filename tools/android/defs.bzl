"""Project Android rule wrappers with repo defaults."""

load(
    "@rules_android//rules:rules.bzl",
    _android_binary = "android_binary",
    _android_local_test = "android_local_test",
)

_DEFAULT_DEBUG_SIGNING_KEYS = ["//signing/android/debug:debug.keystore"]
_DEFAULT_MIN_SDK_VERSION = "23"
_DEFAULT_TARGET_SDK_VERSION = "36"

def _with_default_manifest_values(manifest_values):
    values = {
        "minSdkVersion": _DEFAULT_MIN_SDK_VERSION,
        "targetSdkVersion": _DEFAULT_TARGET_SDK_VERSION,
    }
    if manifest_values != None:
        values.update(manifest_values)
    return values

def android_binary(name, debug_signing_keys = None, manifest_values = None, **kwargs):
    """android_binary with repo-wide debug signing key and manifest SDK defaults."""
    if debug_signing_keys == None:
        debug_signing_keys = _DEFAULT_DEBUG_SIGNING_KEYS
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
