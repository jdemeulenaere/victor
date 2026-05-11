"""Internal Kotlin/WASM compile and link rules for KMP targets."""

KtWasmInfo = provider(
    fields = {
        "klib": "The direct KLIB output for this target.",
        "transitive_klibs": "KLIBs needed to compile or link against this target.",
    },
)

_JAVA_RUNTIME_TOOLCHAIN_TYPE = "@bazel_tools//tools/jdk:runtime_toolchain_type"
_KOTLIN_TOOLCHAIN_TYPE = "@rules_kotlin//kotlin/internal:kt_toolchain_type"
_WASM_TOOLCHAIN_TYPE = "//build/rules/kotlin/multiplatform:wasm_toolchain_type"

def _dedupe_files(files):
    seen = {}
    deduped = []
    for file in files:
        if seen.get(file.path):
            continue
        seen[file.path] = True
        deduped.append(file)
    return deduped

def _collect_dep_klib_depsets(deps):
    klib_depsets = []
    for dep in deps:
        if KtWasmInfo in dep:
            klib_depsets.append(dep[KtWasmInfo].transitive_klibs)
        elif DefaultInfo in dep:
            klib_depsets.append(dep[DefaultInfo].files)
    return klib_depsets

def _compiler_jars(ctx):
    return _dedupe_files([
        file
        for file in ctx.toolchains[_KOTLIN_TOOLCHAIN_TYPE].kotlin_home[DefaultInfo].files.to_list()
        if file.basename.endswith(".jar") and not file.basename.endswith("-sources.jar")
    ])

def _java_executable(ctx):
    return ctx.toolchains[_JAVA_RUNTIME_TOOLCHAIN_TYPE].java_runtime.java_executable_exec_path

def _java_runtime_files(ctx):
    return ctx.toolchains[_JAVA_RUNTIME_TOOLCHAIN_TYPE].java_runtime.files.to_list()

def _plugin_jars(plugins):
    return _dedupe_files([
        file
        for plugin in plugins
        for file in plugin[DefaultInfo].files.to_list()
        if file.basename.endswith(".jar")
    ])

def _dedupe_strings(values):
    seen = {}
    deduped = []
    for value in values:
        if seen.get(value):
            continue
        seen[value] = True
        deduped.append(value)
    return deduped

def _fragment_source_flags(files, source_set_names):
    if len(files) != len(source_set_names):
        fail("expected source_set_names to match srcs length")
    return [
        "-Xfragment-sources={}:{}".format(source_set_names[index], files[index].path)
        for index in range(len(files))
    ]

def _write_lines(ctx, name, values):
    output = ctx.actions.declare_file("{}_{}.txt".format(ctx.label.name, name))
    ctx.actions.write(output = output, content = "\n".join(values) + ("\n" if values else ""))
    return output

def _compile_flags(ctx):
    fragments = _dedupe_strings(ctx.attr.source_set_names)
    return [
        "-Xwasm",
        "-Xwasm-target=wasm-js",
        "-Xir-produce-klib-file",
        "-Xmulti-platform",
        "-Xexpect-actual-classes",
    ] + [
        "-Xfragments={}".format(fragment)
        for fragment in fragments
    ] + [
        "-Xfragment-refines={}".format(refine)
        for refine in ctx.attr.fragment_refines
    ] + _fragment_source_flags(ctx.files.srcs, ctx.attr.source_set_names)

def _run_kotlinc_script(ctx, mode, output, module_name, libraries, plugins = [], flags = [], sources = [], main_klib = None):
    wasm_toolchain = ctx.toolchains[_WASM_TOOLCHAIN_TYPE].kmp_wasm
    compiler_jars = _compiler_jars(ctx)
    library_list = _write_lines(ctx, "{}_libraries".format(mode), [file.path for file in libraries])
    plugin_list = _write_lines(ctx, "{}_plugins".format(mode), [file.path for file in plugins])
    flag_list = _write_lines(ctx, "{}_flags".format(mode), flags)
    source_list = _write_lines(ctx, "{}_sources".format(mode), [file.path for file in sources])

    inputs = libraries + plugins + sources + [
        wasm_toolchain.kotlinc_script,
        library_list,
        plugin_list,
        flag_list,
        source_list,
    ] + compiler_jars + _java_runtime_files(ctx)

    ctx.actions.run_shell(
        inputs = depset(inputs),
        outputs = [output],
        command = "bash \"$@\"",
        arguments = [
            wasm_toolchain.kotlinc_script.path,
            mode,
            _java_executable(ctx),
            wasm_toolchain.compiler_main,
            ":".join([file.path for file in compiler_jars]),
            output.dirname if mode == "compile" else output.path,
            module_name,
            main_klib.path if main_klib else "",
            library_list.path,
            plugin_list.path,
            flag_list.path,
            source_list.path,
        ],
        mnemonic = "KtWasmCompile" if mode == "compile" else "KtWasmLink",
        progress_message = "{} Kotlin/WASM %{{label}}".format("Compiling" if mode == "compile" else "Linking"),
    )

