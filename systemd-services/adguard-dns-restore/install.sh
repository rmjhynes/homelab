#!/usr/bin/env bash
set -e

# Get the directory where this script lives, regardless of where it's called from
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "$EUID" -ne 0 ]; then
  echo "This script must be run as root (it writes to /etc and /usr/local/bin)"
  echo "Try: sudo $0"
  exit 1
fi

# The restore script needs dig to poll AdGuard
if ! command -v dig >/dev/null 2>&1; then
  echo "Missing dependency: dig"
  echo "Install it with: sudo dnf install bind-utils"
  exit 1
fi

echo "Installing AdGuard DNS restore script and systemd service..."

# Copy files and set permissions in one step with `install`
install -m 0755 "${SCRIPT_DIR}/adguard_dns_restore.sh" /usr/local/bin/adguard_dns_restore.sh
install -m 0644 "${SCRIPT_DIR}/adguard_dns_restore.service" /etc/systemd/system/adguard_dns_restore.service

systemctl daemon-reload
systemctl enable adguard_dns_restore.service

echo "Installed and enabled - the service will run on the next boot"
echo "If DNS is currently stuck on the 8.8.8.8 fallback, run it now:"
echo "  sudo systemctl start adguard_dns_restore.service"
echo "Check DNS with:  resolvectl status wlo1   # Current DNS Server should be 127.0.0.1"
