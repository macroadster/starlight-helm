# Starlight Helm Stack

Minimal chart to run Starlight API, Stargate backend, and Postgres.

## Quick Start

```bash
# 1. Create secrets (required for authentication)
kubectl create secret generic stargate-stack-secrets \
  --from-literal=starlight-api-key="starlight-api-$(date +%s)-$(openssl rand -hex 8)" \
  --from-literal=starlight-ingest-token="starlight-ingest-$(date +%s)-$(openssl rand -hex 8)" \
  --from-literal=stargate-api-key="starlight-api-$(date +%s)-$(openssl rand -hex 8)" \
  --from-literal=stargate-ingest-token="stargate-backend-ingest-$(date +%s)-$(openssl rand -hex 8)" \
  --from-literal=starlight-stego-callback-secret="stego-callback-$(date +%s)-$(openssl rand -hex 8)"

# 2. Deploy with secrets
helm install starlight-stack . \
  --set secrets.createDefault=false \
  --set secrets.name=stargate-stack-secrets \
  --set secrets.starlightApiKey=true \
  --set secrets.starlightIngestToken=true \
  --set secrets.stargateApiKey=true \
  --set secrets.stargateIngestToken=true \
  --set secrets.starlightStegoCallbackSecret=true

# 3. Verify deployment
kubectl get pods
kubectl port-forward svc/starlight-api 8080:8080 &
curl http://localhost:8080/health
```

**⚠️ Critical Token Matching Requirements**:
- `starlight-api-key` and `stargate-api-key` **must match** for Stargate → Starlight API calls to work
- `starlight-ingest-token` and `stargate-ingest-token` **must match** for Starlight → Stargate callbacks to work
- Mismatched tokens cause 403/401 errors and prevent inscription workflow

## Requirements
- Docker/Helm/Kubectl access to a cluster (kind/minikube OK).
- Images available locally or in a registry:
  - `stargate-backend:local` (built from `/Users/eric/sandbox/stargate/backend/Dockerfile`)
  - `starlight-api:local` (you may need to build/push separately)
  - `stargate-mcp:local` (built from `/Users/eric/sandbox/stargate/backend/Dockerfile.mcp`)

## Values
- `image.stargate.repository` / `tag`: Stargate backend image (default `stargate-backend:local`)
- `image.starlight.repository` / `tag`: Starlight API image (default `starlight-api:local`)
- `image.mcp.repository` / `tag`: Stargate MCP server image (default `stargate-mcp:local`)
- `image.postgres.repository` / `tag`: Postgres (default `postgres:15`)
- `postgres.*`: credentials/PVC size
- Storage: one PVC (`stargate-blocks-pvc`) shared at `/data` by Stargate and Starlight for both blocks and uploads. Size controlled by `stargate.blocksStorage`, and `stargate.storageClass` can set a specific class.
- `stargate.storage`: `postgres` or `filesystem` (default `postgres`)
- `stargate.pgDsn`: DSN pointing to the Postgres service (`postgres://stargate:stargate@stargate-postgres:5432/stargate?sslmode=disable`)
- `mcp.port`: MCP HTTP port (default `3002`)
- `mcp.claimTtlHours`: claim expiry window exposed to clients (default `72`)
- `mcp.store`: `memory` (default) or `postgres`
- `mcp.pgDsn`: Postgres DSN when `mcp.store=postgres`
- `mcp.seedFixtures`: whether to load seed contracts/tasks on startup (default `true`)
- `mcp.apiKey`: optional API key required via header `X-API-Key`
- `ingress.enabled`: optional Ingress (defaults: frontend `starlight.local`, backend `stargate.local`; set `ingress.className`/`annotations`/`tls` as needed; defaults force SSL redirect and 10m body size)
- `ingress.mcpHost`: optional dedicated host for MCP (default `mcp.local`)
- `resources.*`: set requests/limits for all components (defaults provided)
- `hpa.*`: optional HPAs for backend and starlight (disabled by default)
- `secrets.*`: optionally create/use a secret for API keys/tokens (`stargate-stack-secrets` with keys: `stargate-api-key`, `stargate-ingest-token`, `starlight-api-key`, `starlight-ingest-token`, `starlight-stego-callback-secret`)

