# Saiyan Trainer

**Status:** training complete (March 2026)
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

- **Lua layer (8 NEAT modules + game interface).** `memory_map.lua` defines GBA RAM addresses (P1/P2 health at `0x0300273E`/`0x03002826`, Ki at `0x0300274A`/`0x03002833`, spatial distances) sourced from GameShark TEA decryption, struct stride analysis, and legacy VBA code. `controller.lua` maps 8 NEAT output neurons to GBA button bitmasks via `emu:setKeys()`. The training loop (`training/loop.lua`) runs as a Lua coroutine that yields to mGBA's Qt event loop each frame, evaluating a population of 40 genomes across configurable generations with anti-stall penalties and combo pattern analysis.

- **Container layer (mGBA-Qt + headless display stack).** A multi-stage Dockerfile builds mGBA from source (master branch, required for the `--script` CLI flag absent in the 0.10.5 release and the SDL frontend). The runtime image layers Xvfb, x11vnc, fluxbox, and noVNC behind s6-overlay process supervision, providing browser-based observation of training fights at port 6080. Mesa's llvmpipe handles software OpenGL rendering in headless environments.

- **Kubernetes/Tekton layer (pipeline + Loop + observability).** A Pipeline uses the custom-built Tekton Loop primitive (`feat/pipeline-iteration` branch on `tektoncd/pipeline`) to iterate training batches within a single PipelineRun. Each iteration runs 5 generations of NEAT training, passes results via `$(loop.previousResult.*)`, and stops when a fitness threshold is met or `maxIterations` (20) is reached. The 4-island model runs 4 parallel PipelineRuns, each with its own Loop, sharing a PVC with per-island checkpoint directories. `timeout: "0"` prevents Tekton's default 1-hour silent kill. A `store-champion` task runs after the loop completes to extract final results.

## Motivation

### Why This Project Exists

Tekton Pipelines was designed for CI/CD: short-lived, I/O-bound tasks with predictable resource usage and clear success/failure outcomes. Machine learning workloads violate nearly every one of those assumptions. Training runs last hours or days. Tasks need specialized processes (emulators with virtual displays). Progress is measured in floating-point fitness scores, not exit codes. Populations must fan out across pods and reconverge. Runs chain iteratively until a convergence criterion is met, not until a container exits 0.

The primary motivation for Saiyan Trainer is to discover -- by building a real system -- exactly where Tekton's abstractions break down for ML/DL workloads and what primitives are missing.

### Specific Tekton Gaps Under Investigation

1. **Long-running task management.** Tekton's default pipeline timeout of 1 hour silently kills training runs. The workaround (`timeout: "0"`) is documented nowhere prominently. There is no mechanism for progress reporting from within a running step.

2. **Iterative/looping pipelines.** NEAT training runs until a fitness threshold is met, which may take an unbounded number of pipeline iterations. Tekton had no native loop construct. This project built a Loop primitive (`feat/pipeline-iteration` on `tektoncd/pipeline`, 12+ commits) that supports bounded iteration, convergence detection via CEL expressions, and inter-iteration state passing -- validated across 80 loop iterations (20 batches x 4 islands) with 100% reliability. A TEP proposal is planned to upstream this feature.

3. **Dynamic fan-out with result aggregation.** Matrix fan-out creates one TaskRun per genome, but aggregating results from parallel TaskRuns requires collecting `$(tasks.distributed-eval.results.fitness-score[*])` -- a pattern that is poorly documented and has a hard cap of 256 combinations.

4. **Stateful workspaces across chained runs.** Each PipelineRun gets a fresh `volumeClaimTemplate` PVC. Passing state between chained runs requires an external store (SeaweedFS), adding upload/download overhead that would not exist if Tekton supported workspace inheritance across chained PipelineRuns.

5. **Observability of in-progress tasks.** Tekton provides no streaming metrics or log-structured output from running steps. This project works around it by pushing to Prometheus Pushgateway after completion.

6. **Resource-intensive sidecar processes.** Each training pod needs a virtual framebuffer (Xvfb) and software OpenGL renderer. Tekton's sidecar support exists but is designed for network proxies, not display servers.

### Goals

