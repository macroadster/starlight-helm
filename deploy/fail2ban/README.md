# Fail2ban for Traefik ingress 404s

Host fail2ban jails that ban IPs flooding the Traefik Gateway with 404s
(PHP/WordPress scanners, no-SNI probes). This is the host nftables
fail2ban already used for `sshd`, not the Traefik middleware plugin.

Bans use a dedicated `filter` chain on **prerouting priority -150**
(before kube-proxy / k3s svclb DNAT). The default nftables `input`
hook never sees `hostPort` 80/443, so a Ban there was cosmetic:
Traefik kept logging 404s after the jail fired.

Why not an HTTPRoute middleware? Unmatched scanner requests never hit
the Stargate HTTPRoute (`router="-"` in the access log), so a route
filter would miss the traffic we actually want to ban.

## What goes where

| Path | Role |
|---|---|
| `values.yaml` `fail2ban.*` | committed defaults (off) |
| `values-local.yaml` `fail2ban.*` | this node: enable + host log path (gitignored) |
| `templates/fail2ban-configmap.yaml` | committed template (jail, Traefik overlay) |
| `files/fail2ban/filter.d/` | committed filters + testdata |
| `deploy/fail2ban/install.sh` | renders locally and copies keys onto the host |

`deploy/` itself is **not** the app chart. It holds install notes and
values for *other* cluster components (Traefik helm chart, cert-manager,
ingress-nginx → Traefik migration). The Stargate chart is
`templates/` + `values.yaml` + `values-local.yaml`.

## Apply

```bash
# values-local.yaml must have fail2ban.enabled: true
./deploy/fail2ban/install.sh

# First time only (or after changing fail2ban.accessLog): point Traefik
# at the host file. Overlay is rendered from values-local.yaml.
./deploy/fail2ban/install.sh --traefik

# In-cluster ConfigMap is owned by the app release (not install.sh):
helm upgrade --install starlight-stack . -f values-local.yaml
```

`install.sh` renders with `helm template` and copies keys to the host. It
does not `kubectl apply` the ConfigMap — that would collide with
`helm upgrade`. Re-run it after changing filters or `fail2ban.*` values.
`install.sh` uses `docker nsenter` when you are not root. Jail/action
hook changes require a fail2ban **restart** (reload keeps the old
nftables chain); `install.sh` does that restart.

If an older `install.sh` already applied the ConfigMap, delete or adopt it
before the next app upgrade:

```bash
kubectl delete configmap starlight-stack-fail2ban --ignore-not-found
# or adopt:
# kubectl annotate configmap starlight-stack-fail2ban \
#   meta.helm.sh/release-name=starlight-stack \
#   meta.helm.sh/release-namespace=default --overwrite
# kubectl label configmap starlight-stack-fail2ban \
#   app.kubernetes.io/managed-by=Helm --overwrite
```

## Check

```bash
fail2ban-regex files/fail2ban/testdata/access.log \
  files/fail2ban/filter.d/traefik-404.conf

docker run --rm -i --privileged --pid=host alpine:3.20 \
  nsenter -t 1 -m -u -n -i -- fail2ban-client status traefik-404

# hook must be prerouting, not input
docker run --rm -i --privileged --pid=host alpine:3.20 \
  nsenter -t 1 -m -u -n -i -- \
  nft list chain inet f2b-table f2b-prerouting-traefik-404
```

Unban: `fail2ban-client set traefik-404 unbanip A.B.C.D`
