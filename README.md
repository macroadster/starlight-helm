# Stargate Helm Stack

Bitcoin-native smart contract stack with in-process steganography detection, proposals, funding, and verified work—all built on Bitcoin with smart contracts, escrow, and dispute resolution.

Helm chart for the **Stargate** single binary, with optional Postgres and IPFS. Stego detection (Trin/GGUF) runs **in-process** inside Stargate; there is no separate `starlight-api` pod.

## Quick Start

```bash
# 1. Create secrets (required for authentication)
kubectl create secret generic stargate-stack-secrets \
  --from-literal=stargate-api-key="stargate-api-$(date +%s)-$(openssl rand -hex 8)" \
  --from-literal=stargate-ingest-token="stargate-ingest-$(date +%s)-$(openssl rand -hex 8)"

# 2. Deploy with secrets
helm install stargate-stack . \
  --set secrets.createDefault=false \
  --set secrets.name=stargate-stack-secrets \
  --set secrets.stargateApiKey=true \
  --set secrets.stargateIngestToken=true

# 3. Verify deployment
kubectl get pods
kubectl port-forward svc/stargate 3001:3001 &
curl http://localhost:3001/api/health
```

## Requirements
- Docker/Helm/Kubectl access to a cluster (kind/minikube/Docker Desktop OK).
- Image available locally or in a registry:
  - `stargate:latest` (built from `stargate/Dockerfile`) or `macroadster/stargate:v1`

## Values
- `image.stargate.repository` / `tag`: Stargate image (default `macroadster/stargate:v1`)
- `image.postgres.repository` / `tag`: Postgres (default `postgres:15`, only if `postgres.enabled`)
- `postgres.enabled`: deploy in-cluster Postgres (default `false`; use SQLite on the data PVC)
- `postgres.*`: credentials/PVC size when enabled
- Storage: one PVC (`stargate-blocks-pvc`) mounted at `stargate.dataDir` (default `/data`) for blocks, uploads, model cache, SQLite DBs under `/data/sqlite/`, **and btcd chainstate under `/data/btcd`**. Size controlled by `stargate.blocksStorage` (default **50Gi** for testnet4 full node + indexes); `stargate.storageClass` can set a class. Expanding an existing 1Gi claim requires StorageClass volume expansion or a new PVC.
- `stargate.storage`: `sqlite` (default), `postgres`, `memory`, or `filesystem`
- `stargate.dataDir`: in-container data root (default `/data`); SQLite files at `{dataDir}/sqlite/{mcp,api_keys,ingestions,blocks}.db`
- `stargate.pgDsn`: DSN for Postgres mode (`postgres://stargate:stargate@stargate-postgres:5432/stargate?sslmode=disable`)
- **Postgres → SQLite migration**: build `backend/cmd/migrate-pg-to-sqlite` in stargate, run against the live PG DSN with `--target-dir /data/sqlite` (on the PVC), verify, then set `stargate.storage=sqlite` and `postgres.enabled=false` and upgrade.
- `stargate.proxyBase`: optional external proxy base (default empty; kept for operator override via `STARGATE_PROXY_BASE`)
- `stargate.bitcoinNetwork`: Bitcoin network (`testnet4` default; also `testnet`, `signet`, `mainnet`)
- **btcd full node (no mining)** — Stargate manages `btcd` in the same container (see stargate ADR 0006):
  - `stargate.btcd.mode`: `managed` (default) | `external` | `off`
  - `stargate.btcd.bin`: path to btcd binary (image ships `/usr/local/bin/btcd`)
  - `stargate.btcd.dataDir`: empty → `{dataDir}/btcd` on the data PVC (**must persist**)
  - `stargate.btcd.rpcHost` / `rpcUser` / `rpcPass`: empty uses network defaults + auto auth file
  - `stargate.btcd.p2pPort` / `p2pListen`: testnet4 default `48333`; set `p2pServiceEnabled: true` to expose on the Service
  - `stargate.btcd.txIndex` / `addrIndex`: default `true` (required for historical txs / address UTXOs)
  - `stargate.btcd.allowMainnet`: default `false` (mainnet needs large disk + explicit opt-in)
  - `stargate.probes.startup.failureThreshold`: default `60` (~10m) so managed btcd RPC wait does not trip restarts
