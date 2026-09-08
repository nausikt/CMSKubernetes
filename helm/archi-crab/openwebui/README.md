# archi-crab-openwebui (skeleton)

Wiring only — the Deployment, Service, HTTPRoute and the three things it must be
pointed at. Fill in the rest yourself.

## What it is wired to

| | |
|---|---|
| Models | the **per-env** LiteLLM, never a provider directly |
| MCP servers | their **public hostnames**, authenticating like any other client |
| Identity | the **same** CERN client as the MCP servers — add a redirect URI, do not register a second App |
| Telemetry | the per-env OTel collector, carrying `deployment.environment` |

## The one rule worth keeping

OpenWebUI reaches the MCP servers over their public URLs and completes the same
OAuth flow any other MCP client would. It is tempting to give it an in-cluster
shortcut to `mcp-<name>-proxy:8080` and skip the auth. Don't: that path bypasses
the ToolHive proxy's token validation, so the thing you are testing in preprod
is no longer the thing running in prod.
