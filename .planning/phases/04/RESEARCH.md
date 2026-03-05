# Phase 4: Tekton Pipeline and MLOps - Research

**Researched:** 2026-03-06
**Domain:** Tekton Pipelines orchestration, distributed evaluation, model versioning, observability (Prometheus/Grafana), object storage (SeaweedFS)
**Confidence:** HIGH

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| TKN-01 | Tekton Pipeline definition with setup, train, evaluate, store tasks | Pipeline YAML structure, Pipelines-in-Pipelines, workspace configuration (see Architecture Patterns) |
| TKN-02 | Training Task runs containerized BizHawk NEAT for N generations per PipelineRun | Task step definitions, BizHawk container image as step image, workspace mounts (see Code Examples) |
| TKN-03 | Evaluation Task loads best genome and runs automated fights, reports win rate | Task results for win rate, params for genome path, reuse BizHawk image (see Code Examples) |
| TKN-04 | Storage Task copies genome artifacts to persistent object storage | mc CLI in alpine image, SeaweedFS S3 endpoint, tagging conventions (see Code Examples) |
| TKN-05 | Pipeline can be triggered manually via PipelineRun | PipelineRun YAML with params and workspace bindings (see Code Examples) |
| TKN-06 | Pipeline timeout configured for long-running training (no silent kills) | timeouts.pipeline: "0", keep-pod-on-cancel feature flag (see Common Pitfalls) |
| TKN-07 | Tasks share data via PVC workspace with proper affinity configuration | coschedule: workspaces, ReadWriteOnce PVC, Affinity Assistant (see Architecture Patterns) |
| RET-01 | New PipelineRun can resume training from a previously stored genome checkpoint | setup-generation task pulls from SeaweedFS, passes via workspace (see Architecture Patterns) |
| RET-02 | Each training run's best genome is tagged with generation, fitness, opponent, and date | S3 object path convention + metadata JSON sidecar (see Code Examples) |
| RET-03 | Stored genomes are retrievable by version tag from object storage | mc cp from SeaweedFS by path, listing by prefix (see Code Examples) |
| RET-04 | PipelineRun chaining auto-continues training when fitness threshold not met | finally block + curl to EventListener pattern (see Architecture Patterns) |
| DIST-01 | Multiple genomes can be evaluated in parallel across separate pods | Tekton Matrix fan-out on genome list (see Architecture Patterns) |
| DIST-02 | Fan-out pattern in Tekton distributes genome evaluations | Matrix params with genome IDs, parallel TaskRuns (see Code Examples) |
| DIST-03 | Results from parallel evaluations are aggregated back into the population | Matrix result aggregation with [*] notation (see Code Examples) |
| OBS-01 | Prometheus Pushgateway receives training metrics from batch jobs | Pushgateway deployment, curl-based push from task steps (see Code Examples) |
| OBS-02 | Grafana dashboard shows fitness curves over generations | Dashboard JSON in ConfigMap, Prometheus datasource provisioning (see Code Examples) |
| OBS-03 | Grafana dashboard shows species count and population diversity | Same dashboard provisioning pattern as OBS-02 |
| OBS-04 | Grafana dashboard shows evaluation win rates | Same dashboard provisioning pattern as OBS-02 |
| OBS-05 | BizHawk can record fight replays of best genome as video | BizHawk AVI recording via Lua script, stored as artifact in SeaweedFS (see Open Questions) |
| OBS-06 | Tekton Dashboard installed and shows pipeline runs | Single kubectl apply install, port-forward for access (see Standard Stack) |
| DX-01 | README documents project setup, ROM sourcing, and local development | Documentation task, no specific research needed |
</phase_requirements>

## Summary

Phase 4 wires the containerized BizHawk training (from Phase 3) into a full Tekton-orchestrated MLOps pipeline on Kubernetes. The core deliverables are: a Tekton Pipeline with setup/train/evaluate/store tasks sharing a PVC workspace, SeaweedFS for versioned genome storage, Prometheus Pushgateway + Grafana for training observability, distributed genome evaluation via Tekton's Matrix fan-out, and PipelineRun chaining for automatic training continuation.

