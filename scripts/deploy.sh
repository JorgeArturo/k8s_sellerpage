#!/usr/bin/env bash
#
# Build Docker images and deploy the marketplace to Kubernetes.
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log() { echo "[deploy] $*"; }

build_images() {
  log "Building backend image..."
  docker build -t marketplace-backend:latest "${ROOT_DIR}/backend"

  log "Building frontend image..."
  docker build -t marketplace-frontend:latest "${ROOT_DIR}/frontend"
}

load_images() {
  if command -v minikube &>/dev/null && minikube status &>/dev/null; then
    log "Loading images into minikube..."
    minikube image load marketplace-backend:latest
    minikube image load marketplace-frontend:latest
  elif command -v kind &>/dev/null && kind get clusters 2>/dev/null | grep -q .; then
    local cluster
    cluster="$(kind get clusters | head -1)"
    log "Loading images into kind cluster: ${cluster}..."
    kind load docker-image marketplace-backend:latest --name "${cluster}"
    kind load docker-image marketplace-frontend:latest --name "${cluster}"
  else
    log "No minikube/kind detected. Ensure nodes can pull marketplace-*:latest images."
  fi
}

deploy() {
  log "Applying Kubernetes manifests..."
  kubectl apply -k "${ROOT_DIR}/k8s --validate=false"

  log "Waiting for pods..."
  kubectl -n marketplace rollout status deployment/postgres --timeout=120s
  kubectl -n marketplace rollout status deployment/backend --timeout=120s
  kubectl -n marketplace rollout status deployment/frontend --timeout=120s

  log "Deployment complete."
  kubectl -n marketplace get pods,svc
  echo ""
  echo "Access the marketplace at: http://<node-ip>:30080"
  echo "Default admin: admin@marketplace.local / admin123"
}

main() {
  build_images
  load_images
  deploy
}

main "$@"
