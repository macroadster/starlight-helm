# Starlight Helm Stack

A complete Bitcoin-native smart contract system that keeps the blockchain safe while enabling useful work. This stack combines AI-powered security that detects hidden data in blockchain images with a full workflow system for proposals, funding, and verified work—all built on Bitcoin with smart contracts, escrow, and dispute resolution.

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
  - `stargate-frontend:latest` (built from `stargate/frontend/Dockerfile`)
  - `stargate-backend:latest` (built from `stargate/backend/Dockerfile`)
  - `starlight-api:latest` (built from `starlight/Dockerfile`)

## Values
- `image.stargateFrontend.repository` / `tag`: Stargate frontend image (default `stargate-frontend:latest`)
- `image.stargate.repository` / `tag`: Stargate backend image (default `stargate-backend:latest`)
- `image.starlight.repository` / `tag`: Starlight API image (default `starlight-api:latest`)
- `image.postgres.repository` / `tag`: Postgres (default `postgres:15`)
- `postgres.*`: credentials/PVC size
- Storage: one PVC (`stargate-blocks-pvc`) shared at `/data` by Stargate and Starlight for both blocks and uploads. Size controlled by `stargate.blocksStorage`, and `stargate.storageClass` can set a specific class.
- `stargate.storage`: `postgres` or `filesystem` (default `postgres`)
- `stargate.pgDsn`: DSN pointing to the Postgres service (`postgres://stargate:stargate@stargate-postgres:5432/stargate?sslmode=disable`)
- `stargate.bitcoinNetwork`: Bitcoin network to use (`mainnet` or `testnet`, default `mainnet`)
- `stargate.ipfs.*`: IPFS uploads mirroring configuration (see values for defaults)
  - `stargate.ipfs.mirrorEnabled`: enable IPFS mirror (default `false`)
  - `stargate.ipfs.mirrorUploadEnabled`: publish local uploads to IPFS (default `true`)
  - `stargate.ipfs.mirrorDownloadEnabled`: fetch uploads announced by peers (default `true`)
  - `stargate.ipfs.apiUrl`: IPFS HTTP API base URL (default `http://127.0.0.1:5001`)
  - `stargate.ipfs.mirrorTopic`: PubSub topic for sync announcements (default `stargate-uploads`)
  - `stargate.ipfs.mirrorPollIntervalSec`: local scan interval in seconds (default `10`)
  - `stargate.ipfs.mirrorPublishIntervalSec`: manifest publish interval in seconds (default `30`)
  - `stargate.ipfs.mirrorMaxFiles`: max files in manifest (default `2000`)
  - `stargate.ipfs.httpTimeoutSec`: IPFS HTTP timeout in seconds (default `30`)
- `mcp.port`: MCP HTTP port (default `3002`)
- `mcp.claimTtlHours`: claim expiry window exposed to clients (default `72`)
- `mcp.store`: `memory` (default) or `postgres`
- `mcp.pgDsn`: Postgres DSN when `mcp.store=postgres`
- `mcp.seedFixtures`: whether to load seed contracts/tasks on startup (default `true`)
- `mcp.apiKey`: optional API key required via header `X-API-Key`
- `ingress.enabled`: optional Ingress (defaults: frontend `starlight.local`, backend `stargate.local`; set `ingress.className`/`annotations`/`tls` as needed; defaults force SSL redirect and 10m body size)
- `resources.*`: set requests/limits for all components (defaults provided)
- `hpa.*`: optional HPAs for backend and starlight (disabled by default)
- `secrets.*`: optionally create/use a secret for API keys/tokens (`stargate-stack-secrets` with keys: `stargate-api-key`, `stargate-ingest-token`, `starlight-api-key`, `starlight-ingest-token`, `starlight-stego-callback-secret`)

## Build images (local)
```bash
# Stargate frontend
cd stargate/frontend
docker build -t stargate-frontend:latest .

# Stargate backend
cd stargate/backend
docker build -t stargate-backend:latest .

# Starlight API (if not available)
cd starlight
docker build -t starlight-api:latest .
```

## Secrets Setup (Required for Production)

The Starlight ↔ Stargate integration requires authentication tokens for secure communication. Create secrets before deployment:

### Option 1: Automatic Secret Creation (Recommended)
```bash
cd starlight-helm

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
cd starlight-helm

# Basic installation (without secrets - not recommended for production)
helm install starlight-stack . \
  --set image.stargate.repository=stargate-backend \
  --set image.stargate.tag=latest \
  --set image.starlight.repository=starlight-api \
  --set image.starlight.tag=latest

# Production installation with secrets (recommended)
helm install starlight-stack . \
  --set secrets.createDefault=false \
  --set secrets.name=stargate-stack-secrets \
  --set secrets.starlightApiKey=true \
  --set secrets.starlightIngestToken=true \
  --set secrets.stargateApiKey=true \
  --set secrets.stargateIngestToken=true \
  --set secrets.starlightStegoCallbackSecret=true

# For testnet deployment
helm install starlight-stack . \
  --set stargate.bitcoinNetwork=testnet \
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
# 127.0.0.1 starlight.local stargate.local 
# TLS: default values expect a secret `stargate-stack-tls` with SANs starlight.local, stargate.local,
#   kubectl create secret tls stargate-stack-tls --cert=stargate-stack.crt --key=stargate-stack.key
# Then hit:
# curl -kI https://starlight.local/  # frontend
# curl -kI https://stargate.local/   # backend

# Observability
# - Backend metrics: https://stargate.local/metrics (prometheus format)
# - Starlight metrics: https://stargate.local/metrics if proxied or service scrape on port 8080 (/metrics)
# - Service annotations included for Prometheus auto-scrape (prometheus.io/scrape=true)
```

## Verify
```bash
# Check pod status
kubectl get pods

# Check services
kubectl get svc stargate-backend starlight-api stargate-postgres stargate-mcp

# Port forward for testing
kubectl port-forward svc/starlight-frontend 3000:3000 &
kubectl port-forward svc/stargate-backend 3001:3001 &
kubectl port-forward svc/starlight-api 8080:8080 &

# Test health endpoints
curl http://localhost:3000/health
curl http://localhost:3001/api/health
curl http://localhost:8080/health

# Test Starlight inscription (requires authentication)
# Get API key from secret:
STARLIGHT_API_KEY=$(kubectl get secret stargate-stack-secrets -o jsonpath='{.data.starlight-api-key}' | base64 -d)
curl -X POST "http://localhost:8080/inscribe" \
  -H "Authorization: Bearer $STARLIGHT_API_KEY" \
  -F "image=@test-image.png" \
  -F "message=test message" \
  -F "method=lsb"
```

## CI Automation for Mocked Contracts and Ingestion

For continuous integration (CI) environments or local development where you need to simulate contracts and proposal ingestion, you can leverage the following settings:

### Mocked Contracts and Tasks

To automatically load a set of demo contracts and tasks into the system on startup, configure the following in your `values.yaml`:

- \`mcp.seedFixtures\`: Set this to \`true\`. When enabled, the MCP (Master Control Program) component of the Stargate backend will, upon initialization, check if the \`mcp_contracts\` and \`mcp_tasks\` database tables are empty. If they are, it will populate them with predefined demo data.

  \`\`\`yaml
  mcp:
    seedFixtures: true # Set to true to load demo contracts and tasks
  \`\`\`

  The demo data is defined in the Stargate source code at \`stargate/backend/mcp/fixtures.go\`. If you require custom mock data for your tests, you would typically modify this source file or implement a mechanism to override it.

### Mocked Ingestion of Proposals

The system ingests proposals by polling for "pending" records from the \`starlight_ingestions\` service. While there isn't a direct "mocking" flag for ingestion similar to \`seedFixtures\`, you can simulate proposal ingestion in your CI environment by:

1.  **Creating Pending Ingestion Records**: In your CI setup, you would programmatically insert records into the \`starlight_ingestions\` service/database with a "pending" status. These records represent the proposals you want to be ingested.
2.  **Using Markdown Proposals**: The ingestion sync service can parse proposals from Markdown strings. You can craft specific Markdown content (potentially embedded within the ingestion record metadata) to define your mock proposals.
3.  **Controlling Default Values**: You can influence the default budget and funding address for ingested proposals using environment variables:

    - \`MCP_DEFAULT_BUDGET_SATS\`: Set this environment variable to define a default budget in satoshis for proposals that don't specify one.
    - \`MCP_DEFAULT_FUNDING_ADDRESS\`: Set this environment variable to define a default funding address for proposals.

    These environment variables can be set directly in your deployment configuration (e.g., in a \`Deployment\` manifest or via Helm's \`--set\` flag) for the Stargate backend.

These settings provide a robust way to test your Starlight cluster's behavior with predefined contracts and proposals in an automated fashion.

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
kubectl rollout restart deployment/stargate-frontend
```

## Uninstall
```bash
helm uninstall starlight-stack
kubectl delete secret stargate-stack-secrets  # Optional: remove secrets
```