## Build images (local)
```bash
# Stargate backend
cd /Users/eric/sandbox/stargate/backend
docker build -t stargate-backend:local .

# Starlight API (if not available)
cd /Users/eric/sandbox/starlight
docker build -t starlight-api:local .

# Stargate MCP server
cd /Users/eric/sandbox/stargate/backend
docker build -f Dockerfile.mcp -t stargate-mcp:local .
```

## Secrets Setup (Required for Production)

The Starlight ↔ Stargate integration requires authentication tokens for secure communication. Create secrets before deployment:

### Option 1: Automatic Secret Creation (Recommended)
```bash
cd /Users/eric/sandbox/starlight-helm

# Create secrets with secure random values
# Note: starlight-api-key and stargate-api-key must match for Stargate → Starlight calls
# Note: starlight-ingest-token and stargate-ingest-token must match for Starlight → Stargate callbacks
TIMESTAMP=$(date +%s)
RANDOM=$(openssl rand -hex 8)
kubectl create secret generic stargate-stack-secrets \
  --from-literal=starlight-api-key="starlight-api-$TIMESTAMP-$RANDOM" \
  --from-literal=starlight-ingest-token="starlight-ingest-$TIMESTAMP-$RANDOM" \
  --from-literal=stargate-api-key="starlight-api-$TIMESTAMP-$RANDOM" \
  --from-literal=stargate-ingest-token="starlight-ingest-$TIMESTAMP-$RANDOM" \
  --from-literal=starlight-stego-callback-secret="stego-callback-$TIMESTAMP-$(openssl rand -hex 8)"

# Enable secret usage in Helm
helm install starlight-stack . \
  --set secrets.createDefault=false \
  --set secrets.name=stargate-stack-secrets \
  --set secrets.starlightApiKey=true \
  --set secrets.starlightIngestToken=true \
  --set secrets.stargateApiKey=true \
  --set secrets.stargateIngestToken=true \
  --set secrets.starlightStegoCallbackSecret=true
```

### Option 2: Manual Secret Creation
```bash
# Create secret with your own values
# IMPORTANT: Use matching values for API keys and ingest tokens
kubectl create secret generic stargate-stack-secrets \
  --from-literal=starlight-api-key="your-shared-api-key" \
  --from-literal=starlight-ingest-token="your-shared-ingest-token" \
  --from-literal=stargate-api-key="your-shared-api-key" \
  --from-literal=stargate-ingest-token="your-shared-ingest-token" \
  --from-literal=starlight-stego-callback-secret="your-stego-callback-secret"

# Deploy with secret usage
helm install starlight-stack . \
  --set secrets.createDefault=false \
  --set secrets.name=stargate-stack-secrets \
  --set secrets.starlightApiKey=true \
  --set secrets.starlightIngestToken=true \
  --set secrets.stargateApiKey=true \
  --set secrets.stargateIngestToken=true \
  --set secrets.starlightStegoCallbackSecret=true
```

### Secret Keys Explained
| Secret Key | Used By | Purpose |
|------------|----------|---------|
| `starlight-api-key` | Starlight API | Authenticates `/inscribe` and protected endpoints |
| `starlight-ingest-token` | Starlight API | Token for Stargate ingestion callback |
| `stargate-api-key` | Stargate Backend | API key for calling Starlight services |
| `stargate-ingest-token` | Stargate Backend | Token for Stargate ingestion endpoint |
| `starlight-stego-callback-secret` | Starlight API | HMAC secret for steganography detection callbacks |

**Important**: 
- `starlight-api-key` and `stargate-api-key` **must match** for Stargate → Starlight API calls to work.
- `starlight-ingest-token` and `stargate-ingest-token` **must match** for Starlight → Stargate callbacks to work.

### Option 3: Development (No Authentication)
```bash
# For development only - disables authentication
helm install starlight-stack . \
  --set starlight.allowAnonymousScan=true \
  --set starlight.apiKey="demo-api-key" \
  --set stargate.apiKey="demo-api-key"
```

