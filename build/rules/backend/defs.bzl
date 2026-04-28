"""Shared backend endpoint config generation rules."""

load("@rules_java//java:defs.bzl", "JavaInfo")
load("@rules_kotlin//kotlin:jvm.bzl", "kt_jvm_library")
load("@rules_kotlin//kotlin/internal:defs.bzl", "KtJvmInfo")
load(":providers.bzl", "BackendDeployInfo", "BackendEndpointConfigInfo")

BackendStringFlagInfo = provider(fields = ["value"])

DEFAULT_LOCAL_SERVICE_URL = "127.0.0.1"
DEFAULT_LOCAL_SERVICE_URL_PORT = 8080
_DEFAULT_SERVICE_URL_PROFILE = "//build/rules/backend:backend_service_url_profile"

def _string_flag_impl(ctx):
    return [BackendStringFlagInfo(value = ctx.build_setting_value)]

backend_string_flag = rule(
    implementation = _string_flag_impl,
    build_setting = config.string(flag = True),
)

def _repo_label(label):
    if label.package:
        return "//{}:{}".format(label.package, label.name)
    return "//:{}".format(label.name)

def backend_service_url_settings():
    """Declares backend service URL build settings in the current package."""
    backend_string_flag(
        name = "backend_service_url_profile",
        build_setting_default = "local",
        visibility = ["//visibility:public"],
    )

    native.config_setting(
        name = "backend_service_url_profile_deploy",
        flag_values = {
            ":backend_service_url_profile": "deploy",
        },
        visibility = ["//visibility:public"],
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

def _backend_service_url_config_src_impl(ctx):
    service_url = ctx.attr.local_service_url
    default_port = ctx.attr.local_default_port
    if ctx.attr.service_url_profile != None:
        profile = ctx.attr.service_url_profile[BackendStringFlagInfo].value
        if profile == ctx.attr.deploy_profile:
            service_url = ctx.attr.deploy_service_url[BackendStringFlagInfo].value
            default_port = None
            if not service_url:
                fail("{} is built for deploy, but no resolved deploy service URL was set".format(ctx.label))

    out = ctx.actions.declare_file("{}.kt".format(ctx.label.name))
    ctx.actions.write(
        out,
        _render_backend_config(ctx.attr.custom_package, service_url, default_port = default_port),
    )
    return [DefaultInfo(files = depset([out]))]

_backend_service_url_config_src = rule(
    implementation = _backend_service_url_config_src_impl,
    attrs = {
        "custom_package": attr.string(mandatory = True),
        "deploy_profile": attr.string(default = "deploy"),
        "deploy_service_url": attr.label(),
        "local_default_port": attr.int(default = DEFAULT_LOCAL_SERVICE_URL_PORT),
        "local_service_url": attr.string(default = DEFAULT_LOCAL_SERVICE_URL),
        "service_url_profile": attr.label(),
    },
)

def _backend_endpoint_config_impl(ctx):
    library = ctx.attr.library
    backend = ctx.attr.backend[BackendDeployInfo]

    return [
        library[DefaultInfo],
        library[JavaInfo],
        library[KtJvmInfo],
        BackendEndpointConfigInfo(
            deploy_service_url_flag = _repo_label(ctx.attr.deploy_service_url.label),
            service = backend.service,
        ),
    ]

_backend_endpoint_config = rule(
    implementation = _backend_endpoint_config_impl,
    attrs = {
        "backend": attr.label(
            # This dependency is deploy metadata, not app code.
            cfg = "exec",
            mandatory = True,
            providers = [BackendDeployInfo],
        ),
        "deploy_service_url": attr.label(
            mandatory = True,
            providers = [BackendStringFlagInfo],
        ),
        "library": attr.label(
            mandatory = True,
            providers = [JavaInfo, KtJvmInfo],
        ),
    },
    provides = [JavaInfo, KtJvmInfo, BackendEndpointConfigInfo],
)

def backend_endpoint_config(
        name,
        custom_package,
        backend,
        local_service_url = DEFAULT_LOCAL_SERVICE_URL,
        local_default_port = DEFAULT_LOCAL_SERVICE_URL_PORT,
        deploy_profile = "deploy",
        service_url_profile = _DEFAULT_SERVICE_URL_PROFILE,
        visibility = None):
    """Generates a Kotlin BackendConfig exposing a parsed BackendEndpoint."""
    src = "{}_src".format(name)
    library = "{}__library".format(name)
    deploy_service_url = "{}_deploy_service_url".format(name)

    backend_string_flag(
        name = deploy_service_url,
        build_setting_default = "",
        visibility = ["//visibility:public"],
    )

    src_kwargs = {
        "custom_package": custom_package,
        "deploy_profile": deploy_profile,
        "deploy_service_url": ":{}".format(deploy_service_url),
        "local_default_port": local_default_port,
        "local_service_url": local_service_url,
    }
    if service_url_profile != None:
        src_kwargs["service_url_profile"] = service_url_profile

    _backend_service_url_config_src(
        name = src,
        **src_kwargs
    )
    kt_jvm_library(
        name = library,
        srcs = [":{}".format(src)],
        deps = ["//src/common/grpc/client:backend_endpoint"],
        visibility = ["//visibility:private"],
    )
    _backend_endpoint_config(
        name = name,
        backend = backend,
        deploy_service_url = ":{}".format(deploy_service_url),
        library = ":{}".format(library),
        visibility = visibility,
    )
