# Host Setup

Everything in this repo that runs *on the cluster* is managed by GitOps (ArgoCD), but a few things live at the host-OS level of the homelab machine and can't be managed that way. `setup.sh` applies all of them in one go so nothing has to be remembered after a rebuild:

1. **NetworkManager DNS** - point the WiFi connection at AdGuard (`127.0.0.1`) with `8.8.8.8` as fallback, and ignore DHCP-provided DNS (external servers return `NXDOMAIN` for the custom `.homelab` domains)
2. **`/etc/hosts` cleanup** - remove stale `.homelab` entries that would override AdGuard's DNS rewrites
3. **firewalld** - add the Kubernetes CNI interfaces (`cni0`, `flannel.1`) to the trusted zone so pod-to-pod networking works
4. **adguard_dns_restore service** - runs `systemd-services/adguard-dns-restore/install.sh` to install and enable the systemd unit that restores AdGuard as primary DNS after each boot

## Usage

On the homelab machine:

```bash
sudo ./setup.sh
```

The active WiFi connection is auto-detected; pass a name to override:

```bash
sudo ./setup.sh "my-wifi-connection"
```

## Idempotency

Every step checks the current state first and skips if already configured, so the script is safe to re-run at any time. Situations where re-running makes sense:

- after a machine rebuild / OS reinstall
- after connecting to a different WiFi network (new connection profile means the DNS config needs applying again)
- if firewalld rules have dropped off (this can happen after network changes - see `manifests/adguard/ISSUES.md`)
- when in doubt - a re-run on an already-configured machine changes nothing

The NetworkManager change uses `nmcli device reapply` rather than bouncing the connection, so it is safe to run over SSH.

## Verification

```bash
resolvectl status wlo1           # DNS Servers: 127.0.0.1 8.8.8.8
firewall-cmd --get-active-zones  # cni0 and flannel.1 under trusted
```
