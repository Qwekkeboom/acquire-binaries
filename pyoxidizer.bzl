def make_exe():
    dist = default_python_distribution(flavor=VARS["flavor"])

    policy = dist.make_python_packaging_policy()
    policy.bytecode_optimize_level_two = True
    policy.file_scanner_classify_files = True
    policy.resources_location = "in-memory"

    python_config = dist.make_python_interpreter_config()
    python_config.oxidized_importer = True
    python_config.filesystem_importer = True
    python_config.run_module = "acquire.acquire"

    exe = dist.to_python_executable(
        name="acquire",
        packaging_policy=policy,
        config=python_config,
    )
    exe.windows_runtime_dlls_mode = "when-present"

    # Dependency list of acquire: everything the collection modules and the registered
    # target plugins need, excluding what can't be packaged in this build:
    # - dissect.fve and pycryptodome: crypto extension modules are filtered out
    # - backports.zstd: compiled extension, cannot be loaded from memory on Windows
    # - fusepy: sdist only, incompatible with PyOxidizer's binary-only pip download
    # - ipython: interactive shell only, not needed for acquisition
    pip_args = [
        "acquire==" + VARS["version"],
        "asn1crypto",
        "dissect.cim",
        "dissect.clfs",
        "dissect.cstruct",
        "dissect.etl",
        "dissect.eventlog",
        "dissect.evidence",
        "dissect.executable",
        "dissect.extfs",
        "dissect.fat",
        "dissect.ffs",
        "dissect.hypervisor",
        "dissect.ntfs",
        "dissect.ole",
        "dissect.regf",
        "dissect.shellitem",
        "dissect.squashfs",
        "dissect.target",
        "dissect.thumbcache",
        "dissect.util",
        "dissect.vmfs",
        "dissect.volume",
        "dissect.xfs",
        "minio",
        "ruamel.yaml",
    ]

    # If you want to build acquire from the local source directory, uncomment this and remove the acquire pin from pip_args
    # exe.add_python_resources(exe.read_package_root(CWD, ["acquire"]))

    # Lie about our platform to get cross-compilation to work (msgpack fails to download otherwise)
    if BUILD_TARGET_TRIPLE == "x86_64-pc-windows-msvc":
        pip_args += ["--platform", "win_amd64"]
    elif BUILD_TARGET_TRIPLE == "i686-pc-windows-msvc":
        pip_args += ["--platform", "win32"]
    elif BUILD_TARGET_TRIPLE == "x86_64-unknown-linux-musl":
        pip_args += ["--platform", "manylinux2014_x86_64"]

    # Use pip_download for all the dependencies
    for resource in exe.pip_download(pip_args):
        # Discard msgpack's extension, it has a pure Python fallback
        if resource.name == "msgpack._cmsgpack":
            continue

        # Discard the native Rust extensions of dissect.util, they can't be loaded
        # from memory on Windows and have a pure Python fallback (lz4, lzo and crc32c)
        if resource.name.startswith("dissect.util._native"):
            continue

        # The crypto portions of minio aren't needed for normal usage
        if resource.name == "_cffi_backend" or resource.name.startswith("_argon2_cffi_bindings"):
            continue

        # Discard pycryptodome fully for the time being, unsure how to make it play nicely
        if resource.name.startswith("Crypto"):
            continue

        exe.add_python_resource(resource)

    # Add the _pluginlist.py "overlay"
    # This is created by the CI, if you want to build manually, be sure to generate it:
    # mkdir -p build/lib/dissect/target/plugins/ && target-build-pluginlist > build/lib/dissect/target/plugins/_pluginlist.py
    exe.add_python_resources(exe.read_package_root("build/lib", ["dissect"]))

    # If you want to add your own configuration customizations, you can put them in here
    # 'arguments' allows you to override specific arguments by default, e.g. ['--compress']
    # 'public_key' allows you to include a PEM encoded RSA public key for output encryption
    # NOTE: pycryptodome is not currently packaged in this PyOxidizer configuration, so output encryption is unavailable
    # 'upload' allows you to configure upload credentials
    # Example AWS S3 configuration: {'mode': 'cloud', 'endpoint': 's3.amazonaws.com', 'access_id': '', 'access_key': '', 'bucket': ''}
    exe.add_python_resource(
        exe.make_python_module_source(
            "acquire.config",
            "CONFIG = {'arguments': [], 'public_key': '', 'upload': {}}",
            False
        )
    )

    return exe


def make_embedded_resources(exe):
    return exe.to_embedded_resources()


def make_install(exe):
    files = FileManifest()
    files.add_python_resource(".", exe)

    return files


register_target("exe", make_exe)
register_target("resources", make_embedded_resources, depends=["exe"], default_build_script=True)
register_target("install", make_install, depends=["exe"], default=True)

resolve_targets()
