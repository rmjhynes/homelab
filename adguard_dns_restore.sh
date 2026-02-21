#!/bin/bash

ADGUARD_STATUS=$(kubectl get pod | grep adguard | awk '{print $3}')

RUNNING=false

until [ $RUNNING == true ]
do
  if [ $ADGUARD_STATUS == 'Running' ]; then
    $RUNNING = true
    echo "Adguard pod is running - exiting..."
    exit
  else
    echo "Adguard pod is $ADGUARD_STATUS - waiting for 10 seconds and will retry..."
    sleep 10
  fi
done
