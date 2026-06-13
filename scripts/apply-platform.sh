#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

kubectl apply -f "$ROOT_DIR/k8s/namespaces.yaml"
kubectl apply -f "$ROOT_DIR/k8s/tenant-defaults.yaml"
kubectl apply -f "$ROOT_DIR/k8s/network-policies.yaml"
kubectl apply -f "$ROOT_DIR/k8s/rbac/deployer-dev.yaml"
kubectl apply -f "$ROOT_DIR/k8s/rbac/deployer-staging.yaml"
