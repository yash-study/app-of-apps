{{/*
Expand the name of the chart.
*/}}
{{- define "cadence.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "cadence.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "cadence.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "cadence.labels" -}}
helm.sh/chart: {{ include "cadence.chart" . }}
{{ include "cadence.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "cadence.selectorLabels" -}}
app.kubernetes.io/name: {{ include "cadence.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Component labels
*/}}
{{- define "cadence.componentLabels" -}}
{{ include "cadence.labels" . }}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{/*
Component selector labels
*/}}
{{- define "cadence.componentSelectorLabels" -}}
{{ include "cadence.selectorLabels" . }}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{/*
Service account name
*/}}
{{- define "cadence.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "cadence.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
MySQL host
*/}}
{{- define "cadence.mysql.host" -}}
{{- .Values.mysql.host }}
{{- end }}

{{/*
MySQL port
*/}}
{{- define "cadence.mysql.port" -}}
{{- .Values.mysql.port | toString }}
{{- end }}

{{/*
MySQL default database
*/}}
{{- define "cadence.mysql.database" -}}
{{- .Values.mysql.databases.default }}
{{- end }}

{{/*
MySQL visibility database
*/}}
{{- define "cadence.mysql.visibilityDatabase" -}}
{{- .Values.mysql.databases.visibility }}
{{- end }}

{{/*
MySQL user
*/}}
{{- define "cadence.mysql.user" -}}
{{- .Values.mysql.user }}
{{- end }}

{{/*
MySQL secret name
*/}}
{{- define "cadence.mysql.secretName" -}}
{{- .Values.mysql.existingSecret }}
{{- end }}
