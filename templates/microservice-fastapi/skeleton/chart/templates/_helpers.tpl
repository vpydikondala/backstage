{{- define "backstage.name" -}}
{{ .Chart.Name }}
{{- end }}

{{- define "backstage.chart" -}}
{{ .Chart.Name }}-{{ .Chart.Version }}
{{- end }}
