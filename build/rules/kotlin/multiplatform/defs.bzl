"""Macros and wrappers for Kotlin expect/actual multiplatform libraries."""

load(
    "@rules_android//providers:providers.bzl",
    "AndroidCcLinkParamsInfo",
    "AndroidIdeInfo",
    "AndroidIdlInfo",
    "AndroidLibraryAarInfo",
    "AndroidLibraryResourceClassJarProvider",
    "AndroidLintRulesInfo",
    "AndroidNativeLibsInfo",
    "BaselineProfileProvider",
    "DataBindingV2Info",
    "StarlarkAndroidResourcesInfo",
)
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load("@rules_java//java:defs.bzl", "JavaInfo")
load("@rules_java//java/common:proguard_spec_info.bzl", "ProguardSpecInfo")
load("@rules_kotlin//kotlin:android.bzl", _kt_android_library = "kt_android_library")
load("@rules_kotlin//kotlin:core.bzl", "kt_kotlinc_options")
load("@rules_kotlin//kotlin:jvm.bzl", _kt_jvm_binary = "kt_jvm_binary", _kt_jvm_library = "kt_jvm_library", _kt_jvm_test = "kt_jvm_test")
load("@rules_kotlin//kotlin/internal:defs.bzl", "KtJvmInfo")
load("@third_party_maven_kmp_variants//:variants.bzl", "KMP_MAVEN_VARIANTS", "KOTLIN_STDLIB_WASM_LABEL")
load("//build/rules/backend:providers.bzl", "BackendEndpointConfigInfo")
load("//build/rules/kotlin/multiplatform:wasm.bzl", "KtWasmInfo", "kt_wasm_files", "kt_wasm_imports", "kt_wasm_library")

_SUPPORTED_PLATFORMS = ["android", "jvm", "wasm"]
_KMP_VARIANTS = ["jvm", "android", "wasm", "wasm_imports", "ios"]
_KMP_VARIANT_SETTING = "//build/rules/kotlin/multiplatform/config:kmp_variant"
_THIRD_PARTY_MAVEN_PREFIX = "@third_party_maven//:"

def _kmp_variant_impl(ctx):
    variant = ctx.build_setting_value
    if variant not in _KMP_VARIANTS:
        fail("Unsupported KMP variant '{}'. Expected one of: {}".format(variant, ", ".join(_KMP_VARIANTS)))
    return []

kmp_variant = rule(
    implementation = _kmp_variant_impl,
    build_setting = config.string(flag = True),
)

def _kmp_variant_transition_impl(settings, attr):
    return {_KMP_VARIANT_SETTING: attr.variant}

_kmp_variant_transition = transition(
    implementation = _kmp_variant_transition_impl,
    inputs = [],
    outputs = [_KMP_VARIANT_SETTING],
)

_FORWARDED_PROVIDER_TYPES = [
    AndroidCcLinkParamsInfo,
    AndroidIdlInfo,
    AndroidIdeInfo,
    AndroidLibraryAarInfo,
    AndroidLibraryResourceClassJarProvider,
    AndroidLintRulesInfo,
    AndroidNativeLibsInfo,
    BackendEndpointConfigInfo,
    BaselineProfileProvider,
    DataBindingV2Info,
    JavaInfo,
    KtJvmInfo,
    KtWasmInfo,
    ProguardSpecInfo,
    StarlarkAndroidResourcesInfo,
]

def _single_actual(actual):
    if type(actual) == "list":
        if len(actual) != 1:
            fail("expected one KMP dependency target, found {}".format(len(actual)))
        actual = actual[0]
    return actual

def _kmp_transitioned_dep_impl(ctx):
    actual = _single_actual(ctx.attr.deps)
    providers = [actual[DefaultInfo]]
    for provider_type in _FORWARDED_PROVIDER_TYPES:
        if provider_type in actual:
            providers.append(actual[provider_type])
    if CcInfo in actual:
        providers.append(actual[CcInfo])
    if InstrumentedFilesInfo in actual:
        providers.append(actual[InstrumentedFilesInfo])
    if OutputGroupInfo in actual:
        providers.append(actual[OutputGroupInfo])
    return providers

def _function_transition_allowlist_attr():
    return attr.label(default = Label("@bazel_tools//tools/allowlists/function_transition_allowlist"))

