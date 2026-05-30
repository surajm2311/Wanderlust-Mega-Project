#!/bin/bash

set -e

# Get Worker Node IP
WORKER_IP=$(kubectl get nodes -o wide | grep worker | awk '{print $6}')

if [ -z "$WORKER_IP" ]; then
    echo "ERROR: Unable to determine worker IP"
    exit 1
fi

ENV_FILE="../backend/.env.docker"

if [ ! -f "$ENV_FILE" ]; then
    echo "ERROR: $ENV_FILE not found"
    exit 1
fi

NEW_VALUE="FRONTEND_URL=\"http://${WORKER_IP}:31000\""

CURRENT_VALUE=$(grep "^FRONTEND_URL=" "$ENV_FILE" || true)

if [ "$CURRENT_VALUE" != "$NEW_VALUE" ]; then
    sed -i "s|^FRONTEND_URL=.*|${NEW_VALUE}|" "$ENV_FILE"
    echo "Updated FRONTEND_URL -> $NEW_VALUE"
else
    echo "No changes needed"
fi
