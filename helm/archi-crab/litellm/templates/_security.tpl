{{/*
Pod and container security defaults. Every workload this stack authors uses
these; nothing runs as root, nothing writes to its root filesystem, nothing
keeps a capability it does not need.

The MCP backend containers get equivalent settings from ToolHive itself; these
cover the components we deploy directly (Redis, LiteLLM, collector, OpenWebUI).
*/}}
{{- define "archi.podSecurityContext" -}}
runAsNonRoot: true
runAsUser: 65532
runAsGroup: 65532
fsGroup: 65532
seccompProfile:
  type: RuntimeDefault
{{- end -}}

{{- define "archi.containerSecurityContext" -}}
allowPrivilegeEscalation: false
readOnlyRootFilesystem: true
privileged: false
capabilities:
  drop: ["ALL"]
{{- end -}}