Tekton Pipelines v1.9.0 LTS (February 2026) provides all necessary features: Pipeline/Task/PipelineRun v1 API, Matrix for fan-out (TEP-0090), Pipelines-in-Pipelines (TEP-0056, alpha), workspace affinity assistant (coschedule), task timeout overrides, and keep-pod-on-cancel for debugging failed training runs. The timeout configuration is the single most critical configuration item -- Tekton defaults to 1-hour timeouts that will silently kill training pods.

SeaweedFS replaces MinIO as the S3-compatible object store (MinIO community binaries are no longer distributed since 2025). The MinIO `mc` CLI works with SeaweedFS's S3 API for bucket operations. Prometheus Pushgateway is the standard pattern for batch job metrics -- training pods push metrics via curl, Prometheus scrapes the Pushgateway. Grafana dashboards are provisioned via ConfigMaps with the kiwigrid/k8s-sidecar pattern.

**Primary recommendation:** Build the pipeline incrementally -- first a linear Pipeline (setup, train, evaluate, store) with manual PipelineRun trigger, then add Matrix fan-out for distributed evaluation, then PipelineRun chaining via EventListener, and finally the observability stack.

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Tekton Pipelines | v1.9.0 LTS | Pipeline orchestration | Latest LTS (Feb 2026), stable v1 API, Matrix support, Pipelines-in-Pipelines |
| Tekton Dashboard | latest | Pipeline run visualization | Official Tekton UI, zero-config visibility into runs |
| Tekton Triggers | latest | Event-driven PipelineRun creation | Required for PipelineRun chaining (auto-continuation) |
| SeaweedFS | latest | S3-compatible object storage for genomes | Apache 2.0, Kubeflow default since 2.15, replaces MinIO |
| Prometheus | latest (kube-prometheus-stack) | Metrics collection | Standard K8s observability |
| Prometheus Pushgateway | latest | Batch job metrics receiver | Official pattern for ephemeral/batch jobs |
| Grafana | latest (via kube-prometheus-stack) | Dashboard visualization | Standard K8s observability |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| mc (MinIO Client) | latest | S3 CLI for genome upload/download in Tasks | Every store/retrieve task step |
| curl | (in task images) | Push metrics to Pushgateway, trigger EventListener | Metrics push and PipelineRun chaining |
| kubectl/tkn | latest | Create PipelineRuns from finally tasks | PipelineRun chaining alternative to EventListener |
| kiwigrid/k8s-sidecar | latest | Auto-load Grafana dashboards from ConfigMaps | Dashboard provisioning |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| SeaweedFS | MinIO | MinIO community binaries no longer distributed (2025 licensing change); SeaweedFS is Apache 2.0 |
| mc CLI | aws-cli | aws-cli works with SeaweedFS S3 API but is heavier; mc is purpose-built |
| Pushgateway | OpenTelemetry Collector | OTEL is more modern but adds complexity; Pushgateway is simpler for this use case |
| Tekton Triggers (for chaining) | kubectl create PipelineRun in finally task | Simpler but less observable; Triggers provides audit trail |
| ConfigMap dashboard provisioning | Grafana API | ConfigMaps are declarative, GitOps-friendly; API is imperative |

**Installation:**
```bash
# Tekton Pipelines v1.9.0 LTS
kubectl apply -f https://infra.tekton.dev/releases/pipeline/previous/v1.9.0/release.yaml

# Tekton Dashboard
kubectl apply -f https://infra.tekton.dev/tekton-releases/dashboard/latest/release.yaml

# Tekton Triggers
kubectl apply -f https://storage.googleapis.com/tekton-releases/triggers/latest/release.yaml

# SeaweedFS via Helm
helm repo add seaweedfs https://seaweedfs.github.io/helm-chart/
helm install seaweedfs seaweedfs/seaweedfs \
    --set master.replicas=1 \
    --set volume.replicas=1 \
    --set s3.enabled=true

# Prometheus + Grafana (kube-prometheus-stack)
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install monitoring prometheus-community/kube-prometheus-stack

# Prometheus Pushgateway
helm install pushgateway prometheus-community/prometheus-pushgateway
```

## Architecture Patterns

