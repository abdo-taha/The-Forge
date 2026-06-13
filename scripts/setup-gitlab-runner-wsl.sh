#!/usr/bin/env bash
set -euo pipefail

GITLAB_URL="${GITLAB_URL:-https://gitlab.com}"
RUNNER_DESCRIPTION="${RUNNER_DESCRIPTION:-local-wsl-shell}"
RUNNER_TAGS="${RUNNER_TAGS:-local-wsl}"
RUNNER_USER="${RUNNER_USER:-gitlab-runner}"
REGISTER_RUNNER="${REGISTER_RUNNER:-true}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REGISTRY_CERT="$ROOT_DIR/certs/domain.crt"

if ! command -v curl >/dev/null 2>&1; then
  sudo apt update
  sudo apt install -y curl
fi

if ! command -v gitlab-runner >/dev/null 2>&1; then
  curl -L "https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh" -o /tmp/gitlab-runner-script.deb.sh
  sudo bash /tmp/gitlab-runner-script.deb.sh
  sudo apt install -y gitlab-runner
fi

if getent group docker >/dev/null 2>&1; then
  sudo usermod -aG docker "$RUNNER_USER"
else
  echo "Docker group does not exist. Install/start Docker Desktop WSL integration first." >&2
  exit 1
fi

"$ROOT_DIR/scripts/install-runner-kubeconfigs.sh" "$RUNNER_USER"

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

if [[ "$REGISTER_RUNNER" == "true" ]]; then
  if [[ -z "${GITLAB_RUNNER_TOKEN:-}" ]]; then
    echo "Set GITLAB_RUNNER_TOKEN before running this script, or run with REGISTER_RUNNER=false." >&2
    echo "Example:" >&2
    echo "  GITLAB_RUNNER_TOKEN=glrt-xxx scripts/setup-gitlab-runner-wsl.sh" >&2
    exit 1
  fi

  sudo gitlab-runner register \
    --non-interactive \
    --url "$GITLAB_URL" \
    --token "$GITLAB_RUNNER_TOKEN" \
    --executor "shell" \
    --description "$RUNNER_DESCRIPTION" \
    --tag-list "$RUNNER_TAGS" \
    --run-untagged="false" \
    --locked="true" \
    --access-level="ref_protected"
fi

if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files gitlab-runner.service >/dev/null 2>&1; then
  sudo systemctl restart gitlab-runner
elif command -v service >/dev/null 2>&1; then
  sudo service gitlab-runner restart
else
  echo "Could not restart gitlab-runner automatically. Start it with: sudo gitlab-runner run" >&2
fi

echo "GitLab Runner is installed and configured for WSL shell execution."
echo "Runner tag: ${RUNNER_TAGS}"
echo "Verify with:"
echo "  sudo -u ${RUNNER_USER} docker ps"
echo "  sudo -u ${RUNNER_USER} kubectl get pods -n dev"
echo "  sudo -u ${RUNNER_USER} kubectl auth can-i create deployments -n dev"
echo "  sudo -u ${RUNNER_USER} kubectl auth can-i list nodes"
