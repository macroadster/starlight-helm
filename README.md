# Starlight Helm Stack

Minimal chart to run Starlight API, Stargate backend, and Postgres.

## Requirements
- Docker/Helm/Kubectl access to a cluster (kind/minikube OK).
- Images available locally or in a registry:
  - `stargate-backend:local` (built from `/Users/eric/sandbox/stargate/backend/Dockerfile`)
  - `starlight-api:local` (you may need to build/push separately)

## Values
- `image.stargate.repository` / `tag`: Stargate backend image (default `stargate-backend:local`)
- `image.starlight.repository` / `tag`: Starlight API image (default `starlight-api:local`)
- `image.postgres.repository` / `tag`: Postgres (default `postgres:15`)
- `postgres.*`: credentials/PVC size
- Storage: one PVC (`stargate-blocks-pvc`) shared at `/data` by Stargate and Starlight for both blocks and uploads. Size controlled by `stargate.blocksStorage`, and `stargate.storageClass` can set a specific class.
- `stargate.storage`: `postgres` or `filesystem` (default `postgres`)
- `stargate.pgDsn`: DSN pointing to the Postgres service (`postgres://stargate:stargate@stargate-postgres:5432/stargate?sslmode=disable`)
- `ingress.enabled`: optional Ingress (defaults: frontend `starlight.local`, backend `stargate.local`; set `ingress.className`/`annotations`/`tls` as needed; defaults force SSL redirect and 10m body size)
- `resources.*`: set requests/limits for all components (defaults provided)
- `hpa.*`: optional HPAs for backend and starlight (disabled by default)
- `secrets.*`: optionally create/use a secret for API keys/tokens (`stargate-stack-secrets` with keys: `stargate-api-key`, `stargate-ingest-token`, `starlight-api-key`, `starlight-ingest-token`)

## Build images (local)
```bash
# Stargate backend
cd /Users/eric/sandbox/stargate/backend
docker build -t stargate-backend:local .

# Starlight API (if not available)
cd /Users/eric/sandbox/starlight
docker build -t starlight-api:local .
```

## Install
```bash
cd /Users/eric/sandbox/starlight-helm
helm install starlight-stack . \
  --set image.stargate.repository=stargate-backend \
  --set image.stargate.tag=local \
  --set image.starlight.repository=starlight-api \
  --set image.starlight.tag=local
# Defaults already point to the above tags; override only if using different names.

# Enable ingress (example; update hosts/tls for your cluster)
helm upgrade --install starlight-stack . \
  --set ingress.enabled=true \
  --set ingress.className=nginx

# For local ingress testing (docker-desktop/minikube with ingress-nginx), add to /etc/hosts:
# 127.0.0.1 stargate.local starlight.local
# TLS: default values expect a secret `stargate-stack-tls` with SANs stargate.local, starlight.local
#   kubectl create secret tls stargate-stack-tls --cert=stargate-stack.crt --key=stargate-stack.key
# Then hit:
# curl -kI https://stargate.local/   # backend
# curl -kI https://starlight.local/  # frontend

# Observability
# - Backend metrics: https://stargate.local/metrics (prometheus format)
# - Starlight metrics: https://stargate.local/metrics if proxied or service scrape on port 8080 (/metrics)
# - Service annotations included for Prometheus auto-scrape (prometheus.io/scrape=true)
```

## Verify
```bash
kubectl get pods
kubectl get svc stargate-backend starlight-api stargate-postgres
kubectl port-forward svc/stargate-backend 3001:3001 &
kubectl port-forward svc/starlight-api 8080:8080 &

curl http://localhost:3001/api/health
curl http://localhost:3001/bitcoin/v1/health
```

## Uninstall
```bash
helm uninstall starlight-stack
```
