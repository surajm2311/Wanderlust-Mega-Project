#!/bin/bash

set -e

# Get Worker Node IP
WORKER_IP=$(kubectl get nodes -o wide | grep worker | awk '{print $6}')

if [ -z "$WORKER_IP" ]; then
    echo "ERROR: Unable to determine worker IP"
    exit 1
fi

ENV_FILE="../frontend/.env.docker"

if [ ! -f "$ENV_FILE" ]; then
    echo "ERROR: $ENV_FILE not found"
    exit 1
fi

NEW_VALUE="VITE_API_PATH=\"http://${WORKER_IP}:31100\""

CURRENT_VALUE=$(grep "^VITE_API_PATH=" "$ENV_FILE" || true)

if [ "$CURRENT_VALUE" != "$NEW_VALUE" ]; then
    sed -i "s|^VITE_API_PATH=.*|${NEW_VALUE}|" "$ENV_FILE"
    echo "Updated VITE_API_PATH -> $NEW_VALUE"
else
    echo "No changes needed"
fi
