# `rules_dd_bootstrap` - Bazel rules to bootstrap from an OCI registry

These rules implement repository rules to pull blobs from an oci registry,
including authentication from docker credential helpers.

Example blob pull:
```
load("@rules_dd_bootstrap//:defs.bzl", "dd_oci_blob_pull")
dd_oci_blob_pull(
    name = "test-blob",
    registry = "registry.ddbuild.io",
    repository = "cnab-tools/cmd/judgement-invocation/bundle",
    digest = "sha256:e75309da83eda9d0efbb168a7d46e8caff8d6a850fd19e28f22774869bb58bc0"
)
```

The registry can be overriden by setting `DD_REGISTRY_HOST`, which will force
a fetch.