- Produce a fully functional NEAT training system that can evolve genomes capable of winning fights in DBZ: Supersonic Warriors. **Achieved:** Island-3 champion deals 66/71 damage (93% KO rate).
- Exercise Tekton primitives relevant to ML workloads and build missing ones. **Achieved:** Built a Loop primitive (12+ commits), validated across 80 iterations with 100% reliability.
- Document concrete Tekton pain points with reproduction steps and proposed solutions. **Achieved:** See [blog post](blog/goku-trains-with-the-robocat.md) and [final results](output/FINAL_RESULTS.md).
- Provide a reference architecture for emulator-in-the-loop ML training on Kubernetes. **Achieved:** 4-island parallel training on Kind cluster.

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
|  KUBERNETES CLUSTER (Kind on Apple Silicon)                                       |
|                                                                                   |
|  +--[ PipelineRun: island-1 ]--+  +--[ PipelineRun: island-2 ]--+               |
|  |  train-batch (Loop x20)     |  |  train-batch (Loop x20)     |  ... x4       |
|  |  +------------------------+ |  |  +------------------------+ |               |
|  |  | Iteration 0:           | |  |  | Iteration 0:           | |               |
|  |  |   mGBA NEAT 5 gens     | |  |  |   mGBA NEAT 5 gens     | |               |
|  |  |   → result: fitness    | |  |  |   → result: fitness    | |               |
|  |  |----------------------- | |  |  |----------------------- | |               |
|  |  | Iteration 1:           | |  |  | Iteration 1:           | |               |
|  |  |   resume from PVC      | |  |  |   resume from PVC      | |               |
|  |  |   5 more gens          | |  |  |   5 more gens          | |               |
|  |  |   → result: fitness    | |  |  |   → result: fitness    | |               |
|  |  |----------------------- | |  |  |----------------------- | |               |
|  |  | ...until converged or  | |  |  | ...until converged or  | |               |
|  |  |    maxIterations (20)  | |  |  |    maxIterations (20)  | |               |
|  |  +------------------------+ |  |  +------------------------+ |               |
|  |  store-champion             |  |  store-champion             |               |
|  +-----------------------------+  +-----------------------------+               |
|                                                                                   |
|  +--[ Shared PVC ]-------------------------------------------------------------+|
|  | output/island-1/checkpoints/   output/island-2/checkpoints/   ...            ||
|  | output/island-1/results/       output/island-2/results/       ...            ||
|  +------------------------------------------------------------------------------+|
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
GBA RAM --read8/16--> inputs.lua --normalize--> [5 floats: P1 X, P2 X, P1 HP, P2 HP, frame]
  --forward pass--> network.lua --sigmoid--> [8 outputs: A, B, L, R, Up, Down, Left, Right]
  --threshold > 0--> controller.lua --setKeys(bitmask)--> GBA Input Register
```

## Design Details

### 1. Emulator Integration

mGBA-Qt runs headlessly via Xvfb with Mesa llvmpipe. The `--script` flag (requires master branch) loads `main.lua`. A coroutine wrapper patches `emu:runFrame()` to yield instead of blocking, keeping Qt's event loop alive during training.

### 2. Memory Map Discovery

Addresses found via GameShark TEA decryption (seeds: `09F4FBBD/9681884A/352027E9/F3DEE5A7`), CodeBreaker raw codes, and old VBA code. P1 struct at base `0x03002700`: `+0x38`=power, `+0x3E`=HP, `+0x3F`=maxHP, `+0x4A`=Ki. P2 struct at `0x03002700 + 0xE8` (stride derived from P2 Ki `0x03002833` - P1 Ki `0x0300274B`): P2 HP at `0x03002826`. The old VBA address `0x03004C30` for P2 HP reads a constant 72 on mGBA and is incorrect. Verification overlay (`lua/vis/mem_overlay.lua`) draws live values on-screen.

### 3. NEAT Algorithm

8 modules adapted from MarI/O. Key differences: 5 inputs (vs 169 in MarI/O), 8 outputs (vs 6), multi-component fitness with KO bonus, modular files with lazy dependency injection via `setDependencies()`. Per-generation innovation tracking, 2-pass forward network evaluation, sparse initial topology.

### 4. Training Loop

Coroutine-based: save state reset per genome, per-frame input→network→controller→damage tracking, fitness = `damageDealt×3 + KO(2000) + survival(5) + diversity(1) - stall`. Checkpoints saved as JSON every generation. Population of 40 genomes with 600-frame timeout (~10s per evaluation).

### 5. Container Stack

5-layer display: Xvfb → fluxbox → mGBA-Qt → x11vnc → noVNC. Multi-stage Dockerfile builds mGBA from source. Save states baked into image. VNC conditional on `ENABLE_VNC=true`.

### 6. Tekton Pipeline

`train-batch (Loop, 20 iterations) → store-champion`. The Loop primitive iterates training batches within a single PipelineRun, passing fitness results between iterations for convergence detection. 4-island parallel PipelineRuns share a PVC. `timeout: "0"` at both pipeline and task level to prevent silent kills.

## Kubernetes Infrastructure

Kind cluster (`saiyan`) on Apple Silicon. Custom Tekton controller built from `feat/pipeline-iteration` branch with `enable-api-fields: alpha` for Loop support. CRD patch required for loop state persistence (`x-kubernetes-preserve-unknown-fields` on PipelineRun status). Training image loaded via `kind load image-archive`. Shared PVC with per-island checkpoint directories. VNC observation via `kubectl port-forward` to training pods.

## Tekton Pipeline Design

### Task Flow

`train-batch (Loop, up to 20 iterations) → store-champion`. Each Loop iteration runs 5 generations of NEAT training inside mGBA, writes checkpoints to PVC, and returns fitness results. The Loop evaluates a CEL `until` expression against `$(loop.previousResult.converged)` to detect convergence.

### Island Parallelism

Instead of Matrix fan-out for per-genome evaluation, the system uses 4 independent PipelineRuns (one per island) each running their own Loop. This provides population-level parallelism without the overhead of pod-per-genome scheduling. Islands share a PVC with isolated checkpoint directories (`output/<island-id>/`).

### Tekton Loop (replaces Triggers-based chaining)

The original design used Triggers (EventListener + TriggerTemplate) to chain PipelineRuns. This was replaced by a native Loop primitive built for this project:

```yaml
tasks:
  - name: train-batch
    loop:
      maxIterations: 20
      until: "'$(loop.previousResult.converged)' == 'true'"
    taskRef:
      name: run-training
    params:
      - name: iteration
        value: "$(loop.iteration)"
      - name: previous-fitness
        value: "$(loop.previousResult.best-fitness)"
