---
phase: 04-tekton-pipeline-mlops
plan: 03
subsystem: observability-and-documentation
tags: [prometheus, grafana, pushgateway, dashboards, readme, tekton-dashboard]
dependency-graph:
  requires: [04-01]
  provides: [observability-stack, project-documentation]
  affects: [run-training-task, install-script, pipeline]
tech-stack:
  added: [kube-prometheus-stack, prometheus-pushgateway, grafana-dashboards, k8s-sidecar]
  patterns: [pushgateway-metrics-push, configmap-dashboard-provisioning, honor-labels-scrape]
key-files:
  created:
    - k8s/observability/pushgateway-values.yaml
    - k8s/observability/prometheus-scrape-patch.yaml
    - k8s/observability/grafana/datasource.yaml
    - k8s/observability/grafana/dashboards/fitness-curves.json
    - k8s/observability/grafana/dashboards/species-diversity.json
    - k8s/observability/grafana/dashboards/evaluation-results.json
    - k8s/observability/grafana/dashboard-configmaps.yaml
  modified:
    - k8s/tekton/tasks/run-training.yaml
    - k8s/tekton/pipeline.yaml
    - k8s/setup/install.sh
    - README.md
decisions:
  - "Pushgateway with run_id grouping key to isolate stale metrics from old runs"
  - "Dashboard ConfigMaps with grafana_dashboard label for k8s-sidecar auto-provisioning"
  - "Fight replay recording deferred as stretch goal TODO due to container AVI uncertainty"
  - "honor_labels: true in Prometheus scrape config to preserve Pushgateway labels"
metrics:
  duration: "5m 17s"
  completed: "2026-03-06T21:40:06Z"
  tasks: 2
  files-created: 7
  files-modified: 4
---

# Phase 4 Plan 3: Observability Stack and README Summary

Prometheus Pushgateway + Grafana dashboards for NEAT training observability, with three auto-provisioned dashboards (fitness curves, species diversity, evaluation results) and a comprehensive project README covering setup through deployment.

## What Was Done

### Task 1: Observability Stack Manifests and Metrics Integration

Created the full observability stack:

**Pushgateway deployment** (`pushgateway-values.yaml`): Minimal Helm values with serviceMonitor enabled. Persistence disabled since Pushgateway is a transient metrics cache.

**Prometheus scrape config** (`prometheus-scrape-patch.yaml`): Additional scrape config with `honor_labels: true` to preserve run_id labels pushed by training pods. Includes exact helm upgrade command as a comment.

**Grafana datasource** (`datasource.yaml`): ConfigMap with `grafana_datasource: "1"` label pointing to kube-prometheus-stack's Prometheus instance.

**Three Grafana dashboards** (fitness-curves.json, species-diversity.json, evaluation-results.json): Full Grafana dashboard JSON with proper schema (v39), `__inputs`, `__requires`, templating variables for run_id filtering, and grid-positioned panels:
- Fitness Curves: max fitness timeseries, avg fitness timeseries, generation stat panel
- Species Diversity: species count timeseries, population size stat panel
- Evaluation Results: win rate bar gauge, total fights stat, best fitness timeseries

**Dashboard ConfigMaps** (`dashboard-configmaps.yaml`): Three ConfigMaps embedding the dashboard JSONs with `grafana_dashboard: "1"` label for k8s-sidecar auto-provisioning.

**run-training task update**: Added `push-metrics` step using curlimages/curl that reads training output files and pushes to Pushgateway with run_id grouping key. Added `run-id` param. Documented fight replay recording as stretch goal TODO (OBS-05).

**Pipeline update**: Added run-id param passthrough to run-training task.

**install.sh update**: Added kube-prometheus-stack, Pushgateway, datasource, and dashboard ConfigMap installation. Added Grafana and Prometheus port-forward instructions to summary output.

### Task 2: Comprehensive README

Replaced the stub README with full project documentation:
- Project overview with architecture ASCII diagram
- Prerequisites (K8s 1.28+, kubectl, helm, Docker, ROM, BizHawk)
- 8-step Quick Start guide from clone to running pipeline
- Local development guide (BizHawk without K8s)
- Four-layer architecture (emulation, orchestration, storage, observability)
- Pipeline flow with fan-out and chaining
- Configuration reference tables (pipeline params, container env, SeaweedFS)
- Observability section with dashboard and metrics reference
- Memory address discovery link to docs/MEMORY_MAP.md
- Project structure tree
- Strategic goal: Tekton ML toolkit discovery vehicle
- Contributing guide and acknowledgments

## Deviations from Plan

None - plan executed exactly as written.

## Decisions Made

1. **Pushgateway grouping key uses run_id**: Ensures stale metrics from completed runs do not pollute current dashboards. Pushgateway never forgets metrics, so the run_id label is essential for filtering.

2. **Dashboard JSON files stored separately from ConfigMaps**: The JSON files exist in `dashboards/` for version control readability. The ConfigMaps embed them for Kubernetes-native provisioning. Both are committed.

3. **Fight replay recording deferred (OBS-05)**: Documented as a TODO comment in run-training.yaml rather than implementing, per RESEARCH.md open question about container AVI recording reliability with Xvfb.

4. **honor_labels in Prometheus scrape config**: Required so Prometheus does not overwrite the job and run_id labels pushed by training pods to Pushgateway.

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| 1 | `51a73d9` | Observability stack manifests, dashboards, metrics push integration |
| 2 | `09bc527` | Comprehensive project README |

## Self-Check: PASSED

All 8 created files verified present. Both commit hashes (51a73d9, 09bc527) found in git log.
