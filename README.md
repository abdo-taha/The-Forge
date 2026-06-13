# Reusable Local Kubernetes Platform

This folder is the seed for a separate local platform project. It owns the machine-wide infrastructure that can be reused by Skyress and future projects:

- kind cluster
- HTTPS localhost-only Docker registry
- shared `dev` and `staging` namespaces
- namespace-scoped deployer ServiceAccounts and RBAC
- GitLab Runner setup guidance
- kubeconfig helper scripts

Application repositories should not own or recreate this cluster. They should only build images, scan them, push to `registry.localhost:5001`, and deploy their own Helm charts into namespaces provided by this platform.

## Structure

```text
local-platform/
├── gitlab-runner/
│   └── config.toml.example
├── github-actions/
│   └── local-platform-check.yml.example
├── kind/
│   └── kind-config.yaml
├── k8s/
│   ├── namespaces.yaml
│   ├── network-policies.yaml
│   ├── tenant-defaults.yaml
│   └── rbac/
├── registry/
│   └── docker-compose.registry.yml
└── scripts/
    ├── apply-platform.sh
    ├── bootstrap-kind.sh
    ├── ensure-registry-certs.sh
    ├── install-runner-kubeconfigs.sh
    ├── setup-github-runner-wsl.sh
    ├── setup-gitlab-runner-wsl.sh
    ├── start-registry.sh
    └── create-deployer-kubeconfig.sh
```

## Bootstrap

Run from WSL2 Ubuntu:

```bash
chmod +x local-platform/scripts/*.sh
local-platform/scripts/start-registry.sh
local-platform/scripts/bootstrap-kind.sh
```

This starts:

- HTTPS local registry: `registry.localhost:5001`

And creates:

- kind cluster: `local-dev`
- kube context: `kind-local-dev`
- namespaces: `dev`, `staging`
- namespace quotas and default container requests/limits
- default-deny ingress NetworkPolicies with same-namespace ingress allowed
- namespace deployer ServiceAccount: `gitlab-deployer`

The registry script creates `certs/domain.crt` and `certs/domain.key` if they do not exist. The cluster bootstrap also ensures those cert files exist before creating nodes. The kind config mounts the certificate into every node at cluster creation time, so the nodes trust the local HTTPS registry without post-creation node patching.

If you already created the old HTTP registry, recreate it once before bootstrapping:

```bash
docker stop kind-registry
docker rm kind-registry
```

If you already created the old kind cluster, recreate it once so the node trust config is applied:

```bash
kind delete cluster --name local-dev
```

Then run:

```bash
scripts/start-registry.sh
scripts/bootstrap-kind.sh
```

To push from WSL/Docker to the self-signed registry, Docker must trust the generated CA:

```bash
sudo mkdir -p /etc/docker/certs.d/registry.localhost:5001
sudo cp certs/domain.crt /etc/docker/certs.d/registry.localhost:5001/ca.crt
```

If `registry.localhost` does not resolve in WSL, add it to `/etc/hosts`:

```bash
echo "127.0.0.1 registry.localhost" | sudo tee -a /etc/hosts
```

Use image names like:

```text
registry.localhost:5001/my-app:dev
```

## Cloud-Like Workflow

Treat `kind/kind-config.yaml` like a cloud node pool or cluster bootstrap template. Changes there require recreating the kind cluster because they affect Docker node containers, port mappings, mounted files, and containerd startup config:

```bash
kind delete cluster --name local-dev
scripts/bootstrap-kind.sh
```

Treat files under `k8s/` like live platform resources. Changes there do not require cluster recreation:

```bash
scripts/apply-platform.sh
```

Use this split:

```text
kind/       node and cluster bootstrap, recreate when changed
k8s/        live Kubernetes platform resources, re-apply when changed
registry/   local registry runtime config
scripts/    repeatable platform operations
```

The local platform intentionally gives app deployers namespace-scoped permissions instead of cluster-admin. App projects should deploy with Helm or kubectl into `dev` or `staging` using images from `registry.localhost:5001`.

