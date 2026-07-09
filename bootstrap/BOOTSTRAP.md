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

## Step 2: Handoff to ArgoCD (automated)

After the staged apply, ArgoCD syncs and begins managing itself via [the argocd application manifest](../applications/argocd/application.yaml). At that point the install has two owners: Terraform's state and the self-managed argocd Application. To complete the handoff and make ArgoCD the sole owner, the script removes the Helm release from Terraform's state without deleting it from the cluster:

```bash
terraform state rm helm_release.argocd
```

`bootstrap.sh` runs this itself, but only after verifying that the argocd Application is synced and healthy.

If the sync fails or times out, the script exits **before** the `terraform state rm`, leaving ArgoCD in Terraform's state. From there you can fix the issue and re-run `bootstrap.sh` or teardown with `terraform destroy`.

> [!IMPORTANT]
> Don't re-run `bootstrap.sh` after a successful handoff - the Helm release still exists in the cluster but is no longer in Terraform's state, so the apply would fail. The script detects this and exits early with an explanation.

## Accessing ArgoCD

The `https://argocd.homelab` URL printed by the script requires the argocd application's ingress (created on its first sync) and Pi-hole DNS resolving `*.homelab`. Until both are in place, port-forward instead:

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:80
```

Then browse to `http://localhost:8080` (plain HTTP — the server runs in insecure mode because Traefik terminates TLS at the ingress).

## Teardown

For full cluster teardown, re-import ArgoCD to state first (as it was removed during the handoff), then destroy:

```bash
cd terraform
terraform import -var="kubeconfig_path=$HOME/.kube/config" helm_release.argocd argocd/argocd
terraform destroy -var="kubeconfig_path=$HOME/.kube/config"
```

The `kubeconfig_path` variable has no default, so pass it explicitly (or answer the prompt) when running Terraform outside the bootstrap script.
