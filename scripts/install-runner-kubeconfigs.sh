#!/usr/bin/env bash
set -euo pipefail

RUNNER_USER="${RUNNER_USER:-${1:-}}"
DEFAULT_NAMESPACE="${DEFAULT_NAMESPACE:-dev}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -z "$RUNNER_USER" ]]; then
  echo "Usage: RUNNER_USER=<user> scripts/install-runner-kubeconfigs.sh" >&2
  exit 1
fi

if ! id "$RUNNER_USER" >/dev/null 2>&1; then
  echo "User does not exist: $RUNNER_USER" >&2
  exit 1
fi

RUNNER_HOME="$(getent passwd "$RUNNER_USER" | cut -d: -f6)"
KUBE_DIR="$RUNNER_HOME/.kube"
DEPLOYER_DIR="$KUBE_DIR/deployer-configs"

sudo mkdir -p "$DEPLOYER_DIR"
"$ROOT_DIR/scripts/create-deployer-kubeconfig.sh" dev | sudo tee "$DEPLOYER_DIR/dev.yaml" >/dev/null
"$ROOT_DIR/scripts/create-deployer-kubeconfig.sh" staging | sudo tee "$DEPLOYER_DIR/staging.yaml" >/dev/null
sudo ln -sf "$DEPLOYER_DIR/${DEFAULT_NAMESPACE}.yaml" "$KUBE_DIR/config"
sudo chown -R "${RUNNER_USER}:${RUNNER_USER}" "$KUBE_DIR"
sudo chmod 700 "$KUBE_DIR"
sudo chmod 600 "$DEPLOYER_DIR/dev.yaml" "$DEPLOYER_DIR/staging.yaml"

echo "Installed namespace-scoped kubeconfigs for $RUNNER_USER:"
echo "  $DEPLOYER_DIR/dev.yaml"
echo "  $DEPLOYER_DIR/staging.yaml"
echo "Default kubeconfig points to: $DEFAULT_NAMESPACE"