def _kt_wasm_library_impl(ctx):
    output = ctx.actions.declare_file("{}.klib".format(ctx.attr.module_name))
    dep_klib_depsets = _collect_dep_klib_depsets(ctx.attr.deps)
    dep_klibs = depset(transitive = dep_klib_depsets)
    source_files = ctx.files.srcs
    plugin_jars = _plugin_jars(ctx.attr.plugins)

    _run_kotlinc_script(
        ctx = ctx,
        mode = "compile",
        output = output,
        module_name = ctx.attr.module_name,
        libraries = dep_klibs.to_list(),
        plugins = plugin_jars,
        flags = _compile_flags(ctx),
        sources = source_files,
    )

    transitive_klibs = depset([output], transitive = dep_klib_depsets)
    return [
        DefaultInfo(files = depset([output])),
        KtWasmInfo(
            klib = output,
            transitive_klibs = transitive_klibs,
        ),
    ]

kt_wasm_library = rule(
    implementation = _kt_wasm_library_impl,
    attrs = {
        "deps": attr.label_list(),
        "fragment_refines": attr.string_list(),
        "module_name": attr.string(mandatory = True),
        "plugins": attr.label_list(cfg = "exec"),
        "source_set_names": attr.string_list(),
        "srcs": attr.label_list(allow_files = [".kt"]),
    },
    toolchains = [_JAVA_RUNTIME_TOOLCHAIN_TYPE, _KOTLIN_TOOLCHAIN_TYPE, _WASM_TOOLCHAIN_TYPE],
)

def _kt_wasm_files_impl(ctx):
    output_dir = ctx.actions.declare_directory(ctx.label.name)
    module_info = ctx.attr.module[KtWasmInfo]

    _run_kotlinc_script(
        ctx = ctx,
        mode = "link",
        output = output_dir,
        module_name = ctx.attr.module_name,
        libraries = module_info.transitive_klibs.to_list(),
        main_klib = module_info.klib,
    )

    return [DefaultInfo(files = depset([output_dir]))]

kt_wasm_files = rule(
    implementation = _kt_wasm_files_impl,
    attrs = {
        "module": attr.label(mandatory = True, providers = [KtWasmInfo]),
        "module_name": attr.string(mandatory = True),
    },
    toolchains = [_JAVA_RUNTIME_TOOLCHAIN_TYPE, _KOTLIN_TOOLCHAIN_TYPE, _WASM_TOOLCHAIN_TYPE],
)

def _kt_wasm_imports_impl(ctx):
    files = ctx.attr.files[DefaultInfo].files.to_list()
    directories = [file for file in files if file.is_directory]
    if len(directories) != 1:
        fail("expected exactly one Kotlin/WASM files directory, found {}: {}".format(len(directories), [file.path for file in directories]))

    output = ctx.actions.declare_directory(ctx.attr.out)
    ctx.actions.run_shell(
        inputs = depset(files),
        outputs = [output],
        command = "mkdir -p \"$1\" && cp -RP \"$2\"/. \"$1\"/",
        arguments = [
            output.path,
            directories[0].path,
        ],
        mnemonic = "KtWasmImports",
        progress_message = "Preparing Kotlin/WASM imports %{label}",
    )

    return [DefaultInfo(files = depset([output]))]

kt_wasm_imports = rule(
    implementation = _kt_wasm_imports_impl,
    attrs = {
        "files": attr.label(mandatory = True),
        "out": attr.string(mandatory = True),
    },
)
