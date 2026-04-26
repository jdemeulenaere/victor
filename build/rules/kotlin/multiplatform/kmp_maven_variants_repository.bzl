"""Repository rule that exposes Gradle Module Metadata Kotlin Multiplatform variants."""

_ANDROID_ENV = "android"
_ANDROID_PLATFORM = "androidJvm"
_GRADLE_CATEGORY = "org.gradle.category"
_GRADLE_JVM_ENVIRONMENT = "org.gradle.jvm.environment"
_GRADLE_USAGE = "org.gradle.usage"
_KOTLIN_PLATFORM = "org.jetbrains.kotlin.platform.type"
_KOTLIN_WASM_TARGET = "org.jetbrains.kotlin.wasm.target"
_LIBRARY_CATEGORY = "library"
_KOTLIN_STDLIB_GROUP = "org.jetbrains.kotlin"
_KOTLIN_STDLIB_ARTIFACT = "kotlin-stdlib"
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

def _module_metadata_urls(repositories, group, artifact, version):
    return [
        _module_metadata_url(repository, group, artifact, version)
        for repository in repositories.keys()
    ]

def _download_module_metadata(repository_ctx, curl, repositories, group, artifact, version):
    if not version:
        return None

    path = _module_metadata_path(group, artifact, version)
    for url in _module_metadata_urls(repositories, group, artifact, version):
        result = repository_ctx.execute(
            [curl, "-L", "--fail", "-s", "-o", path, url],
            quiet = True,
        )
        if result.return_code == 0:
            return json.decode(repository_ctx.read(path))

    return None

def _metadata_with_base_url(repository_ctx, curl, repositories, group, artifact, version):
    if not version:
        return None

    for repository in repositories.keys():
        url = _module_metadata_url(repository, group, artifact, version)
        path = _module_metadata_path(group, artifact, version)
        result = repository_ctx.execute(
            [curl, "-L", "--fail", "-s", "-o", path, url],
            quiet = True,
        )
        if result.return_code == 0:
            return struct(
                base_url = _artifact_base_url(repository, group, artifact, version),
                metadata = json.decode(repository_ctx.read(path)),
            )

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

def _select_wasm_module_metadata_variant(module_metadata):
    best = None
    best_score = 0
    for variant in module_metadata.get("variants", []):
        if not _is_wasm_library_variant(variant):
            continue

        score = _usage_score(variant, prefer_runtime = True)
        if best == None or score > best_score:
            best = variant
            best_score = score

    return best

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

def _select_version(artifacts, resolved_wasm_versions, group, artifact, requested_version):
    locked_version = _locked_version_for_coordinate(artifacts, group, artifact)
    version = locked_version or requested_version
    if not version:
        fail("Could not resolve a version for Kotlin/WASM dependency {}:{}".format(group, artifact))

    coordinate = _coordinate_key(group, artifact)
    previous = resolved_wasm_versions.get(coordinate)
    if previous and previous != version:
        if locked_version:
            resolved_wasm_versions[coordinate] = locked_version
            return locked_version
        fail("Conflicting Kotlin/WASM versions for {}: {} and {}".format(coordinate, previous, version))

    resolved_wasm_versions[coordinate] = version
    return version

def _resolve_file_url(base_url, file_url):
    if file_url.startswith("http://") or file_url.startswith("https://"):
        return file_url
    return "{}{}".format(base_url, file_url)

def _download_klib_file(repository_ctx, target_name, base_url, file_entry):
    sha256 = file_entry.get("sha256")
    sha512 = file_entry.get("sha512")
    if not sha256 and not sha512:
        fail("Kotlin/WASM KLIB file {} is missing sha256/sha512 metadata".format(file_entry.get("name")))

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
        fail("Kotlin/WASM KLIB file {} only has sha512 metadata, but shasum was not found".format(file_name))
    result = repository_ctx.execute(
        [shasum, "-a", "512", output],
        quiet = True,
    )
    if result.return_code != 0:
        fail("Could not verify sha512 for Kotlin/WASM KLIB file {}: {}".format(file_name, result.stderr))
    actual_sha512 = result.stdout.split()[0].lower()
    if actual_sha512 != sha512.lower():
        fail("Kotlin/WASM KLIB file {} sha512 mismatch: expected {}, got {}".format(file_name, sha512, actual_sha512))
    return output

def _wasm_label(repository_ctx, target_name):
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

def _select_wasm_version_key(artifacts, resolved_wasm_versions, group, artifact, requested_version):
    version = _select_version(artifacts, resolved_wasm_versions, group, artifact, requested_version)
    return struct(
        key = _coordinate_version_key(group, artifact, version),
        version = version,
    )

