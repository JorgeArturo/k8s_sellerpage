#!/usr/bin/env bash
#
# install-kubeadm.sh — Prepare an Ubuntu VM and install Kubernetes via kubeadm.
#
# Usage:
#   sudo ./install-kubeadm.sh init          # Single-node control plane
#   sudo ./install-kubeadm.sh worker <token> <cp-ip:6443>   # Join as worker
#   sudo ./install-kubeadm.sh reset         # Tear down cluster
#
set -euo pipefail

K8S_VERSION="${K8S_VERSION:-1.29}"
POD_NETWORK_CIDR="${POD_NETWORK_CIDR:-10.244.0.0/16}"
CNI_PLUGIN="${CNI_PLUGIN:-flannel}"

log() { echo "[$(date +'%H:%M:%S')] $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

require_root() {
  [[ $EUID -eq 0 ]] || die "Run this script as root (sudo)."
}

detect_ubuntu() {
  [[ -f /etc/os-release ]] || die "Unsupported OS: /etc/os-release not found."
  # shellcheck source=/dev/null
  source /etc/os-release
  [[ "${ID}" == "ubuntu" ]] || die "This script supports Ubuntu only (found: ${ID})."
  log "Detected Ubuntu ${VERSION_ID}"
}

disable_swap() {
  log "Disabling swap..."
  swapoff -a || true
  sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
}

load_kernel_modules() {
  log "Loading kernel modules..."
  cat >/etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF
  modprobe overlay
  modprobe br_netfilter
}

configure_sysctl() {
  log "Configuring sysctl..."
  cat >/etc/sysctl.d/k8s.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
  sysctl --system >/dev/null
}

install_containerd() {
  log "Installing containerd..."
  apt-get update -qq
  apt-get install -y -qq ca-certificates curl gnupg lsb-release

  install -m 0755 -d /etc/apt/keyrings
  if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
      | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
  fi

  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "${VERSION_CODENAME}") stable" \
    >/etc/apt/sources.list.d/docker.list

  apt-get update -qq
  apt-get install -y -qq containerd.io

  mkdir -p /etc/containerd
  containerd config default >/etc/containerd/config.toml
  sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
  systemctl restart containerd
  systemctl enable containerd
}

install_kubeadm() {
  log "Installing kubeadm, kubelet, kubectl (v${K8S_VERSION})..."
  install -m 0755 -d /etc/apt/keyrings
  if [[ ! -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg ]]; then
    curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/Release.key" \
      | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  fi

  echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
    https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/ /" \
    >/etc/apt/sources.list.d/kubernetes.list

  apt-get update -qq
  apt-get install -y -qq kubelet kubeadm kubectl
  apt-mark hold kubelet kubeadm kubectl
  systemctl enable kubelet
}

install_cni() {
  log "Installing CNI plugin: ${CNI_PLUGIN}..."
  case "${CNI_PLUGIN}" in
    flannel)
      kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
      ;;
    calico)
      kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml
      ;;
    *)
      die "Unknown CNI plugin: ${CNI_PLUGIN}. Use flannel or calico."
      ;;
  esac
}

init_cluster() {
  log "Initializing Kubernetes control plane..."
  kubeadm init \
    --pod-network-cidr="${POD_NETWORK_CIDR}" \
    --apiserver-advertise-address="$(hostname -I | awk '{print $1}')"

  export KUBECONFIG=/etc/kubernetes/admin.conf
  mkdir -p /root/.kube
  cp -i /etc/kubernetes/admin.conf /root/.kube/config
  chown root:root /root/.kube/config

  # Allow scheduling pods on control plane (single-node dev clusters)
  kubectl taint nodes --all node-role.kubernetes.io/control-plane- 2>/dev/null || true

  install_cni

  log "Cluster initialized successfully."
  kubeadm token create --print-join-command
}

join_worker() {
  local token="${1:-}"
  local cp_endpoint="${2:-}"
  [[ -n "${token}" && -n "${cp_endpoint}" ]] \
    || die "Usage: $0 worker <token> <control-plane-ip:6443>"

  log "Joining cluster at ${cp_endpoint}..."
  kubeadm join "${cp_endpoint}" --token "${token}" --discovery-token-unsafe-skip-ca-verification
}

reset_cluster() {
  log "Resetting Kubernetes cluster..."
  kubeadm reset -f
  rm -rf /etc/cni/net.d
  iptables -F && iptables -t nat -F && iptables -t mangle -F && iptables -X || true
  log "Cluster reset complete."
}

prepare_host() {
  require_root
  detect_ubuntu
  disable_swap
  load_kernel_modules
  configure_sysctl
  install_containerd
  install_kubeadm
  log "Host preparation complete. Run '$0 init' to create the cluster."
}

main() {
  local cmd="${1:-prepare}"
  case "${cmd}" in
    prepare)
      prepare_host
      ;;
    init)
      prepare_host
      init_cluster
      ;;
    worker)
      shift
      prepare_host
      join_worker "$@"
      ;;
    reset)
      require_root
      reset_cluster
      ;;
    *)
      cat <<EOF
Kubernetes (kubeadm) installer for Ubuntu

Commands:
  prepare   Install container runtime and kubeadm packages (default)
  init      Prepare host and initialize a single-node control plane
  worker    Join an existing cluster as a worker node
  reset     Remove the cluster from this node

Environment variables:
  K8S_VERSION       Kubernetes version (default: 1.29)
  POD_NETWORK_CIDR  Pod network CIDR (default: 10.244.0.0/16)
  CNI_PLUGIN        flannel or calico (default: flannel)
EOF
      ;;
  esac
}

main "$@"
