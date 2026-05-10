"""Repository rule that exposes Gradle Module Metadata Kotlin Multiplatform variants."""

_ANDROID_ENV = "android"
_ANDROID_PLATFORM = "androidJvm"
_GRADLE_CATEGORY = "org.gradle.category"
_GRADLE_JVM_ENVIRONMENT = "org.gradle.jvm.environment"
_GRADLE_USAGE = "org.gradle.usage"
_KOTLIN_PLATFORM = "org.jetbrains.kotlin.platform.type"
_KOTLIN_NATIVE_TARGET = "org.jetbrains.kotlin.native.target"
_KOTLIN_WASM_TARGET = "org.jetbrains.kotlin.wasm.target"
_LIBRARY_CATEGORY = "library"
_KOTLIN_STDLIB_GROUP = "org.jetbrains.kotlin"
_KOTLIN_STDLIB_ARTIFACT = "kotlin-stdlib"
_IOS_SIMULATOR_ARM64_NATIVE_TARGET = "ios_simulator_arm64"
_NATIVE_PLATFORM = "native"
_STANDARD_JVM_ENV = "standard-jvm"
_JVM_PLATFORM = "jvm"
_WASM_JS_TARGET = "js"
_WASM_PLATFORM = "wasm"

def _sanitize_label_part(value):
    allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    result = []
    for index in range(len(value)):
        char = value[index]
        result.append(char if char in allowed else "_")
    return "".join(result)

def _maven_target_name(group, artifact):
    return _sanitize_label_part("{}_{}".format(group, artifact))

def _maven_label(repo_name, group, artifact):
    repo = repo_name if repo_name.startswith("@") else "@{}".format(repo_name)
    return "{}//:{}".format(repo, _maven_target_name(group, artifact))

def _has_resolved_artifact(resolved_artifacts, group, artifact, packaging = None):
    coordinate = "{}:{}".format(group, artifact)
    if packaging:
        coordinate = "{}:{}".format(coordinate, packaging)
    return resolved_artifacts.get(coordinate, False)

def _resolved_module_label(resolved_artifacts, repo_name, group, artifact):
    if _has_resolved_artifact(resolved_artifacts, group, artifact, "aar") or _has_resolved_artifact(resolved_artifacts, group, artifact):
        return _maven_label(repo_name, group, artifact)
    return None

def _artifact_key_parts(artifact_key):
    parts = artifact_key.split(":")
    if len(parts) < 2:
        return None
    return struct(
        group = parts[0],
        artifact = parts[1],
    )

def _coordinate_key(group, artifact):
    return "{}:{}".format(group, artifact)

def _coordinate_version_key(group, artifact, version):
    return "{}:{}:{}".format(group, artifact, version)

def _module_metadata_url(repository, group, artifact, version):
    repository = repository if repository.endswith("/") else "{}/".format(repository)
    return "{}{}/{}/{}/{}-{}.module".format(
        repository,
        group.replace(".", "/"),
        artifact,
        version,
        artifact,
        version,
    )

def _artifact_base_url(repository, group, artifact, version):
    repository = repository if repository.endswith("/") else "{}/".format(repository)
    return "{}{}/{}/{}/".format(
        repository,
        group.replace(".", "/"),
        artifact,
        version,
    )

def _module_metadata_path(group, artifact, version):
    return "module_metadata_{}_{}_{}.module".format(_sanitize_label_part(group), _sanitize_label_part(artifact), _sanitize_label_part(version))

def _version_for_coordinate(artifacts, group, artifact):
    for artifact_key in artifacts.keys():
        parts = _artifact_key_parts(artifact_key)
        if parts and parts.group == group and parts.artifact == artifact:
            return artifacts[artifact_key].get("version")
    return None

def _locked_version_for_coordinate(artifacts, group, artifact):
    version = _version_for_coordinate(artifacts, group, artifact)
    if version:
        return version

    if artifact.endswith("-wasm-js"):
        return _version_for_coordinate(artifacts, group, artifact[:-len("-wasm-js")])

    return None

def _fetch_module_metadata(repository_ctx, curl, repositories, metadata_cache, group, artifact, version):
    if not version:
        return None

    key = _coordinate_version_key(group, artifact, version)
    if key in metadata_cache:
        return metadata_cache[key]

    for repository in repositories.keys():
        url = _module_metadata_url(repository, group, artifact, version)
        path = _module_metadata_path(group, artifact, version)
        result = repository_ctx.execute(
            [curl, "-L", "--fail", "-s", "-o", path, url],
            quiet = True,
        )
        if result.return_code == 0:
            metadata_cache[key] = struct(
                base_url = _artifact_base_url(repository, group, artifact, version),
                metadata = json.decode(repository_ctx.read(path)),
            )
            return metadata_cache[key]

    metadata_cache[key] = None
    return None