def _resolve_wasm_klib(
        repository_ctx,
        curl,
        repositories,
        artifacts,
        resolved_wasm_versions,
        wasm_targets,
        wasm_labels,
        wasm_build_labels,
        resolving,
        group,
        artifact,
        requested_version):
    root_version = _select_wasm_version_key(
        artifacts,
        resolved_wasm_versions,
        group,
        artifact,
        requested_version,
    )
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
            if wasm_labels.get(key):
                continue
            if resolving.get(key):
                fail("Cyclic Kotlin/WASM dependency graph while resolving {}".format(key))

            resolving[key] = True
            metadata_info = _metadata_with_base_url(repository_ctx, curl, repositories, frame.group, frame.artifact, frame.version)
            if not metadata_info:
                fail("Could not fetch Gradle Module Metadata for Kotlin/WASM dependency {}".format(key))

            variant = _select_wasm_module_metadata_variant(metadata_info.metadata)
            if not variant:
                fail("No wasm-js KMP variant found for {}".format(key))

            available_at = variant.get("available-at")
            if available_at:
                available_version = _select_wasm_version_key(
                    artifacts,
                    resolved_wasm_versions,
                    available_at.get("group"),
                    available_at.get("module"),
                    _available_at_version(available_at, frame.version),
                )
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
            for dependency in variant.get("dependencies", []):
                dep_version = _select_wasm_version_key(
                    artifacts,
                    resolved_wasm_versions,
                    dependency.get("group"),
                    dependency.get("module"),
                    _dependency_version(dependency),
                )
                dep_keys.append(dep_version.key)
                dep_frames.append(struct(
                    artifact = dependency.get("module"),
                    group = dependency.get("group"),
                    key = dep_version.key,
                    state = "start",
                    version = dep_version.version,
                ))

            stack.append(struct(
                base_url = metadata_info.base_url,
                dep_keys = dep_keys,
                key = key,
                state = "finish_target",
                target_name = "{}_wasm".format(_maven_target_name(frame.group, frame.artifact)),
                variant = variant,
                version = frame.version,
            ))
            for dep_frame in reversed(dep_frames):
                if not wasm_labels.get(dep_frame.key):
                    stack.append(dep_frame)
            continue

        if frame.state == "finish_alias":
            wasm_labels[key] = wasm_labels[frame.child_key]
            wasm_build_labels[key] = wasm_build_labels[frame.child_key]
            resolving[key] = False
            continue

        if frame.state == "finish_target":
            dep_labels = _dedupe([wasm_build_labels[dep_key] for dep_key in frame.dep_keys])
            klib_files = [
                _download_klib_file(repository_ctx, frame.target_name, frame.base_url, file_entry)
                for file_entry in frame.variant.get("files", [])
                if file_entry.get("name", "").endswith(".klib")
            ]
            if not klib_files:
                fail("No KLIB file found in wasm-js variant for {}".format(key))

            wasm_targets[key] = struct(
                deps = dep_labels,
                files = klib_files,
                target_name = frame.target_name,
            )
            wasm_labels[key] = _wasm_label(repository_ctx, frame.target_name)
            wasm_build_labels[key] = ":{}".format(frame.target_name)
            resolving[key] = False
            continue

        fail("Unknown Kotlin/WASM resolver state '{}'".format(frame.state))

    if not resolved:
        fail("Kotlin/WASM dependency graph is too deep while resolving {}".format(root_version.key))

    return wasm_labels[root_version.key]

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
    wasm_build_labels = {}
    wasm_labels = {}
    wasm_targets = {}
    resolved_wasm_versions = {}
    resolving = {}
    for coordinate in sorted(base_coordinates.keys()):
        base = base_coordinates[coordinate]
        group = base.group
        artifact = base.artifact
        label = _maven_label(repository_ctx.attr.maven_repo, group, artifact)
        version = _version_for_coordinate(artifacts, group, artifact)
        module_metadata = _download_module_metadata(
            repository_ctx,
            curl,
            repositories,
            group,
            artifact,
            version,
        )
        platform_variants = _metadata_variants(
            module_metadata,
            resolved_artifacts,
            repository_ctx.attr.maven_repo,
        )
        if module_metadata and _select_wasm_module_metadata_variant(module_metadata):
            platform_variants["wasm"] = _resolve_wasm_klib(
                repository_ctx,
                curl,
                repositories,
                artifacts,
                resolved_wasm_versions,
                wasm_targets,
                wasm_labels,
                wasm_build_labels,
                resolving,
                group,
                artifact,
                version,
            )

        if platform_variants:
            variants[label] = platform_variants

    kotlin_stdlib_wasm_label = _resolve_wasm_klib(
        repository_ctx,
        curl,
        repositories,
        artifacts,
        resolved_wasm_versions,
        wasm_targets,
        wasm_labels,
        wasm_build_labels,
        resolving,
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
    for key in sorted(wasm_targets.keys()):
        target = wasm_targets[key]
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
            doc = "Apparent repository name used for generated Kotlin/WASM KLIB labels.",
        ),
    },
    doc = "Generates a Starlark map from root Maven labels to Gradle Module Metadata KMP variants.",
)