- Stego detection (native Path A — Trin/GGUF in-process):
  - `stargate.starlightGguf`: optional local GGUF path override; empty uses data dir + Hugging Face
  - `stargate.starlightHfRepo`: HF repo (default `macroadster/starlight-prod`)
  - `stargate.starlightHfFile`: model filename (default `starlight.gguf`)
  - `stargate.starlightHfRevision`: HF revision (default `main`)
  - On first use the model is auto-downloaded under `/data` (`STARGATE_DATA_DIR=/data`)
- `stargate.ipfs.*`: IPFS uploads mirroring configuration (see values for defaults)
  - `stargate.ipfs.mirrorEnabled`: enable IPFS mirror (default `false`)
  - `stargate.ipfs.mirrorUploadEnabled`: publish local uploads to IPFS (default `true`)
  - `stargate.ipfs.mirrorDownloadEnabled`: fetch uploads announced by peers (default `true`)
  - `stargate.ipfs.apiUrl`: IPFS HTTP API base URL (default `http://stargate-ipfs:5001`)
  - `stargate.ipfs.mirrorTopic`: PubSub topic for sync announcements (default `stargate-uploads`)
  - `stargate.ipfs.mirrorPollIntervalSec`: local scan interval in seconds (default `10`)
  - `stargate.ipfs.mirrorPublishIntervalSec`: manifest publish interval in seconds (default `30`)
  - `stargate.ipfs.mirrorMaxFiles`: max files in manifest (default `2000`)
  - `stargate.ipfs.httpTimeoutSec`: IPFS HTTP timeout in seconds (default `30`)
  - `stargate.ipfs.ingestSyncEnabled`: create ingestion records from mirrored stego uploads (default `false`)
  - `stargate.ipfs.ingestSyncIntervalSec`: poll interval for ingestion sync (default `60`)
  - `stargate.ipfs.ingestSyncManifest`: legacy manifest filename (currently unused; default `stargate-uploads-manifest.json`)
  - `stargate.ipfs.ingestSyncMaxEntries`: max manifest entries processed per tick (default `5000`)
  - `stargate.ipfs.stegoTopic`: PubSub topic for stego announcements (default `stargate-stego`)
  - `stargate.ipfs.stegoAnnounceEnabled`: publish stego announcements on approval (default `true`)
  - `stargate.ipfs.stegoSyncEnabled`: subscribe + reconcile stego announcements (default `true`)
  - `stargate.ipfs.stegoSyncIntervalSec`: retry interval for stego pubsub sync (default `10`)
- `stargate.stego.*`: stego approval/reconcile config (see values for defaults)
  - `stargate.stego.approvalEnabled`: publish stego + IPFS payload on approval (default `false`)
  - `stargate.stego.method`: stego method (default `lsb`)
  - `stargate.stego.issuer`: manifest issuer label (default empty -> hostname)
  - `stargate.stego.ingestTimeoutSec`: wait for stego ingestion (default `30`)
  - `stargate.stego.ingestPollSec`: poll interval for ingestion (default `2`)
  - `stargate.stego.inscribeTimeoutSec`: inscribe timeout (default `60`)
  - `stargate.stego.scanTimeoutSec`: scan timeout (default `30`)
- `ipfs.*`: optional Kubo (IPFS) deployment for mirroring
  - `ipfs.enabled`: deploy Kubo service (default `true`)
  - `ipfs.enablePubsub`: enable pubsub experiment for Kubo (default `true`)
  - `ipfs.apiPort` / `gatewayPort` / `swarmPort`: IPFS ports (defaults `5001` / `8080` / `4001`)
  - `ipfs.storage`: PVC size for IPFS repo (default `5Gi`)
  - `ipfs.storageClass`: optional storage class for IPFS PVC