def _is_library_variant(variant):
    attributes = variant.get("attributes", {})
    return attributes.get(_GRADLE_CATEGORY) == _LIBRARY_CATEGORY and variant.get("available-at") != None

def _is_wasm_library_variant(variant):
    attributes = variant.get("attributes", {})
    return (
        attributes.get(_GRADLE_CATEGORY) == _LIBRARY_CATEGORY and
        attributes.get(_KOTLIN_PLATFORM) == _WASM_PLATFORM and
        attributes.get(_KOTLIN_WASM_TARGET) == _WASM_JS_TARGET and
        _is_api_or_runtime_variant(variant)
    )

def _is_ios_simulator_library_variant(variant):
    attributes = variant.get("attributes", {})
    return (
        attributes.get(_GRADLE_CATEGORY) == _LIBRARY_CATEGORY and
        attributes.get(_KOTLIN_PLATFORM) == _NATIVE_PLATFORM and
        attributes.get(_KOTLIN_NATIVE_TARGET) == _IOS_SIMULATOR_ARM64_NATIVE_TARGET and
        _is_api_or_runtime_variant(variant)
    )

def _is_api_or_runtime_variant(variant):
    usage = variant.get("attributes", {}).get(_GRADLE_USAGE)
    return usage in ["java-api", "kotlin-api", "java-runtime", "kotlin-runtime"]

def _candidate_variant_label(resolved_artifacts, repo_name, variant):
    available_at = variant.get("available-at")
    if not available_at:
        return None
    return _resolved_module_label(
        resolved_artifacts,
        repo_name,
        available_at.get("group"),
        available_at.get("module"),
    )

def _variant_score(variant, platform):
    attributes = variant.get("attributes", {})
    kotlin_platform = attributes.get(_KOTLIN_PLATFORM)
    jvm_environment = attributes.get(_GRADLE_JVM_ENVIRONMENT)
    wasm_target = attributes.get(_KOTLIN_WASM_TARGET)

    if platform == "android":
        if kotlin_platform == _ANDROID_PLATFORM and jvm_environment == _ANDROID_ENV:
            return 500
        if kotlin_platform == _JVM_PLATFORM and jvm_environment == _STANDARD_JVM_ENV:
            return 300
        return 0

    if platform == "jvm":
        if kotlin_platform != _JVM_PLATFORM or jvm_environment != _STANDARD_JVM_ENV:
            return 0
        return 300

    if platform == "wasm":
        if kotlin_platform == _WASM_PLATFORM and wasm_target == _WASM_JS_TARGET:
            return 300
        return 0

    return 0

def _usage_score(variant, prefer_runtime = False):
    usage = variant.get("attributes", {}).get(_GRADLE_USAGE)
    if prefer_runtime:
        if usage in ["java-runtime", "kotlin-runtime"]:
            return 20
        if usage in ["java-api", "kotlin-api"]:
            return 10
        return 0
    if usage in ["java-api", "kotlin-api"]:
        return 20
    if usage in ["java-runtime", "kotlin-runtime"]:
        return 10
    return 0

def _select_module_metadata_variant(module_metadata, resolved_artifacts, repo_name, platform):
    best = None
    best_score = 0
    for variant in module_metadata.get("variants", []):
        if not _is_library_variant(variant) or not _is_api_or_runtime_variant(variant):
            continue
        label = _candidate_variant_label(resolved_artifacts, repo_name, variant)
        if not label:
            continue

        score = _variant_score(variant, platform)
        if score == 0:
            continue
        score = score + _usage_score(variant)
        if best == None or score > best_score:
            best = label
            best_score = score

    return best

def _select_klib_module_metadata_variant(module_metadata, variant_predicate):
    best = None
    best_score = 0
    for variant in module_metadata.get("variants", []):
        if not variant_predicate(variant):
            continue

        score = _usage_score(variant, prefer_runtime = True)
        if best == None or score > best_score:
            best = variant
            best_score = score

    return best

def _select_wasm_module_metadata_variant(module_metadata):
    return _select_klib_module_metadata_variant(module_metadata, _is_wasm_library_variant)

