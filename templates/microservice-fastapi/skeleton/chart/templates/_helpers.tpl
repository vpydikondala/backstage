{{- define "backstage.fullname" -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{- define "backstage.name" -}}
{{ .Chart.Name }}
{{- end }}

{{- define "backstage.chart" -}}
{{ .Chart.Name }}-{{ .Chart.Version }}
{{- end }}
