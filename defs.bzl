def _impl(rctx):
    if CI:
        rctx.template('registry.bzl', template="REGISTRY=\"registry.ddbuild\"")
    else:
        # check ddtool

    rctx.file('BUILD.bazel')

_dd_where_am_i = repository_rule(
    implementation=_impl,
    env = [
        "CI",
    ],
)

def dd_where_am_i(name="dd_registry_uri"):
    _dd_where_am_i(
        name = name,
    )

load("@dd_registry_uri//:registry.bzl", "REGISTRY")

def dd_http_archive(urls, **kwargs):
    # Modify URL iff host === registry.ddbuild.io
    http_archive(
        **kwargs,
    )
