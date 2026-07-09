#!/usr/bin/env bash
#
# Tear down the HPA demo. Deletes the Kind cluster (which removes everything
# in it). Colima is left running; pass --stop-colima to stop it too.
set -euo pipefail

CLUSTER=hpa

log() { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }

if kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
  log "Deleting Kind cluster '$CLUSTER'..."
  kind delete cluster --name "$CLUSTER"
else
  log "Kind cluster '$CLUSTER' not found, nothing to delete."
fi

if [ "${1:-}" = "--stop-colima" ]; then
  log "Stopping Colima..."
  colima stop
fi

log "Done."
