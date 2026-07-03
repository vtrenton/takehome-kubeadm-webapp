#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VALUES_DIR="${PROJECT_ROOT}/values"

export KUBECONFIG="${PROJECT_ROOT}/out/admin.conf"

if [[ ! -f "${KUBECONFIG}" ]]; then
  echo "ERROR: kubeconfig not found at ${KUBECONFIG}"
  echo "Run the Terraform and Ansible kubeadm bootstrap first."
  exit 1
fi

command -v kubectl >/dev/null || { echo "ERROR: kubectl is required"; exit 1; }
command -v helm >/dev/null || { echo "ERROR: helm is required"; exit 1; }

echo "Using KUBECONFIG=${KUBECONFIG}"

echo "Adding Helm repos..."
helm repo add cilium https://helm.cilium.io/ --force-update
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ --force-update
helm repo add argo https://argoproj.github.io/argo-helm --force-update
helm repo update

echo "Installing Cilium..."
helm upgrade --install cilium cilium/cilium \
  --namespace kube-system \
  --values "${VALUES_DIR}/cilium.yaml"

echo "Waiting for Cilium..."
kubectl -n kube-system rollout status daemonset/cilium --timeout=10m
kubectl -n kube-system rollout status deployment/cilium-operator --timeout=10m

echo "Waiting for nodes and CoreDNS..."
kubectl wait --for=condition=Ready nodes --all --timeout=10m
kubectl -n kube-system rollout status deployment/coredns --timeout=10m

echo "Installing metrics-server..."
helm upgrade --install metrics-server metrics-server/metrics-server \
  --namespace kube-system \
  --values "${VALUES_DIR}/metrics-server.yaml"

echo "Waiting for metrics-server..."
kubectl -n kube-system rollout status deployment/metrics-server --timeout=5m

echo "Installing Argo CD..."
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  --values "${VALUES_DIR}/argocd.yaml"

echo "Waiting for Argo CD..."
kubectl -n argocd wait --for=condition=Available deployment --all --timeout=10m
kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout=10m

echo
echo "Core services installed."
echo
kubectl get nodes -o wide

echo
kubectl get pods -A

echo
echo "Argo CD access:"
echo "  kubectl -n argocd port-forward svc/argocd-server 8080:443"

echo
echo "Argo CD initial admin password:"
echo "  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo"
