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

After bootstrap, ArgoCD syncs and begins managing itself via `applications/argocd/`. This creates temporary duplicate resources (Terraform's install + ArgoCD's self-managed install).

To complete the handoff and let ArgoCD be the sole owner:

```bash
cd terraform
terraform state rm helm_release.argocd
```

This removes ArgoCD from Terraform's state without deleting it from the cluster. ArgoCD now fully owns itself.

### What this means

- ArgoCD config changes: Make changes in `applications/argocd/`, commit to git, ArgoCD syncs automatically
- Terraform: Only used for disaster recovery or rebuilding from scratch
- No more duplicates: ArgoCD is the single source of truth

## Local Testing with k3d

Test the bootstrap process locally before deploying to the homelab using k3d (k3s in a container).

### Prerequisites

- Docker
- k3d
- Terraform
- kubectl

### Usage

```bash
# Spin up test cluster and deploy ArgoCD
bash test-local.sh up

# Check status
bash test-local.sh status

# Cleanup
bash test-local.sh down
```

The script will:
1. Check that Docker is running
2. Create a k3d cluster named `homelab-test`
3. Run Terraform to bootstrap ArgoCD in the container
4. Wait for ArgoCD to be ready
5. Display access info (port-forward command, credentials)

### How it works

k3d runs a k3s cluster inside a container and exposes the API server on localhost. Terraform connects via a generated kubeconfig:

```
┌─────────────────────────────────────────────────────────────────┐
│  Your Machine (Host)                                            │
│                                                                 │
│  ┌──────────────┐      ┌────────────────────────────────────┐   │
│  │  Terraform   │      │  k3d Container                     │   │
│  │              │      │  ┌──────────────────────────────┐  │   │
│  │  reads       │      │  │  k3s cluster                 │  │   │
│  │  kubeconfig ─┼──────┼──▶  API server on port 6443     │  │   │
│  │              │      │  │                              │  │   │
│  └──────────────┘      │  └──────────────────────────────┘  │   │
│         │              └──────────────────▲─────────────────┘   │
│         ▼                                 │                     │
│  /tmp/homelab-test-kubeconfig             │                     │
│  (contains: server: https://localhost:XXXXX)                    │
└─────────────────────────────────────────────────────────────────┘
```

### Accessing ArgoCD

After `test-local.sh up` completes, run these commands on your local machine (not inside any container):

```bash
# Point kubectl at the test cluster
export KUBECONFIG=/tmp/homelab-test-kubeconfig

# Forward local port 8080 to ArgoCD server
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Then open https://localhost:8080 in your browser (username: `admin`, password shown in script output).

Note: `kubectl port-forward` runs locally and tunnels through the Kubernetes API - no container shell access needed.

## Teardown

For full cluster teardown (re-import ArgoCD to state first if needed):

```bash
terraform destroy
```

