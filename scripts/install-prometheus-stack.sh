#!/usr/bin/env bash
set -euo pipefail

RELEASE_NAME="${PROMETHEUS_RELEASE_NAME:-monitoring}"
NAMESPACE="${PROMETHEUS_NAMESPACE:-monitoring}"
ADAPTER_RELEASE_NAME="${PROMETHEUS_ADAPTER_RELEASE_NAME:-prometheus-adapter}"
PROMETHEUS_URL="${PROMETHEUS_URL:-http://${RELEASE_NAME}-kube-prometheus-prometheus.${NAMESPACE}.svc}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

command -v helm >/dev/null 2>&1 || {
  echo "helm is required to install the Prometheus stack." >&2
  exit 1
}

command -v kubectl >/dev/null 2>&1 || {
  echo "kubectl is required to install the Prometheus stack." >&2
  exit 1
}

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null
helm repo update prometheus-community

helm upgrade --install "$RELEASE_NAME" prometheus-community/kube-prometheus-stack \
  --namespace "$NAMESPACE" \
  --create-namespace \
  --values "$ROOT_DIR/k8s/kube-prometheus-stack-values.yaml" \
  --wait

helm upgrade --install "$ADAPTER_RELEASE_NAME" prometheus-community/prometheus-adapter \
  --namespace "$NAMESPACE" \
  --values "$ROOT_DIR/k8s/prometheus-adapter-values.yaml" \
  --set "prometheus.url=$PROMETHEUS_URL" \
  --set prometheus.port=9090 \
  --wait

echo "Prometheus stack is installed in namespace: $NAMESPACE"
echo "Check custom metrics with: kubectl get --raw /apis/custom.metrics.k8s.io/v1beta1"
