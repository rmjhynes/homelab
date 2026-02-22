#!/usr/bin/env bash

set -o pipefail

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Poll until adguard service is in 'Running' state
RUNNING=false
until [ $RUNNING == true ]
do
  ADGUARD_STATUS=$(kubectl get pod | grep adguard | awk '{print $3}' || true)
  if [ "$ADGUARD_STATUS" == 'Running' ]; then
    RUNNING=true
    echo "Adguard pod is running - restarting systemd-resolved..."
  else
    echo "Adguard pod is $ADGUARD_STATUS - waiting for 10 seconds and will retry..."
    sleep 10
  fi
done

# Restart systemd-resolved to use adguard as primary DNS again
systemctl restart systemd-resolved

