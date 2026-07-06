#!/usr/bin/env bash

# Waits until the AdGuard pod is answering DNS on 127.0.0.1, then restarts
# systemd-resolved. Needed because resolved sticks with the last *working*
# server: during boot it fails over to the 8.8.8.8 fallback (AdGuard isn't up
# yet) and never moves back to 127.0.0.1 on its own. Run by
# adguard_dns_restore.service once per boot, after k3s.service.

set -o pipefail

# Give up after 5 minutes so the unit cannot try indefinitely
DEADLINE=300

# Poll until adguard answers DNS queries on 127.0.0.1.
# Querying port 53 directly is a stronger signal than checking the pod status:
# it proves AdGuard is actually serving, not just that the container started.
# +time=2 +tries=1: fail fast (2s timeout, single attempt) so each loop
# iteration doesn't hang while AdGuard is still down.
until dig +time=2 +tries=1 @127.0.0.1 google.com > /dev/null
do
  # $SECONDS is a bash builtin: seconds elapsed since the script started
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
