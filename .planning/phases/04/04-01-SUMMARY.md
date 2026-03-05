---
phase: 04-tekton-pipeline-mlops
plan: 01
subsystem: tekton-pipeline
tags: [tekton, kubernetes, pipeline, seaweedfs, mlops]
dependency_graph:
  requires: []
  provides: [saiyan-training-pipeline, setup-generation-task, run-training-task, evaluate-champion-task, store-results-task, seaweedfs-storage, workspace-pvc]
  affects: [04-02, 04-03]
tech_stack:
  added: [tekton-pipelines-v1.9.0-lts, seaweedfs, minio-mc]
  patterns: [linear-pipeline, pvc-workspace-sharing, s3-genome-versioning, checkpoint-resume]
key_files:
  created:
    - k8s/setup/install.sh
    - k8s/storage/seaweedfs-values.yaml
    - k8s/storage/seaweedfs-secret.yaml
    - k8s/storage/workspace-pvc.yaml
    - k8s/tekton/feature-flags-patch.yaml
    - k8s/tekton/tasks/setup-generation.yaml
    - k8s/tekton/tasks/run-training.yaml
    - k8s/tekton/tasks/evaluate-champion.yaml
    - k8s/tekton/tasks/store-results.yaml
    - k8s/tekton/pipeline.yaml
    - k8s/tekton/pipelinerun.yaml
  modified: []
decisions:
  - Tekton v1.9.0 LTS with v1 API for all resources
  - SeaweedFS over MinIO for S3-compatible storage (Apache 2.0 license)
  - mc CLI for S3 operations in task steps
  - Genome path convention genomes/{run-id}/gen-{NNNN}/ for version retrieval
  - volumeClaimTemplate in PipelineRun (ephemeral) with SeaweedFS for persistence
metrics:
  duration: 2m 32s
  completed: 2026-03-06
  tasks_completed: 2
  tasks_total: 2
  files_created: 11
  files_modified: 0
---

# Phase 4 Plan 1: Core Tekton Pipeline Summary

Tekton Pipeline with 4 sequential tasks (setup, train, evaluate, store), SeaweedFS S3 storage for genome versioning, PVC workspace sharing with affinity assistant, and one-command install script for the full K8s stack.

## What Was Built

### Task 1: K8s Infrastructure Manifests and Install Script

Created the `k8s/` directory tree with all infrastructure manifests:

- **install.sh**: One-command setup script that installs Tekton Pipelines v1.9.0 LTS, Dashboard, Triggers, SeaweedFS via Helm, credentials secret, and workspace PVC. Includes pre-flight checks for kubectl/helm and prints port-forward instructions for Tekton Dashboard.
- **seaweedfs-values.yaml**: Single-node dev deployment with S3 enabled.
- **seaweedfs-secret.yaml**: Kubernetes Secret with S3 access credentials for SeaweedFS.
- **workspace-pvc.yaml**: 5Gi ReadWriteOnce PVC for shared workspace.
- **feature-flags-patch.yaml**: ConfigMap patch enabling `keep-pod-on-cancel: true` (prevents log loss) and `coschedule: workspaces` (Affinity Assistant for RWO PVC co-scheduling).

### Task 2: Tekton Pipeline and Task Definitions

Created the complete pipeline definition with 4 tasks and a manual trigger:

- **setup-generation**: Prepares workspace, conditionally fetches genome checkpoint from SeaweedFS via mc CLI when `resume-from` param is provided. Enables retraining from any previously stored checkpoint.
- **run-training**: Runs BizHawk NEAT training with Xvfb virtual framebuffer. Timeout set to "0" to prevent silent kills on long training runs. Outputs final generation number and best fitness score.
- **evaluate-champion**: Loads best genome and runs automated evaluation fights against CPU. Reports fitness score and win rate via task results.
- **store-results**: Uploads champion genome, population, and metadata JSON to SeaweedFS at `genomes/{run-id}/gen-{NNNN}/` path. Metadata includes run_id, generation, fitness, win_rate, date (ISO 8601), and opponent.
- **pipeline.yaml**: Wires 4 tasks sequentially with proper result passing between tasks. Includes comment placeholder for finally block (added by 04-02).
- **pipelinerun.yaml**: Manual trigger template with `timeouts.pipeline: "0"` and volumeClaimTemplate for ephemeral workspace.

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| 1 | 318b837 | K8s infrastructure manifests and install script |
| 2 | db4edf4 | Tekton Pipeline, Task definitions, PipelineRun trigger |

## Deviations from Plan

None - plan executed exactly as written.

## Decisions Made

1. **Tekton v1.9.0 LTS with v1 API**: Latest LTS release, stable API, supports Matrix, timeout overrides, keep-pod-on-cancel.
2. **SeaweedFS over MinIO**: Apache 2.0 license, MinIO community binaries no longer distributed since 2025.
3. **mc CLI for S3 operations**: Purpose-built, lighter than aws-cli, works with SeaweedFS S3v4.
4. **Genome path convention `genomes/{run-id}/gen-{NNNN}/`**: Enables retrieval by version, listing by prefix, and zero-pad ordering.
5. **volumeClaimTemplate (ephemeral) + SeaweedFS (persistent)**: PVC workspace is ephemeral per PipelineRun; store-results copies to SeaweedFS for cross-run persistence.

## Verification Results

- All 11 YAML files parse correctly (validated with Ruby YAML parser)
- install.sh is executable and references Tekton v1.9.0 LTS
- Feature flags ConfigMap has both keep-pod-on-cancel and coschedule set
- Pipeline has 4 tasks with correct runAfter ordering
- run-training task has timeout "0" in pipeline definition
- PipelineRun has timeouts.pipeline "0"
- store-results creates metadata.json with all required tags
- setup-generation conditionally fetches from SeaweedFS
- SeaweedFS credentials referenced via secretKeyRef in both setup-generation and store-results

## Self-Check: PASSED

All 11 created files verified present on disk. Both commit hashes (318b837, db4edf4) verified in git log.
