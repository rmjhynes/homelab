#!/bin/bash
set -euo pipefail

# Get the directory where this script lives, regardless of where it's called from
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# Set to $KUBE_CONFIG env var value or if empty default to $HOME/.kube/config
KUBECONFIG_PATH="${KUBECONFIG:-$HOME/.kube/config}"
export KUBECONFIG="${KUBECONFIG_PATH}"

TF_STATE_PATH="${TERRAFORM_DIR}/terraform.tfstate"

# kubectl accepts a colon-separated list of kubeconfig files that it merges
# (e.g. KUBECONFIG="$HOME/.kube/config:$HOME/.kube/test_cluster"), but
# the Terraform k8s provider config_path takes a single file.
# This function fails early with a clear message instead of passing a multi-path
# value that the provider can't use.
check_kubeconfig() {
  case "${KUBECONFIG_PATH}" in
    *:*)
      log_error "KUBECONFIG contains multiple paths: ${KUBECONFIG_PATH}"
      log_error "The terraform k8s provider can only read a single kubeconfig file - set KUBECONFIG to one file path"
      exit 1
      ;;
  esac
}

check_cluster() {
  log_info "Checking k3s cluster connectivity..."

  if ! kubectl cluster-info >/dev/null 2>&1; then
    log_error "Cannot connect to Kubernetes cluster"
    log_error "Ensure k3s is running and KUBECONFIG is set correctly"
    log_error "Default k3s kubeconfig: /etc/rancher/k3s/k3s.yaml"
    exit 1
  fi

  log_info "Cluster is reachable"
}

# After the handoff to ArgoCD (terraform state rm helm_release.argocd), a
# re-run would fail mid-apply with Helm's "cannot re-use a name that is still
# in use" error. This function exits in case of a re-run.
check_not_bootstrapped() {
  if kubectl -n argocd get deployment argocd-server >/dev/null 2>&1 \
    && ! terraform -chdir="${TERRAFORM_DIR}" state list 2>/dev/null \
      | grep -q '^helm_release\.argocd$'; then
    log_error "ArgoCD is already running but is not in Terraform's state:"
    log_error "this cluster has been bootstrapped and handed off to ArgoCD"
    log_error "(see BOOTSTRAP.md Step 2). Re-running bootstrap would conflict"
    log_error "with the existing install."
    exit 1
  fi
}

# The root app's first sync creates the argocd app, which ArgoCD then syncs
# automatically.
# This function checks the argocd app is synced and healthy, before the argocd
# helm chart can be removed from the Terraform state.
wait_for_self_management() {
  log_info "Waiting for the argocd Application to be created, synced and healthy..."

  if kubectl -n argocd wait application/argocd --for=create --timeout=300s \
    && kubectl -n argocd wait application/argocd \
      --for=jsonpath='{.status.sync.status}'=Synced --timeout=300s \
    && kubectl -n argocd wait application/argocd \
      --for=jsonpath='{.status.health.status}'=Healthy --timeout=300s; then

    log_info "ArgoCD is self-managing"
  else
    log_error "The argocd Application was not created or did not become Synced and Healthy"
    log_error "ArgoCD is still in Terraform's state: fix the sync issue"
    log_error "and re-run this script, or teardown with 'terraform destroy'"
    exit 1
  fi
}

# Remove the Helm release from Terraform state without deleting it from the
# cluster, so ArgoCD fully manages itself.
# Any earlier script exits keep helm_release.argocd still in the state so that
# `terraform destroy` can still be used afor cluster teardown.
handoff_to_argocd() {
  log_info "Removing helm_release.argocd from Terraform state..."
  terraform -chdir="${TERRAFORM_DIR}" state rm helm_release.argocd
  log_info "Handoff complete: ArgoCD now fully manages itself"
}

show_access_info() {
  log_info "Getting ArgoCD admin password..."
  local password
  password=$(get_argocd_password)

  echo ""
  echo "========================================"
  echo "  ArgoCD Access Info"
  echo "========================================"
  echo "  URL:          https://argocd.homelab"
  echo "  Username:     admin"
  echo "  Password:     ${password}"
  echo ""
  echo "  The URL needs the argocd application's ingress (created on its"
  echo "  first sync) and Pi-hole DNS for *.homelab. Until then:"
  echo "  kubectl port-forward svc/argocd-server -n argocd 8080:80"
  echo "  then browse to http://localhost:8080"
  echo "========================================"
  echo ""
  log_info "Bootstrap complete. ArgoCD will now sync applications from git."
}

# If unknown argument is passed at script runtime, print out how the script can
# be run with a description of its purpose.
print_usage() {
  echo "Usage: $0"
  echo ""
  echo "Bootstraps the homelab cluster with ArgoCD."
  echo "Requires k3s to be running and kubectl configured."
  echo ""
}

# Script entrypoint
case "${1:-}" in
  -h|--help)
    print_usage
    ;;
  "")
    check_dependencies terraform kubectl
    check_kubeconfig
    check_cluster
    check_not_bootstrapped
    run_terraform_staged -var="kubeconfig_path=${KUBECONFIG_PATH}"
    wait_for_argocd
    wait_for_self_management
    handoff_to_argocd
    show_access_info
    ;;
  *)
    log_error "Unknown argument: $1"
    print_usage
    exit 1
    ;;
esac
