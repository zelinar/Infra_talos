{{/*
Expand the name of the chart.
*/}}
{{- define "alloy-daemonsets.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "alloy-daemonsets.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if hasPrefix $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Common labels for all resources in this chart.
*/}}
{{- define "alloy-daemonsets.labels" -}}
app.kubernetes.io/name: {{ include "alloy-daemonsets.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end -}}

{{/*
Selector labels (stable, used for matchLabels).
*/}}
{{- define "alloy-daemonsets.selectorLabels" -}}
app.kubernetes.io/name: {{ include "alloy-daemonsets.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Render a single Alloy config section.
*/}}
{{- define "alloy-daemonsets.renderAlloySection" -}}
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

{{/*
Render an ordered set of Alloy config sections.
*/}}
{{- define "alloy-daemonsets.renderAlloySections" -}}
{{- $root := .root -}}
{{- $config := default (dict) .config -}}
{{- $sections := get $config "sections" | default (dict) -}}
{{- $sectionOrder := get $config "sectionOrder" | default (list) -}}
{{- $rendered := list -}}
{{- range $name := $sectionOrder -}}
{{- $section := get $sections $name | default (dict) -}}
{{- $text := include "alloy-daemonsets.renderAlloySection" (dict "root" $root "section" $section) | trim -}}
{{- if $text -}}
{{- $rendered = append $rendered $text -}}
{{- end -}}
{{- end -}}
{{- join "\n\n" $rendered -}}
{{- end -}}
