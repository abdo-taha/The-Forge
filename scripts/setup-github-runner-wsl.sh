#!/usr/bin/env bash
set -euo pipefail

GITHUB_RUNNER_URL="${GITHUB_RUNNER_URL:-}"
GITHUB_RUNNER_TOKEN="${GITHUB_RUNNER_TOKEN:-}"
GITHUB_RUNNER_VERSION="${GITHUB_RUNNER_VERSION:-2.335.1}"
RUNNER_NAME="${RUNNER_NAME:-local-wsl-actions}"
RUNNER_LABELS="${RUNNER_LABELS:-local-wsl,docker,kubernetes}"
RUNNER_USER="${RUNNER_USER:-github-runner}"
RUNNER_HOME="${RUNNER_HOME:-/home/${RUNNER_USER}}"
RUNNER_DIR="${RUNNER_DIR:-${RUNNER_HOME}/actions-runner}"
DEFAULT_NAMESPACE="${DEFAULT_NAMESPACE:-dev}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REGISTRY_CERT="$ROOT_DIR/certs/domain.crt"
RUNNER_ARCHIVE="actions-runner-linux-x64-${GITHUB_RUNNER_VERSION}.tar.gz"
RUNNER_DOWNLOAD_URL="https://github.com/actions/runner/releases/download/v${GITHUB_RUNNER_VERSION}/${RUNNER_ARCHIVE}"

if [[ -z "$GITHUB_RUNNER_URL" || -z "$GITHUB_RUNNER_TOKEN" ]]; then
  echo "Set GITHUB_RUNNER_URL and GITHUB_RUNNER_TOKEN before running this script." >&2
  echo "Example:" >&2
  echo "  GITHUB_RUNNER_URL=https://github.com/OWNER/REPO GITHUB_RUNNER_TOKEN=xxx scripts/setup-github-runner-wsl.sh" >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1 || ! command -v tar >/dev/null 2>&1; then
  sudo apt update
  sudo apt install -y curl tar
fi

if ! id "$RUNNER_USER" >/dev/null 2>&1; then
  sudo useradd --create-home --shell /bin/bash "$RUNNER_USER"
fi

if getent group docker >/dev/null 2>&1; then
  sudo usermod -aG docker "$RUNNER_USER"
else
  echo "Docker group does not exist. Install/start Docker Desktop WSL integration first." >&2
  exit 1
fi

sudo mkdir -p "$RUNNER_DIR"
sudo chown -R "${RUNNER_USER}:${RUNNER_USER}" "$RUNNER_HOME"

if [[ ! -f "$RUNNER_DIR/config.sh" ]]; then
  curl -L "$RUNNER_DOWNLOAD_URL" -o "/tmp/${RUNNER_ARCHIVE}"
  sudo -u "$RUNNER_USER" tar xzf "/tmp/${RUNNER_ARCHIVE}" -C "$RUNNER_DIR"
fi

if [[ -f "$REGISTRY_CERT" ]]; then
  sudo mkdir -p /etc/docker/certs.d/registry.localhost:5001
  sudo cp "$REGISTRY_CERT" /etc/docker/certs.d/registry.localhost:5001/ca.crt
else
  echo "No registry cert found at $REGISTRY_CERT. Run scripts/ensure-registry-certs.sh first." >&2
  exit 1
fi

if ! grep -qE '(^|\s)registry\.localhost($|\s)' /etc/hosts; then
  echo "127.0.0.1 registry.localhost" | sudo tee -a /etc/hosts >/dev/null
fi

DEFAULT_NAMESPACE="$DEFAULT_NAMESPACE" "$ROOT_DIR/scripts/install-runner-kubeconfigs.sh" "$RUNNER_USER"

if [[ ! -f "$RUNNER_DIR/.runner" ]]; then
  sudo -u "$RUNNER_USER" bash -lc "cd '$RUNNER_DIR' && ./config.sh --unattended --replace --url '$GITHUB_RUNNER_URL' --token '$GITHUB_RUNNER_TOKEN' --name '$RUNNER_NAME' --labels '$RUNNER_LABELS'"
fi

if [[ -x "$RUNNER_DIR/svc.sh" ]]; then
  (
    cd "$RUNNER_DIR"
    sudo ./svc.sh install "$RUNNER_USER"
    sudo ./svc.sh start
  )
else
  echo "Could not find svc.sh. Start the runner manually with:" >&2
  echo "  sudo -u ${RUNNER_USER} bash -lc 'cd ${RUNNER_DIR} && ./run.sh'" >&2
fi

echo "GitHub Actions runner is installed and configured."
echo "Runner name: ${RUNNER_NAME}"
echo "Runner labels: ${RUNNER_LABELS}"
echo "Verify with:"
echo "  sudo -u ${RUNNER_USER} docker ps"
echo "  sudo -u ${RUNNER_USER} kubectl get pods -n dev"
echo "  sudo -u ${RUNNER_USER} kubectl auth can-i create deployments -n dev"
echo "  sudo -u ${RUNNER_USER} kubectl auth can-i list nodes"