- `stargate.claimTtlHours`: claim expiry window exposed to clients (default `72`)
- `stargate.seedFixtures`: whether to load seed contracts/tasks on startup (default `false`)
- `stargate.apiKey`: optional API key required via header `X-API-Key`
- `stargate.enableIngestSync`: enable ingestion sync (default `true`)
- `stargate.enableFundingSync`: enable funding sync (default `true`)
- `stargate.fundingProvider`: funding provider (default `blockstream`)
- `stargate.fundingApiBase`: funding API base URL
- `stargate.ingestSyncInterval`: ingest sync interval (default `30s`)
- `ingress.enabled`: optional Ingress (defaults: frontend `starlight.local`, backend `stargate.local`; set `ingress.className`/`annotations`/`tls` as needed)
- `resources.*`: set requests/limits for components (defaults provided)
- `hpa.stargate`: optional HPA for Stargate (disabled by default)
- `secrets.*`: optionally create/use a secret (`stargate-stack-secrets` with keys: `stargate-api-key`, `stargate-ingest-token`)

## Build image (local)
```bash
cd stargate
docker build -t stargate:latest .
```

## Secrets Setup (Required for Production)

### Option 1: Manual Secret Creation (Recommended)
```bash
cd starlight-helm

TIMESTAMP=$(date +%s)
RANDOM=$(openssl rand -hex 8)
kubectl create secret generic stargate-stack-secrets \
  --from-literal=stargate-api-key="stargate-api-$TIMESTAMP-$RANDOM" \
  --from-literal=stargate-ingest-token="stargate-ingest-$TIMESTAMP-$RANDOM"

helm install stargate-stack . \
  --set secrets.createDefault=false \
  --set secrets.name=stargate-stack-secrets \
  --set secrets.stargateApiKey=true \
  --set secrets.stargateIngestToken=true
```

### Option 2: Helm-generated secrets (dev)
```bash
helm install stargate-stack . \
  --set secrets.createDefault=true \
  --set secrets.name=stargate-stack-secrets \
  --set secrets.stargateApiKey="demo-api-key" \
  --set secrets.stargateIngestToken=""
```

### Secret Keys
| Secret Key | Used By | Purpose |
|------------|----------|---------|
| `stargate-api-key` | Stargate | API key via header `X-API-Key` |
| `stargate-ingest-token` | Stargate | Token for ingestion endpoints |

### Development (simple demo key)
```bash
helm install stargate-stack . \
  --set stargate.apiKey="demo-api-key"
```

## Install
```bash
cd starlight-helm

# Basic installation
helm install stargate-stack . \
  --set image.stargate.repository=stargate \
  --set image.stargate.tag=latest

# Production installation with secrets
helm install stargate-stack . \
  --set secrets.createDefault=false \
  --set secrets.name=stargate-stack-secrets \
  --set secrets.stargateApiKey=true \
  --set secrets.stargateIngestToken=true

# For testnet deployment
helm install stargate-stack . \
  --set stargate.bitcoinNetwork=testnet \
  --set secrets.createDefault=false \
  --set secrets.name=stargate-stack-secrets \
  --set secrets.stargateApiKey=true \
  --set secrets.stargateIngestToken=true

# Enable ingress (example; update hosts/tls for your cluster)
helm upgrade --install stargate-stack . \
  --set ingress.enabled=true \
  --set ingress.className=nginx

# For local ingress testing (docker-desktop/minikube with ingress-nginx), add to /etc/hosts:
# 127.0.0.1 starlight.local stargate.local
# TLS: default values expect a secret `stargate-stack-tls` with SANs starlight.local, stargate.local
#   kubectl create secret tls stargate-stack-tls --cert=stargate-stack.crt --key=stargate-stack.key
# Then hit:
# curl -kI https://starlight.local/
# curl -kI https://stargate.local/

# Observability
# - Metrics: https://stargate.local/metrics (prometheus format)
# - Service annotations included for Prometheus auto-scrape (prometheus.io/scrape=true)
```