def _transition_attrs():
    return {
        "deps": attr.label_list(
            cfg = _kmp_variant_transition,
            mandatory = True,
        ),
        "variant": attr.string(mandatory = True),
        "_allowlist_function_transition": _function_transition_allowlist_attr(),
    }

_kmp_transitioned_dep = rule(
    implementation = _kmp_transitioned_dep_impl,
    attrs = _transition_attrs(),
)

def _shell_quote(value):
    return "'" + value.replace("'", "'\\''") + "'"

def _forward_executable_script(executable, forward_args, chdir):
    quoted_args = " ".join([_shell_quote(arg) for arg in forward_args])
    chdir_lines = []
    if chdir:
        chdir_lines = [
            'if [[ -d "$main_runfiles" ]]; then',
            '  cd "$main_runfiles"',
            "fi",
        ]
    return "\n".join([
        "#!/usr/bin/env bash",
        "set -euo pipefail",
        'runfiles_dir="${RUNFILES_DIR:-}"',
        'if [[ -z "$runfiles_dir" ]]; then',
        '  runfiles_dir="$0.runfiles"',
        "fi",
        'main_runfiles="$runfiles_dir/_main"',
    ] + chdir_lines + [
        'if [[ -x "$main_runfiles/{}" ]]; then'.format(executable.short_path),
        '  exec "$main_runfiles/{}" {} "$@"'.format(executable.short_path, quoted_args),
        "fi",
        'if [[ -x "{}" ]]; then'.format(executable.path),
        '  exec "{}" {} "$@"'.format(executable.path, quoted_args),
        "fi",
        'echo "Unable to locate transitioned executable {}" >&2'.format(executable.short_path),
        "exit 1",
        "",
    ])

def _transitioned_executable_providers(ctx):
    actual = _single_actual(ctx.attr.actual)
    default = actual[DefaultInfo]
    executable = default.files_to_run.executable
    if executable == None:
        fail("{} is not executable".format(ctx.attr.actual.label))

    output = ctx.actions.declare_file(ctx.label.name)
    ctx.actions.write(
        output = output,
        content = _forward_executable_script(executable, ctx.attr.forward_args, ctx.attr.chdir),
        is_executable = True,
    )

    runfiles = ctx.runfiles(files = [executable])
    runfiles = runfiles.merge(default.default_runfiles)
    runfiles = runfiles.merge(default.data_runfiles)
    return [DefaultInfo(executable = output, runfiles = runfiles)]

def _kmp_transitioned_binary_impl(ctx):
    return _transitioned_executable_providers(ctx)

def _transitioned_executable_attrs():
    return {
        "actual": attr.label(
            cfg = _kmp_variant_transition,
            executable = True,
            mandatory = True,
        ),
        "chdir": attr.string(),
        "forward_args": attr.string_list(),
        "variant": attr.string(mandatory = True),
        "_allowlist_function_transition": _function_transition_allowlist_attr(),
    }

_kmp_transitioned_binary = rule(
    implementation = _kmp_transitioned_binary_impl,
    attrs = _transitioned_executable_attrs(),
    executable = True,
)

def _kmp_transitioned_test_impl(ctx):
    return _transitioned_executable_providers(ctx)

_kmp_transitioned_test = rule(
    implementation = _kmp_transitioned_test_impl,
    attrs = _transitioned_executable_attrs(),
    test = True,
)

def _normalize_same_package_srcs(srcs, attr_name):
    normalized = []
    for src in srcs:
        if not type(src) == "string":
            fail("{} values must be strings, got {}".format(attr_name, type(src)))
        if src.startswith("//") or src.startswith("@"):
            fail("{} must reference files in the current package: {}".format(attr_name, src))
        normalized.append(src[1:] if src.startswith(":") else src)
    return normalized

def _fragment_sources_flags(fragment_name, srcs):
    package_name = native.package_name()
    if package_name:
        return ["{}:{}/{}".format(fragment_name, package_name, src) for src in srcs]
    return ["{}:{}".format(fragment_name, src) for src in srcs]

def _resolve_dep_for_variant(dep, suffix):
    if dep.startswith(_THIRD_PARTY_MAVEN_PREFIX):
        variants = KMP_MAVEN_VARIANTS.get(dep)
        if variants:
            variant = variants.get(suffix)
            if variant:
                return variant
        if suffix == "wasm":
            fail("No Kotlin/WASM Maven variant found for {}".format(dep))
        return dep

    # Other external repositories are generally regular platform-neutral deps and should not be remapped.
    if dep.startswith("@"):
        return dep

    return dep

