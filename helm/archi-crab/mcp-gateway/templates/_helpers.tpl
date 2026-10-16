{{/*
The naming contract, in one place. Every chart in this stack defines the same
two helpers so a name is never assembled by hand in a template.

  prod      nameSuffix ""          -> crab-mcp-gateway
  staging   nameSuffix "-staging"  -> crab-mcp-gateway-staging
*/}}
{{- define "archi.name" -}}
{{- printf "%s%s" .base (.ctx.Values.nameSuffix | default "") -}}
{{- end -}}

{{/*
Labels carried by EVERY object. env is the join key across Gateway selectors,
Prometheus scrapes and Langfuse traces -- never derived by parsing a name.
*/}}
{{- define "archi.labels" -}}
app.kubernetes.io/part-of: archi-crab
archi-crab.cern.ch/env: {{ .Values.env }}
{{- end -}}

{{/* An MCPServer's suffixed name, and the Service ToolHive derives from it. */}}
{{- define "mcp.serverName" -}}
{{- printf "%s%s" .srv.name (.ctx.Values.nameSuffix | default "") -}}
{{- end -}}

{{- define "mcp.proxyService" -}}
{{- printf "mcp-%s%s-proxy" .srv.name (.ctx.Values.nameSuffix | default "") -}}
{{- end -}}


{{/*
BUNDLE RELEASES (2026-10-16) -- the okg engine x corpus model, applied to the vMCP bundle.
  bundles.releases.<version> = {group, authzSet, backends?, frozen?}
  bundles.latest             = the ONE pointer; vMCPs with `release: latest` follow it
A vMCP with `release:` takes group, authzSet and backends from its release (no per-vMCP
copies to drift apart); a public one serves /releases/<version>/mcp unless `path` overrides.
vMCPs without `release:` keep the legacy per-vMCP keys (prod, okg-webui): unchanged render.
*/}}
{{- define "archi.vmcpRelease" -}}
{{- if .v.release -}}
{{- $r := .v.release -}}
{{- if eq $r "latest" }}{{ $r = .ctx.Values.bundles.latest }}{{ end -}}
{{- if not (hasKey .ctx.Values.bundles.releases (toString $r)) -}}
{{- fail (printf "vmcps[%s].release %q resolves to %q, which is not in bundles.releases" .v.name .v.release (toString $r)) -}}
{{- end -}}
{{- $r -}}
{{- end -}}
{{- end -}}

{{- define "archi.vmcpPath" -}}
{{- if .v.path -}}
{{- .v.path | trimSuffix "/" -}}
{{- else if and .v.release (ne .v.release "latest") (not .v.internal) -}}
{{- printf "/releases/%s" .v.release -}}
{{- end -}}
{{- end -}}

{{/*
A release's FINGERPRINT: everything that defines what its callers get -- the group's
MCPServers (image, env, operator list, bearer switch), its ServerEntries (URL, exchange
audience and client) and its Cedar policies. Ports, resources and comments are out: they
do not change behaviour. Stamped on every vMCP serving the release; a release with
`frozen: <fingerprint>` refuses to render once the members hash differently.
*/}}
{{- define "archi.bundleFingerprintInput" -}}
{{- $ctx := .ctx -}}
{{- $rel := index $ctx.Values.bundles.releases .release -}}
{{- range $s := $ctx.Values.servers }}
{{- if eq ($s.group | default $ctx.Values.group.name) $rel.group }}
server {{ $s.name }} {{ $s.image }} operators={{ $s.operatorUsernames | default "" }} disableBearerAuth={{ $s.disableBearerAuth | default false }}
{{- range $s.env }} {{ .name }}={{ .value | default "" }}{{ end }}
{{- end }}
{{- end }}
{{- range $e := $ctx.Values.serverEntries }}
{{- if eq ($e.group | default $ctx.Values.group.name) $rel.group }}
entry {{ $e.name }} {{ $e.url }} exchange={{ $e.exchangeAudience | default "" }}/{{ $e.clientId | default "" }}
{{- end }}
{{- end }}
{{- range (index $ctx.Values.authz.sets $rel.authzSet).policies }}
policy {{ . }}
{{- end }}
{{- end -}}

{{- define "archi.bundleFingerprint" -}}
{{- include "archi.bundleFingerprintInput" . | sha256sum | trunc 16 -}}
{{- end -}}
