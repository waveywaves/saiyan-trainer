#!/bin/bash
# Resume training from the best island's latest checkpoint.
# Finds the island with highest maxFitness, copies its latest checkpoint
# to a new run-id, and launches a PipelineRun for N more generations.
#
# Usage: ./scripts/resume-training.sh [generations]
#   generations: number of generations to train (default: 2)
set -euo pipefail

GENS="${1:-2}"
PVC_NAME="${PVC_NAME:-saiyan-training-data}"
PIPELINE_NAME="${PIPELINE_NAME:-saiyan-loop-training}"
RUN_ID="resume-$(date +%s)"

echo "==> Scanning PVC for best island checkpoint..."

# Run a pod to find the best island and its latest generation
SCAN_RESULT=$(kubectl run scan-best --image=busybox --rm -i --restart=Never \
  --overrides="{\"spec\":{\"volumes\":[{\"name\":\"data\",\"persistentVolumeClaim\":{\"claimName\":\"${PVC_NAME}\"}}],\"containers\":[{\"name\":\"scan\",\"image\":\"busybox\",\"command\":[\"sh\",\"-c\",\"for island in \$(ls /workspace/output/ 2>/dev/null); do [ -d /workspace/output/\$island/checkpoints ] || continue; LATEST=\$(ls /workspace/output/\$island/checkpoints/gen_*.json 2>/dev/null | sed 's/.*gen_//;s/.json//' | sort -n | tail -1); [ -z \\\"\$LATEST\\\" ] && continue; METRICS=/workspace/output/\$island/results/metrics.json; if [ -f \$METRICS ]; then FITNESS=\$(cat \$METRICS | tr ',' '\\n' | grep maxFitness | tail -1 | sed 's/.*://;s/[^0-9.]//g'); else FITNESS=0; fi; echo \$island \$LATEST \$FITNESS; done\"],\"volumeMounts\":[{\"name\":\"data\",\"mountPath\":\"/workspace\"}]}]}}" 2>/dev/null)

if [ -z "$SCAN_RESULT" ]; then
  echo "ERROR: No islands found on PVC"
  exit 1
fi

# Find the island with the best fitness
BEST_ISLAND=""
BEST_GEN=""
BEST_FITNESS="0"

while read -r island gen fitness; do
  if awk "BEGIN{exit(!($fitness > $BEST_FITNESS))}"; then
    BEST_ISLAND="$island"
    BEST_GEN="$gen"
    BEST_FITNESS="$fitness"
  fi
done <<< "$SCAN_RESULT"

if [ -z "$BEST_ISLAND" ]; then
  echo "ERROR: Could not determine best island"
  exit 1
fi

echo "==> Best island: ${BEST_ISLAND} (gen ${BEST_GEN}, fitness ${BEST_FITNESS})"
echo "==> Creating run '${RUN_ID}' from gen ${BEST_GEN}..."

# Copy the latest checkpoint to the new run-id directory
kubectl run copy-checkpoint --image=busybox --rm -i --restart=Never \
  --overrides="{\"spec\":{\"volumes\":[{\"name\":\"data\",\"persistentVolumeClaim\":{\"claimName\":\"${PVC_NAME}\"}}],\"containers\":[{\"name\":\"copy\",\"image\":\"busybox\",\"command\":[\"sh\",\"-c\",\"mkdir -p /workspace/output/${RUN_ID}/checkpoints /workspace/output/${RUN_ID}/results && cp /workspace/output/${BEST_ISLAND}/checkpoints/gen_${BEST_GEN}.json /workspace/output/${RUN_ID}/checkpoints/gen_${BEST_GEN}.json && echo DONE\"],\"volumeMounts\":[{\"name\":\"data\",\"mountPath\":\"/workspace\"}]}]}}" 2>/dev/null

echo "==> Launching PipelineRun (${GENS} generations)..."

PR_NAME=$(cat <<EOF | kubectl create -f - -o jsonpath='{.metadata.name}'
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  generateName: saiyan-resume-
spec:
  timeouts:
    pipeline: "0"
    tasks: "0"
    finally: "0"
  pipelineRef:
    name: ${PIPELINE_NAME}
  params:
    - name: run-id
      value: "${RUN_ID}"
    - name: generations-per-batch
      value: "${GENS}"
    - name: fitness-threshold
      value: "99999"
    - name: max-batches
      value: "1"
  workspaces:
    - name: training-data
      persistentVolumeClaim:
        claimName: ${PVC_NAME}
EOF
)

echo ""
echo "=== Resume Training Started ==="
echo "  PipelineRun: ${PR_NAME}"
echo "  Source:       ${BEST_ISLAND} gen ${BEST_GEN} (fitness ${BEST_FITNESS})"
echo "  Run ID:       ${RUN_ID}"
echo "  Generations:  ${GENS}"
echo ""
echo "Monitor:"
echo "  kubectl logs -f ${PR_NAME}-train-batch-loop-0-pod -c step-train"
echo "  kubectl get pipelinerun ${PR_NAME} -w"
