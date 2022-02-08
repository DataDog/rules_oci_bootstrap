def _execute_script(rctx, content):
    file = rctx.path("script.sh")
    rctx.file(file, content = content, executable = True)
    res = rctx.execute([file.realpath])
    rctx.delete(file)
    return res

def _read_cred_helpers(rctx):
    raw_config_path = rctx.os.environ["HOME"] + "/.docker/config.json"
    docker_config_env = rctx.os.environ.get("DOCKER_CONFIG")
    if docker_config_env != None:
        raw_config_path_base = docker_config_env + "/config.json"

    config_path = rctx.path(raw_config_path)
    if not config_path.exists:
        return {}

    data = json.decode(rctx.read(config_path))
    if "credHelpers" not in data:
        return {}

    return data["credHelpers"]

def _get_registry_auth(rctx, registry):
    helpers = _read_cred_helpers(rctx)

    helper = helpers.get(registry)
    if helper == None:
        return None

    script = """
    #!/bin/bash
    echo {registry} | docker-credential-{helper} get
    """.format(registry = registry, helper = helper)

    res = _execute_script(rctx, script)

    return struct(**json.decode(res.stdout))

def _dd_oci_blob_pull_impl(rctx):
    registry = rctx.attr.registry
    registry_env = rctx.os.environ.get("DD_REGISTRY_HOST")
    if registry_env != None:
        registry = registry_env

    blob_url = "https://{registry}/v2/{repository}/blobs/{digest}".format(
        registry = registry,
        repository = rctx.attr.repository,
        digest = rctx.attr.digest,
    )

    auth_secret = _get_registry_auth(rctx, registry)
    auths = {}
    if auth_secret != None:
        auths = {
            blob_url: {
                "type": "basic",
                "login": auth_secret.Username,
                "password": auth_secret.Secret,
            },
        }

    print(blob_url, auths)
    algo, sha256digest = rctx.attr.digest.split(":")
    rctx.download(
        url = blob_url,
        output = rctx.path(rctx.attr.file_name),
        sha256 = sha256digest,
        auth = auths,
    )

    rctx.file("BUILD.bazel", rctx.attr.build_file_content)

dd_oci_blob_pull = repository_rule(
    implementation = _dd_oci_blob_pull_impl,
    attrs = {
        "registry": attr.string(),
        "repository": attr.string(),
        "digest": attr.string(),
        "build_file_content": attr.string(
            default = """exports_files(glob(["*"]))""",
        ),
        "file_name": attr.string(
            default = "blob",
        ),
    },
    environ = [
        "DD_REGISTRY_HOST",
        "HOME",
        "DOCKER_CONFIG",
    ],
)