def _select_ios_simulator_module_metadata_variant(module_metadata):
    return _select_klib_module_metadata_variant(module_metadata, _is_ios_simulator_library_variant)

def _metadata_variants(module_metadata, resolved_artifacts, repo_name):
    if not module_metadata:
        return {}

    variants = {}
    android_label = _select_module_metadata_variant(module_metadata, resolved_artifacts, repo_name, "android")
    if android_label:
        variants["android"] = android_label

    jvm_label = _select_module_metadata_variant(module_metadata, resolved_artifacts, repo_name, "jvm")
    if jvm_label:
        variants["jvm"] = jvm_label

    return variants

def _dependency_version(dependency):
    version = dependency.get("version", {})
    return version.get("strictly") or version.get("requires") or version.get("prefers")

def _available_at_version(available_at, fallback_version):
    version = available_at.get("version")
    if type(version) == "dict":
        return version.get("strictly") or version.get("requires") or version.get("prefers") or fallback_version
    if type(version) == "string":
        return version
    return fallback_version

def _select_version(artifacts, resolved_versions, group, artifact, requested_version, platform_name, required = True):
    locked_version = _locked_version_for_coordinate(artifacts, group, artifact)
    version = locked_version or requested_version
    if not version:
        if not required:
            return None
        fail("Could not resolve a version for Kotlin/{} dependency {}:{}".format(platform_name, group, artifact))

    coordinate = _coordinate_key(group, artifact)
    previous = resolved_versions.get(coordinate)
    if previous and previous != version:
        if locked_version:
            resolved_versions[coordinate] = locked_version
            return locked_version
        if not required:
            return None
        fail("Conflicting Kotlin/{} versions for {}: {} and {}".format(platform_name, coordinate, previous, version))

    resolved_versions[coordinate] = version
    return version

def _resolve_file_url(base_url, file_url):
    if file_url.startswith("http://") or file_url.startswith("https://"):
        return file_url
    return "{}{}".format(base_url, file_url)

def _download_klib_file(repository_ctx, target_name, base_url, file_entry):
    sha256 = file_entry.get("sha256")
    sha512 = file_entry.get("sha512")
    if not sha256 and not sha512:
        fail("Kotlin KLIB file {} is missing sha256/sha512 metadata".format(file_entry.get("name")))

    file_name = file_entry.get("name")
    output = "klibs/{}/{}".format(target_name, file_name)
    url = _resolve_file_url(base_url, file_entry.get("url"))
    if sha256:
        repository_ctx.download(
            url = url,
            output = output,
            sha256 = sha256,
        )
        return output

    repository_ctx.download(
        url = url,
        output = output,
    )
    shasum = repository_ctx.which("shasum")
    if not shasum:
        fail("Kotlin KLIB file {} only has sha512 metadata, but shasum was not found".format(file_name))
    result = repository_ctx.execute(
        [shasum, "-a", "512", output],
        quiet = True,
    )
    if result.return_code != 0:
        fail("Could not verify sha512 for Kotlin KLIB file {}: {}".format(file_name, result.stderr))
    actual_sha512 = result.stdout.split()[0].lower()
    if actual_sha512 != sha512.lower():
        fail("Kotlin KLIB file {} sha512 mismatch: expected {}, got {}".format(file_name, sha512, actual_sha512))
    return output

def _generated_label(repository_ctx, target_name):
    return "@{}//:{}".format(repository_ctx.attr.repo_name, target_name)

def _dedupe(values):
    seen = {}
    deduped = []
    for value in values:
        if seen.get(value):
            continue
        seen[value] = True
        deduped.append(value)
    return deduped

def _select_klib_version_key(artifacts, resolved_versions, group, artifact, requested_version, platform_name, required = True):
    version = _select_version(
        artifacts,
        resolved_versions,
        group,
        artifact,
        requested_version,
        platform_name,
        required = required,
    )
    if not version:
        return None

    return struct(
        key = _coordinate_version_key(group, artifact, version),
        version = version,
    )

def _mark_klib_unavailable(resolving, unavailable, key):
    unavailable[key] = True
    resolving[key] = False