```

Loop state is stored in PipelineRun status. `$(loop.previousResult.*)` passes fitness scores between iterations for convergence detection.

### Timeout

`timeout: "0"` on both pipeline-level (`spec.timeouts.pipeline`) and training task. Pipeline-level timeout defaults to 1 hour and silently kills runs -- a critical gotcha for ML workloads.

## MLOps Lifecycle

**Versioning:** `metadata.json` per checkpoint: run_id, generation, fitness, date, opponent. Path: `genomes/{run-id}/gen-{NNNN}/`.

**Retraining:** Loop primitive with `until` convergence detection and `maxIterations` safety limit. Future: plateau detection via fitness derivative.

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
| `0x03004DB4` | u16 | Shop points | GS |
| `0x03004D58` | u16×4 | Unlock flags | CB |

### Verified Addresses (P2) -- discovered via struct stride analysis

P2 struct is offset `0xE8` from P1 struct (derived from P2 Ki `0x03002833` - P1 Ki `0x0300274B`).

| Address | Type | Field | Source |
|---------|------|-------|--------|
| `0x03002826` | u8 | P2 HP (0-255) | struct stride (P1 HP + 0xE8) |
| `0x03002833` | u16 | P2 Ki | old VBA (confirmed) |

**Note:** `0x03004C30` (listed in old VBA code as "P2 HP") reads a constant 72 on mGBA and is **incorrect**. The GameShark "Instant Win" cheat at `0x03002826` writes 0, which is actually setting P2 HP to 0 (KO), confirming this is the correct P2 HP address.

### Unverified Addresses (Spatial + Misc)

| Address | Type | Field | Source |
|---------|------|-------|--------|
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
| `9E69DA42 35B196E8` | `03002826 00000000` | `0x03002826` | P2 HP = 0 (KO) |

### Fitness Function

```
fitness = damageDealt × 3.0 + KO_bonus(2000) + timeout_win(50) + survival(5) + diversity(1) - stall_penalty
Minimum: 0.001 (separates evaluated from unevaluated genomes)
```

The fitness floor was originally `<= 0 → -1`, which killed all gradient signal since nearly every genome scored the same. Removing the floor and adding survival + diversity signals provided differentiation even for genomes that dealt no damage. `W_TIMEOUT_WIN` was reduced from 200 to 50 to break a local optimum where bots learned to switch characters for HP gain and win via timeout instead of fighting.

## Devil's Advocate

Four adversarial agents independently attacked every design decision. Key challenges and responses:

### Critical Bugs Found (all fixed)

**Crossover was broken.** `math.random() == 1` in `crossover.lua:45` was always false in Lua (returns float in `[0,1)`). **Fixed to `math.random(2) == 1`.** This and 98 other issues were caught and fixed in a comprehensive code review.

### Architecture

| Challenge | Response |
|-----------|----------|
| NEAT (2002) vs modern Deep RL (PPO/A3C) | NEAT chosen to exercise Tekton primitives (fan-out, checkpoints, chaining). Goal is Tekton gap discovery, not SOTA AI. |
| All-in-Lua limits parallelism and ecosystem access | Valid for production. Acceptable for proof-of-concept. Future: Python sidecar. |
| Coroutine `emu:runFrame()` patch is fragile monkey-patching | Accepted. Add API version assertions and smoke tests. |
| 300×5400 frames = 7.5 hours/generation | Fixed. Population reduced to 40, timeout to 600 frames. ~4.3 min/generation. |
| 8 inputs too few (no attack states, projectiles, power level) | Accepted. Add `p1_power_level` (already verified). Discover animation state address. |

### Tekton/K8s

| Challenge | Response |
|-----------|----------|
| Tekton vs Argo Workflows (native loops, artifacts, GPU scheduling) | Built a native Loop primitive for Tekton. "Tekton lacked loops" became a contribution. |
| 300 pods via Matrix — scheduling overhead dwarfs computation | Solved differently: 4-island model with 40 genomes per pod, no Matrix fan-out needed. |
| Unbounded Trigger chain with no circuit breaker | Replaced by Loop with `maxIterations: 20` and `until` convergence condition. |
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

1. ~~**Are P2 addresses correct or display copies?**~~ **ANSWERED:** `0x03004C30` is wrong (constant 72 on mGBA). Correct P2 HP is `0x03002826`, derived via struct stride analysis (P2 Ki - P1 Ki = stride `0xE8`).
2. ~~**What does `round_state == 0` mean?**~~ **ANSWERED:** `0x03002826` is not round state -- it is P2 HP. The GameShark "Instant Win" cheat writes 0 to this address because setting P2 HP to 0 is a KO.
3. **Every frame or every N frames?** mGBA runs at real-time 60fps (no turbo mode available). Frame-skip not implemented yet.
4. ~~**Optimal population size?**~~ **ANSWERED:** 40 genomes per island works well. With 600-frame timeout (~10 seconds), each generation takes ~4.3 minutes.
5. **Absolute positions vs relative distances?** Current inputs use X-position for both players. Relative distance could be added.
6. **Multi-round fights?** Currently single-round evaluation.
7. ~~**Other correctness bugs beyond crossover?**~~ **ANSWERED:** 99-issue code review completed. Crossover fixed (`math.random(2) == 1`), copyGenome resets fitness to 0, per-generation innovation tracking, network 2-pass forward evaluation, command injection safety in filesystem operations.

## Risks and Mitigations

| Risk | Impact | Status | Mitigation |
|------|--------|--------|------------|
| Wrong memory addresses | High | **RESOLVED** | P2 HP found via struct stride analysis. Verified with GameShark cheat correlation. |
| Training speed | High | **MITIGATED** | Population 40, 600-frame timeout, 4-island parallel training. ~4.3 min/gen. |
| mGBA API instability | Medium | Open | Building from master branch; no --script flag in stable release. |
| Container size | Medium | Open | Single image with VNC. Two-image split deferred. |
| Fitness misspecification | High | **RESOLVED** | Floor removed, survival+diversity signals added, timeout-win bonus reduced. |
| Unbounded Trigger chain | Medium | **RESOLVED** | Replaced by Tekton Loop with `maxIterations: 20` and convergence detection. |
| Crossover bug | Critical | **FIXED** | `math.random(2) == 1` -- fixed during 99-issue code review. |

## Future Work

### Completed
- ~~Fix crossover bug~~ (fixed during code review)
- ~~Verify all memory addresses via overlay~~ (P2 HP found via struct stride)
- ~~Parallel island model~~ (4-island PipelineRun parallelism, not Matrix)
- ~~Build Tekton Loop primitive~~ (12+ commits on `feat/pipeline-iteration`)

### Short-term
- Draft and submit TEP (Tekton Enhancement Proposal) for Loop primitive
- Publish blog post: [`blog/goku-trains-with-the-robocat.md`](blog/goku-trains-with-the-robocat.md)
- Extract champion genomes from PVC for standalone demo
- Add `p1_power_level` to NEAT input vector
- Pin mGBA to specific commit hash
- Add Dockerfile HEALTHCHECK

### Medium-term
- Curriculum learning (easy → hard CPU difficulty)
- Island migration (exchange genomes between islands)
- Headless training image (drop VNC for faster training)
- Frame-skip evaluation (mGBA currently runs at real-time 60fps)
- Atomic checkpoint writes (temp + rename pattern to prevent corruption)
- Nested loops (Loop + Matrix composition for per-genome parallelism)

### Long-term
- Python sidecar for GPU-accelerated inference
- Multiple game support
- Automated memory address discovery
- Tekton ML toolkit extraction based on experiment findings
- Upstream Tekton Loop as a graduated feature

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
