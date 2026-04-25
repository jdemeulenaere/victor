"""Bazel-managed Android SDK repository for this workspace."""

_ANDROID_REPOSITORY_BASE_URL = "https://dl.google.com/android/repository"

_DEFAULT_API_LEVEL = 36
_DEFAULT_BUILD_TOOLS_VERSION = "36.0.0"
_DEFAULT_PLATFORM_TOOLS_VERSION = "37.0.0"

# Keep the managed SDK minimal: Bazel only needs platform-tools, the selected
# platform, and build-tools for the current host. We intentionally do not fetch
# sdkmanager/cmdline-tools or the emulator.
_PACKAGE_METADATA = {
    "build-tools;36.0.0": {
        "linux": {
            "output": "build-tools/36.0.0",
            "sha256": "5d9ac77fb6ff43d9da518a337b4fcf8f9097113df531d99ccefe80ef7ce8250b",
            "strip_prefix": "android-16",
            "url": "build-tools_r36_linux.zip",
        },
        "macosx": {
            "output": "build-tools/36.0.0",
            "sha256": "04e7f3a72044de4926fa038fa0e251a37bba1e1c3fb8beab6f8401bfd9eb4bf3",
            "strip_prefix": "android-16",
            "url": "build-tools_r36_macosx.zip",
        },
    },
    "platform-tools": {
        # platform-tools is versioned independently from platform/build-tools.
        # 37.0.0 is the current stable release we pin for both Linux and macOS.
        "linux": {
            "output": "platform-tools",
            "sha256": "198ae156ab285fa555987219af237b31102fefe8b9d2bc274708a8d4f2865a07",
            "strip_prefix": "platform-tools",
            "url": "platform-tools_r{}-linux.zip".format(_DEFAULT_PLATFORM_TOOLS_VERSION),
        },
        "macosx": {
            "output": "platform-tools",
            "sha256": "094a1395683c509fd4d48667da0d8b5ef4d42b2abfcd29f2e8149e2f989357c7",
            "strip_prefix": "platform-tools",
            "url": "platform-tools_r{}-darwin.zip".format(_DEFAULT_PLATFORM_TOOLS_VERSION),
        },
    },
    "platforms;android-36": {
        "all": {
            "output": "platforms/android-36",
            "sha256": "37607369a28c5b640b3a7998868d45898ebcb777565a0e85f9acf36f29631d2e",
            "strip_prefix": "android-36",
            "url": "platform-36_r02.zip",
        },
    },
}

def _host_os(repo_ctx):
    host_name = repo_ctx.os.name.lower()
    if "linux" in host_name:
        return "linux"
    if "mac" in host_name or "darwin" in host_name:
        return "macosx"
    fail("Unsupported host OS for Bazel-managed Android SDK: {}".format(repo_ctx.os.name))

def _resolve_version(requested, default):
    return requested if requested else default

def _resolve_supported_packages(api_level, build_tools_version, host_os):
    platform_package = "platforms;android-{}".format(api_level)
    required_packages = [
        platform_package,
        "platform-tools",
        "build-tools;{}".format(build_tools_version),
    ]

    resolved = []
    unsupported = []
    for package_name in required_packages:
        metadata = _PACKAGE_METADATA.get(package_name)
        if not metadata:
            unsupported.append(package_name)
            continue

        archive = metadata.get(host_os) or metadata.get("all")
        if archive == None:
            unsupported.append("{} on {}".format(package_name, host_os))
            continue
        resolved.append(archive)

    if unsupported:
        fail(
            "Unsupported Bazel-managed Android SDK selection: {}. Update build/tools/android/android_sdk_repository.bzl to add pinned package metadata.".format(
                ", ".join(unsupported),
            ),
        )

    return resolved

def _download_sdk_archives(repo_ctx, archives):
    for archive in archives:
        repo_ctx.download_and_extract(
            output = archive["output"],
            sha256 = archive["sha256"],
            stripPrefix = archive["strip_prefix"],
            url = "{}/{}".format(_ANDROID_REPOSITORY_BASE_URL, archive["url"]),
        )

def _android_sdk_repository_impl(repo_ctx):
    api_level = _resolve_version(repo_ctx.attr.api_level, _DEFAULT_API_LEVEL)
    build_tools_version = _resolve_version(repo_ctx.attr.build_tools_version, _DEFAULT_BUILD_TOOLS_VERSION)
    build_tools_directory = build_tools_version

    archives = _resolve_supported_packages(
        api_level = api_level,
        build_tools_version = build_tools_version,
        host_os = _host_os(repo_ctx),
    )
    _download_sdk_archives(repo_ctx, archives)

    repo_ctx.template(
        "BUILD.bazel",
        Label("//build/tools/android:android_sdk_repository.BUILD.bazel.tpl"),
        substitutions = {
            "__api_levels__": str(api_level),
            "__build_tools_directory__": build_tools_directory,
            "__build_tools_version__": build_tools_version,
            "__default_api_level__": str(api_level),
            "__repository_name__": repo_ctx.name,
        },
    )

_android_sdk_repository = repository_rule(
    implementation = _android_sdk_repository_impl,
    attrs = {
        "api_level": attr.int(default = _DEFAULT_API_LEVEL),
        "build_tools_version": attr.string(default = _DEFAULT_BUILD_TOOLS_VERSION),
    },
)

def _android_sdk_repository_extension_impl(module_ctx):
    root_modules = [module for module in module_ctx.modules if module.is_root and module.tags.configure]
    if len(root_modules) > 1:
        fail("Expected at most one root module with android SDK configuration, found {}".format(len(root_modules)))

    module = root_modules[0] if root_modules else module_ctx.modules[0]
    tag = module.tags.configure[0] if module.tags.configure else None

    _android_sdk_repository(
        name = "androidsdk",
        api_level = tag.api_level if tag else _DEFAULT_API_LEVEL,
        build_tools_version = tag.build_tools_version if tag else _DEFAULT_BUILD_TOOLS_VERSION,
    )

    return module_ctx.extension_metadata(reproducible = True)

android_sdk_repository_extension = module_extension(
    implementation = _android_sdk_repository_extension_impl,
    tag_classes = {
        "configure": tag_class(attrs = {
            "api_level": attr.int(default = _DEFAULT_API_LEVEL),
            "build_tools_version": attr.string(default = _DEFAULT_BUILD_TOOLS_VERSION),
        }),
    },
)
