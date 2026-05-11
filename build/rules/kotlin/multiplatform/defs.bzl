"""Public Kotlin Multiplatform rules and repository wrappers."""

load("@build_bazel_rules_apple//apple:apple.bzl", "apple_dynamic_framework_import")
load("@build_bazel_rules_swift//swift:providers.bzl", "SwiftInfo")
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
load("//build/rules/kotlin/multiplatform:ios.bzl", "kt_ios_framework_files")
load("//build/rules/kotlin/multiplatform:wasm.bzl", "KtWasmInfo", "kt_wasm_files", "kt_wasm_imports", "kt_wasm_library")

_ARTIFACT_LIBRARY = "library"
_ARTIFACT_WEB_IMPORTS = "web_imports"
_KMP_ARTIFACTS = [_ARTIFACT_LIBRARY, _ARTIFACT_WEB_IMPORTS]
_KMP_ARTIFACT_SETTING = "//build/rules/kotlin/multiplatform/config:kmp_artifact"
_KMP_PLATFORM_SETTING = "//build/rules/kotlin/multiplatform/config:kmp_platform"
_THIRD_PARTY_MAVEN_PREFIX = "@third_party_maven//:"

_KMP_TARGETS = [
    "android",
    "iosArm64",
    "iosSimulatorArm64",
    "iosX64",
    "jsBrowser",
    "jsNode",
    "jvm",
    "linuxX64",
    "macosArm64",
    "macosX64",
    "mingwX64",
    "wasmJs",
]

_APPLE_FRAMEWORK_TARGETS = {
    "iosArm64": "ios_arm64",
    "iosSimulatorArm64": "ios_simulator_arm64",
    "iosX64": "ios_x64",
    "macosArm64": "macos_arm64",
    "macosX64": "macos_x64",
}

_TARGET_SOURCE_SET_FALLBACKS = {
    "iosArm64": ["ios"],
    "iosSimulatorArm64": ["ios"],
    "iosX64": ["ios"],
    "jsBrowser": ["js"],
    "jsNode": ["js"],
    "linuxX64": ["linux"],
    "macosArm64": ["macos"],
    "macosX64": ["macos"],
    "mingwX64": ["mingw"],
}

_IOS_OR_MACOS_TARGET_COMPATIBLE_WITH = select({
    "@platforms//os:ios": [],
    "@platforms//os:macos": [],
    "//conditions:default": ["@platforms//:incompatible"],
})

def _kmp_platform_impl(ctx):
    platform = ctx.build_setting_value
    if platform not in _KMP_TARGETS:
        fail("Unsupported KMP platform '{}'. Expected one of: {}".format(platform, ", ".join(_KMP_TARGETS)))
    return []

kmp_platform = rule(
    implementation = _kmp_platform_impl,
    build_setting = config.string(flag = True),
)

def _kmp_artifact_impl(ctx):
    artifact = ctx.build_setting_value
    if artifact not in _KMP_ARTIFACTS:
        fail("Unsupported KMP artifact '{}'. Expected one of: {}".format(artifact, ", ".join(_KMP_ARTIFACTS)))
    return []

kmp_artifact = rule(
    implementation = _kmp_artifact_impl,
    build_setting = config.string(flag = True),
)

def _kmp_transition_impl(settings, attr):
    return {
        _KMP_ARTIFACT_SETTING: attr.artifact,
        _KMP_PLATFORM_SETTING: attr.platform,
    }

