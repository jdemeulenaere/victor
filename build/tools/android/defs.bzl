"""Project Android rule wrappers with repo defaults."""

load(
    "@rules_android//rules:rules.bzl",
    _android_binary = "android_binary",
    _android_local_test = "android_local_test",
)
load("@rules_kotlin//kotlin:jvm.bzl", "kt_jvm_library")
load("//build/tools/android:service.bzl", "AndroidStringFlagInfo")

_DEFAULT_DEBUG_SIGNING_KEYS = ["//build/signing/android/debug:debug.keystore"]
_DEFAULT_LOCAL_SERVICE_URL = "127.0.0.1"
_DEFAULT_LOCAL_SERVICE_URL_PORT = 8080
_DEFAULT_MIN_SDK_VERSION = "23"
_DEFAULT_TARGET_SDK_VERSION = "36"
_DEPLOY_SERVICE_URL = "//build/tools/android:android_deploy_service_url"
_SERVICE_URL_PROFILE = "//build/tools/android:android_service_url_profile"

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

def _validate_kotlin_package(package):
    for part in package.split("."):
        if not part:
            fail("Invalid Kotlin package: {}".format(package))
        first = part[0]
        if not (first == "_" or first.isalpha()):
            fail("Invalid Kotlin package: {}".format(package))
        for char in part.elems():
            if not (char == "_" or char.isalpha() or char.isdigit()):
                fail("Invalid Kotlin package: {}".format(package))

def _parse_service_url(service_url, default_port = None):
    if "://" not in service_url:
        if default_port == None:
            fail("service_url must use http or https: {}".format(service_url))
        if "/" in service_url or "?" in service_url or "#" in service_url:
            fail("service_url shorthand must be a host or host:port: {}".format(service_url))
        host_port = service_url
        if ":" not in host_port:
            host_port = "{}:{}".format(host_port, default_port)
        service_url = "http://{}".format(host_port)

    scheme, separator, rest = service_url.partition("://")
    if separator != "://" or scheme not in ["http", "https"]:
        fail("service_url must use http or https: {}".format(service_url))
    if "?" in rest or "#" in rest:
        fail("service_url must be an origin without query or fragment: {}".format(service_url))
    host_port, path_separator, path = rest.partition("/")
    if path_separator and path:
        fail("service_url must be an origin without path: {}".format(service_url))
    if "@" in host_port:
        fail("service_url must not include userinfo: {}".format(service_url))
    if not host_port:
        fail("service_url must include a host: {}".format(service_url))

    default_port = 443 if scheme == "https" else 80
    if host_port.startswith("["):
        closing = host_port.find("]")
        if closing < 0:
            fail("Invalid IPv6 service_url host: {}".format(service_url))
        host = host_port[1:closing]
        suffix = host_port[closing + 1:]
        if suffix.startswith(":"):
            port = int(suffix[1:])
        elif suffix:
            fail("Invalid service_url host/port: {}".format(service_url))
        else:
            port = default_port
    else:
        host = host_port
        port = default_port
        if ":" in host_port:
            host, port_text = host_port.rsplit(":", 1)
            port = int(port_text)
    if not host:
        fail("service_url must include a host: {}".format(service_url))
    if port < 1 or port > 65535:
        fail("service_url port must be between 1 and 65535: {}".format(service_url))

    return struct(
        service_url = "{}://{}".format(scheme, host_port),
        host = host,
        port = port,
        use_plaintext = scheme == "http",
    )

def _render_backend_config(package, service_url, default_port = None):
    _validate_kotlin_package(package)
    endpoint = _parse_service_url(service_url, default_port = default_port)

    return "\n".join([
        "package {}".format(package),
        "",
        "import victor.backend.client.BackendEndpoint",
        "",
        "object BackendConfig {",
        "    val endpoint =",
        "        BackendEndpoint(",
        "            serviceUrl = {},".format(json.encode(endpoint.service_url)),
        "            host = {},".format(json.encode(endpoint.host)),
        "            port = {},".format(endpoint.port),
        "            usePlaintext = {},".format("true" if endpoint.use_plaintext else "false"),
        "        )",
        "}",
        "",
    ])

def _android_service_url_config_src_impl(ctx):
    profile = ctx.attr._service_url_profile[AndroidStringFlagInfo].value
    service_url = ctx.attr.local_service_url
    default_port = _DEFAULT_LOCAL_SERVICE_URL_PORT
    if profile == "deploy":
        service_url = ctx.attr._deploy_service_url[AndroidStringFlagInfo].value
        default_port = None
        if not service_url:
            fail("{} is built for deploy, but no resolved deploy service URL was set".format(ctx.label))
    out = ctx.actions.declare_file("{}.kt".format(ctx.label.name))
    ctx.actions.write(
        out,
        _render_backend_config(ctx.attr.custom_package, service_url, default_port = default_port),
    )
    return [DefaultInfo(files = depset([out]))]

_android_service_url_config_src = rule(
    implementation = _android_service_url_config_src_impl,
    attrs = {
        "custom_package": attr.string(mandatory = True),
        "local_service_url": attr.string(default = _DEFAULT_LOCAL_SERVICE_URL),
        "_deploy_service_url": attr.label(default = _DEPLOY_SERVICE_URL),
        "_service_url_profile": attr.label(default = _SERVICE_URL_PROFILE),
    },
)

def android_service_url_config(
        name,
        custom_package,
        local_service_url = _DEFAULT_LOCAL_SERVICE_URL,
        visibility = None):
    """Generates a BackendConfig using local_service_url locally and the resolved deploy service URL for deploys."""
    src = "{}_src".format(name)
    _android_service_url_config_src(
        name = src,
        custom_package = custom_package,
        local_service_url = local_service_url,
    )
    kt_jvm_library(
        name = name,
        srcs = [":{}".format(src)],
        deps = ["//src/common/grpc/client:backend_endpoint"],
        visibility = visibility,
    )
