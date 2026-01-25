{{- define "camunda-custom.fullname" -}}
{{- .Release.Name }}-camunda
{{- end }}

{{- define "camunda-custom.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}