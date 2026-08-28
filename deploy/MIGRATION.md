# Migrating off kubernetes/ingress-nginx

The community Ingress NGINX controller is archived (last release **v1.15.1**, March 2026). This cluster/chart path replaces it with **Traefik Proxy v3** for HTTP(S). TCP (IPFS swarm, btcd P2P) already uses dedicated LoadBalancer Services and is unchanged.

k3s on this host is started with `--disable=traefik`, so we install Traefik via Helm (same pattern as cert-manager).

## What changes

| Piece | Before | After |
|---|---|---|
| HTTP(S) controller | `ingress-nginx` (class `nginx`) | Traefik v3 (class `traefik`) |
| App chart | `ingress.className: nginx` + nginx annotations | `ingress.provider: traefik` |
| cert-manager HTTP-01 | solver `ingress.class: nginx` | solver `ingress.class: traefik` |
| TLS secret | `stargate-stack-tls` | unchanged (reused) |
| IPFS / btcd P2P | dedicated LB Services | unchanged |

Single-node k3s ServiceLB can only bind host **:80/:443** once. Traefik and ingress-nginx cannot share those ports — cutover has a short outage.

## 1. Install Traefik (after freeing :80/:443)

```bash
# From the starlight-helm repo root
helm repo add traefik https://traefik.github.io/charts
helm repo update traefik

# Pre-pull so the outage window is just pod start
docker pull traefik:v3.7.12

# Drop retired controller (frees the LoadBalancer host ports)
helm uninstall ingress-nginx -n ingress-nginx

# Chart 41.x installs many CRDs first. Helm 4 may time out on the first
# attempt ("CRD not ready / InProgress"). Wait until they are Established
# and retry — leftover CRDs are fine.
helm upgrade --install traefik traefik/traefik \
  --namespace traefik --create-namespace \
  --version 41.3.0 \
  -f deploy/traefik-values.yaml \
  --wait --timeout 8m
```

## 2. Point cert-manager HTTP-01 at Traefik

Existing Certificate + Secret stay valid; this only matters at renewal.

```bash
kubectl patch clusterissuer letsencrypt-prod --type=json \
  -p='[{"op":"replace","path":"/spec/acme/solvers/0/http01/ingress/class","value":"traefik"}]'
```

## 3. Point the app Ingress at Traefik

In `values-local.yaml` (gitignored local overlay):

```yaml
ingress:
  enabled: true
  provider: traefik
  className: traefik
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
```

Then:

```bash
# --force-conflicts: take SSA ownership of ingressClassName if the Ingress
# was previously applied by kubectl / an older field manager.
helm upgrade starlight-stack . -f values-local.yaml --force-conflicts
```

Only the Ingress object should change; Stargate itself does not need a restart.

## 4. Verify

```bash
kubectl -n traefik get deploy,svc,pods
kubectl get ingressclass
kubectl get ingress -A
curl -sS -o /dev/null -w '%{http_code}\n' http://<lb-ip>/ -H 'Host: starlight-ai.freemyip.com'   # 308
curl -skS -o /dev/null -w '%{http_code}\n' https://starlight-ai.freemyip.com/                    # 200
```

## Rollback

Restore ingress-nginx from your last known helm values backup, switch `ingress.provider`/`className` back to `nginx`, and revert the ClusterIssuer class to `nginx`. Uninstall Traefik first so :80/:443 are free.

## Chart values

- `ingress.provider`: `gateway` (HTTPRoute), `traefik` (Ingress, chart default), or `nginx`
- `ingress.className`: empty → provider default (`traefik` / `nginx`); unused for `gateway`
- `ingress.gateway.*`: HTTPRoute parentRefs + optional cert-manager Certificate in the Gateway namespace
- `ingress.annotations`: merged on top of nginx defaults when `provider=nginx`
- `ingress.*.tcpConfigMap.create`: nginx-only leftover; ignored unless `provider=nginx`

## 5. Gateway API (HTTPRoute) on the same Traefik

No second controller. Install standard Gateway API CRDs, turn on Traefik's Gateway provider + cert-manager's Gateway shim, copy the existing TLS secret into `traefik`, then switch the app chart to `provider: gateway`.

```bash
# CRDs (standard channel)
kubectl apply --server-side -f \
  https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.1/standard-install.yaml

# cert-manager 1.19.x: enable Gateway API then restart (checked only at startup)
helm upgrade cert-manager jetstack/cert-manager \
  --namespace cert-manager --version v1.19.3 \
  --reuse-values -f deploy/cert-manager-gateway.yaml
kubectl rollout restart deployment/cert-manager -n cert-manager
kubectl rollout status deployment/cert-manager -n cert-manager --timeout=120s

# TLS secret the Gateway HTTPS listener will terminate
kubectl get secret stargate-stack-tls -n default -o yaml \
  | sed 's/namespace: default/namespace: traefik/' \
  | grep -v '^\s*resourceVersion:' \
  | grep -v '^\s*uid:' \
  | grep -v '^\s*creationTimestamp:' \
  | kubectl apply -f -

# Traefik: bind :80/:443, enable Gateway + HTTP-01 bypass
helm upgrade traefik traefik/traefik \
  --namespace traefik --version 41.3.0 \
  -f deploy/traefik-values.yaml \
  --wait --timeout 8m

kubectl -n traefik get gateway,gatewayclass
# Gateway listeners should show Accepted=True once the secret exists

# App: HTTPRoute + Certificate in traefik ns; Ingress is removed
# values-local.yaml:
#   ingress.provider: gateway
#   ingress.gateway.certificate.create: true
helm upgrade starlight-stack . -f values-local.yaml --force-conflicts

# ACME renewals via Gateway HTTPRoute (HTTP listener on port 80)
kubectl patch clusterissuer letsencrypt-prod --type=json -p='[
  {"op":"replace","path":"/spec/acme/solvers/0/http01","value":{
    "gatewayHTTPRoute":{
      "parentRefs":[{"name":"traefik-gateway","namespace":"traefik","kind":"Gateway"}]
    }
  }}
]'
```

Verify:

```bash
kubectl get httproute,gateway -A
curl -sS -o /dev/null -w '%{http_code}\n' http://<lb-ip>/ -H 'Host: starlight-ai.freemyip.com'  # 301
curl -skS -o /dev/null -w '%{http_code}\n' https://starlight-ai.freemyip.com/                   # 200
```

Rollback to Ingress: set `ingress.provider: traefik`, helm upgrade the app, then disable `providers.kubernetesGateway` if desired. The Kubernetes Ingress provider stays enabled so that rollback does not need a Traefik reinstall.

## 6. Fail2ban on ingress 404s

Host fail2ban tails Traefik access logs and bans scanner IPs at nftables
(same daemon as the `sshd` jail) on **prerouting** (before svclb DNAT).
Jail `ignoreip` skips LAN/RFC1918.
The `traefik-404` filter ignores ACME HTTP-01 and only matches unrouted
404s (`router="-"`). `traefik-scan` still matches backend 404s on
scanner paths.

Local knobs (`fail2ban.enabled`, host log path) go in
`values-local.yaml` (gitignored). Filters, jail defaults, and the
ConfigMap template are committed with the chart. `install.sh` renders
locally and copies onto the host; `helm upgrade` of this chart owns the
in-cluster ConfigMap.

```bash
# values-local.yaml: fail2ban.enabled: true
./deploy/fail2ban/install.sh          # render locally → host fail2ban
./deploy/fail2ban/install.sh --traefik  # first time: Traefik file access logs
helm upgrade --install starlight-stack . -f values-local.yaml
```

Details: **`deploy/fail2ban/README.md`**.
