#!/bin/bash
set -euo pipefail

# Get the directory where this script lives, regardless of where it's called from
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

CLUSTER_NAME="homelab-test"
KUBECONFIG_PATH="/tmp/${CLUSTER_NAME}-kubeconfig"
# Applications reference this repo both with and without the .git suffix, so
# comparisons against it strip the suffix first
REPO_URL="https://github.com/rmjhynes/homelab"

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

# Determine the git branch ArgoCD should sync from
resolve_target_revision() {
  TARGET_REVISION=$(git -C "${SCRIPT_DIR}" branch --show-current)

  if [ -z "${TARGET_REVISION}" ]; then
    log_warn "Could not determine current branch (detached HEAD?), defaulting to HEAD"
    TARGET_REVISION="HEAD"
    return
  fi

  # ArgoCD pulls from GitHub, so it can only sync branches that exist there
  if ! git -C "${SCRIPT_DIR}" ls-remote --exit-code origin "refs/heads/${TARGET_REVISION}" >/dev/null 2>&1; then
    log_warn "Branch '${TARGET_REVISION}' not found on origin - push it or ArgoCD will fail to sync"
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
    log_warn "Cluster '${CLUSTER_NAME}' already exists, deleting..."
    k3d cluster delete "${CLUSTER_NAME}"
  fi

  # Keep the test cluster out of ~/.kube/config; the script and the user
  # access it via the dedicated kubeconfig in /tmp instead
  k3d cluster create "${CLUSTER_NAME}" --wait \
    --kubeconfig-update-default=false \
    --kubeconfig-switch-context=false

  k3d kubeconfig get "${CLUSTER_NAME}" > "${KUBECONFIG_PATH}"
  export KUBECONFIG="${KUBECONFIG_PATH}"

  log_info "Waiting for cluster to be ready..."
  kubectl wait --for=condition=Ready nodes --all --timeout=120s
  log_info "Cluster ready"
}

run_terraform() {
  log_info "Target revision: ${TARGET_REVISION}"

  run_terraform_staged \
    -var="kubeconfig_path=${KUBECONFIG_PATH}" \
    -var="target_revision=${TARGET_REVISION}"
}

# Child Applications in applications/ pin targetRevision: HEAD, which ArgoCD
# resolves to main. Point their homelab repo sources at the branch under test
# instead. The root app is deployed with selfHeal disabled when testing a
# branch (see terraform/main.tf) so these patches are not reverted.
patch_child_apps() {
  if [ "${TARGET_REVISION}" = "HEAD" ]; then
    return
  fi

  export KUBECONFIG="${KUBECONFIG_PATH}"

  log_info "Waiting for the root application to create child applications..."
  local apps=""
  local deadline=$((SECONDS + 180))
  while [ ${SECONDS} -lt ${deadline} ]; do
    apps=$(kubectl get applications -n argocd -o name 2>/dev/null \
      | grep -v "^application.argoproj.io/applications$" || true)
    if [ -n "${apps}" ]; then
      break
    fi
    sleep 5
  done

  if [ -z "${apps}" ]; then
    log_warn "No child applications appeared after 180s - is branch '${TARGET_REVISION}' pushed to GitHub?"
    log_warn "Skipping branch override"
    return
  fi

  # The root app's sync creates all children near-simultaneously; a short
  # settle catches any stragglers from the same sync operation
  sleep 5
  apps=$(kubectl get applications -n argocd -o name 2>/dev/null \
    | grep -v "^application.argoproj.io/applications$" || true)

  log_info "Patching child applications to sync from '${TARGET_REVISION}'..."
  local app original patched
  for app in ${apps}; do
    original=$(kubectl get "${app}" -n argocd -o json)

    # Retarget sources pointing at this repo's HEAD; leave pinned Helm chart
    # versions and other repos untouched. Handles both single-source
    # (.spec.source) and multi-source (.spec.sources) Applications
    patched=$(echo "${original}" | jq --arg repo "${REPO_URL}" --arg rev "${TARGET_REVISION}" '
      {spec: (.spec
        | if has("source") and (.source.repoURL | rtrimstr(".git")) == $repo
              and .source.targetRevision == "HEAD"
            then .source.targetRevision = $rev else . end
        | if has("sources")
            then .sources |= map(
              if (.repoURL | rtrimstr(".git")) == $repo and .targetRevision == "HEAD"
                then .targetRevision = $rev else . end)
            else . end)}')

    if [ "$(echo "${original}" | jq -c .spec)" = "$(echo "${patched}" | jq -c .spec)" ]; then
      continue
    fi

    kubectl patch "${app}" -n argocd --type merge -p "${patched}" >/dev/null
    log_info "  Patched ${app#application.argoproj.io/}"
  done

  log_info "Branch override complete"
}

show_access_info() {
  export KUBECONFIG="${KUBECONFIG_PATH}"

  local password
  password=$(get_argocd_password)

  echo ""
  echo "========================================"
  echo "  ArgoCD Access Info"
  echo "========================================"
  echo "  To use kubectl with this cluster, define an alias:"
  echo "  alias kt='kubectl --kubeconfig ${KUBECONFIG_PATH}'"
  echo ""
  # ArgoCD runs in insecure (plain HTTP) mode once the self-managed app
  # applies applications/argocd/values.yaml, so use the service's HTTP port
  echo "  Port forward: kt port-forward svc/argocd-server -n argocd 8080:80"
  echo "  URL:          http://localhost:8080"
  echo "  Username:     admin"
  echo "  Password:     ${password}"
  echo ""
  echo "  NOTE: The test cluster is NOT merged into ~/.kube/config, so plain"
  echo "  kubectl still points at the live cluster."
  echo "========================================"
}

cmd_status() {
  if ! k3d cluster get "${CLUSTER_NAME}" >/dev/null 2>&1; then
    log_warn "Cluster '${CLUSTER_NAME}' does not exist"
    exit 0
  fi

  export KUBECONFIG="${KUBECONFIG_PATH}"
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
  check_dependencies k3d terraform kubectl docker jq
  check_docker_running
  resolve_target_revision
  create_cluster
  run_terraform
  wait_for_argocd
  patch_child_apps
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
