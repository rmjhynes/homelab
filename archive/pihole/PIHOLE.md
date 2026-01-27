# Pi-hole DNS Configuration

## Goal

Configure Pi-hole as the DNS server for `*.homelab` domains, enabling access to services via `<service>.homelab` URLs (e.g., `argocd.homelab`, `pihole.homelab`).

## Architecture

```
Local Machine (192.168.1.x)
    |
    | DNS query: argocd.homelab
    v
Pi-hole (192.168.1.52:53)
    |
    | Resolves *.homelab -> 192.168.1.52
    v
Traefik Ingress (192.168.1.52)
    |
    | Routes based on Host header
    v
ArgoCD / other services
```

## Configuration Changes

### 1. Wildcard DNS Entry (`values.yaml`)

Resolves ANY `*.homelab` domain to the node IP where Traefik listens:

```yaml
dnsmasq:
  customDnsEntries:
    - address=/homelab/192.168.1.52
```

### 2. Enable hostPort (`values.yaml`)

Exposes Pi-hole DNS on port 53 at the node IP (instead of random NodePorts):

```yaml
dnsHostPort:
  enabled: true
  port: 53
```

### 3. Accept Queries from LAN (`values.yaml`)

By default, dnsmasq only accepts queries from local networks. This allows queries from the LAN:

```yaml
extraEnvVars:
  DNSMASQ_LISTENING: 'all'
```

### 4. Chart Version Upgrade (`application.yaml`)

Upgraded from 2.31.0 to 2.35.0. The older version had a bug where hostPort was only set for TCP, but DNS uses UDP by default.

```yaml
targetRevision: 2.35.0
```

## Local Machine DNS Setup

Configure NetworkManager to use Pi-hole:

```bash
# Find your connection name
nmcli connection show

# Set Pi-hole as DNS server
nmcli connection modify "<connection-name>" ipv4.dns "192.168.1.52"
nmcli connection modify "<connection-name>" ipv4.ignore-auto-dns yes
nmcli connection up "<connection-name>"
```

### Fallback DNS (optional)

Edit `/etc/systemd/resolved.conf` to add fallback DNS if Pi-hole is down:

```ini
[Resolve]
FallbackDNS=8.8.8.8 1.1.1.1
```

Then restart: `sudo systemctl restart systemd-resolved`

## Verification

```bash
# Test Pi-hole DNS directly
dig @192.168.1.52 argocd.homelab

# Test local machine resolution
resolvectl query argocd.homelab

# Test HTTP access
curl -I http://argocd.homelab
```

## Troubleshooting

### "Connection refused" on port 53

Pi-hole DNS is on NodePort (random high port), not port 53. Enable `dnsHostPort.enabled: true`.

### "Ignoring query from non-local network"

dnsmasq is rejecting LAN queries. Add `DNSMASQ_LISTENING: 'all'` to `extraEnvVars`.

### hostPort works for TCP but not UDP

Chart version 2.31.0 only sets hostPort for TCP. Upgrade to 2.35.0 which fixes this.

### Check Pi-hole pod ports

```bash
kubectl get pod -l app=pihole -o jsonpath='{.items[0].spec.containers[0].ports}' | jq
```

Should show hostPort: 53 for both TCP and UDP.

## Alternative: LoadBalancer Approach

Instead of hostPort, you can use a LoadBalancer service (requires MetalLB or similar):

```yaml
dnsHostPort:
  enabled: false

serviceDns:
  type: LoadBalancer
  loadBalancerIP: 192.168.1.100
```

The hostPort approach is simpler for single-node setups.
