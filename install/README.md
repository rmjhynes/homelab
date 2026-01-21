# Self-managed ArgoCD

In a declarative setup, ArgoCD should pull its own changes in from the Helm repo and update itself.

The App of apps pattern is used to define an app that points to this git repository to deploy _sub_ apps that point to Helm chart repositories (like kube-prometheus stack) to pull down and deploy the respective resources associated with the application.

## Bootstrap Workflow

```
┌─────────────────┐         ┌──────────────────────────────────────┐
│   Terraform     │         │              ArgoCD                  │
│   (run ONCE)    │────────▶│  - Manages itself via applications/  │
│                 │         │  - Manages all other applications    │
└─────────────────┘         └──────────────────────────────────────┘
     Bootstrap                    Self-managing (GitOps)
```

Terraform is used **once** for initial cluster bootstrap. After that, ArgoCD takes over and manages everything declaratively via git, including itself.

## Step 1: Bootstrap with Terraform

Run the bootstrap script to deploy ArgoCD to your k3s cluster:

```bash
./bootstrap.sh
```

The script checks dependencies, verifies cluster connectivity, then runs Terraform incrementally.

### Why the incremental apply?

Terraform validates all resources during the planning phase before creating anything. The `kubernetes_manifest` resources for ArgoCD's AppProject and Application require the ArgoCD CRDs to exist for validation to succeed. This creates a chicken-and-egg problem:

1. Terraform wants to validate `kubernetes_manifest.argocd_project` and `kubernetes_manifest.argocd_applications`
2. These reference ArgoCD CRDs (AppProject, Application) that don't exist yet
3. The CRDs only get created when `helm_release.argocd` is applied
4. But Terraform validates everything before applying anything

The script handles this by running Terraform in three stages:
1. First apply: Create the namespace
2. Second apply: Install ArgoCD via Helm (which creates the CRDs)
3. Third apply: Now that CRDs exist, Terraform can validate and apply the remaining resources

## Step 2: Handoff to ArgoCD

After bootstrap, ArgoCD syncs and begins managing itself via [the argocd application manifest](../applications/argocd/application.yaml), there are duplicate ArgoCD resources (Terraform's install + ArgoCD's self-managed install). To complete the handoff and let ArgoCD be the sole owner:

```bash
cd terraform
terraform state rm helm_release.argocd
```

This removes ArgoCD from Terraform's state without deleting it from the cluster so that ArgoCD now fully manages itself.

## Local Testing with k3d

Any changes to the cluster can be tested locally before merging to main using k3d (k3s in a container) with the [test_local.sh script](test_local.sh).

### Kubeconfig Behavior

When `test_local.sh up` is run, k3d automatically merges the test cluster's config into `$HOME/.kube/config` and switches the current context. This means:

- The existing cluster configs (live k3s cluster) remain intact
- `kubectl` commands will target the test cluster until context is switched back to the live Homelab cluster
- When `test_local.sh down` is run, k3d removes the test cluster's entries from kubeconfig

To switch between clusters:

```bash
kubectl config get-contexts
kubectl config use-context <name>
```

### Branch Testing

The script automatically detects the current git branch and configures ArgoCD to sync from that branch. This allows testing feature branch changes before merging to main. For example, if the current feature branch is `feature/new-app`, the script will configure ArgoCD's `targetRevision` to `feature/new-app` instead of `HEAD` and pull this into the k3d container.

> [!IMPORTANT]
> The branch must be pushed to GitHub for ArgoCD to sync it.

### Prerequisites

- Docker
- k3d
- kubectl
- Terraform

### Usage

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

### Architecture

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

## Teardown

For full cluster teardown (re-import ArgoCD to state first if needed):

```bash
terraform destroy
```
