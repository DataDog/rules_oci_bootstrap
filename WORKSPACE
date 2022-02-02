
load("@dd_rules_http//:defs.bzl", "dd_where_am_i")
dd_where_am_i()

load("@dd_rules_http//:http.bzl", "dd_http_archive", "dd_http_file")
dd_http_archive(
    name = "cnab_tools"
    urls = [
        "registry.ddbuild.io/*",
    ],
    digest = "whatever",
)
