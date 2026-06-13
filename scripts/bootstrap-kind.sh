#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-local-dev}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

"$ROOT_DIR/scripts/ensure-registry-certs.sh"

if ! docker network inspect kind >/dev/null 2>&1; then
  docker network create kind
fi

if ! kind get clusters | grep -qx "$CLUSTER_NAME"; then
  (
    cd "$ROOT_DIR"
    kind create cluster --config "$ROOT_DIR/kind/kind-config.yaml"
  )
fi

"$ROOT_DIR/scripts/apply-platform.sh"

echo "Kubernetes context: kind-${CLUSTER_NAME}"
echo "Platform is ready. App projects can deploy into dev and staging."
