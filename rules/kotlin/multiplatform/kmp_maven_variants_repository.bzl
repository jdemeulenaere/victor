"""Repository rule that exposes pinned Kotlin Multiplatform Maven variants."""

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

def _variant_label(resolved_artifacts, repo_name, group, artifact, suffix, packaging = None):
    variant_artifact = "{}-{}".format(artifact, suffix)
    if _has_resolved_artifact(resolved_artifacts, group, variant_artifact, packaging):
        return _maven_label(repo_name, group, variant_artifact)
    return None

def _is_platform_variant_artifact(artifact):
    return artifact.endswith("-android") or artifact.endswith("-desktop") or artifact.endswith("-jvm")

def _kmp_maven_variants_repository_impl(repository_ctx):
    lock = json.decode(repository_ctx.read(repository_ctx.attr.maven_install_json))
    resolved_artifact_keys = lock.get("__RESOLVED_ARTIFACTS_HASH", {}).keys()
    resolved_artifacts = {
        artifact: True
        for artifact in resolved_artifact_keys
    }

    base_coordinates = {}
    for coordinate in resolved_artifact_keys:
        parts = coordinate.split(":")
        if len(parts) < 2:
            continue

        group = parts[0]
        artifact = parts[1]
        if _is_platform_variant_artifact(artifact):
            continue

        base_coordinates["{}:{}".format(group, artifact)] = struct(
            group = group,
            artifact = artifact,
        )

    variants = {}
    for coordinate in sorted(base_coordinates.keys()):
        base = base_coordinates[coordinate]
        group = base.group
        artifact = base.artifact
        label = _maven_label(repository_ctx.attr.maven_repo, group, artifact)
        platform_variants = {}

        android_label = _variant_label(
            resolved_artifacts,
            repository_ctx.attr.maven_repo,
            group,
            artifact,
            "android",
            "aar",
        )
        if not android_label:
            android_label = _variant_label(
                resolved_artifacts,
                repository_ctx.attr.maven_repo,
                group,
                artifact,
                "android",
            )
        if android_label:
            platform_variants["android"] = android_label

        desktop_label = _variant_label(
            resolved_artifacts,
            repository_ctx.attr.maven_repo,
            group,
            artifact,
            "desktop",
        )
        if desktop_label:
            platform_variants["jvm"] = desktop_label
        else:
            jvm_label = _variant_label(
                resolved_artifacts,
                repository_ctx.attr.maven_repo,
                group,
                artifact,
                "jvm",
            )
            if jvm_label:
                platform_variants["jvm"] = jvm_label

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
    doc = "Generates a Starlark map from root Maven labels to pinned KMP platform variants.",
)
