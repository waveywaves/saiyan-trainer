# Saiyan Trainer

**Status:** implementable
**Authors:** @waveywaves

<!-- toc -->
- [Summary](#summary)
- [Motivation](#motivation)
- [Use Cases](#use-cases)
- [Architecture Overview](#architecture-overview)
- [Design Details](#design-details)
- [Kubernetes Infrastructure](#kubernetes-infrastructure)
- [Tekton Pipeline Design](#tekton-pipeline-design)
- [MLOps Lifecycle](#mlops-lifecycle)
- [GBA Memory Map Reference](#appendix-gba-memory-map-reference)
- [Devil's Advocate](#devils-advocate)
- [Open Questions](#open-questions)
- [Risks and Mitigations](#risks-and-mitigations)
- [Future Work](#future-work)
- [References](#references)
<!-- /toc -->

## Summary

Saiyan Trainer is a neuroevolution system that evolves neural networks to play *Dragon Ball Z: Supersonic Warriors* on Game Boy Advance. A NEAT (NeuroEvolution of Augmenting Topologies) algorithm implemented in Lua runs inside the mGBA emulator, reading game RAM directly (HP, Ki, spatial distance, direction) and pressing buttons through the emulator's scripting API. The full training lifecycle -- population initialization, multi-generation evolution, distributed genome evaluation, fitness aggregation, checkpoint versioning, and iterative re-training -- is orchestrated by Tekton Pipelines on Kubernetes.

The system is structured as three layers:

- **Lua layer (8 NEAT modules + game interface).** `memory_map.lua` defines GBA RAM addresses (P1/P2 health at `0x0300273E`/`0x03004C30`, Ki at `0x0300274A`, spatial distances, round state at `0x03002826`) sourced from GameShark TEA decryption and legacy VBA code. `controller.lua` maps 8 NEAT output neurons to GBA button bitmasks via `emu:setKeys()`. The training loop (`training/loop.lua`) runs as a Lua coroutine that yields to mGBA's Qt event loop each frame, evaluating a population of 300 genomes across configurable generations with multi-opponent rotation, anti-stall penalties, and combo pattern analysis.

- **Container layer (mGBA-Qt + headless display stack).** A multi-stage Dockerfile builds mGBA from source (master branch, required for the `--script` CLI flag absent in the 0.10.5 release and the SDL frontend). The runtime image layers Xvfb, x11vnc, fluxbox, and noVNC behind s6-overlay process supervision, providing browser-based observation of training fights at port 6080. Mesa's llvmpipe handles software OpenGL rendering in headless environments.

- **Kubernetes/Tekton layer (pipeline + fan-out + triggers + observability).** A 4-task Pipeline runs setup (checkpoint resume from SeaweedFS), training (with `timeout: "0"` to prevent Tekton's default 1-hour silent kill), Matrix fan-out for parallel genome evaluation, and versioned genome storage. A `finally` task compares best fitness against a configurable threshold and POSTs to a Tekton EventListener to chain the next PipelineRun automatically, creating an open-ended training loop without external orchestration. Prometheus Pushgateway receives per-generation metrics for Grafana dashboards.

## Motivation

### Why This Project Exists

Tekton Pipelines was designed for CI/CD: short-lived, I/O-bound tasks with predictable resource usage and clear success/failure outcomes. Machine learning workloads violate nearly every one of those assumptions. Training runs last hours or days. Tasks need specialized processes (emulators with virtual displays). Progress is measured in floating-point fitness scores, not exit codes. Populations must fan out across pods and reconverge. Runs chain iteratively until a convergence criterion is met, not until a container exits 0.

The primary motivation for Saiyan Trainer is to discover -- by building a real system -- exactly where Tekton's abstractions break down for ML/DL workloads and what primitives are missing.

### Specific Tekton Gaps Under Investigation

1. **Long-running task management.** Tekton's default pipeline timeout of 1 hour silently kills training runs. The workaround (`timeout: "0"`) is documented nowhere prominently. There is no mechanism for progress reporting from within a running step.

2. **Iterative/looping pipelines.** NEAT training runs until a fitness threshold is met, which may take an unbounded number of pipeline iterations. Tekton has no native loop construct. This project uses Triggers (EventListener + TriggerTemplate) to chain PipelineRuns, which works but introduces HTTP call fragility, loses run lineage, and requires manual cleanup of completed PipelineRun resources.

3. **Dynamic fan-out with result aggregation.** Matrix fan-out creates one TaskRun per genome, but aggregating results from parallel TaskRuns requires collecting `$(tasks.distributed-eval.results.fitness-score[*])` -- a pattern that is poorly documented and has a hard cap of 256 combinations.

4. **Stateful workspaces across chained runs.** Each PipelineRun gets a fresh `volumeClaimTemplate` PVC. Passing state between chained runs requires an external store (SeaweedFS), adding upload/download overhead that would not exist if Tekton supported workspace inheritance across chained PipelineRuns.

5. **Observability of in-progress tasks.** Tekton provides no streaming metrics or log-structured output from running steps. This project works around it by pushing to Prometheus Pushgateway after completion.

6. **Resource-intensive sidecar processes.** Each training pod needs a virtual framebuffer (Xvfb) and software OpenGL renderer. Tekton's sidecar support exists but is designed for network proxies, not display servers.

### Goals

- Produce a fully functional NEAT training system that can evolve genomes capable of winning fights in DBZ: Supersonic Warriors.
- Exercise every Tekton primitive relevant to ML workloads: long tasks, Matrix fan-out, Triggers chaining, workspace persistence, result aggregation, observability integration.
- Document concrete Tekton pain points with reproduction steps and proposed solutions.
- Provide a reference architecture for emulator-in-the-loop ML training on Kubernetes.

### Non-Goals

- Building a production-grade ML platform or framework.
- Achieving state-of-the-art fighting game AI.
- Supporting emulators other than mGBA or games other than DBZ: Supersonic Warriors.
- Replacing or forking Tekton.

## Use Cases

### UC-1: ML Researcher Running NEAT Training on Kubernetes

An ML researcher pushes a ROM and save state to the cluster, triggers a PipelineRun with `generations-per-batch: 50` and `fitness-threshold: 5000`, and walks away. The pipeline trains, evaluates genomes in parallel across pods, stores versioned checkpoints to SeaweedFS, and automatically chains new PipelineRuns until the fitness threshold is met. The researcher monitors progress through Grafana dashboards.

### UC-2: DevOps Engineer Evaluating Tekton for ML Pipelines

A platform engineer deploys Saiyan Trainer as a reference workload on a Kind cluster to stress-test Tekton's handling of long-running tasks, fan-out to parallel pods, result aggregation, automatic pipeline chaining, and Prometheus-based observability.

### UC-3: Game AI Researcher Studying Neuroevolution

A game AI researcher uses the Lua layer directly -- loading `main.lua` in mGBA locally -- to iterate on fitness function weights, NEAT hyperparameters, and input normalization. No Kubernetes required.

### UC-4: Tekton Community Understanding ML Workload Requirements

A Tekton contributor reads this design document to understand what ML workloads need. Concrete examples provide actionable input for TEP discussions.

## Architecture Overview

### Full System Diagram

```
+-----------------------------------------------------------------------------------+
|  KUBERNETES CLUSTER (Kind for local dev)                                          |
|                                                                                   |
|  +--[ Tekton Pipeline: saiyan-training-pipeline ]----------------------------+   |
|  |                                                                            |   |
|  |  1. setup-generation    2. run-training     3a. get-genome-list           |   |
|  |  +----------------+    +----------------+   +-------------------+          |   |
|  |  | Pull checkpoint|    | Run mGBA NEAT  |   | List genome IDs  |          |   |
|  |  | from SeaweedFS |--->| N generations  |-->| as JSON array    |          |   |
|  |  | (minio/mc)     |    | (mgba-qt)      |   | (alpine)         |          |   |
|  |  +----------------+    +-------+--------+   +---------+---------+          |   |
|  |                                |                       |                   |   |
|  |                                | push-metrics          | Matrix fan-out    |   |
|  |                                v                       v                   |   |
|  |                     +------------------+   3b. distributed-eval            |   |
|  |                     | Prometheus       |   +---------+---------+           |   |
|  |                     | Pushgateway      |   | genome-0| genome-1| ...       |   |
|  |                     +--------+---------+   | (pod)   | (pod)   | (pod)     |   |
|  |                              |             +---------+---------+           |   |
|  |                              v                       |                    |   |
|  |                     +------------------+             v                    |   |
|  |                     | Grafana          |   3c. aggregate-results          |   |
|  |                     | Dashboards       |   +-------------------+          |   |
|  |                     +------------------+   | Find champion     |          |   |
|  |                                            +---------+---------+          |   |
|  |                                                      |                   |   |
|  |                                            4. store-results              |   |
|  |                                            +-------------------+          |   |
|  |                                            | Upload to         |          |   |
|  |                                            | SeaweedFS S3      |          |   |
|  |                                            +---------+---------+          |   |
|  |                                                      |                   |   |
|  |  finally: decide-continue                            |                   |   |
|  |  fitness < threshold? --curl--> EventListener -> new PipelineRun         |   |
|  +-------------------------------------------------------------------+------+   |
|                                                                                   |
|  +--[ SeaweedFS ]------+  +--[ Prometheus ]------+  +--[ Grafana ]------+        |
|  | genomes/{run-id}/   |  | neat_fitness_max     |  | Fitness Curves    |        |
|  |   gen-{NNNN}/       |  | neat_fitness_avg     |  | Species Diversity |        |
|  |     champion.json   |  | neat_species_count   |  | Eval Results      |        |
|  +---------------------+  +----------------------+  +-------------------+        |
+-----------------------------------------------------------------------------------+
```

### Container Architecture

```
+--[ Docker: saiyan-trainer/mgba ]--------------------------------------------------+
|  s6-overlay: xvfb -> fluxbox -> mgba (mgba-qt --script main.lua rom.gba)         |
|              xvfb -> x11vnc -> novnc (browser at :6080)                           |
|  Env: DISPLAY=:99, LIBGL_ALWAYS_SOFTWARE=1, GALLIUM_DRIVER=llvmpipe               |
+-----------------------------------------------------------------------------------+
```

### Lua Module Graph

```
main.lua -> savestate_helper.lua
         -> training/loop.lua -> neat/{config,innovation,genome,network,species,
                                       crossover,mutation,pool}
                              -> game/{inputs -> memory_map, fitness}
                              -> controller.lua
                              -> training/{checkpoint -> lib/dkjson, combo_logger}
```

### Data Flow

```
GBA RAM --read8/16--> inputs.lua --normalize--> [9 floats]
  --forward pass--> network.lua --sigmoid--> [8 outputs]
  --threshold > 0--> controller.lua --setKeys(bitmask)--> GBA Input Register
```

## Design Details

### 1. Emulator Integration

mGBA-Qt runs headlessly via Xvfb with Mesa llvmpipe. The `--script` flag (requires master branch) loads `main.lua`. A coroutine wrapper patches `emu:runFrame()` to yield instead of blocking, keeping Qt's event loop alive during training.

### 2. Memory Map Discovery

Addresses found via GameShark TEA decryption (seeds: `09F4FBBD/9681884A/352027E9/F3DEE5A7`), CodeBreaker raw codes, and old VBA code. P1 struct at base `0x03002700`: `+0x38`=power, `+0x3E`=HP, `+0x3F`=maxHP, `+0x4A`=Ki. Verification overlay (`lua/vis/mem_overlay.lua`) draws live values on-screen.

### 3. NEAT Algorithm

8 modules adapted from MarI/O. Key differences: 9 inputs (vs 169), 8 outputs (vs 6), multi-component fitness, modular files with lazy dependency injection via `setDependencies()`.

### 4. Training Loop

Coroutine-based: save state reset per genome, per-frame input→network→controller→damage tracking, fitness = `damageDealt×2 - damageTaken×1.5 + win(1000) - loss(500) - stall`. Checkpoints saved as JSON every generation.

### 5. Container Stack

5-layer display: Xvfb → fluxbox → mGBA-Qt → x11vnc → noVNC. Multi-stage Dockerfile builds mGBA from source. Save states baked into image. VNC conditional on `ENABLE_VNC=true`.

### 6. Tekton Pipeline

`setup → train → distributed-eval (Matrix) → store`. Retraining via Triggers chain. Metrics via Pushgateway. `timeout: "0"` to prevent silent kills.

## Kubernetes Infrastructure

Kind cluster. Install script bootstraps: Tekton Pipelines v1.9.0 LTS, Dashboard, Triggers, SeaweedFS (Helm), kube-prometheus-stack (Helm), Pushgateway, workspace PVC (5Gi). SeaweedFS at `http://seaweedfs-s3:8333`. Three Grafana dashboards: Fitness Curves, Species Diversity, Evaluation Results.

## Tekton Pipeline Design

### Task Flow

`setup-generation → run-training → get-genome-list → distributed-eval (Matrix) → aggregate-results → store-results`. `finally: decide-continue` chains via EventListener POST.

### Matrix Fan-Out

`get-genome-list` emits genome IDs as array. One TaskRun per element. `aggregate-results` collects `[*]` arrays. Max 256 combinations.

### Retraining Chain

If `fitness < threshold`: POST to EventListener → TriggerTemplate → new PipelineRun with `resume-from=latest`.

### Timeout

`timeout: "0"` on pipeline and training task. `keep-pod-on-cancel: "true"`.

## MLOps Lifecycle

**Versioning:** `metadata.json` per checkpoint: run_id, generation, fitness, date, opponent. Path: `genomes/{run-id}/gen-{NNNN}/`.

**Retraining:** Threshold-based chain via Triggers. Future: plateau detection.

**Reproducibility:** Deterministic save states, seeded random, full population checkpoints.

## Appendix: GBA Memory Map Reference

### Verified Addresses (P1)

| Address | Type | Field | Source |
|---------|------|-------|--------|
| `0x0300273E` | u8 | P1 HP (0-255) | GS + CB + VBA |
| `0x0300273F` | u8 | P1 Max HP | GS + CB |
| `0x03002738` | u8 | P1 Power Level (0-3) | GS |
| `0x0300274A` | u16 | P1 Ki (8.8 fixed-point) | CB + GS |
| `0x0300274B` | u8 | P1 Ki integer (0-100%) | derived |
| `0x03002826` | u8 | Round state | CB + GS |
| `0x03004DB4` | u16 | Shop points | GS |
| `0x03004D58` | u16×4 | Unlock flags | CB |

### Unverified Addresses (P2 + Spatial)

| Address | Type | Field | Source |
|---------|------|-------|--------|
| `0x03004C30` | u8 | P2 HP | old VBA |
| `0x03002833` | u16 | P2 Ki | old VBA |
| `0x03002CD4` | u16 | X distance (0-630) | old VBA |
| `0x03002CD8` | u16 | Y distance (0-630) | old VBA |
| `0x0300288C` | u8 | Direction (0-32) | old VBA |
| `0x03002830` | u16 | Timer | placeholder |

### Cheat Code Decryption

| Encrypted (GameShark) | Decrypted | Address | Effect |
|-----------------------|-----------|---------|--------|
| `3EDD7118 5A58A127` | `0300273E 000000FF` | `0x0300273E` | Infinite HP |
| `B8CE7B32 38AB9D94` | `0300273F 000000FF` | `0x0300273F` | Max HP |
| `CB1E748C 4A108A48` | `03002738 00000003` | `0x03002738` | Power Level max |
| `DC4B8E1A AF073E65` | `1300274A 00006400` | `0x0300274A` | Ki 100% |
| `9E69DA42 35B196E8` | `03002826 00000000` | `0x03002826` | Instant Win |

### Fitness Function

```
fitness = damageDealt × 2.0 - damageTaken × 1.5 + win(1000) - loss(500) - stall(0.5/frame after 300f)
Floor: if fitness <= 0, set to -1 (0 is "not evaluated" sentinel)
```

## Devil's Advocate

Four adversarial agents independently attacked every design decision. Key challenges and responses:

### Critical Bugs Found

**Crossover is broken.** `math.random() == 1` in `crossover.lua:45` is always false in Lua (returns float in `[0,1)`). Crossover produces clones, not recombinations. **Must fix to `math.random(2) == 1`.**

### Architecture

| Challenge | Response |
|-----------|----------|
| NEAT (2002) vs modern Deep RL (PPO/A3C) | NEAT chosen to exercise Tekton primitives (fan-out, checkpoints, chaining). Goal is Tekton gap discovery, not SOTA AI. |
| All-in-Lua limits parallelism and ecosystem access | Valid for production. Acceptable for proof-of-concept. Future: Python sidecar. |
| Coroutine `emu:runFrame()` patch is fragile monkey-patching | Accepted. Add API version assertions and smoke tests. |
| 300×5400 frames = 7.5 hours/generation | Critical. Reduce population, add frame-skip, use Matrix for intra-generation parallelism. |
| 8 inputs too few (no attack states, projectiles, power level) | Accepted. Add `p1_power_level` (already verified). Discover animation state address. |

### Tekton/K8s

| Challenge | Response |
|-----------|----------|
| Tekton vs Argo Workflows (native loops, artifacts, GPU scheduling) | The project exists to discover these gaps. "Tekton lacks loops" is a finding. |
| 300 pods via Matrix — scheduling overhead dwarfs computation | Batch genomes per pod (30-50). Reserve large fan-out for real clusters. |
| Unbounded Trigger chain with no circuit breaker | Add max generation counter, plateau detection, PVC cleanup. |
| `timeout: "0"` is a cluster-killer | Set generous finite timeout (4h). Add heartbeat-based liveness. |
| SeaweedFS for <1MB JSONs is over-engineered | Counter: validates Tekton's S3 artifact pattern. PVC-only works for local dev. |
| No resource requests/limits on any pod | Accepted. Add explicit CPU/memory requests to all task steps. |

### Fitness + Training

| Challenge | Response |
|-----------|----------|
| Fitness rewards hit-trading over skill | Use damage ratio. Scale win bonus proportional to remaining HP. |
| No curriculum learning — random networks vs max CPU | Implement staged difficulty via save states. |
| Anti-stall penalty punishes defensive play | Replace with time-efficiency bonus on wins only. |
| Fully-connected initial topology defeats NEAT's minimal-start principle | Use sparse init (3 connections per output). |

### Container

| Challenge | Response |
|-----------|----------|
| 5 processes for headless training | Two-image split: slim training + full observation. |
| Building from `master` is non-reproducible | Pin to commit hash. Build separate `mgba-base` image. |
| No CI integration tests without copyrighted ROM | Bundle open-source test ROM for smoke tests. |
| No K8s health check or liveness probe | Add Dockerfile HEALTHCHECK + Lua heartbeat file. |

## Open Questions

1. **Are P2 addresses correct or display copies?** P2 HP at `0x03004C30` is 9458 bytes from P1 HP.
2. **What does `round_state == 0` mean?** Instant-win cheat writes 0. May be "win" not "in progress."
3. **Every frame or every N frames?** 5-frame skip gives 5x speedup.
4. **Optimal population size?** Start with 50-100 for feasible generation times.
5. **Absolute positions vs relative distances?** Relative misses stage boundary info.
6. **Multi-round fights?** Best-of-3 vs single round evaluation.
7. **Other correctness bugs beyond crossover?** Needs systematic NEAT audit.

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Wrong memory addresses | High | Verify all via overlay before training |
| Training speed | High | Frame-skip, smaller population, parallel eval |
| mGBA API instability | Medium | Pin commit hash, add assertions |
| Container size | Medium | Two-image split |
| Fitness misspecification | High | Monitor via noVNC, per-component logging |
| Unbounded Trigger chain | Medium | Max iteration counter, plateau detection |
| Crossover bug | Critical | Fix `math.random() == 1` → `math.random(2) == 1` |

## Future Work

### Short-term
- Fix crossover bug
- Verify all memory addresses via overlay
- Add `p1_power_level` to input vector
- Pin mGBA to commit hash
- Add Dockerfile HEALTHCHECK

### Medium-term
- Curriculum learning (easy → hard CPU)
- Parallel island model via Matrix
- Headless training image (drop VNC)
- Frame-skip evaluation
- Real-time Grafana dashboards

### Long-term
- Python sidecar for GPU-accelerated inference
- Multiple game support
- Automated memory address discovery
- Tekton ML toolkit extraction

## Training Results (March 2026)

4-island neuroevolution experiment using Tekton Loop, 155 generations, ~6 hours overnight.

| Island | Final Gen | Best Fitness | P2 Damage | Strategy |
|--------|-----------|--------------|-----------|----------|
| island-1 | 142 | 191.1 | 31 | Peaked early, regressed |
| island-2 | 155 | 218.8 | 27 | Broke 75-gen plateau |
| **island-3** | **155** | **2234.7** | **66/71 (93% KO)** | **Champion** |
| island-4 | 155 | 204.3 | 49 | Steady climber |

**Champion (island-3)**: 114 genes, 21 hidden nodes, 33 unique combo patterns. Evolved from button-mashing (Gen 0) to near-perfect KOs (Gen 51+). P2 HP: 71 → 5.

**Key breakthroughs**:
- Gen 14: First damage dealt (20 HP)
- Gen 51: Full KO achieved (71 damage, fitness 2234)
- Island-2 escaped 75-generation plateau through speciation

**Bugs found and fixed**: Wrong P2 HP memory address, stale results file on PVC, corrupt checkpoint from Docker crash, pipeline-level timeout confusion.

**Full results**: See [`output/FINAL_RESULTS.md`](output/FINAL_RESULTS.md)

**Blog post**: [`blog/goku-trains-with-the-robocat.md`](blog/goku-trains-with-the-robocat.md)

## References

1. Stanley & Miikkulainen (2002). [Evolving Neural Networks through Augmenting Topologies](https://nn.cs.utexas.edu/downloads/papers/stanley.ec02.pdf)
2. SethBling (2015). [MarI/O — Machine Learning for Video Games](https://www.youtube.com/watch?v=qv6UVOQ0F44)
3. [mGBA Emulator](https://mgba.io/) | [GitHub](https://github.com/mgba-emu/mgba)
4. [mGBA Scripting API](https://mgba.io/docs/scripting.html)
5. [Tekton Pipelines](https://tekton.dev/) | [GitHub](https://github.com/tektoncd/pipeline)
6. [s6-overlay](https://github.com/just-containers/s6-overlay)
7. [noVNC](https://novnc.com/) | [GitHub](https://github.com/novnc/noVNC)
8. [SeaweedFS](https://github.com/seaweedfs/seaweedfs)
9. [Prometheus](https://prometheus.io/) | [Grafana](https://grafana.com/)
10. [Old VBA Code](https://github.com/waveywaves/VisualBoyAdvance-LUA)
