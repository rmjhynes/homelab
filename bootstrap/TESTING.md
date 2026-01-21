# Local Testing with k3d

Any changes to the cluster can be tested locally before merging to main using k3d (k3s in a container) with the [test_local.sh script](test_local.sh).

## Kubeconfig Behavior

When `test_local.sh up` is run, k3d automatically merges the test cluster's config into `$HOME/.kube/config` and switches the current context. This means:

- The existing live Homelab cluster kubeconfig remains usable
- `kubectl` commands will target the test cluster until context is switched back to the live Homelab cluster
- When `test_local.sh down` is run, k3d removes the test cluster's entries from kubeconfig

To switch between clusters:

```bash
kubectl config get-contexts
kubectl config use-context <name>
```

## Branch Testing

The script automatically detects the current git branch and configures ArgoCD to sync from that branch. This allows testing feature branch changes before merging to main. For example, if the current feature branch is `feature/new-app`, the script will configure ArgoCD's `targetRevision` to `feature/new-app` instead of `HEAD` and pull this into the k3d container.

> [!IMPORTANT]
> The branch must be pushed to GitHub for ArgoCD to sync it.

## Prerequisites

- Docker
- k3d
- kubectl
- Terraform

## Usage

```bash
# Create test cluster and deploy ArgoCD to sync feature branch changes
bash test_local.sh up

# Check status of the cluster
bash test_local.sh status

# Teardown cluster container
bash test_local.sh down
```

The script will:
1. Check that dependencies are installed
2. Create a k3d cluster named `homelab-test`
3. Run Terraform to bootstrap ArgoCD in the container
4. Wait for ArgoCD to be ready
5. Display access info (port-forward command, credentials)

## Architecture

k3d runs a k3s cluster inside a container and exposes the API server on localhost. The Terraform Kubernetes provider reads the kubeconfig file to authenticate and connect to the cluster's API server, allowing it to provision the ArgoCD resources:

```
┌─────────────────────────────────────────────────────────────────┐
│  Homelab machine                                                │
│                                                                 │
│  ┌──────────────┐      ┌────────────────────────────────────┐   │
│  │  Terraform   │      │  k3d Container                     │   │
│  │              │      │  ┌──────────────────────────────┐  │   │
│  │  Reads       │      │  │  k3s cluster                 │  │   │
│  │  kubeconfig ─┼──────┼──▶  API server on port 6443     │  │   │
│  │              │      │  │                              │  │   │
│  └──────────────┘      │  └──────────────────────────────┘  │   │
│         │              └──────────────────▲─────────────────┘   │
│         ▼                                 │                     │
│  /tmp/homelab-test-kubeconfig             │                     │
│  (contains: server: https://localhost:XXXXX)                    │
└─────────────────────────────────────────────────────────────────┘
```
