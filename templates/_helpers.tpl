{{/*
Ingress controller provider: traefik (default), gateway (Gateway API HTTPRoute),
or nginx (retired community controller).
*/}}
{{- define "stargate.ingress.provider" -}}
{{- default "traefik" .Values.ingress.provider -}}
{{- end -}}

{{/*
True when the networking.k8s.io Ingress object should be rendered.
*/}}
{{- define "stargate.ingress.useIngress" -}}
{{- $p := include "stargate.ingress.provider" . -}}
{{- if or (eq $p "traefik") (eq $p "nginx") -}}
true
{{- end -}}
{{- end -}}

{{/*
True when a Gateway API HTTPRoute should be rendered.
*/}}
{{- define "stargate.ingress.useGateway" -}}
{{- if eq (include "stargate.ingress.provider" .) "gateway" -}}
true
{{- end -}}
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
Hostnames for HTTPRoute / Certificate (tls.hosts, then frontend/backend).
*/}}
{{- define "stargate.ingress.hosts" -}}
{{- $hosts := list -}}
{{- range .Values.ingress.tls | default list -}}
{{- range .hosts | default list -}}
{{- $hosts = append $hosts . -}}
{{- end -}}
{{- end -}}
{{- if .Values.ingress.frontendHost -}}
{{- $hosts = append $hosts .Values.ingress.frontendHost -}}
{{- end -}}
{{- if .Values.ingress.backendHost -}}
{{- $hosts = append $hosts .Values.ingress.backendHost -}}
{{- end -}}
{{- $uniq := list -}}
{{- range $hosts -}}
{{- if not (has . $uniq) -}}
{{- $uniq = append $uniq . -}}
{{- end -}}
{{- end -}}
{{- join "," $uniq -}}
{{- end -}}

{{/*
dnsNames for cert-manager: tls.hosts only (never *.local).
*/}}
{{- define "stargate.ingress.certificateHosts" -}}
{{- $hosts := list -}}
{{- $cfg := ((.Values.ingress.gateway | default dict).certificate | default dict) -}}
{{- range $cfg.dnsNames | default list -}}
{{- $hosts = append $hosts . -}}
{{- end -}}
{{- if not $hosts -}}
{{- range .Values.ingress.tls | default list -}}
{{- range .hosts | default list -}}
{{- if not (hasSuffix ".local" .) -}}
{{- $hosts = append $hosts . -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- join "," $hosts -}}
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
