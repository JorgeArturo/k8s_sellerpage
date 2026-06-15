#!/usr/bin/env bash
#
# Build Docker images and deploy the marketplace to Kubernetes.
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log() { echo "[deploy] $*"; }

check_and_install_docker() {
  if command -v docker &>/dev/null; then
    log "Docker is already installed."
    return 0
  fi

  log "Docker not found. Installing Docker..."

  if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    if command -v brew &>/dev/null; then
      log "Installing Docker via Homebrew..."
      brew install docker
      log "Docker installed. Starting Docker Desktop..."
      open -a Docker
      log "Waiting for Docker to start (up to 60 seconds)..."
      for i in {1..60}; do
        if docker info &>/dev/null; then
          log "Docker is ready."
          return 0
        fi
        sleep 1
      done
      log "Warning: Docker may still be starting. If docker commands fail, wait a moment and try again."
    else
      log "Homebrew not found. Please install Homebrew from https://brew.sh or Docker Desktop from https://www.docker.com/products/docker-desktop"
      exit 1
    fi
  elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    # Linux
    log "Installing Docker on Linux..."
    sudo apt-get update
    sudo apt-get install -y docker.io docker-compose
    sudo systemctl start docker
    sudo usermod -aG docker "$USER"
    log "Docker installed. You may need to log out and back in for group changes to take effect."
  else
    log "Unsupported OS: $OSTYPE. Please install Docker manually from https://www.docker.com"
    exit 1
  fi
}

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
  kubectl apply -k "${ROOT_DIR}/k8s"

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
  check_and_install_docker
  build_images
  load_images
  deploy
}

main "$@"
