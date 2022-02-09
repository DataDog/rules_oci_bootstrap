# `rules_oci_bootstrap` - Bazel rules to bootstrap from an OCI registry

These rules implement repository rules to pull blobs from an oci registry,
including authentication from docker credential helpers. Serving the primary
use-case of bootstrapping a Bazel `WORKSPACE` solely from a OCI artifact
registry.

## Motivation

At Datadog we have a globally distributed [OCI artifact registry](https://github.com/opencontainers/distribution-spec/blob/v1.0.1/spec.md)
that we pull artifacts to be used at build time from.

In the past we checked in large Go binaries into source control that knew how
to pull from the registry, however this binary became quickly disconnected from
the actual source, slowed down pulling times and was unable to be cached by
Bazel because it wasn't using `rctx.download`.

This implementation is purely Bazel Starlark-based, using the
[`repository_ctx`](https://docs.bazel.build/versions/main/skylark/lib/repository_ctx.html#download)
apis so that blobs pulled by these rules can be cached by Bazel.

In addition to issues mentioned above, we have multiple network
partitions where the registry defined in the `WORKSPACE` file is not always available.
In this case, a script that wraps the `bazel` command can override the registry
host via the `OCI_REGISTRY_HOST` environment variable.

## Setup

To import this repository while on MacOS, run the following and then paste into
your `WORKSPACE` file:
```
echo """
git_repository(
    name = \"rules_oci_bootstrap\",
    remote = \"https://github.com/DataDog/rules_oci_bootstrap.git\",
    commit = \"$(git ls-remote ssh://git@github.com/DataDog/rules_oci_bootstrap | head -1 | cut -f 1)\",
)
""" | pbcopy
```

On Linux run the following command to get the latest commit:
```
git ls-remote ssh://git@github.com/DataDog/rules_oci_bootstrap | head -1 | cut -f 1
```

Then substitiute `$COMMIT` in the following block, which you can paste in your
`WORKSPACE` file:
```
git_repository(
    name = "rules_oci_bootstrap",
    remote = "https://github.com/DataDog/rules_oci_bootstrap.git",
    commit = "$COMMIT",
)
```

## Usage

To pull a single file, which can be referenced at `@test_blob//:blob`, you can
add something like the following to your `WORKSPACE`:
```
load("@rules_oci_bootstrap//:defs.bzl", "oci_blob_pull")

oci_blob_pull(
    name = "test_blob",
    registry = "registry.example.com",
    repository = "my/repository",
    digest = "sha256:abcd...",
)
```

To pull a `.tar.gz` (or any other archive), you can do something like this,
however you may want to provide your own `BUILD` file via `build_file_content`:
```
load("@rules_oci_bootstrap//:defs.bzl", "oci_blob_pull")

oci_blob_pull(
    name = "test_blob",
    registry = "registry.example.com",
    repository = "my/repository",
    digest = "sha256:abcd...",
    extract = True,
    type = "tar.gz",
)
```

NOTE: The registry can be overriden by setting `OCI_REGISTRY_HOST`, which will override
the registry parameter. This should be done by a script that wraps `bazel` when the
user is in a different network partition, when not provided the `registry`
attribute will serve as the default.
