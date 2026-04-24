"""Repository rule that derives KMP metadata/platform variants from Gradle module metadata."""

def _sanitize_label_component(value):
    raw = []
    lower = value.lower()
    for i in range(len(lower)):
        ch = lower[i]
        if ("a" <= ch and ch <= "z") or ("0" <= ch and ch <= "9"):
            raw.append(ch)
        else:
            raw.append("_")

    collapsed = []
    prev_underscore = False
    for ch in raw:
        if ch == "_":
            if prev_underscore:
                continue
            prev_underscore = True
        else:
            prev_underscore = False
        collapsed.append(ch)

    label = "".join(collapsed)
    if label and label[0] >= "0" and label[0] <= "9":
        label = "_" + label
    return label

def _label_for(group, artifact):
    return _sanitize_label_component("{}_{}".format(group, artifact))

def _extract_base_versions(lock):
    versions = {}
    artifacts = lock.get("artifacts", {})
    for coord, meta in artifacts.items():
        parts = coord.split(":")
        if len(parts) < 2:
            continue
        base = "{}:{}".format(parts[0], parts[1])
        version = meta.get("version")
        if not version:
            continue

        # Prefer entries without explicit extension/classifier when available.
        if len(parts) == 2 or base not in versions:
            versions[base] = version
    return versions

def _direct_bases(lock):
    bases = []
    input_hash = lock.get("__INPUT_ARTIFACTS_HASH", {})
    for key in input_hash.keys():
        if key == "repositories":
            continue
        parts = key.split(":")
        if len(parts) < 2:
            continue
        bases.append("{}:{}".format(parts[0], parts[1]))
    return sorted(depset(bases).to_list())

def _all_bases(lock):
    out = {}
    for coord in lock.get("artifacts", {}).keys():
        parts = coord.split(":")
        if len(parts) < 2:
            continue
        out["{}:{}".format(parts[0], parts[1])] = True
    return out

def _kmp_candidate_bases(lock, direct_bases):
    all_bases = _all_bases(lock)
    suffixes = [
        "-android",
        "-desktop",
        "-jvm",
        "-iosarm64",
        "-iossimulatorarm64",
        "-iosx64",
        "-linuxx64",
        "-macosarm64",
        "-macosx64",
        "-wasm-js",
    ]

    candidates = {}
    for base in direct_bases:
        group, artifact = base.split(":", 1)
        for suffix in suffixes:
            if "{}:{}{}".format(group, artifact, suffix) in all_bases:
                candidates[base] = True
                break
    return candidates

def _try_download(ctx, url, output, sha256 = None):
    if sha256:
        return ctx.download(url = url, output = output, sha256 = sha256, allow_fail = True)
    return ctx.download(url = url, output = output, allow_fail = True)

def _ordered_repositories(repositories, group):
    google = [repo for repo in repositories if "google" in repo]
    non_google = [repo for repo in repositories if "google" not in repo]
    if group.startswith("androidx."):
        return google + non_google
    return non_google + google

def _find_module(ctx, repositories, group, artifact, version, label):
    rel = "{}/{}/{}/{}-{}.module".format(group.replace(".", "/"), artifact, version, artifact, version)
    for repo in _ordered_repositories(repositories, group):
        base = repo[:-1] if repo.endswith("/") else repo
        url = "{}/{}".format(base, rel)
        out = "tmp/{}.module".format(label)
        result = _try_download(ctx, url = url, output = out)
        if result.success:
            return struct(
                url_dir = "{}/{}/{}/{}".format(base, group.replace(".", "/"), artifact, version),
                module = json.decode(ctx.read(out)),
            )
    return None

def _extract_metadata_file(module):
    for variant in module.get("variants", []):
        attrs = variant.get("attributes", {})
        if attrs.get("org.gradle.usage") != "kotlin-metadata":
            continue
        if attrs.get("org.jetbrains.kotlin.platform.type") != "common":
            continue
        files = variant.get("files", [])
        if not files:
            continue
        return files[0]
    return None

