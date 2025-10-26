{{/*
Helm Template Helpers
These functions are used throughout the templates to generate consistent names and labels
*/}}

{{/*
Expand the name of the chart.
Returns: "cadence" (or override from values.nameOverride)
*/}}
{{- define "cadence.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
Returns: "release-name-cadence" or just "release-name" if it contains "cadence"
Example: If release name is "cadence", returns "cadence"
         If release name is "my-release", returns "my-release-cadence"
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
Returns: "cadence-1.0.0"
Used in: helm.sh/chart label
*/}}
{{- define "cadence.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels applied to all resources
These labels help with resource management, querying, and ArgoCD tracking
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
These labels are used for pod selection and must be immutable
Used in: Deployment/StatefulSet selector and Service selector
*/}}
{{- define "cadence.selectorLabels" -}}
app.kubernetes.io/name: {{ include "cadence.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Component-specific labels
Adds app.kubernetes.io/component label to differentiate services
Usage: {{ include "cadence.componentLabels" (dict "component" "frontend" "context" $) }}
*/}}
{{- define "cadence.componentLabels" -}}
{{ include "cadence.labels" .context }}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{/*
Component-specific selector labels
Usage: {{ include "cadence.componentSelectorLabels" (dict "component" "frontend" "context" $) }}
*/}}
{{- define "cadence.componentSelectorLabels" -}}
{{ include "cadence.selectorLabels" .context }}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{/*
Service account name
Returns the name of the ServiceAccount to use
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
Returns the MySQL hostname or IP address
*/}}
{{- define "cadence.mysql.host" -}}
{{- .Values.mysql.host }}
{{- end }}

{{/*
MySQL port
Returns the MySQL port as a string
*/}}
{{- define "cadence.mysql.port" -}}
{{- .Values.mysql.port | toString }}
{{- end }}

{{/*
MySQL default database name
Returns the name of the default (main) Cadence database
*/}}
{{- define "cadence.mysql.database" -}}
{{- .Values.mysql.databases.default }}
{{- end }}

{{/*
MySQL visibility database name
Returns the name of the visibility database
*/}}
{{- define "cadence.mysql.visibilityDatabase" -}}
{{- .Values.mysql.databases.visibility }}
{{- end }}

{{/*
MySQL user
Returns the MySQL username
*/}}
{{- define "cadence.mysql.user" -}}
{{- .Values.mysql.user }}
{{- end }}

{{/*
MySQL secret name
Returns the name of the Kubernetes secret containing MySQL credentials
This secret is created by External Secrets Operator
*/}}
{{- define "cadence.mysql.secretName" -}}
{{- .Values.mysql.existingSecret }}
{{- end }}

{{/*
Component image
Returns the full image path for a component
Usage: {{ include "cadence.componentImage" (dict "component" .Values.frontend "context" $) }}
*/}}
{{- define "cadence.componentImage" -}}
{{- if .component.image }}
{{- printf "%s:%s" .component.image.repository .component.image.tag }}
{{- else }}
{{- printf "%s:%s" .context.Values.global.image.repository .context.Values.global.image.tag }}
{{- end }}
{{- end }}
