# Self-managed ArgoCD
In a declarative setup, ArgoCD should pull its own changes in from the Helm repo and update itself.

The App of apps pattern is used to define an app that points to this git repository to deploy _sub_ apps that point to Helm chart repositories (like kube-prometheus stack) to pull down and deploy the respective resources associated with the application.

## Bootstrap with Terraform

The `terraform/` directory contains Terraform configuration to bootstrap the homelab cluster.

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

This will:
1. Create the `argocd` namespace
2. Install ArgoCD via the [argocd helm chart](https://github.com/argoproj/argo-helm)
3. Apply the AppProject (`project.yaml`)
4. Apply the root Application (`applications.yaml`) that pulls everything from this git repository

### Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `kubeconfig_path` | Path to kubeconfig file | `/etc/rancher/k3s/k3s.yaml` |
| `argocd_chart_version` | ArgoCD Helm chart version | latest |
| `argocd_namespace` | Namespace for ArgoCD | `argocd` |

### Teardown

```bash
terraform destroy
```

## Improvements
Since there is an application that pulls down the ArgoCD helm chart in addition to the initial bootstrap install, there is currently 2 of each argocd resource. This is not ideal but works for now. In the future I will try to seperate them in different namespaces.

## Archive
The original `bootstrap.sh` script has been moved to `archive/bootstrap.sh` for reference.
