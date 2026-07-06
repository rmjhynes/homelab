# AdGuard DNS Restore

## Problem

The machine's DNS is `127.0.0.1` (the AdGuard pod, via `hostNetwork`) with `8.8.8.8` as fallback. During boot, `127.0.0.1` is not answering yet (k3s has to start and the kubelet has to restart the AdGuard pod - ArgoCD is not involved in reboot recovery), so systemd-resolved fails over to `8.8.8.8`.

The catch is that systemd-resolved sticks with the last *working* server - even once AdGuard is up, DNS stays on `8.8.8.8` until resolved is restarted. I want all traffic (both machine and cluster) to run through AdGuard for tracking purposes.

## Solution

`adguard_dns_restore.service` is a oneshot unit that runs after `k3s.service` on boot. Its script polls until AdGuard answers a DNS query on `127.0.0.1` (up to a 5 minute deadline so the unit can never hang the boot sequence), then restarts `systemd-resolved` so it goes back to using AdGuard as primary DNS. This means I don't have to manually point the DNS back to AdGuard after every reboot.

## Installation

```bash
sudo ./install.sh
```

The installer symlinks `adguard_dns_restore.sh` into `/usr/local/bin` and `adguard_dns_restore.service` into `/etc/systemd/system`, then enables the service.

### When the script should be used

Run it **once** on the homelab machine as part of host setup (alongside the NetworkManager DNS config and firewalld rules in `manifests/adguard/ISSUES.md`). After that the service triggers itself on every boot so nothing needs running manually.

Re-run it only if:

- the machine is rebuilt / the OS is reinstalled
- the repo checkout moves to a different path (the symlinks would go stale)
- the `.service` file is edited

No re-run is needed after reboots, after editing the `.sh` script (the symlink picks up changes instantly), or after cluster teardown/rebuild - the systemd side is independent of cluster state.

### Verification

After a reboot:

```bash
resolvectl status wlo1   # Current DNS Server should be 127.0.0.1
```

## Known limitation

The service only runs once per boot. If AdGuard goes down while the machine is running, resolved fails over to `8.8.8.8` and stays there until the next reboot (or a manual `sudo systemctl restart systemd-resolved`).
