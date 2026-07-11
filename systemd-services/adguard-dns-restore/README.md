# AdGuard DNS Restore

## Problem

The machine's DNS is `127.0.0.1` (the AdGuard pod, via `hostNetwork`) with `8.8.8.8` as fallback. During boot, `127.0.0.1` is not answering yet (k3s has to start and the kubelet has to restart the AdGuard pod), so systemd-resolved fails over to `8.8.8.8`.

Even once AdGuard is up and running, DNS stays on `8.8.8.8` and does not point back to AdGuard as the primary until resolved is restarted.
I want all traffic (both machine and cluster) to run through AdGuard for tracking purposes.

## Solution

`adguard_dns_restore.service` is a oneshot unit that runs after `k3s.service` on boot. Its script polls until AdGuard answers a DNS query on `127.0.0.1`, then restarts `systemd-resolved` so it goes back to using AdGuard as primary DNS. This means I don't have to manually point the DNS back to AdGuard after every reboot once the pod is running.

## Installation

The service is normally installed by [host-setup/setup.sh](../../host-setup/setup.sh) at the repo root, which runs this directory's `install.sh` as one of its steps alongside the other host config. Run that script if setting up the machine for the first time or run `install.sh` only if this service's files have been edited:

```bash
sudo ./install.sh
```

> [!NOTE]
> The installer has to copy rather than symlink; SELinux labels everything under `/home` as `user_home_t`, which systemd is not allowed to read or execute, so symlinks into the repo failed with `Failed to enable unit: Access denied`.
> Copies created in `/etc` and `/usr/local/bin` pick up the correct SELinux labels automatically.

### Re-running

Like the rest of host setup, the installer is idempotent - re-running it (directly or via `host-setup/setup.sh`) just overwrites the installed service and script files with the current repo versions. After installation the service triggers itself on every boot, so a re-run only actually *does* something in two cases:

- the machine is rebuilt / the OS is reinstalled
- the `.service` file or the `.sh` script is edited (the installed copies don't track the repo as they are not symlinked)

### Verification

After a reboot:

```bash
resolvectl status wlo1   # Current DNS Server should be 127.0.0.1
```

## Known limitation

The service only runs once per boot. If AdGuard goes down while the machine is running, resolved fails over to `8.8.8.8` and stays there until the next reboot (or a manual `sudo systemctl restart systemd-resolved`).
