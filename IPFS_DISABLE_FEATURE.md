# IPFS Global Disable Feature

## Overview

The Starlight backend now supports a global IPFS disable mechanism that prevents all IPFS operations when IPFS is disabled. This feature was added to fix the issue where IPFS publish operations were happening even when IPFS was configured to be disabled.

## Environment Variables

### Single IPFS Control
```bash
IPFS_ENABLED=false  # Set to "false" to disable IPFS
IPFS_ENABLED=true   # Set to "true" or omit to enable IPFS (default)
```

When `IPFS_ENABLED` is set to "false", all IPFS operations throughout the application will be gracefully disabled with appropriate logging.

## Implementation Details

### Global Check Function
A new function `ipfs.IsEnabled()` has been added to check if IPFS is enabled:
- Returns `false` if `IPFS_ENABLED=false` or `IPFS_DISABLED=true`
- Returns `true` by default (IPFS enabled)

### Client Behavior
- `ipfs.NewClientFromEnv()` returns `nil` when IPFS is disabled
- All IPFS client methods (`AddBytes`, `Cat`, `PubsubPublish`) return appropriate errors when client is nil
- All IPFS operation sites have been updated to handle disabled state

### Updated Components

The following components now respect the global IPFS disable setting:

1. **Handlers** (`backend/handlers/handlers.go`)
   - `publishPendingIngestAnnouncement()` - skips publish when IPFS disabled

2. **Stego Publishing** (`backend/middleware/smart_contract/stego_publish.go`)
   - `maybePublishStegoForProposal()` - skips stego approval when IPFS disabled
   - All IPFS client creation sites handle nil client

3. **Smart Contract Server** (`backend/middleware/smart_contract/server.go`)
   - All IPFS publish operations check for nil client
   - Graceful fallback with logging when IPFS disabled

4. **Sync Services**
   - `sync_pubsub.go` - Returns error when IPFS disabled
   - `ingestion_sync.go` - Returns error when IPFS disabled
   - `stego_reconcile.go` - Handles nil IPFS client
   - `ipfs_ingest_sync.go` - Checks global IPFS enable before starting

5. **Block Monitor** (`backend/bitcoin/block_monitor.go`)
   - Already handles nil IPFS client correctly

## Helm Chart Configuration

The Helm chart has been updated with the simplified IPFS enable/disable configuration:

### Environment Variables
```yaml
stargate:
  ipfs:
    enabled: true    # Maps to IPFS_ENABLED (set to "false" to disable)
```

### Deployment Template
The deployment template now sets:
- `IPFS_ENABLED={{ .Values.stargate.ipfs.enabled }}`

## Usage Examples

### Disable IPFS via Helm
```bash
helm install starlight . \
  --set stargate.ipfs.enabled=false
```

### Disable IPFS via Environment
```bash
export IPFS_ENABLED=false

# Then restart the application
```

## Behavior When Disabled

When IPFS is disabled:

1. **No Network Connections**: No IPFS API calls are made
2. **Graceful Degradation**: Features that require IPFS log appropriate messages and continue
3. **Error Handling**: Operations that explicitly need IPFS return clear error messages
4. **Logging**: All skipped IPFS operations are logged for visibility

### Example Log Messages
```
pending ingest announce: IPFS disabled, skipping for abc123
stego approval: IPFS disabled, skipping for proposal-456
psbt: ingest update publish skipped - IPFS disabled
```

## Testing

### Verification
To verify IPFS is disabled:

1. Check environment variables are set
2. Check logs for "IPFS disabled" messages
3. Monitor network traffic (no IPFS API calls should be made)
4. Verify application continues to function for non-IPFS features

### Unit Tests
The IPFS disable functionality has been tested:
- `ipfs.IsEnabled()` returns `false` when `IPFS_ENABLED=false`
- `ipfs.IsEnabled()` returns `true` when `IPFS_ENABLED=true` or unset
- `ipfs.NewClientFromEnv()` returns `nil` when disabled
- All IPFS client methods return appropriate errors when client is `nil`

## Migration Notes

This change is **backward compatible**:
- Default behavior (IPFS enabled) is unchanged
- Existing IPFS configuration continues to work
- No breaking changes to APIs or configuration

To disable IPFS in existing deployments, set either `IPFS_ENABLED=false` or `IPFS_DISABLED=true`.