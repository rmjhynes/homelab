#!/usr/bin/env bash

set -o pipefail

LINK=wlo1

# Get the DNS server currently being used for the device
CURRENT="$(resolvectl status "$LINK" | awk '/Current DNS Server:/ {print $NF}')"

# Only restart systemd-resolved when resolved has failed over to the fallback
if [ "$CURRENT" != "8.8.8.8" ]; then
  exit 0
fi

# Query adguard with a non-existant random (won't be in the cache) domain to 
# force it to resolve via an upstream server.
# If it comes back with non-existant domain (NXDOMAIN) or somehow does resolve 
# with the random prefix (returns NOERROR) then restart resolved to point back
# to it (127.0.0.1), as it is resolving as needed
if dig +time=2 +tries=1 @127.0.0.1 "probe-${RANDOM}.google.com" | grep -qE 'status: (NOERROR|NXDOMAIN)'; then
  echo "resolved is on the 8.8.8.8 fallback but AdGuard is answering - restarting systemd-resolved..."
  systemctl restart systemd-resolved
fi
