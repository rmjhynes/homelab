# Host Setup

Everything in this repo that runs *on the cluster* is managed by ArgoCD, but a few things live at the host-OS level of the homelab machine and can't be managed that way. `setup.sh` applies all of them in one go so nothing has to be remembered after a rebuild.

## Workflow

### New machine, after cluster has been created

1. Configures NetworkManager wifi connection to point at AdGuard (`127.0.0.1`) as primary DNS with `8.8.8.8` as the fallback
2. Does not edit `/etc/hosts` as this is a new machine and does therefore not contain any manually added `.homelab` entries
3. Configures the following in `firewalld` as per [k3s docs](https://docs.k3s.io/installation/requirements?_highlight=firewalld&os=rhel#firewalld-1):
    - Adds k8s CNI interfaces (`cni0`, `flannel.1`) and pod/service CIDR sources (`10.42.0.0/16`, `10.43.0.0/16`) to the trusted zone to allow inter pod networking
    - Allows `6443/tcp` for the apiserver
4. Installs and enables:
    - The `adguard_dns_restore.service` systemd service which restarts `systemd-resolved` to point DNS back to using adguard when its up
    - The `adguard_dns_check.timer` which re-checks every 2 minutes and restores AdGuard as primary DNS if `systemd-resolved` has fallen back to `8.8.8.8`

### Machine that has already been setup and is in use

1. Checks NetworkManager wifi connection points at AdGuard (`127.0.0.1`) as primary DNS with `8.8.8.8` as the fallback
2. Checks `/etc/hosts` does not contain any manually added `.homelab` entries that will override DNS and mask  AdGuard's rewrites
3. Checks the following is configured in `firewalld`:
    - k8s CNI interfaces (`cni0`, `flannel.1`) and pod/service CIDR sources (`10.42.0.0/16`, `10.43.0.0/16`) are in the trusted zone to allow inter pod networking
    - `6443/tcp` (apiserver) is allowed
4. Installs and enables:
    - The `adguard_dns_restore.service` systemd service which restarts `systemd-resolved` to point DNS back to using adguard when its up
    - The `adguard_dns_check.timer` which re-checks every 2 minutes and restores AdGuard as primary DNS if `systemd-resolved` has fallen back to `8.8.8.8`

## Usage

```bash
sudo ./setup.sh
```

The active WiFi connection is auto-detected, but you can pass an override:

```bash
sudo ./setup.sh "my-wifi-connection"
```

## Idempotency

Every step checks the current state first and skips if already configured, so the script is safe to re-run at any time. Situations where re-running makes sense:

- after a machine rebuild / OS reinstall
- after connecting to a different WiFi network (new connection profile means the DNS config needs applying again)
- if firewalld rules have changed
- when in doubt - a re-run on an already-configured machine changes nothing

> [!NOTE]
> The NetworkManager change uses `nmcli device reapply` rather than bouncing the connection, so it is safe to run over SSH.

## NetworkManager connections vs devices

The script touches both a *connection* (the saved profile for the WiFi network, e.g. `my-wifi-connection`) and a *device* (the physical interface it runs on e.g. `wlo1`), because settings live in one and take effect in the other:

- `nmcli connection modify` edits the profile on disk (`/etc/NetworkManager/system-connections/`) which is persistent across reboots/reconnects, but does not update the running interface
- `nmcli device reapply` syncs the live interface to whatever profile is active on it which allows the change to take effect immediately without dropping the connection

DNS *can* be set directly at device level (`nmcli device modify wlo1 ipv4.dns ...` or going straight to systemd-resolved with `resolvectl dns wlo1 ...`), but these changes are lost on reconnect/reboot.

## Verification

`setup.sh` verifies the applied state itself at the end of every run and exits non-zero if any check fails. To re-check manually:

```bash
resolvectl status wlo1            # DNS Servers: 127.0.0.1 8.8.8.8
firewall-cmd --info-zone=trusted  # interfaces: cni0 flannel.1, sources: 10.42.0.0/16 10.43.0.0/16
firewall-cmd --list-ports         # 6443/tcp (default zone)
```
