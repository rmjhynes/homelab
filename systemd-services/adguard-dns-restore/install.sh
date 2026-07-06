#!/usr/bin/env bash
set -e

# Installs adguard_dns_restore as a systemd service: symlinks the script and
# unit file out of this repo, then enables the unit so it runs on every boot.
# Idempotent - safe to re-run after moving the repo or editing the files.

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

chmod +x "${SCRIPT_DIR}/adguard_dns_restore.sh"

# -f so re-running replaces stale symlinks (e.g. if the repo moved)
ln -sf "${SCRIPT_DIR}/adguard_dns_restore.sh" /usr/local/bin/adguard_dns_restore.sh
ln -sf "${SCRIPT_DIR}/adguard_dns_restore.service" /etc/systemd/system/adguard_dns_restore.service

systemctl daemon-reload
systemctl enable adguard_dns_restore.service

echo "Installed and enabled - the service will run on the next boot."
echo "To test it now:    sudo systemctl start adguard_dns_restore.service"
echo "To check the DNS:  resolvectl status wlo1   # Current DNS Server should be 127.0.0.1"
