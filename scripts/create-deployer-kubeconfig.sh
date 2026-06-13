#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${1:-dev}"
SERVICE_ACCOUNT="${SERVICE_ACCOUNT:-gitlab-deployer}"
CLUSTER_CONTEXT="${CLUSTER_CONTEXT:-kind-local-dev}"
CLUSTER_NAME="${CLUSTER_NAME:-kind-local-dev}"
USER_NAME="${SERVICE_ACCOUNT}-${NAMESPACE}"

TOKEN="$(kubectl -n "$NAMESPACE" create token "$SERVICE_ACCOUNT" --duration=8760h)"
SERVER="$(kubectl config view -o jsonpath="{.clusters[?(@.name==\"$CLUSTER_NAME\")].cluster.server}")"
CA_DATA="$(kubectl config view --raw -o jsonpath="{.clusters[?(@.name==\"$CLUSTER_NAME\")].cluster.certificate-authority-data}")"

cat <<EOF
apiVersion: v1
kind: Config
clusters:
- name: ${CLUSTER_NAME}
  cluster:
    certificate-authority-data: ${CA_DATA}
    server: ${SERVER} 
contexts:
- name: ${CLUSTER_CONTEXT}
  context:
    cluster: ${CLUSTER_NAME}
    namespace: ${NAMESPACE}
    user: ${USER_NAME}
current-context: ${CLUSTER_CONTEXT}
users:
- name: ${USER_NAME}
  user:
    token: ${TOKEN}
EOF
