---
phase: 04-tekton-pipeline-mlops
plan: 02
subsystem: tekton-distributed-evaluation
tags: [tekton, matrix, fan-out, triggers, pipelinerun-chaining, distributed-evaluation]
dependency-graph:
  requires: [04-01]
  provides: [distributed-evaluation, pipelinerun-chaining, continuation-triggers]
  affects: [pipeline.yaml, pipelinerun.yaml]
tech-stack:
  added: [tekton-triggers, tekton-matrix]
  patterns: [matrix-fan-out, eventlistener-chaining, finally-task-gating]
key-files:
  created:
    - k8s/tekton/tasks/evaluate-genome.yaml
    - k8s/tekton/tasks/aggregate-fitness.yaml
    - k8s/tekton/tasks/decide-continue.yaml
    - k8s/tekton/triggers/event-listener.yaml
    - k8s/tekton/triggers/trigger-template.yaml
    - k8s/tekton/triggers/trigger-binding.yaml
    - k8s/tekton/triggers/rbac.yaml
  modified:
    - k8s/tekton/pipeline.yaml
decisions:
  - "Used inline taskSpec for get-genome-list to keep it tightly coupled with the pipeline rather than a separate Task definition"
  - "Added when expression on decide-continue to only trigger continuation if store-results succeeded"
  - "Used alpine image with shell-based aggregation instead of heavier tooling for aggregate-fitness"
metrics:
  duration: "2m 21s"
  completed: "2026-03-05T21:37:18Z"
  tasks-completed: 2
  tasks-total: 2
  files-created: 7
  files-modified: 1
---

# Phase 4 Plan 2: Distributed Evaluation Fan-Out and PipelineRun Chaining Summary

Tekton Matrix fan-out for parallel genome evaluation across pods with EventListener-based PipelineRun chaining for automatic training continuation.

## What Was Built

### Task 1: Distributed Evaluation with Matrix Fan-Out

Created three new pipeline stages replacing the single-pod evaluate-champion pattern:

1. **evaluate-genome Task** - Evaluates a single genome in its own pod. Each genome gets a unique results subdirectory to avoid workspace conflicts during parallel execution. Used as the Matrix fan-out unit.

2. **aggregate-fitness Task** - Collects fitness scores and genome IDs from all parallel evaluations via array params. Finds the best genome, computes average fitness, and writes results.

3. **get-genome-list inline task** - Reads the population directory after training and outputs genome IDs as an array result for Matrix consumption.

4. **Pipeline updates** - Added `get-genome-list -> distributed-eval (Matrix) -> aggregate-results` flow. The original evaluate-champion is preserved as a commented alternative for resource-constrained clusters. store-results now reads from aggregate-results.

### Task 2: PipelineRun Chaining via Tekton Triggers

Created the full Tekton Triggers stack for automatic training continuation:

1. **decide-continue Task** - Compares best fitness against threshold. If below, POSTs to `el-training-continuation.default:8080` with run-id and resume-from path. Used in the pipeline's `finally` block with a `when` expression gating on store-results success.

2. **EventListener** - `training-continuation` listens for continuation events using the triggers SA.

3. **TriggerTemplate** - Creates a new PipelineRun with `generateName: saiyan-training-`, inheriting run-id and resume-from params, 5Gi workspace, and `timeouts.pipeline: "0"`.

4. **TriggerBinding** - Extracts `run-id` and `resume-from` from the HTTP POST body.

5. **RBAC** - ServiceAccount `tekton-triggers-sa` with ClusterRole granting minimum permissions: create/get/list pipelineruns, get/list pipelines, and read access to triggers resources.

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| 1 | f379e86 | Distributed evaluation tasks and Matrix fan-out pipeline |
| 2 | 93aabbc | PipelineRun chaining via Tekton Triggers |

## Deviations from Plan

None - plan executed exactly as written.

## Decisions Made

1. **Inline taskSpec for get-genome-list** - Used inline taskSpec in the pipeline rather than a separate Task YAML file. This task is tightly coupled to the pipeline's internal structure and unlikely to be reused elsewhere.

2. **When expression on decide-continue** - Added `when: input=$(tasks.store-results.status) operator=in values=["Succeeded"]` to prevent triggering continuation when the pipeline failed before storing results. This follows the RESEARCH.md guidance about finally tasks running regardless of success/failure.

3. **Shell-based aggregation** - Used pure shell arithmetic in aggregate-fitness instead of installing jq or other tools. Keeps the image lightweight (alpine) and avoids additional dependencies for simple integer comparison.

## Verification

All automated checks passed:
- evaluate-genome.yaml exists with `evaluate-genome` task name
- aggregate-fitness.yaml exists with `aggregate-fitness` task name
- pipeline.yaml contains `matrix` configuration
- pipeline.yaml contains `fitness-score[*]` result aggregation
- decide-continue.yaml exists with `curl` for EventListener POST
- All trigger resources exist with correct names
- RBAC ServiceAccount `tekton-triggers-sa` configured
- Pipeline `finally` block wired with `decide-continue`

## Self-Check: PASSED

All 7 created files verified present on disk. Both commit hashes (f379e86, 93aabbc) verified in git log.
