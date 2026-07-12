#!/usr/bin/env bash
set -e

# Applies all host-level config the AdGuard DNS setup needs on the homelab
# machine

# Get the directory where this script lives, regardless of where it's called from
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# AdGuard (via hostNetwork on 127.0.0.1) as primary
# 8.8.8.8 as fallback so internet stays reachable if the AdGuard pod is down
DNS_SERVERS="127.0.0.1 8.8.8.8"

if [ "$EUID" -ne 0 ]; then
  echo "This script must be run as root (it configures NetworkManager, /etc/hosts, firewalld and systemd)"
  echo "Use sudo $0 instead"
  exit 1
fi

# 1. NetworkManager: use AdGuard (127.0.0.1) as DNS with 8.8.8.8 fallback

# Use the wifi connection name passed as $1, otherwise auto detect the active WiFi connection
# awk extracts only the connection of type 802-11-wireless from the list of connections
CONN="${1:-$(nmcli --terse --fields NAME,TYPE connection show --active | awk -F: '$2 == "802-11-wireless" {print $1; exit}')}"

if [ -z "$CONN" ]; then
  echo "Could not auto-detect an active WiFi connection"
  echo "Pass the connection name explicitly: sudo $0 <wifi-connection-name>"
  exit 1
fi

# Get device (network interface) associated with the wifi connection so changes can be reapplied
# without dropping the wifi connection, and to check DNS servers configured for it
# REMEMBER: DNS is modified at the connection level but reapplied at the device level
DEVICE="$(nmcli --terse --fields NAME,DEVICE connection show --active | awk --field-separator=: --assign=c="$CONN" '$1 == c {print $2; exit}')"

CURRENT_DNS="$(nmcli --get-values ipv4.dns connection show "$CONN")"
CURRENT_IGNORE_AUTO_DNS="$(nmcli --get-values ipv4.ignore-auto-dns connection show "$CONN")"

# Configure connection DNS if not already done
# nmcli --get-values prints the DNS servers comma separated, so replace space with comma
EXPECTED_DNS="$(echo "$DNS_SERVERS" | tr ' ' ',')"
if [ "$CURRENT_DNS" = "$EXPECTED_DNS" ] && [ "$CURRENT_IGNORE_AUTO_DNS" = "yes" ]; then
  echo "NetworkManager DNS already configured on '${CONN}' - skipping"
else
  echo "Setting DNS servers (${DNS_SERVERS}) on '${CONN}'..."
  nmcli connection modify "$CONN" ipv4.dns "$DNS_SERVERS"
  # Ignore DHCP-provided DNS servers as they don't know the .homelab rewrites
  nmcli connection modify "$CONN" ipv4.ignore-auto-dns yes
  # `device reapply` pushes the profile change to the live device without dropping the
  # connection (unlike 'con down && con up'), so this is safe to run over SSH
  nmcli device reapply "$DEVICE"
fi

# 2. Delete stale .homelab entries from /etc/hosts if they exist
# and write changes back to the file

if grep --silent '\.homelab' /etc/hosts; then
  echo "Removing stale .homelab entries from /etc/hosts..."
  sed --in-place '/\.homelab/d' /etc/hosts
else
  echo "No stale .homelab entries in /etc/hosts - skipping"
fi

# 3. Configure firewalld to allow k3s to work

if systemctl is-active --quiet firewalld; then
  RELOAD=no
  for INTERFACE in cni0 flannel.1; do
    if firewall-cmd --zone=trusted --query-interface="$INTERFACE" > /dev/null 2>&1; then
      echo "firewalld: ${INTERFACE} already in trusted zone - skipping"
    else
      echo "firewalld: adding ${INTERFACE} to trusted zone..."
      firewall-cmd --zone=trusted --add-interface="$INTERFACE" --permanent
      RELOAD=yes
    fi
  done

  for SOURCE in 10.42.0.0/16 10.43.0.0/16; do
    if firewall-cmd --zone=trusted --query-source="$SOURCE" > /dev/null 2>&1; then
      echo "firewalld: ${SOURCE} already a trusted source - skipping"
    else
      echo "firewalld: adding ${SOURCE} to trusted zone sources..."
      firewall-cmd --zone=trusted --add-source="$SOURCE" --permanent
      RELOAD=yes
    fi
  done

  if firewall-cmd --query-port=6443/tcp > /dev/null 2>&1; then
    echo "firewalld: port 6443/tcp already allowed - skipping"
  else
    echo "firewalld: allowing port 6443/tcp (k3s apiserver)..."
    firewall-cmd --add-port=6443/tcp --permanent
    RELOAD=yes
  fi

  # Single reload at the end if any changes made so the permanent rules become active
  if [ "$RELOAD" = "yes" ]; then
    echo "Reloading firewall-cmd..."
    firewall-cmd --reload
  fi
else
  echo "firewalld is not running - skipping k8s firewall rules"
fi

# 4. Call script to install and enable the adguard_dns_restore systemd service

echo ""
sudo "${SCRIPT_DIR}/../systemd-services/adguard-dns-restore/install.sh"

# 5. Verify DNS and firewalld configured as expected

echo ""
echo "Verifying host setup..."
FAILED=no

# systemd-resolved should be using AdGuard first with 8.8.8.8 as fallback
if resolvectl dns "$DEVICE" | grep --silent "$DNS_SERVERS"; then
  echo "OK:   ${DEVICE} DNS servers are '${DNS_SERVERS}'"
else
  echo "FAIL: ${DEVICE} DNS servers are not '${DNS_SERVERS}' (resolvectl dns ${DEVICE})"
  FAILED=yes
fi

if systemctl is-active --quiet firewalld; then
  # --query-* checks the the rules are actually in effect
  # after the reload above
  for CHECK in "interface cni0" "interface flannel.1" "source 10.42.0.0/16" "source 10.43.0.0/16"; do
    TYPE="${CHECK% *}" # e.g. "interface cni0" -> "interface"
    VALUE="${CHECK#* }" # e.g. "interface cni0" -> "cni0"
    if firewall-cmd --zone=trusted --query-"$TYPE"="$VALUE" > /dev/null 2>&1; then
      echo "OK:   trusted zone has ${TYPE} ${VALUE}"
    else
      echo "FAIL: trusted zone is missing ${TYPE} ${VALUE}"
      FAILED=yes
    fi
  done

  if firewall-cmd --query-port=6443/tcp > /dev/null 2>&1; then
    echo "OK:   port 6443/tcp (k3s apiserver) is allowed through firewalld"
  else
    echo "FAIL: port 6443/tcp (k3s apiserver) is not allowed through firewalld"
    FAILED=yes
  fi
else
  echo "SKIP: firewalld is not running - firewall checks skipped"
fi

echo ""
if [ "$FAILED" = "yes" ]; then
  echo "Host setup finished with FAILED checks - see above"
  exit 1
fi
echo "Host setup complete - all checks passed :)"