def _resolve_klib(
        repository_ctx,
        curl,
        repositories,
        metadata_cache,
        artifacts,
        resolved_versions,
        targets,
        labels,
        build_labels,
        resolving,
        unavailable,
        group,
        artifact,
        requested_version,
        platform_name,
        variant_description,
        target_suffix,
        variant_selector,
        required = True,
        skip_dependency = None):
    root_version = _select_klib_version_key(
        artifacts,
        resolved_versions,
        group,
        artifact,
        requested_version,
        platform_name,
        required = required,
    )
    if not root_version:
        return None

    stack = [struct(
        artifact = artifact,
        group = group,
        key = root_version.key,
        state = "start",
        version = root_version.version,
    )]

    resolved = False
    for _ in range(10000):
        if not stack:
            resolved = True
            break

        frame = stack.pop()
        key = frame.key
        if frame.state == "start":
            if labels.get(key):
                continue
            if unavailable.get(key):
                continue
            if resolving.get(key):
                fail("Cyclic Kotlin/{} dependency graph while resolving {}".format(platform_name, key))

            resolving[key] = True
            metadata_info = _fetch_module_metadata(
                repository_ctx,
                curl,
                repositories,
                metadata_cache,
                frame.group,
                frame.artifact,
                frame.version,
            )
            if not metadata_info:
                if not required:
                    _mark_klib_unavailable(resolving, unavailable, key)
                    continue
                fail("Could not fetch Gradle Module Metadata for Kotlin/{} dependency {}".format(platform_name, key))

            variant = variant_selector(metadata_info.metadata)
            if not variant:
                if not required:
                    _mark_klib_unavailable(resolving, unavailable, key)
                    continue
                fail("No {} KMP variant found for {}".format(variant_description, key))

            available_at = variant.get("available-at")
            if available_at:
                available_version = _select_klib_version_key(
                    artifacts,
                    resolved_versions,
                    available_at.get("group"),
                    available_at.get("module"),
                    _available_at_version(available_at, frame.version),
                    platform_name,
                    required = required,
                )
                if not available_version:
                    _mark_klib_unavailable(resolving, unavailable, key)
                    continue
                stack.append(struct(
                    child_key = available_version.key,
                    key = key,
                    state = "finish_alias",
                ))
                stack.append(struct(
                    artifact = available_at.get("module"),
                    group = available_at.get("group"),
                    key = available_version.key,
                    state = "start",
                    version = available_version.version,
                ))
                continue

            dep_frames = []
            dep_keys = []
            unavailable_dependency = False
            for dependency in variant.get("dependencies", []):
                dep_group = dependency.get("group")
                dep_artifact = dependency.get("module")
                if skip_dependency and skip_dependency(dep_group, dep_artifact):
                    continue

                dep_version = _select_klib_version_key(
                    artifacts,
                    resolved_versions,
                    dep_group,
                    dep_artifact,
                    _dependency_version(dependency),
                    platform_name,
                    required = required,
                )
                if not dep_version:
                    unavailable_dependency = True
                    continue
                dep_keys.append(dep_version.key)
                dep_frames.append(struct(
                    artifact = dep_artifact,
                    group = dep_group,
                    key = dep_version.key,
                    state = "start",
                    version = dep_version.version,
                ))

            if unavailable_dependency:
                _mark_klib_unavailable(resolving, unavailable, key)
                continue

            stack.append(struct(
                base_url = metadata_info.base_url,
                dep_keys = dep_keys,
                key = key,
                state = "finish_target",
                target_name = "{}_{}".format(_maven_target_name(frame.group, frame.artifact), target_suffix),
                variant = variant,
                version = frame.version,
            ))
            for dep_frame in reversed(dep_frames):
                if not labels.get(dep_frame.key):
                    stack.append(dep_frame)
            continue

        if frame.state == "finish_alias":
            if unavailable.get(frame.child_key):
                if required:
                    fail("No {} KMP variant found for {}".format(variant_description, frame.child_key))
                _mark_klib_unavailable(resolving, unavailable, key)
                continue
            labels[key] = labels[frame.child_key]
            build_labels[key] = build_labels[frame.child_key]
            resolving[key] = False
            continue

        if frame.state == "finish_target":
            unavailable_deps = [dep_key for dep_key in frame.dep_keys if unavailable.get(dep_key)]
            if unavailable_deps:
                if required:
                    fail("No {} KMP variant found for {}".format(variant_description, unavailable_deps[0]))
                _mark_klib_unavailable(resolving, unavailable, key)
                continue
            dep_labels = _dedupe([build_labels[dep_key] for dep_key in frame.dep_keys])
            klib_files = [
                _download_klib_file(repository_ctx, frame.target_name, frame.base_url, file_entry)
                for file_entry in frame.variant.get("files", [])
                if file_entry.get("name", "").endswith(".klib")
            ]
            if not klib_files and not dep_labels:
                if not required:
                    _mark_klib_unavailable(resolving, unavailable, key)
                    continue
                fail("No KLIB file found in {} variant for {}".format(variant_description, key))

            targets[key] = struct(
                deps = dep_labels,
                files = klib_files,
                target_name = frame.target_name,
            )
            labels[key] = _generated_label(repository_ctx, frame.target_name)
            build_labels[key] = ":{}".format(frame.target_name)
            resolving[key] = False
            continue

        fail("Unknown Kotlin/{} resolver state '{}'".format(platform_name, frame.state))

    if not resolved:
        fail("Kotlin/{} dependency graph is too deep while resolving {}".format(platform_name, root_version.key))

    if unavailable.get(root_version.key):
        if required:
            fail("No {} KMP variant found for {}".format(variant_description, root_version.key))
        return None

    return labels[root_version.key]

