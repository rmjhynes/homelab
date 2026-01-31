# AdGuard Home

## Setup

### 1. Complete AdGuard Setup Wizard

Access `http://<machine-ip>:3000`:
- Create admin username/password
- Configure listen interfaces (defaults are usually fine with hostNetwork)
    - Admin was `127.0.0.1:3001`
    - DNS was `127.0.0.1:53`

### 2. Configure Local Machine DNS

For systemd-resolved (persistent):
```bash
sudo mkdir -p /etc/systemd/resolved.conf.d
sudo tee /etc/systemd/resolved.conf.d/adguard.conf << EOF
[Resolve]
DNS=127.0.0.1:53
EOF
sudo systemctl restart systemd-resolved
```

### 3. Verify DNS

```bash
dig @192.168.1.21 google.com
```

### 4. Access AdGuard UI
Navigate to `127.0.0.1:3001`

## Architecture

AdGuard runs as a bare Pod with `hostNetwork: true`, binding directly to the host's network interfaces. This allows it to serve DNS on port 53 without NodePort or LoadBalancer complexity.

### DNS Policy: `ClusterFirstWithHostNet`

Normal pods get their own network namespace with a `/etc/resolv.conf` pointing to CoreDNS (the cluster DNS). This lets them resolve both:
- External names like `google.com`
- Cluster service names like `my-service.default.svc.cluster.local`

When `hostNetwork: true` is set, the pod shares the **host's** network namespace, including the host's `/etc/resolv.conf`. The host doesn't know about Kubernetes services, so DNS lookups for cluster services would fail.

`dnsPolicy: ClusterFirstWithHostNet` solves this - it tells Kubernetes to still inject CoreDNS into the pod's DNS configuration, even though it's using the host network. The pod can then resolve both external names and cluster service names.

**Without it**: Pod uses host DNS so can't resolve `my-service.default.svc.cluster.local`

**With it**: Pod uses CoreDNS so can resolve both external and cluster names

```
┌────────────────────────────────────────────────────┐
│  Local Machine                                     │
│                                                    │
│   ┌─────────────────┐       ┌──────────────────┐   │
│   │ systemd-resolved│─────▶│ AdGuard Pod      │   │
│   │ DNS=127.0.0.1   │       │ (hostNetwork)    │   │
│   └─────────────────┘       │                  │   │
│                             │ 127.0.0.1:53 DNS │   │
│                             │ 127.0.0.1:3001 UI│   │
│                             └──────────────────┘   │
└────────────────────────────────────────────────────┘
```

## Persistent Storage

Configuration and data persist across machine and pod restarts using hostPath volumes with `DirectoryOrCreate`:

| Container Path | Host Path | Purpose |
|----------------|-----------|---------|
| `/opt/adguardhome/conf` | `/var/lib/rancher/k3s/storage/adguard/conf` | Settings, users, blocklists |
| `/opt/adguardhome/work` | `/var/lib/rancher/k3s/storage/adguard/work` | Query logs, stats, cache |

The `DirectoryOrCreate` type means Kubernetes creates these directories automatically if they don't exist - no manual setup is required.

## Local DNS Configuration

The local machine uses systemd-resolved to route DNS queries to AdGuard:

```ini
# /etc/systemd/resolved.conf.d/adguard.conf
[Resolve]
DNS=127.0.0.1:53
```

### DNS Fallback Behavior

If AdGuard goes down, systemd-resolved automatically falls back to DHCP-provided DNS servers from the network router. This provides resilience without explicit `FallbackDNS` configuration.

To verify current DNS sources:
```bash
resolvectl status
```