### Recommended Project Structure
```
k8s/
├── tekton/
│   ├── pipeline.yaml              # Main training pipeline
│   ├── tasks/
│   │   ├── setup-generation.yaml  # Pull genome, prepare workspace
│   │   ├── run-training.yaml      # BizHawk NEAT training
│   │   ├── evaluate-champion.yaml # Evaluation fights
│   │   ├── store-results.yaml     # Upload to SeaweedFS
│   │   └── decide-continue.yaml   # Check threshold, trigger next
│   ├── triggers/
│   │   ├── event-listener.yaml    # Receives continuation events
│   │   ├── trigger-template.yaml  # Creates new PipelineRun
│   │   └── trigger-binding.yaml   # Extracts params from event
│   └── pipelinerun.yaml           # Manual trigger template
├── storage/
│   ├── seaweedfs-values.yaml      # SeaweedFS Helm values
│   └── workspace-pvc.yaml         # Persistent workspace PVC
├── observability/
│   ├── pushgateway.yaml           # Pushgateway deployment
│   ├── prometheus-scrape.yaml     # Scrape config for Pushgateway
│   └── grafana/
│       ├── datasource.yaml        # Prometheus datasource ConfigMap
│       └── dashboards/
│           ├── fitness-curves.json     # Fitness over generations
│           ├── species-diversity.json  # Species count dashboard
│           └── evaluation-results.json # Win rate dashboard
└── setup/
    └── install.sh                 # One-script cluster setup
```

### Pattern 1: Linear Pipeline with Workspace Sharing
**What:** A Pipeline with sequential tasks (setup -> train -> evaluate -> store) sharing a single PVC workspace via Tekton's workspace mechanism. Each task reads from and writes to a shared directory.
**When to use:** Always -- this is the core pipeline structure.
**Example:**
```yaml
# Source: Tekton official docs - Pipelines
apiVersion: tekton.dev/v1
kind: Pipeline
metadata:
  name: saiyan-training-pipeline
spec:
  params:
    - name: run-id
      type: string
    - name: generations-per-batch
      type: string
      default: "50"
    - name: resume-from
      type: string
      default: ""
      description: "S3 path to genome checkpoint to resume from (empty for fresh start)"
    - name: fitness-threshold
      type: string
      default: "5000"
  workspaces:
    - name: shared-workspace
  tasks:
    - name: setup-generation
      taskRef:
        name: setup-generation
      workspaces:
        - name: workspace
          workspace: shared-workspace
      params:
        - name: run-id
          value: $(params.run-id)
        - name: resume-from
          value: $(params.resume-from)
    - name: run-training
      taskRef:
        name: run-training
      runAfter:
        - setup-generation
      timeout: "0"
      workspaces:
        - name: workspace
          workspace: shared-workspace
      params:
        - name: generations
          value: $(params.generations-per-batch)
    - name: evaluate-champion
      taskRef:
        name: evaluate-champion
      runAfter:
        - run-training
      workspaces:
        - name: workspace
          workspace: shared-workspace
    - name: store-results
      taskRef:
        name: store-results
      runAfter:
        - evaluate-champion
      workspaces:
        - name: workspace
          workspace: shared-workspace
      params:
        - name: run-id
          value: $(params.run-id)
        - name: generation
          value: $(tasks.run-training.results.final-generation)
        - name: fitness
          value: $(tasks.evaluate-champion.results.best-fitness)
        - name: win-rate
          value: $(tasks.evaluate-champion.results.win-rate)
  finally:
    - name: decide-continue
      taskRef:
        name: decide-continue
      params:
        - name: win-rate
          value: $(tasks.evaluate-champion.results.win-rate)
        - name: fitness-threshold
          value: $(params.fitness-threshold)
        - name: run-id
          value: $(params.run-id)
        - name: latest-genome-path
          value: $(tasks.store-results.results.genome-s3-path)
```

### Pattern 2: Matrix Fan-Out for Distributed Evaluation
**What:** Use Tekton Matrix to evaluate multiple genomes in parallel across separate pods. Each genome gets its own pod running BizHawk evaluation fights.
**When to use:** For DIST-01/02/03 -- distributing genome evaluation across pods.
**Example:**
```yaml
# Source: Tekton official docs - Matrix
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: evaluate-genome
spec:
  params:
    - name: genome-id
      type: string
  results:
    - name: fitness-score
      description: Fitness score for this genome
  workspaces:
    - name: workspace
  steps:
    - name: evaluate
      image: saiyan-trainer/bizhawk:latest
      script: |
        #!/bin/bash
        xvfb-run /opt/bizhawk/EmuHawkMono.sh \
          --lua=/workspace/evaluate_single.lua \
          -- $(params.genome-id) \
          /workspace/rom.gba
        cat /workspace/results/$(params.genome-id)/fitness.txt \
          | tee $(results.fitness-score.path)
---
# In the Pipeline, fan out evaluation:
tasks:
  - name: distributed-eval
    taskRef:
      name: evaluate-genome
    matrix:
      params:
        - name: genome-id
          value: $(tasks.get-genome-list.results.genome-ids[*])
    workspaces:
      - name: workspace
        workspace: shared-workspace
  - name: aggregate-results
    taskRef:
      name: aggregate-fitness
    runAfter:
      - distributed-eval
    params:
      - name: fitness-scores
        value: $(tasks.distributed-eval.results.fitness-score[*])
```

