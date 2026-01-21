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

Run the bootstrap script to deploy ArgoCD to the k3s cluster:

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

## Teardown

For full cluster teardown (re-import ArgoCD to state first if needed):

```bash
terraform destroy
```
