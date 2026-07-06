{{/*
Expand the chart name.
*/}}
{{- define "webapp.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "webapp.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := include "webapp.name" . -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Common labels.
*/}}
{{- define "webapp.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
app.kubernetes.io/name: {{ include "webapp.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/*
Selector labels.
*/}}
{{- define "webapp.selectorLabels" -}}
app.kubernetes.io/name: {{ include "webapp.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
TLS secret name.
*/}}
{{- define "webapp.tlsSecretName" -}}
{{- default (printf "%s-tls" (include "webapp.fullname" .)) .Values.tls.secretName -}}
{{- end -}}

{{/*
Self-signed issuer name.
*/}}
{{- define "webapp.selfSignedIssuerName" -}}
{{- default (printf "%s-selfsigned" (include "webapp.fullname" .)) .Values.certManager.selfSigned.issuerName -}}
{{- end -}}

{{/*
Gateway name.
*/}}
{{- define "webapp.gatewayName" -}}
{{- default (printf "%s-gateway" (include "webapp.fullname" .)) .Values.route.gateway.name -}}
{{- end -}}

{{/*
Required route hostname.
*/}}
{{- define "webapp.hostname" -}}
{{- required "route.hostname is required" .Values.route.hostname -}}
{{- end -}}