def _resolve_wasm_klib(
        repository_ctx,
        curl,
        repositories,
        metadata_cache,
        artifacts,
        resolved_wasm_versions,
        wasm_targets,
        wasm_labels,
        wasm_build_labels,
        resolving,
        unavailable,
        group,
        artifact,
        requested_version,
        required = True):
    return _resolve_klib(
        repository_ctx,
        curl,
        repositories,
        metadata_cache,
        artifacts,
        resolved_wasm_versions,
        wasm_targets,
        wasm_labels,
        wasm_build_labels,
        resolving,
        unavailable,
        group,
        artifact,
        requested_version,
        "WASM",
        "wasm-js",
        "wasm",
        _select_wasm_module_metadata_variant,
        required = required,
    )

def _is_native_bundled_dependency(group, artifact):
    return group == _KOTLIN_STDLIB_GROUP and artifact in [
        "kotlin-stdlib",
        "kotlin-stdlib-common",
    ]

def _append_klib_filegroups(build_lines, targets):
    for key in sorted(targets.keys()):
        target = targets[key]
        build_lines.append("filegroup(")
        build_lines.append("    name = {},".format(repr(target.target_name)))
        build_lines.append("    srcs = [")
        for file_path in target.files:
            build_lines.append("        {},".format(repr(file_path)))
        for dep in sorted(target.deps):
            build_lines.append("        {},".format(repr(dep)))
        build_lines.append("    ],")
        build_lines.append(")")
        build_lines.append("")

def _resolve_ios_simulator_klib(
        repository_ctx,
        curl,
        repositories,
        metadata_cache,
        artifacts,
        resolved_ios_simulator_versions,
        ios_simulator_targets,
        ios_simulator_labels,
        ios_simulator_build_labels,
        resolving,
        unavailable,
        group,
        artifact,
        requested_version,
        required = True):
    return _resolve_klib(
        repository_ctx,
        curl,
        repositories,
        metadata_cache,
        artifacts,
        resolved_ios_simulator_versions,
        ios_simulator_targets,
        ios_simulator_labels,
        ios_simulator_build_labels,
        resolving,
        unavailable,
        group,
        artifact,
        requested_version,
        "iOS simulator",
        _IOS_SIMULATOR_ARM64_NATIVE_TARGET,
        _IOS_SIMULATOR_ARM64_NATIVE_TARGET,
        _select_ios_simulator_module_metadata_variant,
        required = required,
        skip_dependency = _is_native_bundled_dependency,
    )