Note: kind's default CNI may not enforce NetworkPolicies the same way a cloud CNI does. The policies are included so your manifests follow the cloud model, but enforcement depends on the installed CNI.

## GitLab Runner

Install and configure a local WSL shell runner:

```bash
GITLAB_RUNNER_TOKEN=glrt-xxx scripts/setup-gitlab-runner-wsl.sh
```

The script:

- installs GitLab Runner if missing
- registers a shell runner tagged `local-wsl`
- adds the `gitlab-runner` user to the Docker group
- installs namespace-scoped deployer kubeconfigs for `dev` and `staging`
- installs the local registry CA for Docker
- adds `registry.localhost` to `/etc/hosts` if needed

You can customize registration:

```bash
GITLAB_URL=https://gitlab.com \
RUNNER_DESCRIPTION=local-wsl-shell \
RUNNER_TAGS=local-wsl \
GITLAB_RUNNER_TOKEN=glrt-xxx \
scripts/setup-gitlab-runner-wsl.sh
```

To install/configure the host without registering:

```bash
REGISTER_RUNNER=false scripts/setup-gitlab-runner-wsl.sh
```

Verify:

```bash
sudo -u gitlab-runner docker ps
sudo -u gitlab-runner kubectl get pods -n dev
sudo -u gitlab-runner kubectl auth can-i create deployments -n dev
sudo -u gitlab-runner kubectl auth can-i list nodes
```

## GitHub Actions Runner

Install and configure a local WSL GitHub Actions self-hosted runner:

```bash
GITHUB_RUNNER_URL=https://github.com/OWNER/REPO \
GITHUB_RUNNER_TOKEN=github-runner-token \
scripts/setup-github-runner-wsl.sh
```

Get the token from:

```text
GitHub repository -> Settings -> Actions -> Runners -> New self-hosted runner
```

The script:

- creates a dedicated `github-runner` Linux user
- downloads the GitHub Actions runner
- registers it with labels `local-wsl,docker,kubernetes`
- installs it as a service when supported by WSL
- adds the `github-runner` user to the Docker group
- installs namespace-scoped deployer kubeconfigs for `dev` and `staging`
- installs the local registry CA for Docker
- adds `registry.localhost` to `/etc/hosts` if needed

You can customize it:

```bash
GITHUB_RUNNER_URL=https://github.com/OWNER/REPO \
GITHUB_RUNNER_TOKEN=github-runner-token \
RUNNER_NAME=local-wsl-actions \
RUNNER_LABELS=local-wsl,docker,kubernetes \
scripts/setup-github-runner-wsl.sh
```

Use it in GitHub Actions:

```yaml
name: local-platform-check

on:
  push:

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

Verify:

```bash
sudo -u github-runner docker ps
sudo -u github-runner kubectl get pods -n dev
sudo -u github-runner kubectl auth can-i create deployments -n dev
sudo -u github-runner kubectl auth can-i list nodes
```

## CI Kubeconfigs

Generate namespace-scoped kubeconfigs and store them as masked, protected CI variables in each application project that needs deployment:

```bash
local-platform/scripts/create-deployer-kubeconfig.sh dev | base64 -w0
local-platform/scripts/create-deployer-kubeconfig.sh staging | base64 -w0
```

Use these variable names:

```text
KUBECONFIG_DEV_B64
KUBECONFIG_STAGING_B64
```

## What Belongs Here

- Cluster creation config
- Registry config
- Shared namespaces
- Shared deployer RBAC
- Runner setup examples
- Reusable bootstrap scripts
- Platform-level documentation

## What Does Not Belong Here

- Application Helm charts
- Application Kubernetes Secrets
- App-specific NetworkPolicies
- App-specific `.gitlab-ci.yml`
- Real kubeconfigs or runner tokens
- Registry image storage
- kind runtime data

## Docker Socket Risk

Avoid mounting `/var/run/docker.sock` into shared runners. It gives CI jobs root-equivalent control of the Docker host. For local development, prefer a locked WSL2 shell runner scoped to your own projects. If you later run the runner in Kubernetes, prefer rootless BuildKit, Kaniko, or Buildah over Docker socket mounting.
