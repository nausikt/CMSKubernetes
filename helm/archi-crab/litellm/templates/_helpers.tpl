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
