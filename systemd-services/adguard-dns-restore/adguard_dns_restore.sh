#!/usr/bin/env bash

set -o pipefail

# Give up after 5 minutes so the unit cannot try indefinitely
DEADLINE=300

# Poll until adguard answers DNS queries on 127.0.0.1.
# Querying port 53 directly is a stronger signal than checking the pod status
# as it proves AdGuard is actually serving.
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
