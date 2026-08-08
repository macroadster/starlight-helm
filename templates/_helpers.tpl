{{/*
Ingress controller provider: traefik (default) or nginx (retired community controller).
*/}}
{{- define "stargate.ingress.provider" -}}
{{- default "traefik" .Values.ingress.provider -}}
{{- end -}}

{{/*
IngressClass name. Explicit ingress.className wins; otherwise provider default.
*/}}
{{- define "stargate.ingress.className" -}}
{{- if .Values.ingress.className -}}
{{- .Values.ingress.className -}}
{{- else if eq (include "stargate.ingress.provider" .) "nginx" -}}
nginx
{{- else -}}
traefik
{{- end -}}
{{- end -}}

{{/*
True when the retired community ingress-nginx TCP ConfigMap path is in play.
*/}}
{{- define "stargate.ingress.useNginxTCP" -}}
{{- if eq (include "stargate.ingress.provider" .) "nginx" -}}
true
{{- end -}}
{{- end -}}

{{/*
Merged Ingress annotations. nginx provider injects common defaults; caller annotations win.
*/}}
{{- define "stargate.ingress.annotations" -}}
{{- $defaults := dict }}
{{- if eq (include "stargate.ingress.provider" .) "nginx" }}
{{- $defaults = dict
      "nginx.ingress.kubernetes.io/ssl-redirect" "true"
      "nginx.ingress.kubernetes.io/proxy-body-size" "10m"
      "nginx.ingress.kubernetes.io/enable-access-log" "true"
}}
{{- end }}
{{- $ann := mergeOverwrite $defaults (.Values.ingress.annotations | default dict) }}
{{- if gt (len $ann) 0 }}
{{- toYaml $ann }}
{{- end }}
{{- end }}