## Install
```bash
cd /Users/eric/sandbox/starlight-helm

# Basic installation (without secrets - not recommended for production)
helm install starlight-stack . \
  --set image.stargate.repository=stargate-backend \
  --set image.stargate.tag=local \
  --set image.starlight.repository=starlight-api \
  --set image.starlight.tag=local

# Production installation with secrets (recommended)
helm install starlight-stack . \
  --set secrets.createDefault=false \
  --set secrets.name=stargate-stack-secrets \
  --set secrets.starlightApiKey=true \
  --set secrets.starlightIngestToken=true \
  --set secrets.stargateApiKey=true \
  --set secrets.stargateIngestToken=true \
  --set secrets.starlightStegoCallbackSecret=true

# Defaults already point to the above tags; override only if using different names.

# Enable ingress (example; update hosts/tls for your cluster)
helm upgrade --install starlight-stack . \
  --set ingress.enabled=true \
  --set ingress.className=nginx

# For local ingress testing (docker-desktop/minikube with ingress-nginx), add to /etc/hosts:
# 127.0.0.1 stargate.local starlight.local mcp.local
# TLS: default values expect a secret `stargate-stack-tls` with SANs stargate.local, starlight.local, mcp.local
#   kubectl create secret tls stargate-stack-tls --cert=stargate-stack.crt --key=stargate-stack.key
# Then hit:
# curl -kI https://stargate.local/   # backend
# curl -kI https://starlight.local/  # frontend
# curl -kI https://mcp.local/healthz # MCP server

# Observability
# - Backend metrics: https://stargate.local/metrics (prometheus format)
# - Starlight metrics: https://stargate.local/metrics if proxied or service scrape on port 8080 (/metrics)
# - MCP metrics: https://mcp.local/metrics
# - Service annotations included for Prometheus auto-scrape (prometheus.io/scrape=true)
```

## Verify
```bash
# Check pod status
kubectl get pods

# Check services
kubectl get svc stargate-backend starlight-api stargate-postgres stargate-mcp

# Port forward for testing
kubectl port-forward svc/stargate-backend 3001:3001 &
kubectl port-forward svc/starlight-api 8080:8080 &
kubectl port-forward svc/starlight-mcp 3002:3002 &

# Test health endpoints
curl http://localhost:3001/api/health
curl http://localhost:8080/health
curl http://localhost:3002/healthz

# Test MCP with API key (if configured)
# curl -H "X-API-Key: <key>" http://localhost:3002/mcp/v1/tasks

# Test Starlight inscription (requires authentication)
# Get API key from secret:
STARLIGHT_API_KEY=$(kubectl get secret stargate-stack-secrets -o jsonpath='{.data.starlight-api-key}' | base64 -d)
curl -X POST "http://localhost:8080/inscribe" \
  -H "Authorization: Bearer $STARLIGHT_API_KEY" \
  -F "image=@test-image.png" \
  -F "message=test message" \
  -F "method=lsb"
```

## Troubleshooting

### 403/401 Authentication Errors

#### Starlight API Returns 403 Forbidden
**Cause**: API key mismatch between Stargate and Starlight
```bash
# Check API key mismatch
echo "Starlight expects:"
kubectl exec deployment/starlight-api -- env | grep STARGATE_API_KEY
echo "Stargate sends:"
kubectl exec deployment/stargate-backend -- env | grep STARGATE_API_KEY

# Fix by updating Stargate API key to match Starlight's
kubectl patch secret stargate-stack-secrets --patch='{"data":{"stargate-api-key":"'$(kubectl get secret stargate-stack-secrets -o jsonpath='{.data.starlight-api-key}')'"}}'
kubectl rollout restart deployment/stargate-backend
```

#### Stargate Callback Returns 401 Unauthorized  
**Cause**: Ingest token mismatch between Starlight and Stargate
```bash
# Check ingest token mismatch
echo "Starlight sends:"
kubectl exec deployment/starlight-api -- env | grep STARGATE_INGEST_TOKEN
echo "Stargate expects:"
kubectl exec deployment/stargate-backend -- env | grep STARGATE_INGEST_TOKEN

# Fix by updating Stargate ingest token to match Starlight's
STARLIGHT_INGEST_TOKEN=$(kubectl get secret stargate-stack-secrets -o jsonpath='{.data.starlight-ingest-token}' | base64 -d)
kubectl patch secret stargate-stack-secrets --patch='{"data":{"stargate-ingest-token":"'$(echo -n "$STARLIGHT_INGEST_TOKEN" | base64)'"}}'
kubectl rollout restart deployment/stargate-backend
```