def _label_string(name):
    package_name = native.package_name()
    if package_name:
        return "//{}:{}".format(package_name, name)
    return "//:{}".format(name)

def _kmp_variant_condition(variant):
    return "//build/rules/kotlin/multiplatform/config:kmp_variant_{}".format(variant)

def _private_target_name(name, suffix):
    return "{}__{}".format(name, suffix)

def _normalize_dep_list(values, attr_name):
    if values == None:
        return []
    if not type(values) == "list":
        fail("{} must be a list of label strings".format(attr_name))
    normalized = []
    for value in values:
        if not type(value) == "string":
            fail("{} values must be strings, got {}".format(attr_name, type(value)))
        normalized.append(value)
    return normalized

def _normalize_tag_list(values):
    if values == None:
        return []
    if not type(values) == "list":
        fail("tags must be a list of strings")
    normalized = []
    for value in values:
        if not type(value) == "string":
            fail("tags values must be strings, got {}".format(type(value)))
        normalized.append(value)
    return normalized

def _platform_opts_name(name, platform_suffix):
    return "{}__{}_kmp_opts".format(name, platform_suffix)

def _normalize_platforms(platforms):
    if not type(platforms) == "list":
        fail("platforms must be a list containing any of: {}".format(", ".join(_SUPPORTED_PLATFORMS)))
    if not platforms:
        fail("kt_multiplatform_library requires at least one platform")

    seen = {}
    normalized = []
    for platform in platforms:
        if not type(platform) == "string":
            fail("platforms values must be strings, got {}".format(type(platform)))
        if platform not in _SUPPORTED_PLATFORMS:
            fail("Unsupported platform '{}'. Expected one of: {}".format(platform, ", ".join(_SUPPORTED_PLATFORMS)))
        if seen.get(platform):
            fail("Duplicate platform '{}'".format(platform))
        seen[platform] = True
        normalized.append(platform)
    return normalized

def _has_platform(platforms, platform):
    return platform in platforms

def _variant_platform(variant):
    return "wasm" if variant == "wasm_imports" else variant

def _selected_variant_target(name, variant):
    if variant == "wasm_imports":
        return ":{}".format(_private_target_name(name, "wasm_imports"))
    return ":{}".format(_private_target_name(name, variant))

def _define_public_alias(name, selected_platforms, visibility):
    native.alias(
        name = name,
        actual = select(
            {
                _kmp_variant_condition(variant): _selected_variant_target(name, variant)
                for variant in _KMP_VARIANTS
                if _variant_platform(variant) in selected_platforms
            },
            no_match_error = "KMP target {} does not provide the selected variant. Available platforms: {}".format(
                _label_string(name),
                ", ".join(selected_platforms),
            ),
        ),
        visibility = visibility,
    )

def kmp_variant_forward(name, actual, variant, visibility = None, **kwargs):
    _kmp_transitioned_dep(
        name = name,
        deps = [actual],
        variant = variant,
        visibility = visibility,
        **kwargs
    )

def kmp_variant_binary(name, actual, variant, visibility = None, **kwargs):
    _kmp_transitioned_binary(
        name = name,
        actual = actual,
        variant = variant,
        visibility = visibility,
        **kwargs
    )

def kmp_variant_test(name, actual, variant, visibility = None, **kwargs):
    _kmp_transitioned_test(
        name = name,
        actual = actual,
        variant = variant,
        visibility = visibility,
        **kwargs
    )

def _impl_target_name(name):
    return "{}__impl".format(name)

def _set_optional_attr(kwargs, attr_name, value):
    if value != None:
        kwargs[attr_name] = value

def _mark_manual(kwargs):
    tags = kwargs.get("tags")
    if tags == None:
        kwargs["tags"] = ["manual"]
    elif "manual" not in tags:
        kwargs["tags"] = tags + ["manual"]

def _public_common_kwargs(kwargs):
    public_kwargs = {}
    for attr_name in [
        "compatible_with",
        "deprecation",
        "exec_compatible_with",
        "features",
        "restricted_to",
        "tags",
        "target_compatible_with",
        "testonly",
    ]:
        value = kwargs.get(attr_name)
        if value != None:
            public_kwargs[attr_name] = value
    return public_kwargs

