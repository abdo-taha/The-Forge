# The Forge

A reusable local Kubernetes platform for development and CI testing.

It provides:

- a kind Kubernetes cluster
- an HTTPS local Docker registry
- `dev` and `staging` namespaces
- namespace-scoped deployer RBAC
- resource quotas and default container requests/limits
- optional Prometheus monitoring stack for custom-metric autoscaling
- optional GitHub Actions and GitLab Runner setup scripts

## Requirements

- WSL2 Ubuntu
- Docker Desktop with WSL integration enabled
- `kubectl`
- `kind`
- `openssl`
- `helm`

## Project Structure

```text
.
|-- github-actions/
|   `-- local-platform-check.yml.example
|-- gitlab-runner/
|   `-- config.toml.example
|-- k8s/
|   |-- namespaces.yaml
|   |-- network-policies.yaml
|   |-- tenant-defaults.yaml
|   `-- rbac/
|-- kind/
|   `-- kind-config.yaml
|-- registry/
|   `-- docker-compose.registry.yml
`-- scripts/
    |-- apply-platform.sh
    |-- bootstrap-kind.sh
    |-- create-deployer-kubeconfig.sh
    |-- ensure-registry-certs.sh
    |-- install-prometheus-stack.sh
    |-- install-runner-kubeconfigs.sh
    |-- setup-github-runner-wsl.sh
    |-- setup-gitlab-runner-wsl.sh
    `-- start-registry.sh
```

## Quick Start

Run from WSL2 Ubuntu:

```bash
cd "/mnt/c/path/to/The Forge"
chmod +x scripts/*.sh
scripts/start-registry.sh
scripts/bootstrap-kind.sh
```

Verify:

```bash
kubectl get namespaces
kubectl get resourcequota -n dev
kubectl get limitrange -n dev
kubectl get serviceaccount gitlab-deployer -n dev
docker ps
```

Use local image names like:

```text
127.0.0.1:5001/my-app:dev
```

## Local Registry

Start the registry:

```bash
scripts/start-registry.sh
```

The registry is exposed at:

```text
https://registry.localhost:5001
```

The scripts generate local TLS files under `certs/`. These files are ignored by git.
They also copy the registry CA into `registry-certs/127.0.0.1:5001/ca.crt`
for kind. Inside the cluster, containerd resolves image pulls for
`127.0.0.1:5001/my-app:tag` through the HTTPS `kind-registry:5000` mirror
defined in `registry-certs/127.0.0.1:5001/hosts.toml`.

To make Docker trust the generated certificate:

```bash
sudo mkdir -p /etc/docker/certs.d/registry.localhost:5001
sudo cp certs/domain.crt /etc/docker/certs.d/registry.localhost:5001/ca.crt
```

If `registry.localhost` does not resolve:

```bash
echo "127.0.0.1 registry.localhost" | sudo tee -a /etc/hosts
```

Verify image push and kind pull behavior:

```bash
docker tag busybox:1.36 127.0.0.1:5001/busybox:test
docker push 127.0.0.1:5001/busybox:test
kubectl run pull-test -n dev --image=127.0.0.1:5001/busybox:test --restart=Never
```

## Cluster Bootstrap

Create or update the local platform:

```bash
scripts/bootstrap-kind.sh
```

This creates:

- kind cluster `local-dev`
- kube context `kind-local-dev`
- namespaces `dev` and `staging`
- namespace quotas and default resource settings
- basic NetworkPolicy manifests
- deployer ServiceAccounts and RBAC

If `kind/kind-config.yaml` changes, recreate the cluster:

```bash
kind delete cluster --name local-dev
scripts/bootstrap-kind.sh
```

If only files under `k8s/` change, re-apply them:

```bash
scripts/apply-platform.sh
```

## Prometheus Autoscaling Metrics

Install Prometheus, Grafana, Alertmanager, and the Prometheus Adapter:

```bash
scripts/install-prometheus-stack.sh
```

This installs:

- `kube-prometheus-stack` in the `monitoring` namespace
- `prometheus-adapter` in the `monitoring` namespace
- Custom Metrics API support for Kubernetes HPA

Verify the adapter:

```bash
kubectl get --raw /apis/custom.metrics.k8s.io/v1beta1
```

The adapter includes a sample rule that exposes pod-level
`http_requests_total` as `http_requests_per_second`. Apps need to expose
Prometheus metrics and have a `ServiceMonitor` or `PodMonitor` so Prometheus can
scrape them.

Example HPA using that metric:

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: my-app
  namespace: dev
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: my-app
  minReplicas: 1
  maxReplicas: 5
  metrics:
    - type: Pods
      pods:
        metric:
          name: http_requests_per_second
        target:
          type: AverageValue
          averageValue: "10"
```

## CI Kubeconfigs

Generate namespace-scoped kubeconfigs:

```bash
scripts/create-deployer-kubeconfig.sh dev
scripts/create-deployer-kubeconfig.sh staging
```

For CI variables:

```bash
scripts/create-deployer-kubeconfig.sh dev | base64 -w0
scripts/create-deployer-kubeconfig.sh staging | base64 -w0
```

Suggested variable names:

```text
KUBECONFIG_DEV_B64
KUBECONFIG_STAGING_B64
```

## GitHub Actions Runner

Create a self-hosted runner token in GitHub:

```text
Repository -> Settings -> Actions -> Runners -> New self-hosted runner
```

Then run:

```bash
GITHUB_RUNNER_URL=https://github.com/OWNER/REPO \
GITHUB_RUNNER_TOKEN=github-runner-token \
scripts/setup-github-runner-wsl.sh
```

The runner is registered with labels:

```text
local-wsl,docker,kubernetes
```

Example workflow:

```yaml
name: local-platform-check

on:
  workflow_dispatch:

jobs:
  check:
    runs-on: [self-hosted, local-wsl]
    steps:
      - uses: actions/checkout@v4
      - run: docker ps
      - run: kubectl get pods -n dev
      - run: kubectl auth can-i create deployments -n dev
      - run: kubectl auth can-i list nodes
```

Expected access:

```text
create deployments in dev: yes
list cluster nodes: no
```

## GitLab Runner

Create a GitLab runner token, then run:

```bash
GITLAB_RUNNER_TOKEN=glrt-xxx scripts/setup-gitlab-runner-wsl.sh
```

The runner is registered as a WSL shell runner tagged:

```text
local-wsl
```

## Security Notes

- Do not commit generated files from `certs/`.
- Do not commit kubeconfigs, tokens, `.env` files, or runner config files.
- Self-hosted runners can execute code on your machine. Use them only with trusted repositories and workflows.
- The provided runner scripts install namespace-scoped kubeconfigs instead of copying your admin kubeconfig.