def _extract_platform_variants(module):
    out = {}
    for variant in module.get("variants", []):
        attrs = variant.get("attributes", {})
        platform = attrs.get("org.jetbrains.kotlin.platform.type")
        if platform not in ["jvm", "androidJvm"]:
            continue

        available_at = variant.get("available-at")
        if not available_at:
            continue

        group = available_at.get("group")
        artifact = available_at.get("module")
        if not group or not artifact:
            continue

        key = "jvm" if platform == "jvm" else "android"
        if key not in out:
            out[key] = _label_for(group, artifact)
    return out

def _kmp_variants_repo_impl(ctx):
    lock = json.decode(ctx.read(ctx.attr.maven_install_json))
    base_versions = _extract_base_versions(lock)
    bases = _direct_bases(lock)
    kmp_candidates = _kmp_candidate_bases(lock, bases)

    metadata_srcs = {}
    platform_variants = {}
    known_targets = {}

    for base in bases:
        version = base_versions.get(base)
        if not version:
            continue

        group, artifact = base.split(":", 1)
        label = _label_for(group, artifact)
        known_targets[label] = True

        if base not in kmp_candidates:
            continue

        module_info = _find_module(
            ctx = ctx,
            repositories = ctx.attr.repositories,
            group = group,
            artifact = artifact,
            version = version,
            label = label,
        )
        if not module_info:
            continue

        metadata_file = _extract_metadata_file(module_info.module)
        if metadata_file:
            file_url = metadata_file.get("url")
            if file_url:
                if "://" in file_url:
                    full_url = file_url
                else:
                    full_url = "{}/{}".format(module_info.url_dir, file_url)

                ext = file_url.rsplit(".", 1)[-1] if "." in file_url else "bin"
                if ext not in ["jar", "klib"]:
                    ext = "bin"
                out = "files/{}.{}".format(label, ext)
                result = _try_download(
                    ctx,
                    url = full_url,
                    output = out,
                    sha256 = metadata_file.get("sha256"),
                )
                if result.success:
                    metadata_srcs[label] = out

        platform = _extract_platform_variants(module_info.module)
        if platform:
            platform_variants[label] = platform

    build_lines = [
        "package(default_visibility = [\"//visibility:public\"])",
        "",
    ]

    for base in bases:
        group, artifact = base.split(":", 1)
        label = _label_for(group, artifact)
        src = metadata_srcs.get(label)
        if src:
            srcs_expr = "[\"{}\"]".format(src)
        else:
            srcs_expr = "[]"
        build_lines.extend([
            "filegroup(",
            "    name = \"{}\",".format(label),
            "    srcs = {},".format(srcs_expr),
            ")",
            "",
        ])

    ctx.file("BUILD.bazel", "\n".join(build_lines))

    variants_lines = ["KMP_PLATFORM_VARIANTS = {"]
    for label in sorted(platform_variants.keys()):
        variants = platform_variants[label]
        variants_lines.append("    \"{}\": {{".format(label))
        if "android" in variants:
            variants_lines.append("        \"android\": \"{}\",".format(variants["android"]))
        if "jvm" in variants:
            variants_lines.append("        \"jvm\": \"{}\",".format(variants["jvm"]))
        variants_lines.append("    },")
    variants_lines.append("}")
    variants_lines.append("")

    variants_lines.append("KMP_METADATA_VARIANTS = {")
    for label in sorted(metadata_srcs.keys()):
        variants_lines.append("    \"{}\": True,".format(label))
    variants_lines.append("}")
    variants_lines.append("")

    variants_lines.append("KMP_KNOWN_TARGETS = {")
    for label in sorted(known_targets.keys()):
        variants_lines.append("    \"{}\": True,".format(label))
    variants_lines.append("}")
    variants_lines.append("")

    ctx.file("variants.bzl", "\n".join(variants_lines))

kmp_variants_repo = repository_rule(
    implementation = _kmp_variants_repo_impl,
    attrs = {
        "maven_install_json": attr.label(mandatory = True, allow_single_file = True),
        "repositories": attr.string_list(mandatory = True),
    },
)
