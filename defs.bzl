# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache-2.0 License, at your convenience
#
# This product includes software developed at Datadog (https://www.datadoghq.com/). Copyright 2020 Datadog, Inc.

def debug(rctx, *args):
    if rctx.attr.debug or rctx.os.environ.get("OCI_BOOTSTRAP_DEBUG") == "true":
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

    debug(rctx, "reading docker config from: ", raw_config_path)

    config_path = rctx.path(raw_config_path)
    if not config_path.exists:
        return {}

    data = json.decode(rctx.read(config_path))
    if "credHelpers" not in data:
        return {}

    return data["credHelpers"]

def _get_registry_auth(rctx, registry):
    helpers = _read_cred_helpers(rctx)

    debug(rctx, "found helpers: ", helpers)

    helper = helpers.get(registry)
    if helper == None:
        return None

    script = """
    #!/bin/bash
    echo {registry} | docker-credential-{helper} get
    """.format(registry = registry, helper = helper)

    res = _execute_script(rctx, script)
    if res.return_code > 0:
        fail("failed to run credential helper, stdout: {}, stderr: {}".format(res.stdout, res.stderr))

    debug(rctx, "credential helper out: ", res.stdout)

    return struct(**json.decode(res.stdout))

def _oci_blob_pull_impl(rctx):
    registry = rctx.attr.registry
    registry_env = rctx.os.environ.get("OCI_REGISTRY_HOST")
    if registry_env != None and registry_env != "":
        registry = registry_env
    debug(rctx, "using '{}' as registry, env set to '{}'".format(registry, registry_env))

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
    else:
        result = rctx.execute([rctx.path(rctx.attr.token_handler), registry, rctx.attr.repository])
        data = json.decode(result.stdout)
        token = data.get("token")
        if token != None:
            auths = {
                blob_url: {
                    "type": "pattern",
                    "pattern": "Bearer {}".format(token),
                },
            }

    debug(rctx, "pulling from: ", blob_url)

    algo, sha256digest = rctx.attr.digest.split(":")
    if rctx.attr.extract:
        rctx.download_and_extract(
            url = blob_url,
            sha256 = sha256digest,
            auth = auths,
            type = rctx.attr.type,
            stripPrefix = rctx.attr.strip_prefix,
        )
    else:
        rctx.download(
            url = blob_url,
            output = rctx.path(rctx.attr.file_name),
            sha256 = sha256digest,
            auth = auths,
        )

    if rctx.attr.build_file_content != "":
        rctx.file("BUILD.bazel", rctx.attr.build_file_content)

oci_blob_pull = repository_rule(
    implementation = _oci_blob_pull_impl,
    doc = """
    Pull a blob from an OCI registry using the http API. This rule also follows
    the docker credential helper pattern to authenticate to the registry if
    listed in the `.docker/config.json`.
    """,
    attrs = {
        "registry": attr.string(
            mandatory = True,
            doc = "The registry host to pull from, can be overidden by the 'OCI_REGISTRY_HOST' env variable.",
        ),
        "repository": attr.string(
            mandatory = True,
            doc = "The OCI repository to pull from.",
        ),
        "digest": attr.string(
            mandatory = True,
            doc = "The expected algo:digest of the artifact, for example 'sha256:abcd'",
        ),
        # XXX: We're specifically not supporting tags as we want this to be
        # reproducable.
        "build_file_content": attr.string(
            default = """exports_files(glob(["*"]))""",
            doc = "The content to place in the build file at the root of the repository",
        ),
        "file_name": attr.string(
            default = "blob",
            doc = "If not being extracted, then save the file as this name",
        ),
        "extract": attr.bool(
            default = False,
            doc = "If true, extract the blob as if it were a archive",
        ),
        "type": attr.string(
            default = "tar.gz",
            doc = "The archive type, aka zip, tar, tar.gz, etc.",
        ),
        "strip_prefix": attr.string(
            default = "",
            doc = "A directory prefix to strip from the extracted files.",
        ),
        "token_handler": attr.label(
            default = "//:token.py",
        ),
        "debug": attr.bool(
            default = False,
            doc = "emit debug logs",
        ),
    },
    environ = [
        "OCI_REGISTRY_HOST",
        "HOME",
        "DOCKER_CONFIG",
        "OCI_BOOTSTRAP_DEBUG",
    ],
)
