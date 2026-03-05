#!/usr/bin/env bash
# Saiyan Trainer - One-command Kubernetes setup
# Installs Tekton Pipelines v1.9.0 LTS, Dashboard, Triggers,
# SeaweedFS object storage, and workspace PVC.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ------------------------------------------------------------------
# Pre-flight checks
# ------------------------------------------------------------------
for cmd in kubectl helm; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "ERROR: '$cmd' is required but not found in PATH."
    exit 1
  fi
done

echo "==> Cluster context: $(kubectl config current-context)"

# ------------------------------------------------------------------
# 1. Tekton Pipelines v1.9.0 LTS
# ------------------------------------------------------------------
echo ""
echo "==> Installing Tekton Pipelines v1.9.0 LTS ..."
kubectl apply -f https://infra.tekton.dev/releases/pipeline/previous/v1.9.0/release.yaml

echo "==> Waiting for Tekton Pipelines controller to be ready ..."
kubectl wait --for=condition=ready pod \
  -l app=tekton-pipelines-controller \
  -n tekton-pipelines \
  --timeout=120s

# ------------------------------------------------------------------
# 2. Tekton feature-flags patch (keep-pod-on-cancel, coschedule)
# ------------------------------------------------------------------
echo ""
echo "==> Applying Tekton feature-flags patch ..."
kubectl apply -f "$SCRIPT_DIR/../tekton/feature-flags-patch.yaml"

# ------------------------------------------------------------------
# 3. Tekton Dashboard
# ------------------------------------------------------------------
echo ""
echo "==> Installing Tekton Dashboard ..."
kubectl apply -f https://infra.tekton.dev/tekton-releases/dashboard/latest/release.yaml

# ------------------------------------------------------------------
# 4. Tekton Triggers
# ------------------------------------------------------------------
echo ""
echo "==> Installing Tekton Triggers ..."
kubectl apply -f https://storage.googleapis.com/tekton-releases/triggers/latest/release.yaml

# ------------------------------------------------------------------
# 5. SeaweedFS (S3-compatible object storage)
# ------------------------------------------------------------------
echo ""
echo "==> Installing SeaweedFS via Helm ..."
helm repo add seaweedfs https://seaweedfs.github.io/helm-chart/ 2>/dev/null || true
helm repo update
helm upgrade --install seaweedfs seaweedfs/seaweedfs \
  -f "$SCRIPT_DIR/../storage/seaweedfs-values.yaml" \
  --wait --timeout 180s

# ------------------------------------------------------------------
# 6. SeaweedFS credentials secret
# ------------------------------------------------------------------
echo ""
echo "==> Applying SeaweedFS credentials secret ..."
kubectl apply -f "$SCRIPT_DIR/../storage/seaweedfs-secret.yaml"

# ------------------------------------------------------------------
# 7. Shared workspace PVC
# ------------------------------------------------------------------
echo ""
echo "==> Applying workspace PVC ..."
kubectl apply -f "$SCRIPT_DIR/../storage/workspace-pvc.yaml"

# ------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------
echo ""
echo "============================================"
echo "  Saiyan Trainer - Setup Complete"
echo "============================================"
echo ""
echo "Installed:"
echo "  - Tekton Pipelines v1.9.0 LTS"
echo "  - Tekton Dashboard"
echo "  - Tekton Triggers"
echo "  - SeaweedFS (S3-compatible storage)"
echo "  - Workspace PVC (5Gi)"
echo ""
echo "Feature flags:"
echo "  - keep-pod-on-cancel: true"
echo "  - coschedule: workspaces"
echo ""
echo "Next steps:"
echo "  1. Apply Tekton tasks:   kubectl apply -f k8s/tekton/tasks/"
echo "  2. Apply pipeline:       kubectl apply -f k8s/tekton/pipeline.yaml"
echo "  3. Trigger a run:        kubectl create -f k8s/tekton/pipelinerun.yaml"
echo ""
echo "Tekton Dashboard (port-forward):"
echo "  kubectl port-forward -n tekton-pipelines svc/tekton-dashboard 9097:9097"
echo "  Open: http://localhost:9097"
