#!/bin/bash
set -e

# Get the directory where this script lives, regardless of where it's called from
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/terraform"

CLUSTER_NAME="homelab-test"
KUBECONFIG_PATH="/tmp/${CLUSTER_NAME}-kubeconfig"
TARGET_REVISION=$(git branch --show-current)

# Colours for output
RED='\033[0;31m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Colour

# Render log text with specific colour depending on log type
log_info() { echo -e "${CYAN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

check_dependencies() {
  log_info "Checking dependencies..."
  local missing=()

  command -v k3d >/dev/null 2>&1 || missing+=("k3d")
  command -v terraform >/dev/null 2>&1 || missing+=("terraform")
  command -v kubectl >/dev/null 2>&1 || missing+=("kubectl")
  command -v docker >/dev/null 2>&1 || missing+=("docker")

  if [ ${#missing[@]} -ne 0 ]; then
    log_error "Missing dependencies: ${missing[*]}"
    exit 1
  fi

  if ! docker info >/dev/null 2>&1; then
    log_error "Docker is not running"
    exit 1
  fi

  log_info "All dependencies found"
}

cleanup() {
  log_info "Cleaning up..."
  if k3d cluster list 2>/dev/null | grep -q "${CLUSTER_NAME}"; then
    k3d cluster delete "${CLUSTER_NAME}"
  fi

  rm -f "${KUBECONFIG_PATH}"
  rm -rf "${TERRAFORM_DIR}/.terraform" \
    "${TERRAFORM_DIR}/terraform.tfstate" \
    "${TERRAFORM_DIR}/terraform.tfstate.backup"

  log_info "Cleanup complete"
  log_warn "Remember to switch kubectl context back to the live cluster:"
  echo "  kubectl config use-context <live-cluster-context>"
}

create_cluster() {
  log_info "Creating k3d cluster '${CLUSTER_NAME}'..."

  if k3d cluster list 2>/dev/null | grep -q "${CLUSTER_NAME}"; then
    log_warn "Cluster '${CLUSTER_NAME}' already exists, deleting..."
    k3d cluster delete "${CLUSTER_NAME}"
  fi

  k3d cluster create "${CLUSTER_NAME}" --wait

  k3d kubeconfig get "${CLUSTER_NAME}" > "${KUBECONFIG_PATH}"
  export KUBECONFIG="${KUBECONFIG_PATH}"

  log_info "Waiting for cluster to be ready..."
  kubectl wait --for=condition=Ready nodes --all --timeout=120s
  log_info "Cluster ready"
}

run_terraform() {
  log_info "Running Terraform..."
  log_info "Target revision: ${TARGET_REVISION}"

  terraform -chdir="${TERRAFORM_DIR}" init

  # Stage 1: Create namespace
  log_info "Stage 1/3: Creating argocd namespace..."
  terraform -chdir="${TERRAFORM_DIR}" apply \
    -var="kubeconfig_path=${KUBECONFIG_PATH}" \
    -var="target_revision=${TARGET_REVISION}" \
    -target=kubernetes_namespace.argocd \
    -auto-approve

  # Stage 2: Install ArgoCD helm chart (creates CRDs)
  log_info "Stage 2/3: Installing ArgoCD helm chart..."
  terraform -chdir="${TERRAFORM_DIR}" apply \
    -var="kubeconfig_path=${KUBECONFIG_PATH}" \
    -var="target_revision=${TARGET_REVISION}" \
    -target=helm_release.argocd \
    -auto-approve

  # Stage 3: Apply manifests (CRDs now exist)
  log_info "Stage 3/3: Applying ArgoCD project and root application maniftests ..."
  terraform -chdir="${TERRAFORM_DIR}" apply \
    -var="kubeconfig_path=${KUBECONFIG_PATH}" \
    -var="target_revision=${TARGET_REVISION}" \
    -auto-approve

  log_info "Terraform apply complete"
}

show_access_info() {
  export KUBECONFIG="${KUBECONFIG_PATH}"

  local password
  password=$(kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "not yet available")

  echo ""
  echo "========================================"
  echo "  ArgoCD Access Info"
  echo "========================================"
  echo "  Port forward: kubectl port-forward svc/argocd-server -n argocd 8080:443"
  echo "  URL:          https://localhost:8080"
  echo "  Username:     admin"
  echo "  Password:     ${password}"
  echo ""
  echo "  To use kubectl with this cluster:"
  echo "  export KUBECONFIG=${KUBECONFIG_PATH}"
  echo ""
  echo "  NOTE: The kubectl context has been switched to the test cluster."
  echo "  To switch back to the live cluster:"
  echo "  kubectl config use-context <live-cluster-context>"
  echo "========================================"
}

wait_for_argocd() {
  log_info "Waiting for ArgoCD to be ready..."
  export KUBECONFIG="${KUBECONFIG_PATH}"

  kubectl wait --for=condition=available deployment/argocd-server \
    -n argocd --timeout=300s

  log_info "ArgoCD is ready"
}

cmd_status() {
  if ! k3d cluster list 2>/dev/null | grep -q "${CLUSTER_NAME}"; then
    log_warn "Cluster '${CLUSTER_NAME}' does not exist"
    exit 0
  fi

  export KUBECONFIG="${KUBECONFIG_PATH}"
  echo ""
  log_info "Cluster status:"
  k3d cluster list | grep "${CLUSTER_NAME}"
  echo ""
  log_info "ArgoCD pods:"
  kubectl get pods -n argocd 2>/dev/null || echo "ArgoCD namespace not found"
  echo ""
  log_info "ArgoCD applications:"
  kubectl get applications -n argocd 2>/dev/null || echo "No applications found"
}

cmd_up() {
  check_dependencies
  create_cluster
  run_terraform
  wait_for_argocd
  show_access_info
  log_info "Test environment ready. Run '$0 down' to cleanup."
}

print_usage() {
  echo "Usage: $0 [command]"
  echo ""
  echo "Commands:"
  echo "  up       Create cluster and deploy ArgoCD (default)"
  echo "  down     Delete cluster and cleanup"
  echo "  status   Show cluster and ArgoCD status"
  echo ""
}

# Script entrypoint
# Use first argument or default to "up" if not provided
case "${1:-up}" in
  up)
    cmd_up
    ;;
  down)
    cleanup
    ;;
  status)
    cmd_status
    ;;
  -h|--help)
    print_usage
    ;;
  *)
    log_error "Unknown command: $1"
    print_usage
    exit 1
    ;;
esac
