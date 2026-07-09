#!/usr/bin/env bash
#
# Bring the HPA demo to "ready to show" state, so the only thing left to do live
# is start the load generator and watch it scale.
#
# Does everything up to (but not including) load generation:
#   Colima -> Kind cluster -> pre-pull images -> metrics-server (+ Kind patch)
#   -> php-apache deployment -> demo HPA -> wait until the HPA is reading metrics.
#
# Idempotent: safe to re-run. Run it a minute or two before you present.
set -euo pipefail

CLUSTER=hpa
NODE="${CLUSTER}-control-plane"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

# 3. Pre-pull images (hpa-example is amd64-only -> emulated + slow on Apple
#    Silicon; pulling it now keeps the demo from stalling on a live pull)
log "Pre-pulling images into $NODE (hpa-example runs emulated, this can be slow)..."
for img in \
  registry.k8s.io/metrics-server/metrics-server:v0.8.1 \
  registry.k8s.io/hpa-example \
  busybox:1.28 ; do
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
kubectl top nodes

# 5. Workload + demo HPA (short scale-down window so the demo is snappy)
log "Deploying php-apache and the demo HPA..."
kubectl apply -f "$DIR/php-apache.yaml"
kubectl rollout status deployment/php-apache --timeout=180s
kubectl apply -f "$DIR/hpa-demo.yaml"

log "Waiting for the HPA to read metrics (first reading is <unknown> for ~15-30s)..."
until kubectl get hpa php-apache --no-headers 2>/dev/null | grep -vq '<unknown>'; do sleep 3; done
kubectl get hpa php-apache

cat <<'EOF'

============================================================
  HPA demo is READY. During the demo, in two terminals:

  # terminal 1 - watch it scale
  kubectl get hpa php-apache --watch

  # terminal 2 - generate load
  kubectl run -i --tty load-generator --rm --image=busybox:1.28 --restart=Never -- \
    /bin/sh -c "while sleep 0.01; do wget -q -O- http://php-apache; done"

  Stop the load (Ctrl+C in terminal 2) to watch it scale back down (~15-30s).
  Teardown when done:  kind delete cluster --name hpa
============================================================
EOF