### Pattern 3: PipelineRun Chaining via EventListener
**What:** When training has not met the fitness threshold, a finally task sends an HTTP event to a Tekton EventListener, which creates a new PipelineRun pointing to the latest genome checkpoint.
**When to use:** For RET-04 -- automatic training continuation.
**Example:**
```yaml
# Source: Tekton Triggers docs
apiVersion: triggers.tekton.dev/v1beta1
kind: EventListener
metadata:
  name: training-continuation
spec:
  serviceAccountName: tekton-triggers-sa
  triggers:
    - name: continue-training
      bindings:
        - ref: training-continuation-binding
      template:
        ref: training-continuation-template
---
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerTemplate
metadata:
  name: training-continuation-template
spec:
  params:
    - name: run-id
    - name: resume-from
  resourcetemplates:
    - apiVersion: tekton.dev/v1
      kind: PipelineRun
      metadata:
        generateName: saiyan-training-
      spec:
        pipelineRef:
          name: saiyan-training-pipeline
        params:
          - name: run-id
            value: $(tt.params.run-id)
          - name: resume-from
            value: $(tt.params.resume-from)
        workspaces:
          - name: shared-workspace
            volumeClaimTemplate:
              spec:
                accessModes:
                  - ReadWriteOnce
                resources:
                  requests:
                    storage: 5Gi
        timeouts:
          pipeline: "0"
---
# In the decide-continue finally task:
steps:
  - name: trigger-next
    image: curlimages/curl:latest
    script: |
      #!/bin/sh
      WIN_RATE=$(params.win-rate)
      THRESHOLD=$(params.fitness-threshold)
      if [ "$WIN_RATE" -lt "$THRESHOLD" ]; then
        curl -X POST http://el-training-continuation.tekton-pipelines:8080 \
          -H "Content-Type: application/json" \
          -d "{\"run-id\": \"$(params.run-id)\", \"resume-from\": \"$(params.latest-genome-path)\"}"
        echo "Triggered continuation PipelineRun"
      else
        echo "Fitness threshold met. Training complete."
      fi
```

### Pattern 4: Timeout and Keep-Pod Configuration
**What:** Configure Tekton to never silently kill long-running training and retain pods for debugging.
**When to use:** Always -- must be configured before first training run.
**Example:**
```yaml
# Source: Tekton additional-configs docs
# Step 1: Enable keep-pod-on-cancel in feature-flags ConfigMap
apiVersion: v1
kind: ConfigMap
metadata:
  name: feature-flags
  namespace: tekton-pipelines
data:
  keep-pod-on-cancel: "true"
  coschedule: "workspaces"
---
# Step 2: Set timeout to 0 (disabled) on PipelineRun
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  name: saiyan-training-run-001
spec:
  pipelineRef:
    name: saiyan-training-pipeline
  timeouts:
    pipeline: "0"
  taskRunSpecs:
    - pipelineTaskName: run-training
      timeout: "0"
```

