#!/usr/bin/env bash

set -o pipefail

# Give up after 5 minutes so the unit cannot try indefinitely
DEADLINE=300

# Poll until adguard answers DNS queries on 127.0.0.1.
# Without @, dig would ask whatever /etc/resolv.conf points at - systemd-
# resolved (127.0.0.53), which can answer from its 8.8.8.8 fallback and prove
# nothing about AdGuard. @127.0.0.1 sends the query straight to AdGuard's
# listener (port defaults to 53), so success means AdGuard itself is serving.
# +time=2 +tries=1 = 2s timeout, single attempt so each loop
# iteration doesn't hang whilst AdGuard isn't up
until dig +time=2 +tries=1 @127.0.0.1 google.com > /dev/null
do
  # $SECONDS is a bash builtin for seconds elapsed since the script started
  if [ "$SECONDS" -ge "$DEADLINE" ]; then
    echo "Adguard did not answer DNS on 127.0.0.1 within ${DEADLINE}s - giving up"
    exit 1
  fi
  echo "Adguard is not answering DNS yet - waiting for 10 seconds and will retry..."
  sleep 10
done

echo "Adguard is answering DNS - restarting systemd-resolved..."

# Restart systemd-resolved to use adguard as primary DNS again
systemctl restart systemd-resolved
