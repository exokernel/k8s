#!/usr/bin/env bash
#
# Bring the VPA demo to "ready to show" state.
#
# Does everything up to the point where VPA is watching the hamster workload:
#   Colima -> Kind cluster -> pre-pull images -> metrics-server (+ Kind patch)
#   -> VPA components (vpa-up.sh) -> hamster deployment + VerticalPodAutoscaler.
#
# Run this a FEW MINUTES BEFORE the demo: the recommender needs some usage
# history, so by the time you present, `kubectl describe vpa hamster-vpa` will
# already show a recommendation and you can show pods getting rightsized.
#
# Idempotent: safe to re-run.
set -euo pipefail

CLUSTER=vpa
NODE="${CLUSTER}-control-plane"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VPA_DIR="$DIR/autoscaler/vertical-pod-autoscaler"

log() { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }

# 1. Docker runtime
if colima status >/dev/null 2>&1; then
  log "Colima already running."
else
  log "Starting Colima..."
  colima start
fi

# 2. Kind cluster
if kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
  log "Kind cluster '$CLUSTER' already exists."
else
  log "Creating Kind cluster '$CLUSTER'..."
  kind create cluster --name "$CLUSTER"
fi
kubectl config use-context "kind-${CLUSTER}" >/dev/null

# 3. Pre-pull images
log "Pre-pulling images into $NODE..."
for img in \
  registry.k8s.io/metrics-server/metrics-server:v0.8.1 \
  registry.k8s.io/autoscaling/vpa-recommender:1.7.0 \
  registry.k8s.io/autoscaling/vpa-updater:1.7.0 \
  registry.k8s.io/autoscaling/vpa-admission-controller:1.7.0 \
  registry.k8s.io/ubuntu-slim:0.14 ; do
  docker exec "$NODE" crictl pull "$img"
done

# 4. metrics-server (+ Kind patch). Patch guarded so re-runs don't add the flag twice.
log "Installing metrics-server..."
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
if kubectl get deploy metrics-server -n kube-system \
     -o jsonpath='{.spec.template.spec.containers[0].args}' | grep -q 'kubelet-insecure-tls'; then
  log "metrics-server already patched for Kind."
else
  log "Patching metrics-server with --kubelet-insecure-tls (required for Kind)..."
  kubectl patch -n kube-system deployment metrics-server --type=json \
    -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
fi
kubectl rollout status -n kube-system deployment/metrics-server --timeout=120s
log "Waiting for node metrics to start flowing..."
until kubectl top nodes >/dev/null 2>&1; do sleep 3; done

# 5. VPA components (install only if not already present)
if kubectl get deploy vpa-recommender -n kube-system >/dev/null 2>&1; then
  log "VPA already installed."
else
  if [ ! -d "$VPA_DIR" ]; then
    log "Cloning kubernetes/autoscaler..."
    git clone https://github.com/kubernetes/autoscaler.git "$DIR/autoscaler"
  fi
  log "Installing VPA (vpa-up.sh)..."
  ( cd "$VPA_DIR" && ./hack/vpa-up.sh )
fi
for d in vpa-recommender vpa-updater vpa-admission-controller; do
  kubectl rollout status -n kube-system "deployment/$d" --timeout=120s
done

# 6. Workload + VerticalPodAutoscaler
log "Deploying hamster workload and its VerticalPodAutoscaler..."
kubectl apply -f "$DIR/hamster.yaml"
kubectl rollout status deployment/hamster --timeout=120s

cat <<'EOF'

============================================================
  VPA demo is READY. Give the recommender a few minutes, then:

  # the recommendation VPA computed (target / lower / upper bound)
  kubectl describe vpa hamster-vpa

  # watch pods get evicted and recreated with larger requests
  kubectl get pods -l app=hamster --watch
  kubectl describe pod -l app=hamster | grep -A2 Requests

  Teardown when done:  ./teardown-demo.sh
============================================================
EOF
