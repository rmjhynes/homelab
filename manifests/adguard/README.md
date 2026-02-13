# AdGuard Home

## Setup

### 1. Complete AdGuard Setup Wizard

Access `http://<machine-ip>:3000`:
- Create admin username/password
- Configure listen interfaces (defaults are usually fine with hostNetwork)
    - Admin: `0.0.0.0:3001`
    - DNS: `127.0.0.1:53`

### 2. Configure Local Machine DNS

Configure NetworkManager to use AdGuard and ignore DHCP-provided DNS:

```bash
nmcli con mod "<wifi-name>" ipv4.dns "127.0.0.1"
nmcli con mod "<wifi-name>" ipv4.ignore-auto-dns yes
nmcli con down "<wifi-name>" && nmcli con up "<wifi-name>"
```

> [!NOTE]  
> `8.8.8.8` is the fallback DNS in case the adguard deployment goes down and the internet cannot be accessed to redeploy (via Argocd)

Verify with:
```bash
resolvectl status wlo1

Link 3 (wlo1)
    Current Scopes: DNS LLMNR/IPv4 LLMNR/IPv6
         Protocols: +DefaultRoute LLMNR=resolve -mDNS -DNSOverTLS DNSSEC=no/unsupported
Current DNS Server: 127.0.0.1
       DNS Servers: 127.0.0.1 8.8.8.8
     Default Route: yes
```

### 3. Verify DNS

```bash
dig @192.168.1.21 google.com
```

### 4. Access AdGuard UI
Navigate to `adguard.homelab`

## Architecture

AdGuard runs as a bare Pod with `hostNetwork: true`, binding directly to the host's network interfaces. This allows it to serve DNS on port 53 without NodePort or LoadBalancer complexity.

The admin UI binds to `0.0.0.0:3001` (all interfaces) rather than `127.0.0.1:3001`. This is necessary because the Kubernetes Service routes traffic to the node's actual IP, not `127.0.0.1`. If the UI only listened on localhost, the Service couldn't reach it and the `adguard.homelab` ingress wouldn't work. DNS remains on `127.0.0.1:53` since it's accessed directly via the host network, not through a Service.

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
│   │ NetworkManager  │─────▶│ AdGuard Pod      │   │
│   │ DNS=127.0.0.1   │       │ (hostNetwork)    │   │
│   └─────────────────┘       │                  │   │
│                             │ 127.0.0.1:53 DNS │   │
│                             │ 0.0.0.0:3001  UI │   │
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

NetworkManager is configured to use AdGuard (`127.0.0.1`) for DNS and ignore DHCP-provided servers. This ensures custom `.homelab` domains resolve correctly via AdGuard's DNS rewrites.
