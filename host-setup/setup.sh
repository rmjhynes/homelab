#!/usr/bin/env bash
set -e

# Applies all host-level config the AdGuard DNS setup needs on the homelab
# machine (Fedora). Idempotent - every step checks current state first, so
# it's safe to re-run any time (after a machine rebuild, WiFi change, etc).
#
# 1. NetworkManager: use AdGuard (127.0.0.1) as DNS with 8.8.8.8 fallback
# 2. Remove stale .homelab entries from /etc/hosts
# 3. firewalld: trust the Kubernetes CNI interfaces (pod-to-pod networking)
# 4. Install and enable the adguard_dns_restore systemd service
#
# Usage: sudo ./setup.sh [wifi-connection-name]
# The active WiFi connection is auto-detected if no name is given.

# Get the directory where this script lives, regardless of where it's called from
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# AdGuard (via hostNetwork on 127.0.0.1) first; 8.8.8.8 as fallback so the
# internet stays reachable if the AdGuard pod is down
DNS_SERVERS="127.0.0.1 8.8.8.8"

if [ "$EUID" -ne 0 ]; then
  echo "This script must be run as root (it configures NetworkManager, /etc/hosts, firewalld and systemd)"
  echo "Try: sudo $0"
  exit 1
fi

### 1. NetworkManager DNS ###

# Use the connection name passed as $1, otherwise auto-detect the active WiFi
# connection (type 802-11-wireless)
CONN="${1:-$(nmcli -t -f NAME,TYPE con show --active | awk -F: '$2 == "802-11-wireless" {print $1; exit}')}"

if [ -z "$CONN" ]; then
  echo "Could not auto-detect an active WiFi connection"
  echo "Pass the connection name explicitly: sudo $0 <wifi-connection-name>"
  exit 1
fi

CURRENT_DNS="$(nmcli -g ipv4.dns con show "$CONN")"
CURRENT_IGNORE_AUTO_DNS="$(nmcli -g ipv4.ignore-auto-dns con show "$CONN")"

# nmcli -g prints the DNS servers comma-separated, hence ${DNS_SERVERS// /,}
if [ "$CURRENT_DNS" = "${DNS_SERVERS// /,}" ] && [ "$CURRENT_IGNORE_AUTO_DNS" = "yes" ]; then
  echo "NetworkManager DNS already configured on '${CONN}' - skipping"
else
  echo "Setting DNS servers (${DNS_SERVERS}) on '${CONN}'..."
  nmcli con mod "$CONN" ipv4.dns "$DNS_SERVERS"
  # Ignore DHCP-provided DNS servers - they don't know the .homelab rewrites
  nmcli con mod "$CONN" ipv4.ignore-auto-dns yes
  # 'device reapply' pushes the profile change to the live device without
  # tearing the connection down (unlike 'con down && con up'), so this is
  # safe to run over SSH
  DEVICE="$(nmcli -t -f NAME,DEVICE con show --active | awk -F: -v c="$CONN" '$1 == c {print $2; exit}')"
  nmcli device reapply "$DEVICE"
fi

### 2. Stale /etc/hosts entries ###

# Old manual .homelab entries in /etc/hosts override DNS and mask AdGuard's
# rewrites - remove them so resolution always goes through AdGuard
if grep -q '\.homelab' /etc/hosts; then
  echo "Removing stale .homelab entries from /etc/hosts..."
  sed -i '/\.homelab/d' /etc/hosts
else
  echo "No stale .homelab entries in /etc/hosts - skipping"
fi

### 3. firewalld - trust CNI interfaces ###

# k3s pod-to-pod networking needs the CNI interfaces in the trusted zone,
# otherwise firewalld blocks cross-pod traffic
if systemctl is-active --quiet firewalld; then
  RELOAD=no
  for IFACE in cni0 flannel.1; do
    if firewall-cmd --zone=trusted --query-interface="$IFACE" > /dev/null 2>&1; then
      echo "firewalld: ${IFACE} already in trusted zone - skipping"
    else
      echo "firewalld: adding ${IFACE} to trusted zone..."
      firewall-cmd --zone=trusted --add-interface="$IFACE" --permanent
      RELOAD=yes
    fi
  done
  # Single reload at the end so the permanent rules become active
  if [ "$RELOAD" = "yes" ]; then
    firewall-cmd --reload
  fi
else
  echo "firewalld is not running - skipping CNI firewall rules"
fi

### 4. adguard_dns_restore systemd service ###

# Already idempotent itself (symlinks with -f, enable) and checks for dig
"${SCRIPT_DIR}/../systemd-services/adguard-dns-restore/install.sh"

echo ""
echo "Host setup complete."
echo "Verify DNS:      resolvectl status wlo1   # DNS Servers: 127.0.0.1 8.8.8.8"
echo "Verify firewall: firewall-cmd --get-active-zones"