def _kmp_maven_variants_repository_impl(repository_ctx):
    curl = repository_ctx.which("curl")
    if not curl:
        fail("kmp_maven_variants_repository requires curl to fetch Gradle Module Metadata")

    lock = json.decode(repository_ctx.read(repository_ctx.attr.maven_install_json))
    artifacts = lock.get("artifacts", {})
    repositories = lock.get("repositories", {})
    input_artifacts = lock.get("__INPUT_ARTIFACTS_HASH", {})
    resolved_artifact_keys = lock.get("__RESOLVED_ARTIFACTS_HASH", {}).keys()
    resolved_artifacts = {
        artifact: True
        for artifact in resolved_artifact_keys
    }
    metadata_cache = {}

    base_coordinates = {}
    for coordinate in input_artifacts.keys():
        if coordinate == "repositories":
            continue

        parts = coordinate.split(":")
        if len(parts) != 2:
            continue

        group = parts[0]
        artifact = parts[1]
        base_coordinates[_coordinate_key(group, artifact)] = struct(
            group = group,
            artifact = artifact,
        )

    variants = {}
    ios_simulator_build_labels = {}
    ios_simulator_labels = {}
    ios_simulator_targets = {}
    resolved_ios_simulator_versions = {}
    ios_simulator_resolving = {}
    ios_simulator_unavailable = {}
    wasm_build_labels = {}
    wasm_labels = {}
    wasm_targets = {}
    resolved_wasm_versions = {}
    wasm_resolving = {}
    wasm_unavailable = {}
    for coordinate in sorted(base_coordinates.keys()):
        base = base_coordinates[coordinate]
        group = base.group
        artifact = base.artifact
        label = _maven_label(repository_ctx.attr.maven_repo, group, artifact)
        version = _version_for_coordinate(artifacts, group, artifact)
        metadata_info = _fetch_module_metadata(
            repository_ctx,
            curl,
            repositories,
            metadata_cache,
            group,
            artifact,
            version,
        )
        module_metadata = metadata_info.metadata if metadata_info else None
        platform_variants = _metadata_variants(
            module_metadata,
            resolved_artifacts,
            repository_ctx.attr.maven_repo,
        )
        if module_metadata and _select_wasm_module_metadata_variant(module_metadata):
            wasm_variant = _resolve_wasm_klib(
                repository_ctx,
                curl,
                repositories,
                metadata_cache,
                artifacts,
                resolved_wasm_versions,
                wasm_targets,
                wasm_labels,
                wasm_build_labels,
                wasm_resolving,
                wasm_unavailable,
                group,
                artifact,
                version,
                required = False,
            )
            if wasm_variant:
                platform_variants["wasm"] = wasm_variant
        if module_metadata and _select_ios_simulator_module_metadata_variant(module_metadata):
            ios_variant = _resolve_ios_simulator_klib(
                repository_ctx,
                curl,
                repositories,
                metadata_cache,
                artifacts,
                resolved_ios_simulator_versions,
                ios_simulator_targets,
                ios_simulator_labels,
                ios_simulator_build_labels,
                ios_simulator_resolving,
                ios_simulator_unavailable,
                group,
                artifact,
                version,
                required = False,
            )
            if ios_variant:
                platform_variants["ios"] = ios_variant

        if platform_variants:
            variants[label] = platform_variants

    kotlin_stdlib_wasm_label = _resolve_wasm_klib(
        repository_ctx,
        curl,
        repositories,
        metadata_cache,
        artifacts,
        resolved_wasm_versions,
        wasm_targets,
        wasm_labels,
        wasm_build_labels,
        wasm_resolving,
        wasm_unavailable,
        _KOTLIN_STDLIB_GROUP,
        _KOTLIN_STDLIB_ARTIFACT,
        _version_for_coordinate(artifacts, _KOTLIN_STDLIB_GROUP, _KOTLIN_STDLIB_ARTIFACT),
    )

    lines = [
        '"""Generated Kotlin Multiplatform Maven variant labels."""',
        "",
        "KOTLIN_STDLIB_WASM_LABEL = {}".format(repr(kotlin_stdlib_wasm_label)),
        "",
        "KMP_MAVEN_VARIANTS = {",
    ]
    for label in sorted(variants.keys()):
        lines.append("    {}: {{".format(repr(label)))
        for platform in sorted(variants[label].keys()):
            lines.append("        {}: {},".format(repr(platform), repr(variants[label][platform])))
        lines.append("    },")
    lines.append("}")
    lines.append("")

    build_lines = [
        'package(default_visibility = ["//visibility:public"])',
        "",
    ]
    _append_klib_filegroups(build_lines, ios_simulator_targets)
    _append_klib_filegroups(build_lines, wasm_targets)

    repository_ctx.file("BUILD.bazel", "\n".join(build_lines))
    repository_ctx.file("variants.bzl", "\n".join(lines))

kmp_maven_variants_repository = repository_rule(
    implementation = _kmp_maven_variants_repository_impl,
    attrs = {
        "maven_install_json": attr.label(
            allow_single_file = True,
            mandatory = True,
            doc = "rules_jvm_external maven_install.json lock file.",
        ),
        "maven_repo": attr.string(
            default = "third_party_maven",
            doc = "Apparent repository name used for generated Maven labels.",
        ),
        "repo_name": attr.string(
            default = "third_party_maven_kmp_variants",
            doc = "Apparent repository name used for generated Kotlin KLIB labels.",
        ),
    },
    doc = "Generates a Starlark map from root Maven labels to Gradle Module Metadata KMP variants.",
)
