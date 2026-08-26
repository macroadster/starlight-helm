#!/usr/bin/env bash
# Render fail2ban config from the starlight-stack chart + values-local.yaml
# and copy it onto this k3s node. Does not apply the ConfigMap; helm upgrade
# of starlight-stack owns the in-cluster object.
# Prefers docker nsenter so it works without sudo.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
CHART_ROOT="$(cd "$ROOT/../.." && pwd)"
RELEASE="${FAIL2BAN_RELEASE:-starlight-stack}"
VALUES_LOCAL="${FAIL2BAN_VALUES:-${CHART_ROOT}/values-local.yaml}"

HOST_FILTER_DIR=/etc/fail2ban/filter.d
HOST_JAIL_DIR=/etc/fail2ban/jail.d
HOST_LOGROTATE=/etc/logrotate.d/traefik

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT
RENDERED="$WORK/fail2ban-configmap.yaml"
HELM_ERR="$WORK/helm.err"

nsenter_host() {
  if [[ "${1:-}" == "--" ]]; then
    shift
  fi
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
    return
  fi
  if command -v docker >/dev/null 2>&1; then
    docker run --rm -i --privileged --pid=host alpine:3.20 \
      nsenter -t 1 -m -u -n -i -- "$@"
    return
  fi
  if sudo -n true 2>/dev/null; then
    sudo "$@"
    return
  fi
  echo "need root, passwordless sudo, or docker to configure host fail2ban" >&2
  exit 1
}

copy_to_host() {
  local dest="$1" mode="$2"
  nsenter_host sh -c "cat > '$dest' && chmod $mode '$dest'"
}

cm_key() {
  local v
  v="$(python3 - "$RENDERED" "$1" <<'PY'
import sys
path, key = sys.argv[1], sys.argv[2]
lines = open(path, encoding="utf-8").read().splitlines()
in_data = False
i = 0
n = len(lines)
while i < n:
    line = lines[i]
    if not in_data:
        if line == "data:" or line.startswith("data:"):
            in_data = True
        i += 1
        continue
    if line == "---":
        break
    if not line.startswith("  "):
        if line.strip() == "":
            i += 1
            continue
        break
    if line.startswith("    "):
        i += 1
        continue
    rest = line[2:]
    if ":" not in rest:
        i += 1
        continue
    k, _, val = rest.partition(":")
    k, val = k.strip(), val.strip()
    if k != key:
        i += 1
        continue
    if val.startswith("|"):
        block = []
        i += 1
        while i < n:
            bl = lines[i]
            if bl.startswith("    "):
                block.append(bl[4:])
            elif bl.strip() == "":
                block.append("")
            else:
                break
            i += 1
        sys.stdout.write("\n".join(block))
        raise SystemExit(0)
    if len(val) >= 2 and val[0] == val[-1] and val[0] in "\"'":
        val = val[1:-1]
    sys.stdout.write(val)
    raise SystemExit(0)
    i += 1
raise SystemExit(1)
PY
)" || { echo "missing ConfigMap key: $1" >&2; exit 1; }
  if [[ -z "$v" ]]; then
    echo "missing ConfigMap key: $1" >&2
    exit 1
  fi
  printf '%s' "$v"
}

if ! command -v helm >/dev/null 2>&1; then
  echo "helm is required to render fail2ban config" >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required to parse rendered fail2ban config" >&2
  exit 1
fi
if [[ ! -f "$VALUES_LOCAL" ]]; then
  echo "missing $VALUES_LOCAL (set fail2ban.enabled: true there)" >&2
  exit 1
fi

echo "rendering ConfigMap from chart + values-local.yaml (not applying)"
if ! helm template "$RELEASE" "$CHART_ROOT" \
  -f "$VALUES_LOCAL" \
  --show-only templates/fail2ban-configmap.yaml \
  > "$RENDERED" 2>"$HELM_ERR"; then
  if grep -q "could not find template" "$HELM_ERR"; then
    echo "fail2ban is disabled; set fail2ban.enabled: true in $VALUES_LOCAL" >&2
  else
    cat "$HELM_ERR" >&2
  fi
  exit 1
fi
if [[ ! -s "$RENDERED" ]]; then
  echo "fail2ban is disabled; set fail2ban.enabled: true in $VALUES_LOCAL" >&2
  exit 1
fi

HOST_LOG_DIR="$(cm_key 'host-dir')"
FILE_NAME="$(cm_key 'file-name')"
TRAEFIK_UID="$(cm_key 'traefik-uid')"
TRAEFIK_GID="$(cm_key 'traefik-gid')"

echo "creating ${HOST_LOG_DIR}/${FILE_NAME} (uid ${TRAEFIK_UID})"
nsenter_host sh -c "mkdir -p '${HOST_LOG_DIR}' && chown ${TRAEFIK_UID}:${TRAEFIK_GID} '${HOST_LOG_DIR}' && chmod 755 '${HOST_LOG_DIR}' && touch '${HOST_LOG_DIR}/${FILE_NAME}' && chown ${TRAEFIK_UID}:${TRAEFIK_GID} '${HOST_LOG_DIR}/${FILE_NAME}'"

echo "installing fail2ban filters and jail"
cm_key 'traefik-404.conf' | copy_to_host "${HOST_FILTER_DIR}/traefik-404.conf" 644
cm_key 'traefik-scan.conf' | copy_to_host "${HOST_FILTER_DIR}/traefik-scan.conf" 644
cm_key 'traefik-ingress.local' | copy_to_host "${HOST_JAIL_DIR}/traefik-ingress.local" 644
cm_key 'logrotate-traefik' | copy_to_host "${HOST_LOGROTATE}" 644

if [[ "${1:-}" == "--print-traefik-values" ]]; then
  cm_key 'traefik-accesslog.yaml'
  echo
  exit 0
fi

if [[ "${1:-}" == "--traefik" ]]; then
  overlay="$WORK/traefik-accesslog.yaml"
  cm_key 'traefik-accesslog.yaml' > "$overlay"
  echo "upgrading Traefik with access-log overlay from values-local.yaml"
  helm upgrade traefik traefik/traefik \
    --namespace traefik --version 41.2.0 \
    -f "${CHART_ROOT}/deploy/traefik-values.yaml" \
    -f "$overlay" \
    --wait --timeout 8m
fi

echo "reloading fail2ban"
nsenter_host fail2ban-client reload
nsenter_host fail2ban-client status
nsenter_host fail2ban-client status traefik-404
nsenter_host fail2ban-client status traefik-scan
echo "ok"