### Anti-Patterns to Avoid
- **One Task per generation:** Each Task creates a new pod. BizHawk startup (Mono boot + ROM load) takes seconds. Batch 50+ generations per Task instead.
- **Storing genomes only in PVC workspace:** volumeClaimTemplate PVCs are deleted with the PipelineRun. Always copy to SeaweedFS in the store-results task.
- **Using results for large data:** Tekton results are limited to 4096 bytes. Pass file paths via results; pass actual genome data via workspace files.
- **Disabling Affinity Assistant on RWO PVCs:** Without the Affinity Assistant, tasks on different nodes cannot mount the same RWO PVC, causing scheduling deadlocks.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| S3-compatible object storage | Custom file server or NFS for genomes | SeaweedFS with Helm chart | S3 API is standard, mc CLI works out of the box, versioning by path convention |
| Batch job metrics collection | Custom metrics endpoint in Lua | Prometheus Pushgateway + curl | Standard K8s pattern, Grafana integration out of the box |
| Dashboard provisioning | Manual Grafana UI dashboard creation | ConfigMap + k8s-sidecar auto-provisioning | Declarative, version-controlled, survives pod restarts |
| Pipeline continuation logic | Custom Kubernetes controller | Tekton Triggers EventListener + TriggerTemplate | Battle-tested, provides audit trail, official Tekton component |
| Fan-out parallel evaluation | Custom Job controller or shell loop | Tekton Matrix (TEP-0090) | Native Tekton feature, result aggregation built in |
| Pipeline run visualization | Custom web UI | Tekton Dashboard (kubectl apply) | Zero-effort install, shows logs/status/history |

**Key insight:** Phase 4 is almost entirely "assembly" of well-established Kubernetes and Tekton patterns. The only custom code is the glue scripts in task steps (shell scripts that invoke mc, curl, and BizHawk). Do not build infrastructure that already exists.

## Common Pitfalls

### Pitfall 1: Tekton Default Timeout Kills Long-Running Training
**What goes wrong:** Tekton PipelineRuns default to 1-hour timeout. Training runs taking hours are silently killed, pods deleted, logs lost.
**Why it happens:** Tekton is designed for CI/CD (minutes), not ML training (hours). Both pipeline-level AND task-level timeouts must be configured.
**How to avoid:** Set `timeouts.pipeline: "0"` on PipelineRun AND `timeout: "0"` on the run-training task. Enable `keep-pod-on-cancel: "true"` in the feature-flags ConfigMap so timed-out pods retain logs.
**Warning signs:** TaskRun status shows "TaskRunTimeout" after exactly 1 hour with no logs.

### Pitfall 2: PVC Workspace Scheduling Deadlocks
**What goes wrong:** Tasks sharing a ReadWriteOnce PVC get scheduled on different nodes. Second task hangs in Pending with "volume node affinity conflict."
**Why it happens:** Kubernetes scheduler does not inherently co-locate pods needing the same PVC. Cloud PVs are often zonal.
**How to avoid:** Use Tekton's Affinity Assistant (`coschedule: "workspaces"` in feature-flags, enabled by default). For cross-run persistence, use a separate pre-provisioned ReadWriteMany PVC or object storage (SeaweedFS), not the workspace PVC.
**Warning signs:** Pods stuck in Pending; PipelineRun works on single-node cluster but fails on multi-node.

### Pitfall 3: Pushgateway Stale Metrics
**What goes wrong:** Pushgateway never forgets pushed metrics. Old training run metrics persist and show up in Grafana after the training pod is gone.
**Why it happens:** Pushgateway is a cache, not an aggregator. It exposes pushed metrics to Prometheus forever unless manually deleted.
**How to avoid:** Include `run-id` and `generation` labels in pushed metrics. Add a cleanup step in the store-results task that deletes the Pushgateway group after metrics are scraped. Use `honor_labels: true` in Prometheus scrape config.
**Warning signs:** Grafana shows flat lines for old runs; metric cardinality grows unbounded.

### Pitfall 4: Results Size Limit
**What goes wrong:** Trying to pass genome JSON through Tekton results (limited to 4096 bytes) causes TaskRun failure.
**Why it happens:** Tekton results are stored in the TaskRun status (etcd), not designed for large payloads.
**How to avoid:** Pass file paths and small scalar values (fitness score, generation number, win rate, S3 path) through results. Pass actual genome data through the shared workspace filesystem.
**Warning signs:** TaskRun fails with "result exceeded max size" error.

### Pitfall 5: SeaweedFS S3 Signature Version
**What goes wrong:** mc or aws-cli fails to authenticate with SeaweedFS S3 endpoint.
**Why it happens:** SeaweedFS supports AWS Signature V4 but older S3 clients may default to V2.
**How to avoid:** Use `mc alias set` with `--api S3v4` flag. Configure SeaweedFS IAM with access/secret keys matching your mc alias.
**Warning signs:** 403 Forbidden or SignatureDoesNotMatch errors from S3 operations.

