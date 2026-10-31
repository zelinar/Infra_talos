{{/*
victoria-common.vmBackupBlock
*/}}
{{- define "victoria-common.vmBackupBlock" -}}
{{- $b := . | default dict -}}
{{- if $b.enabled -}}
vmBackup:
{{- $spec := omit $b "enabled" -}}
{{- if $spec }}
{{ toYaml $spec | nindent 2 }}
{{- else }}
  {}
{{- end }}
{{- end -}}
{{- end -}}
