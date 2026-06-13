#!/usr/bin/env bash
set -euo pipefail

REGISTRY_NAME="${REGISTRY_NAME:-kind-registry}"
REGISTRY_HOST="${REGISTRY_HOST:-registry.localhost}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CERT_DIR="$ROOT_DIR/certs"
CERT_FILE="$CERT_DIR/domain.crt"
KEY_FILE="$CERT_DIR/domain.key"

mkdir -p "$CERT_DIR"

if [[ ! -f "$CERT_FILE" || ! -f "$KEY_FILE" ]]; then
  openssl req -newkey rsa:4096 -nodes -sha256 \
    -keyout "$KEY_FILE" \
    -x509 -days 365 \
    -out "$CERT_FILE" \
    -subj "/CN=${REGISTRY_HOST}" \
    -addext "subjectAltName=DNS:${REGISTRY_HOST},DNS:${REGISTRY_NAME},DNS:localhost,IP:127.0.0.1"
fi
