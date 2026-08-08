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
docker pull traefik:v3.7.10

# Drop retired controller (frees the LoadBalancer host ports)
helm uninstall ingress-nginx -n ingress-nginx

# Chart 41.x installs many CRDs first. Helm 4 may time out on the first
# attempt ("CRD not ready / InProgress"). Wait until they are Established
# and retry — leftover CRDs are fine.
helm upgrade --install traefik traefik/traefik \
  --namespace traefik --create-namespace \
  --version 41.2.0 \
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

Restore ingress-nginx from the last known values (see `/home/eric/exports/ingress-nginx-backup-*` on this host), switch `ingress.provider`/`className` back to `nginx`, and revert the ClusterIssuer class to `nginx`. Uninstall Traefik first so :80/:443 are free.

## Chart values

- `ingress.provider`: `traefik` (default) or `nginx`
- `ingress.className`: empty → provider default (`traefik` / `nginx`)
- `ingress.annotations`: merged on top of nginx defaults when `provider=nginx`
- `ingress.*.tcpConfigMap.create`: nginx-only leftover; ignored unless `provider=nginx`

Gateway API is not enabled yet (`providers.kubernetesGateway.enabled=false`). Traefik can grow into that later without another controller swap.