_kmp_transition = transition(
    implementation = _kmp_transition_impl,
    inputs = [],
    outputs = [_KMP_ARTIFACT_SETTING, _KMP_PLATFORM_SETTING],
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
    SwiftInfo,
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
        "artifact": attr.string(default = _ARTIFACT_LIBRARY),
        "deps": attr.label_list(
            cfg = _kmp_transition,
            mandatory = True,
        ),
        "platform": attr.string(mandatory = True),
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

def _transitioned_executable_attrs():
    return {
        "actual": attr.label(
            cfg = _kmp_transition,
            executable = True,
            mandatory = True,
        ),
        "artifact": attr.string(default = _ARTIFACT_LIBRARY),
        "chdir": attr.string(),
        "forward_args": attr.string_list(),
        "platform": attr.string(mandatory = True),
        "_allowlist_function_transition": _function_transition_allowlist_attr(),
    }

_kmp_transitioned_binary = rule(
    implementation = _transitioned_executable_providers,
    attrs = _transitioned_executable_attrs(),
    executable = True,
)

_kmp_transitioned_test = rule(
    implementation = _transitioned_executable_providers,
    attrs = _transitioned_executable_attrs(),
    test = True,
)

def _normalize_same_package_srcs(srcs, attr_name):
    normalized = []
    for src in srcs or []:
        if not type(src) == "string":
            fail("{} values must be strings, got {}".format(attr_name, type(src)))
        if src.startswith("//") or src.startswith("@"):
            fail("{} must reference files in the current package: {}".format(attr_name, src))
        normalized.append(src[1:] if src.startswith(":") else src)
    return normalized

def _repo_source_path(src):
    package_name = native.package_name()
    if package_name:
        return "{}/{}".format(package_name, src)
    return src

def _normalize_string_list(values, attr_name, list_description):
    if values == None:
        return []
    if not type(values) == "list":
        fail("{} must be a list of {}".format(attr_name, list_description))
    normalized = []
    for value in values:
        if not type(value) == "string":
            fail("{} values must be strings, got {}".format(attr_name, type(value)))
        normalized.append(value)
    return normalized

def _normalize_dep_list(values, attr_name):
    return _normalize_string_list(values, attr_name, "label strings")

def _normalize_name_list(values, attr_name):
    return _normalize_string_list(values, attr_name, "strings")

def _normalize_tag_list(values):
    return _normalize_name_list(values, "tags")

def _dedupe(values):
    seen = {}
    result = []
    for value in values:
        if seen.get(value):
            continue
        seen[value] = True
        result.append(value)
    return result

def _maven_variant_keys(platform):
    if platform == "wasmJs":
        return ["wasmJs", "wasm"]
    if platform == "iosSimulatorArm64":
        return [platform, "ios"]
    if platform in _APPLE_FRAMEWORK_TARGETS:
        return [platform]
    if platform in ["jsBrowser", "jsNode"]:
        return [platform, "js"]
    return [platform]

def _resolve_dep_for_platform(dep, platform):
    if dep.startswith(_THIRD_PARTY_MAVEN_PREFIX):
        variants = KMP_MAVEN_VARIANTS.get(dep)
        if variants:
            for key in _maven_variant_keys(platform):
                variant = variants.get(key)
                if variant:
                    return variant
        if platform in ["jvm", "android"]:
            return dep
        fail("No Kotlin/{} Maven variant found for {}".format(platform, dep))

    return dep

def _label_string(name):
    package_name = native.package_name()
    if package_name:
        return "//{}:{}".format(package_name, name)
    return "//:{}".format(name)

def _config_setting_name(platform, artifact = _ARTIFACT_LIBRARY):
    return "kmp_{}_{}".format(platform, artifact)

def _config_condition(platform, artifact = _ARTIFACT_LIBRARY):
    return "//build/rules/kotlin/multiplatform/config:{}".format(_config_setting_name(platform, artifact))

def _private_target_name(name, suffix):
    return "{}__{}".format(name, suffix)

def _impl_target_name(name):
    return "{}__impl".format(name)

def _platform_opts_name(name, target_id):
    return "{}__{}_kmp_opts".format(name, target_id)

def _set_optional_attr(kwargs, attr_name, value):
    if value != None:
        kwargs[attr_name] = value

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

def _transitioned_label_list(owner_name, labels, platform, artifact, attr_name, testonly = None):
    if labels == None:
        return None
    if type(labels) != "list":
        return labels

    transitioned = []
    for index, label in enumerate(labels):
        dep_name = "{}__{}_{}_{}_forward".format(owner_name, attr_name, platform, index)
        transition_kwargs = {}
        if testonly != None:
            transition_kwargs["testonly"] = testonly
        kmp_platform_forward(
            name = dep_name,
            actual = label,
            artifact = artifact,
            platform = platform,
            visibility = ["//visibility:private"],
            **transition_kwargs
        )
        transitioned.append(":{}".format(dep_name))
    return transitioned

def kmp_platform_forward(name, actual, platform, artifact = _ARTIFACT_LIBRARY, visibility = None, **kwargs):
    _kmp_transitioned_dep(
        name = name,
        artifact = artifact,
        deps = [actual],
        platform = platform,
        visibility = visibility,
        **kwargs
    )

def kmp_platform_binary(name, actual, platform, artifact = _ARTIFACT_LIBRARY, visibility = None, **kwargs):
    _kmp_transitioned_binary(
        name = name,
        actual = actual,
        artifact = artifact,
        platform = platform,
        visibility = visibility,
        **kwargs
    )

def kmp_platform_test(name, actual, platform, artifact = _ARTIFACT_LIBRARY, visibility = None, **kwargs):
    _kmp_transitioned_test(
        name = name,
        actual = actual,
        artifact = artifact,
        platform = platform,
        visibility = visibility,
        **kwargs
    )

def _define_transitioned_rule(
        name,
        rule_fn,
        forward_fn,
        platform,
        visibility,
        kwargs,
        deps = None,
        exports = None,
        runtime_deps = None):
    public_kwargs = _public_common_kwargs(kwargs)
    testonly = kwargs.get("testonly")
    _set_optional_attr(kwargs, "deps", _transitioned_label_list(name, deps, platform, _ARTIFACT_LIBRARY, "deps", testonly))
    _set_optional_attr(kwargs, "exports", _transitioned_label_list(name, exports, platform, _ARTIFACT_LIBRARY, "exports", testonly))
    _set_optional_attr(kwargs, "runtime_deps", _transitioned_label_list(name, runtime_deps, platform, _ARTIFACT_LIBRARY, "runtime_deps", testonly))

    impl = _impl_target_name(name)
    rule_fn(
        name = impl,
        visibility = ["//visibility:private"],
        **kwargs
    )
    forward_fn(
        name = name,
        actual = ":{}".format(impl),
        platform = platform,
        visibility = visibility,
        **public_kwargs
    )

def kt_jvm_library(name, deps = None, exports = None, runtime_deps = None, visibility = None, **kwargs):
    """kt_jvm_library wrapper that resolves public KMP deps to JVM artifacts."""
    _define_transitioned_rule(
        name = name,
        rule_fn = _kt_jvm_library,
        forward_fn = kmp_platform_forward,
        platform = "jvm",
        visibility = visibility,
        kwargs = kwargs,
        deps = deps,
        exports = exports,
        runtime_deps = runtime_deps,
    )

def kt_jvm_test(name, deps = None, runtime_deps = None, visibility = None, **kwargs):
    """kt_jvm_test wrapper that resolves public KMP deps to JVM artifacts."""
    _define_transitioned_rule(
        name = name,
        rule_fn = _kt_jvm_test,
        forward_fn = kmp_platform_test,
        platform = "jvm",
        visibility = visibility,
        kwargs = kwargs,
        deps = deps,
        runtime_deps = runtime_deps,
    )

def kt_jvm_binary(name, deps = None, runtime_deps = None, visibility = None, **kwargs):
    """kt_jvm_binary wrapper that resolves public KMP deps to JVM artifacts."""
    _define_transitioned_rule(
        name = name,
        rule_fn = _kt_jvm_binary,
        forward_fn = kmp_platform_binary,
        platform = "jvm",
        visibility = visibility,
        kwargs = kwargs,
        deps = deps,
        runtime_deps = runtime_deps,
    )

def kt_android_library(name, deps = None, exports = None, visibility = None, **kwargs):
    """kt_android_library wrapper that resolves public KMP deps to Android artifacts."""
    _define_transitioned_rule(
        name = name,
        rule_fn = _kt_android_library,
        forward_fn = kmp_platform_forward,
        platform = "android",
        visibility = visibility,
        kwargs = kwargs,
        deps = deps,
        exports = exports,
    )

def kmp_source_set(srcs = None, deps = None, exports = None, runtime_deps = None, depends_on = None):
    """Declares one production Kotlin source set for kt_multiplatform_library."""
    return struct(
        kind = "kmp_source_set",
        depends_on = depends_on or [],
        deps = deps or [],
        exports = exports or [],
        runtime_deps = runtime_deps or [],
        srcs = srcs or [],
    )

def _optional_dict(value, attr_name):
    if value == None:
        return {}
    if type(value) != "dict":
        fail("{} must be a dict".format(attr_name))
    return value

def _source_set_names_from_maps(maps):
    seen = {}
    names = []
    for source_set_map in maps:
        for name in source_set_map.keys():
            if not type(name) == "string":
                fail("source set names must be strings, got {}".format(type(name)))
            if seen.get(name):
                continue
            seen[name] = True
            names.append(name)
    return names

def _with_helper_default_depends_on(name, depends_on, source_sets):
    depends_on = depends_on or []
    if name != "common" and "common" in source_sets and "common" not in depends_on:
        return ["common"] + depends_on
    return depends_on

def kmp_source_sets(srcs, deps = None, exports = None, runtime_deps = None, depends_on = None):
    """Builds kmp_source_set structs from source-set keyed attribute maps."""
    srcs = _optional_dict(srcs, "kmp_source_sets srcs")
    deps = _optional_dict(deps, "kmp_source_sets deps")
    exports = _optional_dict(exports, "kmp_source_sets exports")
    runtime_deps = _optional_dict(runtime_deps, "kmp_source_sets runtime_deps")
    depends_on = _optional_dict(depends_on, "kmp_source_sets depends_on")

    names = _source_set_names_from_maps([srcs, deps, exports, runtime_deps, depends_on])
    names_set = {
        name: True
        for name in names
    }

    source_sets = {}
    for name in names:
        source_sets[name] = kmp_source_set(
            depends_on = _with_helper_default_depends_on(name, depends_on.get(name), names_set),
            deps = deps.get(name),
            exports = exports.get(name),
            runtime_deps = runtime_deps.get(name),
            srcs = srcs.get(name),
        )
    return source_sets

def kmp_jvm(source_set = None):
    return struct(kind = "kmp_target", type = "jvm", source_set = source_set)

def kmp_android(source_set = None, namespace = None, manifest = None):
    return struct(
        kind = "kmp_target",
        manifest = manifest,
        namespace = namespace,
        source_set = source_set,
        type = "android",
    )

def kmp_wasm_js(source_set = None, module_name = None):
    return struct(
        kind = "kmp_target",
        module_name = module_name,
        source_set = source_set,
        type = "wasm_js",
    )

def kmp_apple_framework(source_set = None, module_name = None):
    return struct(
        kind = "kmp_target",
        module_name = module_name,
        source_set = source_set,
        type = "apple_framework",
    )

def kmp_js_browser(source_set = None, module_name = None):
    return struct(kind = "kmp_target", module_name = module_name, source_set = source_set, type = "js_browser")

def kmp_js_node(source_set = None, module_name = None):
    return struct(kind = "kmp_target", module_name = module_name, source_set = source_set, type = "js_node")

def kmp_targets(target_ids, android_namespace = None, android_manifest = None, apple_framework_module_name = None):
    """Builds common kt_multiplatform_library target structs from target IDs."""
    if type(target_ids) != "list":
        fail("kmp_targets target_ids must be a list")

    targets = {}
    has_android = False
    has_apple = False
    for target_id in target_ids:
        if not type(target_id) == "string":
            fail("KMP target IDs must be strings, got {}".format(type(target_id)))
        if targets.get(target_id):
            fail("Duplicate KMP target '{}'".format(target_id))
        if target_id == "jvm":
            targets[target_id] = kmp_jvm()
        elif target_id == "android":
            has_android = True
            targets[target_id] = kmp_android(
                manifest = android_manifest,
                namespace = android_namespace,
            )
        elif target_id == "wasmJs":
            targets[target_id] = kmp_wasm_js()
        elif target_id in _APPLE_FRAMEWORK_TARGETS:
            has_apple = True
            if not apple_framework_module_name:
                fail("kmp_targets with Apple target '{}' requires apple_framework_module_name".format(target_id))
            targets[target_id] = kmp_apple_framework(module_name = apple_framework_module_name)
        elif target_id == "jsBrowser":
            targets[target_id] = kmp_js_browser()
        elif target_id == "jsNode":
            targets[target_id] = kmp_js_node()
        elif target_id in ["linuxX64", "mingwX64"]:
            fail("KMP target '{}' is recognized, but this repository currently does not register a Kotlin/Native artifact rule for it".format(target_id))
        else:
            fail("Unsupported KMP target '{}'. Expected one of: {}".format(target_id, ", ".join(_KMP_TARGETS)))

    if android_namespace != None and not has_android:
        fail("kmp_targets android_namespace requires target 'android'")
    if android_manifest != None and not has_android:
        fail("kmp_targets android_manifest requires target 'android'")
    if apple_framework_module_name != None and not has_apple:
        fail("kmp_targets apple_framework_module_name requires an Apple framework target")
    return targets

def _normalize_source_sets(source_sets):
    if not type(source_sets) == "dict":
        fail("kt_multiplatform_library source_sets must be a dict")
    if not source_sets.get("common"):
        fail("kt_multiplatform_library requires a 'common' source set")

    normalized = {}
    for name, source_set in source_sets.items():
        if not type(name) == "string":
            fail("source set names must be strings, got {}".format(type(name)))
        if not hasattr(source_set, "kind") or source_set.kind != "kmp_source_set":
            fail("source_sets['{}'] must be created with kmp_source_set(...)".format(name))
        depends_on = _normalize_name_list(source_set.depends_on, "source_sets['{}'].depends_on".format(name))
        normalized[name] = struct(
            depends_on = depends_on,
            deps = _normalize_dep_list(source_set.deps, "source_sets['{}'].deps".format(name)),
            exports = _normalize_dep_list(source_set.exports, "source_sets['{}'].exports".format(name)),
            runtime_deps = _normalize_dep_list(source_set.runtime_deps, "source_sets['{}'].runtime_deps".format(name)),
            srcs = _normalize_same_package_srcs(source_set.srcs, "source_sets['{}'].srcs".format(name)),
        )

    for name, source_set in normalized.items():
        for parent in source_set.depends_on:
            if parent not in normalized:
                fail("source set '{}' depends on unknown source set '{}'".format(name, parent))

    _validate_no_source_set_cycles(normalized)
    return normalized

def _validate_no_source_set_cycles(source_sets):
    for start in source_sets.keys():
        visiting = {}
        visited = {}
        stack = [struct(name = start, path = [], state = "enter")]
        done = False
        for _ in range(10000):
            if not stack:
                done = True
                break
            frame = stack.pop()
            if frame.state == "exit":
                visiting[frame.name] = False
                visited[frame.name] = True
                continue
            if visited.get(frame.name):
                continue
            if visiting.get(frame.name):
                fail("Cycle in kt_multiplatform_library source_sets: {}".format(" -> ".join(frame.path + [frame.name])))
            visiting[frame.name] = True
            stack.append(struct(name = frame.name, path = frame.path, state = "exit"))
            for parent in source_sets[frame.name].depends_on:
                stack.append(struct(name = parent, path = frame.path + [frame.name], state = "enter"))
        if not done:
            fail("kt_multiplatform_library source_sets graph is too deep")

def _default_source_set_for_target(target_id, source_sets):
    candidates = [target_id] + _TARGET_SOURCE_SET_FALLBACKS.get(target_id, []) + ["common"]
    for candidate in candidates:
        if candidate in source_sets:
            return candidate
    return None

def _normalize_targets(targets, source_sets):
    if not type(targets) == "dict":
        fail("kt_multiplatform_library targets must be a dict")
    if not targets:
        fail("kt_multiplatform_library requires at least one target")

    normalized = {}
    for target_id, target in targets.items():
        if target_id not in _KMP_TARGETS:
            fail("Unsupported KMP target '{}'. Expected one of: {}".format(target_id, ", ".join(_KMP_TARGETS)))
        if not hasattr(target, "kind") or target.kind != "kmp_target":
            fail("targets['{}'] must be created with a kmp_* target helper".format(target_id))

        source_set = target.source_set
        if source_set == None:
            source_set = _default_source_set_for_target(target_id, source_sets)
        if source_set == None:
            fail("targets['{}'] must set source_set because no default source set exists".format(target_id))
        if source_set not in source_sets:
            fail("targets['{}'] references unknown source set '{}'".format(target_id, source_set))

        if target_id == "jvm" and target.type != "jvm":
            fail("target 'jvm' must use kmp_jvm(...)")
        if target_id == "android" and target.type != "android":
            fail("target 'android' must use kmp_android(...)")
        if target_id == "wasmJs" and target.type != "wasm_js":
            fail("target 'wasmJs' must use kmp_wasm_js(...)")
        if target_id in _APPLE_FRAMEWORK_TARGETS and target.type != "apple_framework":
            fail("target '{}' must use kmp_apple_framework(...)".format(target_id))
        if target_id == "jsBrowser" and target.type != "js_browser":
            fail("target 'jsBrowser' must use kmp_js_browser(...)")
        if target_id == "jsNode" and target.type != "js_node":
            fail("target 'jsNode' must use kmp_js_node(...)")
        if target_id in ["linuxX64", "mingwX64"]:
            fail("KMP target '{}' is recognized, but this repository currently does not register a Kotlin/Native artifact rule for it".format(target_id))

        normalized[target_id] = struct(
            manifest = target.manifest if hasattr(target, "manifest") else None,
            module_name = target.module_name if hasattr(target, "module_name") else None,
            namespace = target.namespace if hasattr(target, "namespace") else None,
            source_set = source_set,
            type = target.type,
        )

    return normalized

def _source_set_closure(source_sets, root):
    ordered = []
    seen = {}
    stack = [struct(expanded = False, name = root)]
    done = False
    for _ in range(10000):
        if not stack:
            done = True
            break
        frame = stack.pop()
        if frame.expanded:
            ordered.append(frame.name)
            continue
        if seen.get(frame.name):
            continue
        seen[frame.name] = True
        stack.append(struct(expanded = True, name = frame.name))
        for parent in reversed(source_sets[frame.name].depends_on):
            if not seen.get(parent):
                stack.append(struct(expanded = False, name = parent))
    if not done:
        fail("kt_multiplatform_library source_sets graph is too deep")
    return ordered

def _target_source_layout(source_sets, closure):
    srcs = []
    source_set_names = []
    fragment_sources = []
    for source_set in closure:
        for src in source_sets[source_set].srcs:
            srcs.append(src)
            source_set_names.append(source_set)
            fragment_sources.append("{}:{}".format(source_set, _repo_source_path(src)))
    return struct(
        fragment_sources = fragment_sources,
        source_set_names = source_set_names,
        srcs = srcs,
    )

def _target_fragment_refines(source_sets, closure):
    closure_set = {}
    for source_set in closure:
        closure_set[source_set] = True
    values = []
    for source_set in closure:
        for parent in source_sets[source_set].depends_on:
            if closure_set.get(parent):
                values.append("{}:{}".format(source_set, parent))
    return values

def _target_label_attr(source_sets, closure, attr_name, platform):
    labels = []
    for source_set in closure:
        labels.extend(getattr(source_sets[source_set], attr_name))
    return [_resolve_dep_for_platform(label, platform) for label in _dedupe(labels)]

def _define_platform_opts(name, target_id, closure, fragment_sources, fragment_refines):
    kt_kotlinc_options(
        name = _platform_opts_name(name, target_id),
        x_expect_actual_classes = True,
        x_fragment_refines = fragment_refines,
        x_fragment_sources = fragment_sources,
        x_fragments = closure,
        x_multi_platform = True,
    )

def _define_public_alias(name, target_specs, visibility):
    variants = {}
    for target_id, target in target_specs.items():
        if target.type == "wasm_js":
            variants[_config_condition(target_id, _ARTIFACT_LIBRARY)] = ":{}".format(_private_target_name(name, target_id))
            variants[_config_condition(target_id, _ARTIFACT_WEB_IMPORTS)] = ":{}".format(_private_target_name(name, "{}_imports".format(target_id)))
        else:
            variants[_config_condition(target_id, _ARTIFACT_LIBRARY)] = ":{}".format(_private_target_name(name, target_id))

    if "jvm" in target_specs and "android" not in target_specs:
        variants[_config_condition("android", _ARTIFACT_LIBRARY)] = ":{}".format(_private_target_name(name, "jvm"))

    native.alias(
        name = name,
        actual = select(
            variants,
            no_match_error = "KMP target {} does not provide the selected platform/artifact. Available targets: {}".format(
                _label_string(name),
                ", ".join(sorted(target_specs.keys())),
            ),
        ),
        visibility = visibility,
    )

def kt_multiplatform_library(
        name,
        source_sets,
        targets,
        plugins = None,
        tags = None,
        visibility = None):
    """Creates a Kotlin Multiplatform library from explicit source sets and targets."""
    normalized_source_sets = _normalize_source_sets(source_sets)
    normalized_targets = _normalize_targets(targets, normalized_source_sets)
    normalized_plugins = _normalize_dep_list(plugins, "plugins")
    user_tags = _normalize_tag_list(tags)

    for target_id, target in normalized_targets.items():
        closure = _source_set_closure(normalized_source_sets, target.source_set)
        source_layout = _target_source_layout(normalized_source_sets, closure)
        fragment_refines = _target_fragment_refines(normalized_source_sets, closure)
        srcs = source_layout.srcs
        source_set_names = source_layout.source_set_names
        deps = _target_label_attr(normalized_source_sets, closure, "deps", target_id)
        exports = _target_label_attr(normalized_source_sets, closure, "exports", target_id)
        runtime_deps = _target_label_attr(normalized_source_sets, closure, "runtime_deps", target_id)

        if target.type == "jvm":
            _define_platform_opts(name, target_id, closure, source_layout.fragment_sources, fragment_refines)
            _kt_jvm_library(
                name = _private_target_name(name, target_id),
                srcs = srcs,
                deps = deps,
                exports = exports,
                kotlinc_opts = ":{}".format(_platform_opts_name(name, target_id)),
                plugins = normalized_plugins,
                runtime_deps = runtime_deps,
                tags = user_tags,
                visibility = ["//visibility:private"],
            )

        elif target.type == "android":
            _define_platform_opts(name, target_id, closure, source_layout.fragment_sources, fragment_refines)
            android_kwargs = dict(
                name = _private_target_name(name, target_id),
                srcs = srcs,
                deps = deps,
                exports = exports,
                kotlinc_opts = ":{}".format(_platform_opts_name(name, target_id)),
                plugins = normalized_plugins,
                tags = user_tags,
                visibility = ["//visibility:private"],
            )
            if target.manifest:
                android_kwargs["manifest"] = target.manifest
            if target.namespace:
                android_kwargs["custom_package"] = target.namespace
            _kt_android_library(**android_kwargs)

        elif target.type == "wasm_js":
            wasm_deps = deps + [KOTLIN_STDLIB_WASM_LABEL]
            module_name = target.module_name or name
            kt_wasm_library(
                name = _private_target_name(name, target_id),
                deps = wasm_deps,
                fragment_refines = fragment_refines,
                module_name = module_name,
                plugins = normalized_plugins,
                source_set_names = source_set_names,
                srcs = srcs,
                tags = user_tags,
                visibility = ["//visibility:private"],
            )
            kt_wasm_files(
                name = _private_target_name(name, "{}_files".format(target_id)),
                module = ":{}".format(_private_target_name(name, target_id)),
                module_name = module_name,
                visibility = ["//visibility:private"],
            )
            kt_wasm_imports(
                name = _private_target_name(name, "{}_imports".format(target_id)),
                files = ":{}".format(_private_target_name(name, "{}_files".format(target_id))),
                out = name,
                visibility = ["//visibility:private"],
            )

        elif target.type == "apple_framework":
            if not target.module_name:
                fail("targets['{}'] uses kmp_apple_framework and requires module_name".format(target_id))
            framework_files = _private_target_name(name, "{}_framework_files".format(target_id))
            kt_ios_framework_files(
                name = framework_files,
                deps = deps,
                fragment_refines = fragment_refines,
                konan_target = _APPLE_FRAMEWORK_TARGETS[target_id],
                module_name = target.module_name,
                plugins = normalized_plugins,
                source_set_names = source_set_names,
                srcs = srcs,
                tags = user_tags,
                target_compatible_with = _IOS_OR_MACOS_TARGET_COMPATIBLE_WITH,
                visibility = ["//visibility:private"],
            )
            apple_dynamic_framework_import(
                name = _private_target_name(name, target_id),
                framework_imports = [":{}".format(framework_files)],
                tags = user_tags,
                target_compatible_with = _IOS_OR_MACOS_TARGET_COMPATIBLE_WITH,
                visibility = ["//visibility:private"],
            )

        elif target.type in ["js_browser", "js_node"]:
            fail("Kotlin/JS target '{}' is recognized but not implemented yet; use kmp_wasm_js for the current web sample".format(target_id))

        else:
            fail("Unsupported target type '{}' for target '{}'".format(target.type, target_id))

    _define_public_alias(name, normalized_targets, visibility)