def _define_platform_opts(name, platform_suffix, platform_fragment, common_srcs, platform_srcs):
    kt_kotlinc_options(
        name = _platform_opts_name(name, platform_suffix),
        x_expect_actual_classes = True,
        x_fragment_refines = ["{}:commonMain".format(platform_fragment)],
        x_fragment_sources = _fragment_sources_flags(platform_fragment, platform_srcs) + _fragment_sources_flags("commonMain", common_srcs),
        x_fragments = [platform_fragment, "commonMain"],
        x_multi_platform = True,
    )

def _define_transitioned_rule(
        name,
        rule_fn,
        forward_fn,
        variant,
        visibility,
        kwargs,
        deps = None,
        exports = None,
        runtime_deps = None):
    public_kwargs = _public_common_kwargs(kwargs)
    _set_optional_attr(kwargs, "deps", deps)
    _set_optional_attr(kwargs, "exports", exports)
    _set_optional_attr(kwargs, "runtime_deps", runtime_deps)
    _mark_manual(kwargs)

    impl = _impl_target_name(name)
    rule_fn(
        name = impl,
        visibility = ["//visibility:private"],
        **kwargs
    )
    forward_fn(
        name = name,
        actual = ":{}".format(impl),
        variant = variant,
        visibility = visibility,
        **public_kwargs
    )

def kt_jvm_library(name, deps = None, exports = None, runtime_deps = None, visibility = None, **kwargs):
    """kt_jvm_library wrapper that resolves public KMP deps to JVM variants."""
    _define_transitioned_rule(
        name = name,
        rule_fn = _kt_jvm_library,
        forward_fn = kmp_variant_forward,
        variant = "jvm",
        visibility = visibility,
        kwargs = kwargs,
        deps = deps,
        exports = exports,
        runtime_deps = runtime_deps,
    )

def kt_jvm_test(name, deps = None, runtime_deps = None, visibility = None, **kwargs):
    """kt_jvm_test wrapper that resolves public KMP deps to JVM variants."""
    _define_transitioned_rule(
        name = name,
        rule_fn = _kt_jvm_test,
        forward_fn = kmp_variant_test,
        variant = "jvm",
        visibility = visibility,
        kwargs = kwargs,
        deps = deps,
        runtime_deps = runtime_deps,
    )

def kt_jvm_binary(name, deps = None, runtime_deps = None, visibility = None, **kwargs):
    """kt_jvm_binary wrapper that resolves public KMP deps to JVM variants."""
    _define_transitioned_rule(
        name = name,
        rule_fn = _kt_jvm_binary,
        forward_fn = kmp_variant_binary,
        variant = "jvm",
        visibility = visibility,
        kwargs = kwargs,
        deps = deps,
        runtime_deps = runtime_deps,
    )

def kt_android_library(name, deps = None, exports = None, visibility = None, **kwargs):
    """kt_android_library wrapper that resolves public KMP deps to Android variants."""
    _define_transitioned_rule(
        name = name,
        rule_fn = _kt_android_library,
        forward_fn = kmp_variant_forward,
        variant = "android",
        visibility = visibility,
        kwargs = kwargs,
        deps = deps,
        exports = exports,
    )