### Pitfall 6: Finally Tasks Cannot Access Workspace
**What goes wrong:** The decide-continue task in the finally block needs results from previous tasks but cannot access the workspace.
**Why it happens:** Finally tasks can access workspaces, but they run regardless of task success/failure. If a task fails before writing results, the finally task reads stale data.
**How to avoid:** Use task results (not workspace files) for the small values the decide-continue task needs (win-rate, fitness, genome path). Check `$(tasks.evaluate-champion.status)` with when expressions.
**Warning signs:** Continuation triggered with wrong genome path or stale fitness score.

## Code Examples

Verified patterns from official sources:

### Task with Results and Params (setup-generation)
```yaml
# Source: Tekton Tasks docs
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: setup-generation
spec:
  params:
    - name: run-id
      type: string
    - name: resume-from
      type: string
      default: ""
  results:
    - name: population-initialized
      description: "true if population was loaded from checkpoint"
  workspaces:
    - name: workspace
  steps:
    - name: fetch-checkpoint
      image: minio/mc:latest
      script: |
        #!/bin/bash
        mc alias set swfs http://seaweedfs-s3:8333 "$ACCESS_KEY" "$SECRET_KEY" --api S3v4
        RESUME="$(params.resume-from)"
        if [ -n "$RESUME" ]; then
          mc cp "swfs/$RESUME" /workspace/checkpoint/
          echo "true" | tee $(results.population-initialized.path)
        else
          echo "false" | tee $(results.population-initialized.path)
        fi
      env:
        - name: ACCESS_KEY
          valueFrom:
            secretKeyRef:
              name: seaweedfs-creds
              key: access-key
        - name: SECRET_KEY
          valueFrom:
            secretKeyRef:
              name: seaweedfs-creds
              key: secret-key
```

### Store Results with Genome Tagging
```yaml
# Source: Tekton Tasks docs + mc CLI docs
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: store-results
spec:
  params:
    - name: run-id
      type: string
    - name: generation
      type: string
    - name: fitness
      type: string
    - name: win-rate
      type: string
  results:
    - name: genome-s3-path
      description: "S3 path to stored champion genome"
  workspaces:
    - name: workspace
  steps:
    - name: tag-and-upload
      image: minio/mc:latest
      script: |
        #!/bin/bash
        mc alias set swfs http://seaweedfs-s3:8333 "$ACCESS_KEY" "$SECRET_KEY" --api S3v4

        RUN_ID="$(params.run-id)"
        GEN="$(params.generation)"
        FITNESS="$(params.fitness)"
        WIN_RATE="$(params.win-rate)"
        DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)

        # Create metadata sidecar
        cat > /workspace/metadata.json <<METADATA
        {
          "run_id": "$RUN_ID",
          "generation": $GEN,
          "fitness": $FITNESS,
          "win_rate": $WIN_RATE,
          "date": "$DATE",
          "opponent": "cpu-normal"
        }
        METADATA

        S3_PATH="genomes/$RUN_ID/gen-$(printf '%04d' $GEN)"
        mc cp /workspace/champion.json "swfs/saiyan-trainer/$S3_PATH/champion.json"
        mc cp /workspace/metadata.json "swfs/saiyan-trainer/$S3_PATH/metadata.json"
        mc cp /workspace/population.json "swfs/saiyan-trainer/$S3_PATH/population.json"

        echo "saiyan-trainer/$S3_PATH/champion.json" | tee $(results.genome-s3-path.path)
      env:
        - name: ACCESS_KEY
          valueFrom:
            secretKeyRef:
              name: seaweedfs-creds
              key: access-key
        - name: SECRET_KEY
          valueFrom:
            secretKeyRef:
              name: seaweedfs-creds
              key: secret-key
```

### Push Metrics to Pushgateway
```bash
# Source: Prometheus Pushgateway docs
# Called from a step in run-training task after BizHawk completes

# Push training metrics
cat <<EOF | curl --data-binary @- http://pushgateway.monitoring:9091/metrics/job/neat-training/run_id/${RUN_ID}
# HELP neat_generation Current NEAT generation number
# TYPE neat_generation gauge
neat_generation ${GENERATION}
# HELP neat_fitness_max Highest fitness in current generation
# TYPE neat_fitness_max gauge
neat_fitness_max ${MAX_FITNESS}
# HELP neat_fitness_avg Average fitness across population
# TYPE neat_fitness_avg gauge
neat_fitness_avg ${AVG_FITNESS}
# HELP neat_species_count Number of active species
# TYPE neat_species_count gauge
neat_species_count ${SPECIES_COUNT}
EOF
```

