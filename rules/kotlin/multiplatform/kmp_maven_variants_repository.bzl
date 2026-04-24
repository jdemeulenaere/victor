"""Repository rule that exposes Gradle Module Metadata Kotlin Multiplatform variants."""

_ANDROID_ENV = "android"
_ANDROID_PLATFORM = "androidJvm"
_GRADLE_CATEGORY = "org.gradle.category"
_GRADLE_JVM_ENVIRONMENT = "org.gradle.jvm.environment"
_GRADLE_USAGE = "org.gradle.usage"
_KOTLIN_PLATFORM = "org.jetbrains.kotlin.platform.type"
_LIBRARY_CATEGORY = "library"
_STANDARD_JVM_ENV = "standard-jvm"
_JVM_PLATFORM = "jvm"

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

def _module_metadata_path(group, artifact, version):
    return "module_metadata_{}_{}_{}.module".format(_sanitize_label_part(group), _sanitize_label_part(artifact), _sanitize_label_part(version))

def _version_for_coordinate(artifacts, group, artifact):
    for artifact_key in artifacts.keys():
        parts = _artifact_key_parts(artifact_key)
        if parts and parts.group == group and parts.artifact == artifact:
            return artifacts[artifact_key].get("version")
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

def _is_library_variant(variant):
    attributes = variant.get("attributes", {})
    return attributes.get(_GRADLE_CATEGORY) == _LIBRARY_CATEGORY and variant.get("available-at") != None

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

    return 0

def _usage_score(variant):
    usage = variant.get("attributes", {}).get(_GRADLE_USAGE)
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
    for coordinate in sorted(base_coordinates.keys()):
        base = base_coordinates[coordinate]
        group = base.group
        artifact = base.artifact
        label = _maven_label(repository_ctx.attr.maven_repo, group, artifact)
        module_metadata = _download_module_metadata(
            repository_ctx,
            curl,
            repositories,
            group,
            artifact,
            _version_for_coordinate(artifacts, group, artifact),
        )
        platform_variants = _metadata_variants(
            module_metadata,
            resolved_artifacts,
            repository_ctx.attr.maven_repo,
        )

        if platform_variants:
            variants[label] = platform_variants

    lines = [
        '"""Generated Kotlin Multiplatform Maven variant labels."""',
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

    repository_ctx.file("BUILD.bazel", "")
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
    },
    doc = "Generates a Starlark map from root Maven labels to Gradle Module Metadata KMP variants.",
)