## Verify
```bash
# Check pod status
kubectl get pods

# Check services
kubectl get svc stargate stargate-postgres

# Port forward for testing
kubectl port-forward svc/stargate 3001:3001 &

# Test health endpoint
curl http://localhost:3001/api/health
```

## Upgrading from chart 0.1.x (starlight-api removed)

Chart **0.2.0** removes the separate `starlight-api` Deployment/Service. Detection is in-process in Stargate.

When upgrading an existing cluster:

```bash
# After helm upgrade, remove the old resources if they remain
kubectl delete deployment starlight-api --ignore-not-found
kubectl delete service starlight-api --ignore-not-found
kubectl delete hpa starlight-api --ignore-not-found
kubectl delete pdb starlight-api-pdb --ignore-not-found
kubectl delete configmap opencode-config --ignore-not-found

# Optional: drop unused secret keys from an existing secret
# (stargate only needs stargate-api-key and stargate-ingest-token)
```

Also clear any old `stargate.proxyBase` that pointed at `http://starlight-api:8080` (default is now empty).

## CI Automation for Mocked Contracts and Ingestion

### Mocked Contracts and Tasks

Set `stargate.seedFixtures: true` to load demo contracts/tasks when tables are empty (see `stargate/backend/mcp/fixtures.go`).

### Mocked Ingestion of Proposals

1. Insert pending records into `starlight_ingestions` with status `"pending"`.
2. Use Markdown proposals in ingestion metadata as needed.
3. Optional env defaults:
   - `STARGATE_DEFAULT_BUDGET_SATS`
   - `STARGATE_DEFAULT_FUNDING_ADDRESS`

## Troubleshooting

### 401 Unauthorized on API calls
```bash
# Confirm API key in secret and pod env
kubectl get secret stargate-stack-secrets -o jsonpath='{.data.stargate-api-key}' | base64 -d; echo
kubectl exec deployment/stargate -- env | grep STARGATE_API_KEY

# Restart after secret changes
kubectl rollout restart deployment/stargate
```

### Ingest token issues
```bash
kubectl get secret stargate-stack-secrets -o jsonpath='{.data.stargate-ingest-token}' | base64 -d; echo
kubectl exec deployment/stargate -- env | grep STARGATE_INGEST_TOKEN
kubectl rollout restart deployment/stargate
```

### Stego / GGUF model not loading
```bash
# Confirm HF env and data dir
kubectl exec deployment/stargate -- env | grep -E 'STARLIGHT_|STARGATE_DATA_DIR'
# Model cache lands under /data (PVC stargate-blocks-pvc)
kubectl exec deployment/stargate -- ls -la /data || true
```

## Secret Management

### View Current Secrets
```bash
kubectl get secret stargate-stack-secrets -o jsonpath='{.data.stargate-api-key}' | base64 -d; echo
kubectl get secret stargate-stack-secrets -o jsonpath='{.data.stargate-ingest-token}' | base64 -d; echo
```

### Update Secrets
```bash
kubectl patch secret stargate-stack-secrets --patch='{"data":{"stargate-api-key":"'$(echo -n 'new-api-key' | base64)'"}}'
kubectl rollout restart deployment/stargate
```

### Rotate Secrets
```bash
TIMESTAMP=$(date +%s)
RANDOM=$(openssl rand -hex 8)
kubectl create secret generic stargate-stack-secrets-new \
  --from-literal=stargate-api-key="stargate-api-$TIMESTAMP-$RANDOM" \
  --from-literal=stargate-ingest-token="stargate-ingest-$TIMESTAMP-$RANDOM"

kubectl delete secret stargate-stack-secrets
kubectl get secret stargate-stack-secrets-new -o yaml | sed 's/name: stargate-stack-secrets-new/name: stargate-stack-secrets/' | kubectl apply -f -
kubectl delete secret stargate-stack-secrets-new
kubectl rollout restart deployment/stargate
```

## Uninstall
```bash
helm uninstall stargate-stack
kubectl delete secret stargate-stack-secrets  # Optional: remove secrets
```
