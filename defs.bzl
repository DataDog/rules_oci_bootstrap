# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache-2.0 License, at your convenience
#
# This product includes software developed at Datadog (https://www.datadoghq.com/). Copyright 2020 Datadog, Inc.

DEBUG = False
def debug(*args):
    if DEBUG:
        print(*args)

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

    debug("reading docker config from: ", raw_config_path)

    config_path = rctx.path(raw_config_path)
    if not config_path.exists:
        return {}

    data = json.decode(rctx.read(config_path))
    if "credHelpers" not in data:
        return {}

    return data["credHelpers"]

def _get_registry_auth(rctx, registry):
    helpers = _read_cred_helpers(rctx)

    debug("found helpers: ", helpers)

    helper = helpers.get(registry)
    if helper == None:
        return None

    script = """
    #!/bin/bash
    echo {registry} | docker-credential-{helper} get
    """.format(registry = registry, helper = helper)

    res = _execute_script(rctx, script)

    return struct(**json.decode(res.stdout))

def _oci_blob_pull_impl(rctx):
    registry = rctx.attr.registry
    registry_env = rctx.os.environ.get("OCI_REGISTRY_HOST")
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

    debug("Pulling from: ", blob_url, ", auth token: ", auths)
    algo, sha256digest = rctx.attr.digest.split(":")
    rctx.download(
        url = blob_url,
        output = rctx.path(rctx.attr.file_name),
        sha256 = sha256digest,
        auth = auths,
    )

    if rctx.attr.extract:
        rctx.extract(rctx.path(rctx.attr.file_name))

    rctx.file("BUILD.bazel", rctx.attr.build_file_content)

oci_blob_pull = repository_rule(
    implementation = _oci_blob_pull_impl,
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
        "extract": attr.bool(
            default = False,
        )
    },
    environ = [
        "OCI_REGISTRY_HOST",
        "HOME",
        "DOCKER_CONFIG",
    ],
)
