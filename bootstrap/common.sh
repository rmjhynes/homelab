#!/bin/bash
# Shared helpers for bootstrap.sh and test_local.sh. This file is sourced, not
# executed. Sourcing scripts must define SCRIPT_DIR first and set
# TF_STATE_PATH before calling run_terraform_staged.

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

# Check that the commands passed as imputs to function are installed
check_dependencies() {
  log_info "Checking dependencies..."
  local missing=()
  local cmd

  for cmd in "$@"; do
    command -v "${cmd}" >/dev/null 2>&1 || missing+=("${cmd}")
  done

  if [ ${#missing[@]} -ne 0 ]; then
    log_error "Missing dependencies: ${missing[*]}"
    exit 1
  fi

  log_info "All dependencies found"
}

# Run the incremental Terraform bootstrap. Terraform validates
# kubernetes_manifest resources during planning, but the ArgoCD CRDs they need
# don't exist until the Helm chart is installed so there is three -target
# stages. -var flags are passed through to every apply.
run_terraform_staged() {
  log_info "Running Terraform..."

  terraform -chdir="${TERRAFORM_DIR}" init -reconfigure \
    -backend-config="path=${TF_STATE_PATH}"

  # Stage 1: Create namespace
  log_info "Stage 1/3: Creating argocd namespace..."
  terraform -chdir="${TERRAFORM_DIR}" apply "$@" \
    -target=kubernetes_namespace.argocd -auto-approve

  # Stage 2: Install ArgoCD helm chart (creates CRDs)
  log_info "Stage 2/3: Installing ArgoCD helm chart..."
  terraform -chdir="${TERRAFORM_DIR}" apply "$@" \
    -target=helm_release.argocd -auto-approve

  # Stage 3: Apply manifests (CRDs now exist)
  log_info "Stage 3/3: Applying ArgoCD project and root application manifests..."
  terraform -chdir="${TERRAFORM_DIR}" apply "$@" -auto-approve

  log_info "Terraform apply complete"
}

wait_for_argocd() {
  log_info "Waiting for ArgoCD to be ready..."

  kubectl wait --for=condition=available deployment/argocd-server \
    -n argocd --timeout=300s

  log_info "ArgoCD is ready"
}

get_argocd_password() {
  local password
  password=$(kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || true)

  echo "${password:-not yet available}"
}