### Prometheus Scrape Config for Pushgateway
```yaml
# Source: Prometheus docs
# Add to prometheus values or scrape config
scrape_configs:
  - job_name: "pushgateway"
    honor_labels: true
    static_configs:
      - targets: ["pushgateway.monitoring.svc:9091"]
```

### Grafana Dashboard ConfigMap
```yaml
# Source: Grafana provisioning docs
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboard-fitness
  labels:
    grafana_dashboard: "1"   # Picked up by k8s-sidecar
data:
  fitness-curves.json: |
    {
      "dashboard": {
        "title": "Saiyan Trainer - Fitness Curves",
        "panels": [
          {
            "title": "Max Fitness Over Generations",
            "type": "timeseries",
            "targets": [
              {
                "expr": "neat_fitness_max",
                "legendFormat": "Run {{run_id}}"
              }
            ]
          },
          {
            "title": "Species Count",
            "type": "timeseries",
            "targets": [
              {
                "expr": "neat_species_count",
                "legendFormat": "Run {{run_id}}"
              }
            ]
          }
        ]
      }
    }
```

### Manual PipelineRun Trigger
```yaml
# Source: Tekton PipelineRuns docs
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  name: saiyan-training-run-001
spec:
  pipelineRef:
    name: saiyan-training-pipeline
  params:
    - name: run-id
      value: "run-001"
    - name: generations-per-batch
      value: "50"
    - name: resume-from
      value: ""
    - name: fitness-threshold
      value: "5000"
  workspaces:
    - name: shared-workspace
      volumeClaimTemplate:
        spec:
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: 5Gi
  timeouts:
    pipeline: "0"
```

