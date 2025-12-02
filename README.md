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
- `stargate.storage`: `postgres` or `filesystem` (default `postgres`)
- `stargate.pgDsn`: DSN pointing to the Postgres service (`postgres://stargate:stargate@stargate-postgres:5432/stargate?sslmode=disable`)

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
