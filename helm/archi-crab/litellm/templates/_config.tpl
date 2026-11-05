{{/*
LiteLLM's config.yaml, in one place: the ConfigMap holds it and the Deployment's pod template carries its
sha256 (checksum/config), so a model or setting change rolls the pod by itself (no manual rollout restart).
*/}}
{{- define "litellm.config" -}}
{{- if contains "__MIMO_FLASH__" (toYaml .Values.models) }}
{{- fail "litellm: values-staging.yaml still holds the placeholder __MIMO_FLASH__: put AIGW's model id there (aigw-keys.sh add prints it)" }}
{{- end -}}
model_list:
{{- if .Values.models }}
{{ toYaml .Values.models | indent 2 }}
{{- else }}
  []   # TODO populate. See values.yaml for why there is no quality chain.
{{- end }}
litellm_settings:
  drop_params: true
{{- if .Values.telemetry.otel }}
  callbacks: ["otel"]
{{- end }}
{{- end -}}