def kt_multiplatform_library(
        name,
        srcs,
        platforms,
        deps = None,
        plugins = None,
        android_manifest = None,
        android_custom_package = None,
        tags = None,
        visibility = None):
    """Creates a Kotlin Multiplatform-style library with one public label.

    This macro follows the Kotlin Gradle plugin model for platform compilations:
    - each platform target compiles common + platform sources together
    - Kotlin fragment flags model source-set relations (`commonMain` refined by each platform source set)
    - `:<name>` selects the correct private implementation target for the consumer's KMP variant

    Args:
    - platforms: required list containing any of `android`, `jvm`, `wasm`.
    - srcs: required dictionary with keys `common`, `jvm`, `android`, `wasm`.
    - deps: optional dictionary with keys:
      - `common`: deps added to all selected platform targets. `@third_party_maven` Kotlin Multiplatform
        labels are resolved through Gradle Module Metadata when available; other external labels are used as-is.
        first-party KMP labels are selected through the public target's KMP variant.
      - `jvm`: regular deps for the JVM target only.
      - `android`: regular deps for the Android target only.
      - `wasm`: KLIB deps for the WASM target only.
    - plugins: optional list of compiler plugins applied to all selected platform targets.
    - tags: optional list of tags applied to all selected platform targets.
    """
    selected_platforms = _normalize_platforms(platforms)
    if deps == None:
        deps = {}
    if not type(deps) == "dict":
        fail("deps must be a dict with keys common/android/jvm/wasm")
    for key in deps.keys():
        if key not in ["common", "android", "jvm", "wasm"]:
            fail("Unsupported deps key '{}'. Expected one of: common, android, jvm, wasm".format(key))

    normalized_plugins = _normalize_dep_list(plugins, "plugins")

    if not type(srcs) == "dict":
        fail("srcs must be a dict with keys common/android/jvm/wasm")
    for key in srcs.keys():
        if key not in ["common", "android", "jvm", "wasm"]:
            fail("Unsupported srcs key '{}'. Expected one of: common, android, jvm, wasm".format(key))

    common = _normalize_same_package_srcs(srcs.get("common", []), "common_srcs")
    android = _normalize_same_package_srcs(srcs.get("android", []), "android_srcs")
    jvm = _normalize_same_package_srcs(srcs.get("jvm", []), "jvm_srcs")
    wasm = _normalize_same_package_srcs(srcs.get("wasm", []), "wasm_srcs")

    if not common:
        fail("kt_multiplatform_library requires non-empty common_srcs")

    common_deps = _normalize_dep_list(deps.get("common"), "deps[\"common\"]")
    android_deps = _normalize_dep_list(deps.get("android"), "deps[\"android\"]")
    jvm_deps = _normalize_dep_list(deps.get("jvm"), "deps[\"jvm\"]")
    wasm_deps = _normalize_dep_list(deps.get("wasm"), "deps[\"wasm\"]")
    user_tags = _normalize_tag_list(tags)

    if _has_platform(selected_platforms, "jvm"):
        common_jvm_deps = [_resolve_dep_for_variant(dep, "jvm") for dep in common_deps]
        _define_platform_opts(
            name = name,
            platform_suffix = "jvm",
            platform_fragment = "jvmMain",
            common_srcs = common,
            platform_srcs = jvm,
        )
        _kt_jvm_library(
            name = _private_target_name(name, "jvm"),
            srcs = common + jvm,
            kotlinc_opts = ":{}".format(_platform_opts_name(name, "jvm")),
            plugins = normalized_plugins,
            tags = user_tags,
            visibility = ["//visibility:private"],
            deps = common_jvm_deps + jvm_deps,
        )

    if _has_platform(selected_platforms, "android"):
        common_android_deps = [_resolve_dep_for_variant(dep, "android") for dep in common_deps]
        _define_platform_opts(
            name = name,
            platform_suffix = "android",
            platform_fragment = "androidMain",
            common_srcs = common,
            platform_srcs = android,
        )

        android_kwargs = dict(
            name = _private_target_name(name, "android"),
            srcs = common + android,
            kotlinc_opts = ":{}".format(_platform_opts_name(name, "android")),
            plugins = normalized_plugins,
            tags = user_tags,
            visibility = ["//visibility:private"],
            deps = common_android_deps + android_deps,
        )
        if android_manifest:
            android_kwargs["manifest"] = android_manifest
        if android_custom_package:
            android_kwargs["custom_package"] = android_custom_package
        _kt_android_library(**android_kwargs)

    if _has_platform(selected_platforms, "wasm"):
        common_wasm_deps = [_resolve_dep_for_variant(dep, "wasm") for dep in common_deps]
        kt_wasm_library(
            name = _private_target_name(name, "wasm"),
            common_srcs = common,
            deps = common_wasm_deps + wasm_deps + [KOTLIN_STDLIB_WASM_LABEL],
            module_name = name,
            platform_srcs = wasm,
            plugins = normalized_plugins,
            tags = user_tags,
            visibility = ["//visibility:private"],
        )
        kt_wasm_files(
            name = _private_target_name(name, "wasm_files"),
            module = ":{}".format(_private_target_name(name, "wasm")),
            module_name = name,
            visibility = ["//visibility:private"],
        )
        kt_wasm_imports(
            name = _private_target_name(name, "wasm_imports"),
            files = ":{}".format(_private_target_name(name, "wasm_files")),
            out = name,
            visibility = ["//visibility:private"],
        )

    _define_public_alias(name, selected_platforms, visibility)
