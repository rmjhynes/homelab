#!/bin/bash
set -euo pipefail

# Get the directory where this script lives, regardless of where it's called from
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

CLUSTER_NAME="homelab-test"
KUBECONFIG_PATH="/tmp/${CLUSTER_NAME}-kubeconfig"
# This is only set in the context of the script
# Need to set this manually witch 'kubectl --kubeconfig ${KUBECONFIG_PATH}'
# when the script finishes (see show_access_info() output)
export KUBECONFIG="${KUBECONFIG_PATH}"

# Keep all mutable Terraform artifacts (providers, state) in /tmp so test runs
# never touch the live cluster's state in the repo terraform directory
TF_STATE_PATH="/tmp/${CLUSTER_NAME}.tfstate"
export TF_DATA_DIR="/tmp/${CLUSTER_NAME}-tfdata"

check_docker_running() {
  if ! docker info >/dev/null 2>&1; then
    log_error "Docker is not running"
    exit 1
  fi
}

# Determine the git branch that ArgoCD should sync from and any changes not
# pushed to remote
resolve_target_revision() {
  TARGET_REVISION=$(git branch --show-current)

  if [ -z "${TARGET_REVISION}" ]; then
    log_warn "Could not determine current branch (detached HEAD?) - exiting..."
    exit 1
    return
  fi

  # ArgoCD pulls from GitHub, so it can only sync branches that exist there
  local ls_remote_rc=0
  git ls-remote --exit-code origin "refs/heads/${TARGET_REVISION}" >/dev/null 2>&1 || ls_remote_rc=$?
  # --exit-code exits with status "2" when no matching refs are found in the
  # remote repository.
  if [ "${ls_remote_rc}" -eq 2 ]; then
    log_error "Branch '${TARGET_REVISION}' not found on remote. ArgoCD will fail to sync unless its pushed - exiting..."
    exit 1
  fi

  local unpushed_commits=$(git rev-list --count @{u}..HEAD)
  if [ "${unpushed_commits}" -gt 0 ]; then
    log_warn "You have ${unpushed_commits} commit(s) not yet pushed to remote - the test cluster may not include all expected changes"
  fi

  if [ -n "$(git status --porcelain)" ]; then
    log_warn "Uncommitted changes exist - you may want to commit and push these to see the changes reflected in the test cluster"
  fi
}

cleanup() {
  log_info "Cleaning up..."
  if k3d cluster get "${CLUSTER_NAME}" >/dev/null 2>&1; then
    k3d cluster delete "${CLUSTER_NAME}"
  fi

  rm -f "${KUBECONFIG_PATH}" "${TF_STATE_PATH}" "${TF_STATE_PATH}.backup"
  rm -rf "${TF_DATA_DIR}"

  log_info "Cleanup complete"
}

create_cluster() {
  log_info "Creating k3d cluster '${CLUSTER_NAME}'..."

  if k3d cluster get "${CLUSTER_NAME}" >/dev/null 2>&1; then
    log_warn "Cluster '${CLUSTER_NAME}' already exists - deleting..."
    k3d cluster delete "${CLUSTER_NAME}"
  fi

  # Create the test cluster, keep it out of the default kubeconfig
  # (isolated from the live cluster) and don't switch from live cluster context
  # to test cluster context
  k3d cluster create "${CLUSTER_NAME}" --wait \
    --kubeconfig-update-default=false \
    --kubeconfig-switch-context=false

  # Write test cluster kubeconfig to /tmp
  k3d kubeconfig get "${CLUSTER_NAME}" > "${KUBECONFIG_PATH}"

  log_info "Waiting for cluster to be ready..."
  kubectl wait --for=condition=Ready nodes --all --timeout=120s
  log_info "Cluster is ready"
}

run_terraform() {
  # Print branch in which we are pulling k8s manifests from
  log_info "Target revision: ${TARGET_REVISION}"

  run_terraform_staged \
    -var="kubeconfig_path=${KUBECONFIG_PATH}" \
    -var="target_revision=${TARGET_REVISION}"
}

show_access_info() {
  local password
  password=$(get_argocd_password)

  echo ""
  echo "======================================================================="
  echo "                        ArgoCD Access Info"
  echo "======================================================================="
  echo "  To use kubectl with this cluster, define an alias:"
  echo "  alias kt='kubectl --kubeconfig ${KUBECONFIG_PATH}'"
  echo ""
  # ArgoCD runs in HTTP mode once the self-managed app applies
  # applications/argocd/values.yaml, so use the service's HTTP port
  echo "  Port forward: kt port-forward svc/argocd-server -n argocd 8080:80"
  echo "  URL:          http://localhost:8080"
  echo "  Username:     admin"
  echo "  Password:     ${password}"
  echo ""
  echo "  NOTE: The test cluster is NOT merged into ~/.kube/config, so plain"
  echo "  kubectl still points at the live cluster. Use the alias above."
  echo "======================================================================="
}

cmd_status() {
  if ! k3d cluster get "${CLUSTER_NAME}" >/dev/null 2>&1; then
    log_warn "Cluster '${CLUSTER_NAME}' does not exist"
    exit 0
  fi

  echo ""
  log_info "Cluster status:"
  k3d cluster list | awk -v name="${CLUSTER_NAME}" 'NR==1 || $0 ~ name'
  echo ""
  log_info "ArgoCD pods:"
  kubectl get pods -n argocd 2>/dev/null || echo "ArgoCD namespace not found"
  echo ""
  log_info "ArgoCD applications:"
  kubectl get applications -n argocd 2>/dev/null || echo "No applications found"
}

cmd_up() {
  check_dependencies docker k3d kubectl terraform
  check_docker_running
  resolve_target_revision
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
