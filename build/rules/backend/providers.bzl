"""Providers for backend endpoint configuration metadata."""

BackendDeployInfo = provider(
    fields = {
        "service": "Cloud Run service name for a backend deploy target.",
    },
)

BackendEndpointConfigInfo = provider(
    fields = {
        "deploy_service_url_flag": "Build setting flag used to inject the deploy service URL.",
        "service": "Cloud Run service name this endpoint config talks to.",
    },
)

BackendEndpointConfigSetInfo = provider(
    fields = {
        "entries": "Depset of JSON-encoded endpoint config metadata entries.",
    },
)
