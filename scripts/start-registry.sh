#!/usr/bin/env bash
set -euo pipefail

REGISTRY_NAME="${REGISTRY_NAME:-kind-registry}"
REGISTRY_HOST="${REGISTRY_HOST:-registry.localhost}"
REGISTRY_PORT="${REGISTRY_PORT:-5001}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CERT_DIR="$ROOT_DIR/certs"

"$ROOT_DIR/scripts/ensure-registry-certs.sh"

if ! docker network inspect kind >/dev/null 2>&1; then
  docker network create kind
fi

if ! docker inspect "$REGISTRY_NAME" >/dev/null 2>&1; then
  docker run -d --restart=unless-stopped \
    --name "$REGISTRY_NAME" \
    --network kind \
    -p "127.0.0.1:${REGISTRY_PORT}:5000" \
    -v "${CERT_DIR}:/certs:ro" \
    -e REGISTRY_HTTP_ADDR=0.0.0.0:5000 \
    -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/domain.crt \
    -e REGISTRY_HTTP_TLS_KEY=/certs/domain.key \
    registry:2
fi

if ! docker network inspect kind --format '{{json .Containers}}' | grep -q "\"$REGISTRY_NAME\""; then
  docker network connect kind "$REGISTRY_NAME"
fi

echo "Local registry: https://${REGISTRY_HOST}:${REGISTRY_PORT}"
