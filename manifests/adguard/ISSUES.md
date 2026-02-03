# AdGuard DNS Issues

Summary of fixes applied to get AdGuard DNS rewrites working with Traefik ingress.

## 1. System DNS Configuration

By default, NetworkManager uses DNS servers provided by DHCP (typically a router or ISP). These external servers don't know about the custom `.homelab` domains and will return `NXDOMAIN`. Configure NetworkManager to use AdGuard (127.0.0.1) so DNS queries actually use the rewrites configured above:

```bash
nmcli con mod "<wifi-name>" ipv4.dns "127.0.0.1"
nmcli con mod "<wifi-name>" ipv4.ignore-auto-dns yes
nmcli con down "<wifi-name>" && nmcli con up "<wifi-name>"
```

Verify with:
```bash
resolvectl status wlo1
```

## 2. Remove Stale `/etc/hosts` Entries

Check for and remove any old entries that override DNS:

```bash
grep homelab /etc/hosts
sudo sed -i '/\.homelab/d' /etc/hosts
```

## 3. Firewalld - Trust CNI Interfaces

If using `firewalld`, add Kubernetes CNI interfaces to the trusted zone. This is required for pod-to-pod networking:

```bash
firewall-cmd --zone=trusted --add-interface=cni0 --permanent
firewall-cmd --zone=trusted --add-interface=flannel.1 --permanent
firewall-cmd --reload
```

Verify with:
```bash
firewall-cmd --get-active-zones
```

> [!NOTE]  
> This may need to be re-applied after network changes (WiFi reconnection, etc.).

## Verification

```bash
# Test DNS resolution
dig home.homelab @127.0.0.1

# Test HTTP routing
curl -I http://home.homelab
```
