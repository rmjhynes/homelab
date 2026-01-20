#!/bin/bash
set -e

# Get the directory where this script lives, regardless of where it's called from
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/terraform"

# Colours for output
RED='\033[0;31m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Colour

# Render log text with specific colour depending on log type
log_info() { echo -e "${CYAN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

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

check_dependencies() {
  log_info "Checking dependencies..."
  local missing=()

  command -v terraform >/dev/null 2>&1 || missing+=("terraform")
  command -v kubectl >/dev/null 2>&1 || missing+=("kubectl")

  if [ ${#missing[@]} -ne 0 ]; then
    log_error "Missing dependencies: ${missing[*]}"
    exit 1
  fi

  log_info "All dependencies found"
}

run_terraform() {
  log_info "Running Terraform..."

  terraform -chdir="${TERRAFORM_DIR}" init

  # Stage 1: Create namespace
  log_info "Stage 1/3: Creating argocd namespace..."
  terraform -chdir="${TERRAFORM_DIR}" apply \
    -target=kubernetes_namespace.argocd \
    -auto-approve

  # Stage 2: Install ArgoCD helm chart (creates CRDs)
  log_info "Stage 2/3: Installing ArgoCD helm chart..."
  terraform -chdir="${TERRAFORM_DIR}" apply \
    -target=helm_release.argocd \
    -auto-approve

  # Stage 3: Apply manifests (CRDs now exist)
  log_info "Stage 3/3: Applying ArgoCD project and root application manifests..."
  terraform -chdir="${TERRAFORM_DIR}" apply \
    -auto-approve

  log_info "Terraform apply complete"
}

show_access_info() {
  log_info "Getting ArgoCD admin password..."
  local password
  password=$(kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "not yet available")

  echo ""
  echo "========================================"
  echo "  ArgoCD Access Info"
  echo "========================================"
  echo "  URL:          https://argocd.homelab"
  echo "  Username:     admin"
  echo "  Password:     ${password}"
  echo "========================================"
  echo ""
  log_info "Bootstrap complete. ArgoCD will now sync applications from git."
}

wait_for_argocd() {
  log_info "Waiting for ArgoCD to be ready..."

  kubectl wait --for=condition=available deployment/argocd-server \
    -n argocd --timeout=300s

  log_info "ArgoCD is ready"
}

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
    check_dependencies
    check_cluster
    run_terraform
    wait_for_argocd
    show_access_info
    ;;
  *)
    log_error "Unknown argument: $1"
    print_usage
    exit 1
    ;;
esac
