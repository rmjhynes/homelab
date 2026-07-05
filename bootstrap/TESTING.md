# Local Testing with k3d

Any changes to the cluster can be tested locally before merging to main using k3d (k3s in a container) with the [test_local.sh script](test_local.sh).

## Kubeconfig Behavior

The test cluster is fully isolated from `$HOME/.kube/config`. When `test_local.sh up` is run, the test cluster's kubeconfig is written only to `/tmp/homelab-test-kubeconfig`, so the current kubectl context always continues pointing at the live Homelab cluster.

To run kubectl commands against the test cluster, define an alias (add it to `~/.zshrc` to make it permanent):

```bash
alias kt='kubectl --kubeconfig /tmp/homelab-test-kubeconfig'
```

Then `kt` targets the test cluster (e.g. `kt get pods -n argocd`) while plain `kubectl` continues to target the live cluster — no context switching needed. Alternatively, `export KUBECONFIG=/tmp/homelab-test-kubeconfig` points kubectl at the test cluster for the current shell only. Running `test_local.sh down` deletes the test kubeconfig along with the cluster.

## Terraform State

Test runs never touch the Terraform state in `terraform/` (which may hold the live cluster's bootstrap state). All Terraform artifacts for a test run are written to `/tmp` (`homelab-test.tfstate` and the `homelab-test-tfdata` provider directory) and removed by `test_local.sh down`.

## Branch Testing

The script automatically detects the current git branch and configures ArgoCD to sync from that branch. This allows testing feature branch changes before merging to main. Two things happen when the current branch is not `main`:

1. Terraform sets the root Application's `targetRevision` to the branch, so the Application definitions in `applications/` are read from the branch.
2. After ArgoCD syncs, the script patches every child Application source that points at this repo with `targetRevision: HEAD` (which ArgoCD would otherwise resolve to `main`) to sync from the branch instead. Pinned Helm chart versions and external repos are left untouched, so changes to `manifests/` and Helm values on the branch are actually deployed.

To keep these patches from being reverted, the root Application is deployed with `selfHeal` disabled in test clusters (the live bootstrap keeps `selfHeal: true`).

> [!IMPORTANT]
> The branch must be pushed to GitHub for ArgoCD to sync it. The script warns if the current branch does not exist on `origin`.

## Prerequisites

- Docker
- k3d
- kubectl
- Terraform
- jq

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
2. Detect the current git branch (and warn if it isn't pushed)
3. Create a k3d cluster named `homelab-test`
4. Run Terraform to bootstrap ArgoCD in the container
5. Wait for ArgoCD to be ready
6. Patch child Applications to sync from the current branch
7. Display access info (port-forward command, credentials)

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
