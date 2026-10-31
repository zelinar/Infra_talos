{{/*
Expand the name of the chart.
*/}}
{{- define "grafana-alloy.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
*/}}
{{- define "grafana-alloy.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "grafana-alloy.namespace" -}}
{{- .Release.Namespace }}
{{- end }}

{{- define "grafana-alloy.labels" -}}
app.kubernetes.io/name: {{ include "grafana-alloy.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end -}}

{{- define "grafana-alloy.selectorLabels" -}}
app.kubernetes.io/name: {{ include "grafana-alloy.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "grafana-alloy.serviceName" -}}
{{- printf "%s-%s" .Release.Name "alloy-external" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "grafana-alloy.renderAlloySection" -}}
{{- $root := .root -}}
{{- $section := default (dict) .section -}}
{{- $enabled := true -}}
{{- if hasKey $section "enabled" -}}
{{- $enabled = $section.enabled -}}
{{- end -}}
{{- if $enabled -}}
{{- $parts := list -}}
{{- with (get $section "content") -}}
{{- $rendered := tpl . $root | trim -}}
{{- if $rendered -}}
{{- $parts = append $parts $rendered -}}
{{- end -}}
{{- end -}}
{{- with (get $section "extra") -}}
{{- $rendered := tpl . $root | trim -}}
{{- if $rendered -}}
{{- $parts = append $parts $rendered -}}
{{- end -}}
{{- end -}}
{{- join "\n\n" $parts -}}
{{- end -}}
{{- end -}}

{{- define "grafana-alloy.renderAlloySections" -}}
{{- $root := .root -}}
{{- $config := default (dict) .config -}}
{{- $sections := get $config "sections" | default (dict) -}}
{{- $sectionOrder := get $config "sectionOrder" | default (list) -}}
{{- $rendered := list -}}
{{- range $name := $sectionOrder -}}
{{- $section := get $sections $name | default (dict) -}}
{{- $text := include "grafana-alloy.renderAlloySection" (dict "root" $root "section" $section) | trim -}}
{{- if $text -}}
{{- $rendered = append $rendered $text -}}
{{- end -}}
{{- end -}}
{{- join "\n\n" $rendered -}}
{{- end -}}

{{- define "grafana-alloy.durationSeconds" -}}
{{- $total := 0 -}}
{{- range $m := regexFindAll "[0-9]+[hms]" . -1 -}}
{{- $numLen := sub (len $m) 1 | int -}}
{{- $unit := substr $numLen (len $m) $m -}}
{{- $num := substr 0 $numLen $m | int -}}
{{- if eq $unit "h" -}}{{- $total = add $total (mul $num 3600) | int -}}
{{- else if eq $unit "m" -}}{{- $total = add $total (mul $num 60) | int -}}
{{- else -}}{{- $total = add $total $num | int -}}
{{- end -}}
{{- end -}}
{{- $total -}}
{{- end -}}