### 403 Forbidden Errors
If you get `403 Forbidden` from Starlight `/inscribe` endpoint:
```bash
# Check API key mismatch
echo "Starlight expects:"
kubectl exec deployment/starlight-api -- env | grep STARGATE_API_KEY
echo "Stargate sends:"
kubectl exec deployment/stargate-backend -- env | grep STARGATE_API_KEY

# Fix by updating Stargate API key to match Starlight's
kubectl patch secret stargate-stack-secrets --patch='{"data":{"stargate-api-key":"'$(kubectl get secret stargate-stack-secrets -o jsonpath='{.data.starlight-api-key}')'"}}'
kubectl rollout restart deployment/stargate-backend
```

### Callback Issues
If Starlight → Stargate callbacks fail:
```bash
# Check callback URLs and tokens
echo "Starlight sends:"
kubectl exec deployment/starlight-api -- env | grep STARGATE_INGEST_TOKEN
echo "Stargate expects:"
kubectl exec deployment/stargate-backend -- env | grep STARGATE_INGEST_TOKEN

# Fix token mismatch by updating Stargate to match Starlight
STARLIGHT_INGEST_TOKEN=$(kubectl get secret stargate-stack-secrets -o jsonpath='{.data.starlight-ingest-token}' | base64 -d)
kubectl patch secret stargate-stack-secrets --patch='{"data":{"stargate-ingest-token":"'$(echo -n "$STARLIGHT_INGEST_TOKEN" | base64)'"}}'
kubectl rollout restart deployment/stargate-backend

# Test callback endpoint manually
STARGATE_INGEST_TOKEN=$(kubectl get secret stargate-stack-secrets -o jsonpath='{.data.stargate-ingest-token}' | base64 -d)
curl -X POST "http://localhost:3001/api/ingest-inscription" \
  -H "X-Ingest-Token: $STARGATE_INGEST_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"id":"test","filename":"test.png","method":"lsb","message_length":10,"image_base64":"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/Ptq4YQAAAABJRU5ErkJggg==","metadata":{}}'
```

## Secret Management

### View Current Secrets
```bash
# List all secret values (decoded)
kubectl get secret stargate-stack-secrets -o yaml | awk '
/^\s*[a-zA-Z-]+:/ {
  key = $1
  gsub(/:/, "", key)
  getline
  if (/data:/) {
    getline
    value = $2
    cmd = "echo " value " | base64 -d"
    cmd | getline decoded
    close(cmd)
    print key ": " decoded
  }
}'

# Or view specific secret
kubectl get secret stargate-stack-secrets -o jsonpath='{.data.starlight-api-key}' | base64 -d
```

### Update Secrets
```bash
# Update individual secret values
kubectl patch secret stargate-stack-secrets --patch='{"data":{"starlight-api-key":"'$(echo -n 'new-api-key' | base64)'"}}'

# IMPORTANT: Update matching pairs to maintain communication
kubectl patch secret stargate-stack-secrets --patch='{"data":{"stargate-api-key":"'$(echo -n 'new-api-key' | base64)'"}}'

# Restart deployments to load new secrets
kubectl rollout restart deployment/starlight-api
kubectl rollout restart deployment/stargate-backend
```

### Rotate Secrets
```bash
# Generate new secrets and update (with matching pairs)
TIMESTAMP=$(date +%s)
RANDOM=$(openssl rand -hex 8)
kubectl create secret generic stargate-stack-secrets-new \
  --from-literal=starlight-api-key="starlight-api-$TIMESTAMP-$RANDOM" \
  --from-literal=starlight-ingest-token="starlight-ingest-$TIMESTAMP-$RANDOM" \
  --from-literal=stargate-api-key="starlight-api-$TIMESTAMP-$RANDOM" \
  --from-literal=stargate-ingest-token="starlight-ingest-$TIMESTAMP-$RANDOM" \
  --from-literal=starlight-stego-callback-secret="stego-callback-$TIMESTAMP-$(openssl rand -hex 8)"

# Replace old secret
kubectl delete secret stargate-stack-secrets
kubectl get secret stargate-stack-secrets-new -o yaml | sed 's/name: stargate-stack-secrets-new/name: stargate-stack-secrets/' | kubectl apply -f -
kubectl delete secret stargate-stack-secrets-new

# Restart deployments
kubectl rollout restart deployment/starlight-api
kubectl rollout restart deployment/stargate-backend
```

## Uninstall
```bash
helm uninstall starlight-stack
kubectl delete secret stargate-stack-secrets  # Optional: remove secrets
```