### Matrix Result Aggregation
```yaml
# Source: Tekton Matrix docs
# Consuming aggregated results from fanned-out evaluation
tasks:
  - name: aggregate-fitness
    taskRef:
      name: aggregate-fitness-scores
    params:
      - name: all-fitness-scores
        value: $(tasks.distributed-eval.results.fitness-score[*])
      - name: all-genome-ids
        value: $(tasks.distributed-eval.results.genome-id[*])
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| MinIO for S3 storage | SeaweedFS | 2025 (MinIO licensing change) | SeaweedFS is Apache 2.0, now Kubeflow default |
| disable-affinity-assistant flag | coschedule feature flag | Tekton post-v0.68 | New flag with 4 modes: workspaces, pipelineruns, isolate-pipelinerun, disabled |
| Tekton v1beta1 API | Tekton v1 API | Tekton v1.0 (May 2025) | v1 is stable, use it for all resources |
| Pipeline-level timeout only | Task-level timeout overrides | Tekton v1.9.0 LTS | Can set per-task timeouts via taskRunSpecs |
| Manual dashboard creation | ConfigMap + k8s-sidecar provisioning | Grafana 7+ | Declarative, GitOps-compatible dashboard management |

**Deprecated/outdated:**
- `disable-affinity-assistant` feature flag: replaced by `coschedule` flag
- Tekton v1beta1 API: use v1
- MinIO community binaries: no longer distributed; use SeaweedFS or build MinIO from source

## Open Questions

1. **BizHawk fight replay recording as video**
   - What we know: BizHawk supports AVI recording via Lua API (`client.openrom`, `client.aviwrite`)
   - What's unclear: Whether Xvfb rendering in containers produces viewable AVI files, and file size implications
   - Recommendation: Implement as a stretch goal; store replay save states in SeaweedFS and render locally if container recording fails

2. **Pipelines-in-Pipelines stability**
   - What we know: TEP-0056 is available in v1.9.0 but requires `enable-api-fields: alpha`
   - What's unclear: Whether alpha status means production-ready for our use case
   - Recommendation: Use flat Pipeline definition for MVP; consider Pipelines-in-Pipelines for refactoring if the pipeline grows complex

3. **Matrix fan-out maximum concurrent pods**
   - What we know: Default max is 256 combinations; configurable via config-defaults ConfigMap
   - What's unclear: Cluster resource limits for running many BizHawk pods simultaneously (each needs ~1GB RAM)
   - Recommendation: Start with small fan-out (5-10 parallel evaluations), increase based on cluster capacity

4. **SeaweedFS IAM configuration**
   - What we know: SeaweedFS has embedded IAM with S3 API, AWS Signature V4 support
   - What's unclear: Exact configuration steps for creating access credentials in SeaweedFS Helm deployment
   - Recommendation: Use the Helm chart's secret configuration for S3 credentials; test mc alias connection early

## Sources

### Primary (HIGH confidence)
- [Tekton Pipelines v1.9.0 LTS Blog](https://tekton.dev/blog/2026/02/02/tekton-pipelines-v1.9.0-lts-continued-innovation-and-stability/) - LTS features, timeout overrides, keep-pod-on-cancel
- [Tekton Pipelines Docs](https://tekton.dev/docs/pipelines/pipelines/) - Pipeline YAML structure, workspaces, finally, when expressions
- [Tekton PipelineRuns Docs](https://tekton.dev/docs/pipelines/pipelineruns/) - Timeouts, workspace binding, taskRunSpecs
- [Tekton Tasks Docs](https://tekton.dev/docs/pipelines/tasks/) - Results, params, steps
- [Tekton Matrix Docs](https://tekton.dev/docs/pipelines/matrix/) - Fan-out pattern, result aggregation, concurrency limits
- [Tekton Workspaces Docs](https://tekton.dev/docs/pipelines/workspaces/) - PVC configuration, Affinity Assistant
- [Tekton Affinity Assistants Docs](https://tekton.dev/docs/pipelines/affinityassistants/) - coschedule modes
- [Tekton Additional Configs](https://tekton.dev/docs/pipelines/additional-configs/) - feature-flags ConfigMap
- [Tekton Dashboard Install](https://tekton.dev/docs/dashboard/install/) - Installation and access methods
- [Tekton Triggers Docs](https://tekton.dev/docs/triggers/) - EventListener, TriggerTemplate, TriggerBinding
- [Prometheus Pushgateway GitHub](https://github.com/prometheus/pushgateway) - Push semantics, grouping keys
- [Prometheus Pushing Docs](https://prometheus.io/docs/instrumenting/pushing/) - When to use Pushgateway
- [Grafana Provisioning Docs](https://grafana.com/docs/grafana/latest/administration/provisioning/) - Dashboard and datasource provisioning

### Secondary (MEDIUM confidence)
- [SeaweedFS Helm Chart README](https://github.com/seaweedfs/seaweedfs/blob/master/k8s/charts/seaweedfs/README.md) - Helm deployment, S3 enabling
- [SeaweedFS GitHub](https://github.com/seaweedfs/seaweedfs) - S3 API capabilities
- [Chaining Tekton Pipelines (Medium)](https://medium.com/@nuwanv/chaining-tekton-pipelines-using-tekton-triggers-c0fd2c2fade1) - EventListener chaining pattern
- [Grafana Dashboard ConfigMap Guide](https://blog.cloudcover.ch/posts/grafana-helm-dashboard-import/) - Helm chart dashboard provisioning
- [Pushgateway Kubernetes Setup](https://devopscube.com/setup-prometheus-pushgateway-on-kubernetes/) - Deployment manifests
- [TEP-0056 GitHub](https://github.com/tektoncd/community/blob/main/teps/0056-pipelines-in-pipelines.md) - Pipelines-in-Pipelines design
- [TEP-0090 GitHub](https://github.com/tektoncd/community/blob/main/teps/0090-matrix.md) - Matrix design

### Tertiary (LOW confidence)
- [SeaweedFS Kubernetes Deployment (DeepWiki)](https://deepwiki.com/seaweedfs/seaweedfs/6.3.3-kubernetes-deployment) - Deployment details

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All components (Tekton, SeaweedFS, Prometheus, Grafana) are well-established K8s tools with official docs verified
- Architecture: HIGH - Pipeline patterns (workspace sharing, Matrix fan-out, Triggers chaining) are documented in official Tekton docs with YAML examples
- Pitfalls: HIGH - Timeout kills, PVC deadlocks, Pushgateway staleness are well-documented in Tekton community and Prometheus docs

**Research date:** 2026-03-06
**Valid until:** 2026-04-06 (30 days - stable technologies)
