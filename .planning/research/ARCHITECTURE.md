# Architecture Patterns

**Domain:** Neuroevolution game bot with MLOps pipeline orchestration
**Researched:** 2026-03-06

## Recommended Architecture

The system has four distinct layers: the **Emulation Layer** (BizHawk + Lua NEAT running locally or in a container), the **Orchestration Layer** (Tekton Pipelines on Kubernetes), the **Storage Layer** (genome versioning + metrics persistence), and the **Observability Layer** (training progress visibility). These layers communicate through Kubernetes-native mechanisms: PVC-backed workspaces for artifact passing, container images for encapsulating the emulator, and Prometheus metrics for observability.

```
+------------------------------------------------------------------+
|                     OBSERVABILITY LAYER                           |
|  Grafana Dashboards  <--  Prometheus  <--  Metrics Exporter      |
+------------------------------------------------------------------+
        ^                                         ^
        |  (scrapes /metrics)                     |  (pushes metrics)
+------------------------------------------------------------------+
|                     ORCHESTRATION LAYER                           |
|                                                                   |
|  Tekton Pipeline: train-generation                                |
|    |                                                              |
|    +-> Task: setup-generation                                     |
|    |     Load previous best genome (or init population)           |
|    |     Write config to shared workspace                         |
|    |                                                              |
|    +-> Task: run-training        (BizHawk container)              |
|    |     EmuHawk + Lua NEAT script                                |
|    |     Runs N generations of NEAT evolution                     |
|    |     Writes genomes + fitness logs to workspace               |
|    |     Pushes generation metrics to Pushgateway                 |
|    |                                                              |
|    +-> Task: evaluate-champion                                    |
|    |     Loads best genome, runs evaluation fights                |
|    |     Records win rate, avg damage, survival time              |
|    |                                                              |
|    +-> Task: store-results                                        |
|    |     Tags and versions genome artifacts                       |
|    |     Updates genome registry (S3/MinIO or PVC)                |
|    |     Writes evaluation summary                                |
|    |                                                              |
|    +-> Task: decide-continue                                      |
|          If fitness threshold not met -> trigger next pipeline run |
|          If met -> mark as champion, stop                         |
|                                                                   |
|  Shared Workspace: PVC (ReadWriteOnce, affinity-scheduled)        |
+------------------------------------------------------------------+
        |                                         |
        v                                         v
+------------------------------------------------------------------+
|                       STORAGE LAYER                               |
|                                                                   |
|  Genome Store          |  Metrics Store     |  Save States        |
|  (MinIO/S3 bucket      |  (Prometheus TSDB) |  (PVC or object     |
|   or PVC directory)    |                    |   store)             |
|                        |                    |                      |
|  /genomes/             |  neat_generation   |  /savestates/        |
|    run-001/            |  neat_fitness_max  |    fight-start.state |
|      gen-0001.json     |  neat_fitness_avg  |                      |
|      gen-0050.json     |  neat_species_cnt  |                      |
|      champion.json     |  eval_win_rate     |                      |
|    run-002/            |  eval_avg_damage   |                      |
|      ...               |                    |                      |
+------------------------------------------------------------------+

+------------------------------------------------------------------+
|                      EMULATION LAYER                              |
|  (runs inside the run-training Task container)                    |
|                                                                   |
|  BizHawk (EmuHawk via Xvfb)                                      |
|    |                                                              |
|    +-> GBA Core (mGBA)                                            |
|    |     Loads ROM: DBZ Supersonic Warriors                       |
|    |     Loads save state: fight-start.state                      |
|    |                                                              |
|    +-> Lua NEAT Script                                            |
|          Reads game memory -> neural network inputs               |
|          NEAT population management                               |
|          Neural network forward pass -> controller outputs        |
|          Fitness evaluation per genome                             |
|          Genome serialization to workspace                        |
|          Metrics emission (file or HTTP to Pushgateway)           |
+------------------------------------------------------------------+
```

### Component Boundaries

| Component | Responsibility | Communicates With |
|-----------|---------------|-------------------|
| **Lua NEAT Script** | Implements NEAT algorithm (population, speciation, crossover, mutation), reads GBA memory for game state, drives controller inputs, evaluates fitness, serializes genomes | BizHawk (memory API, joypad API, savestate API), filesystem (genome files, fitness logs) |
| **BizHawk Container Image** | Packages EmuHawk + Xvfb + Lua 5.4 + Mono + all dependencies into a runnable Docker image; entry point loads ROM + save state + Lua script via CLI args | Lua NEAT Script (hosts it), Tekton workspace (reads config, writes outputs) |
| **Tekton Pipeline (train-generation)** | Orchestrates a training run: setup, run N generations, evaluate champion, store results, decide whether to continue | All Tasks share a PVC workspace; triggers itself for continuation |
| **Tekton Task: setup-generation** | Pulls latest genome state from storage, prepares config (population size, mutation rates, generation count), writes to workspace | Genome Store (reads), Workspace (writes) |
| **Tekton Task: run-training** | Runs the BizHawk container with the NEAT script for a batch of generations | BizHawk Container, Workspace (reads config, writes genomes), Prometheus Pushgateway (pushes metrics) |
| **Tekton Task: evaluate-champion** | Runs the best genome through multiple evaluation fights against CPU, records stats | BizHawk Container (reuses image), Workspace (reads champion genome, writes eval results) |
| **Tekton Task: store-results** | Versions and tags genome artifacts, copies to long-term storage | Workspace (reads), Genome Store (writes), optionally Prometheus Pushgateway |
| **Tekton Task: decide-continue** | Checks if fitness/win-rate thresholds are met; if not, triggers next PipelineRun | Workspace (reads eval summary), Tekton API (creates new PipelineRun) |
| **Genome Store (MinIO or PVC)** | Persistent, versioned storage for NEAT genome JSON files, organized by run and generation | Tekton Tasks (read/write via workspace mount or S3 CLI) |
| **Prometheus + Pushgateway** | Collects and stores time-series training metrics (fitness, species count, generation number, win rate) | Lua script or wrapper pushes to Pushgateway; Prometheus scrapes Pushgateway |
| **Grafana** | Visualizes training progress dashboards: fitness curves, species diversity, evaluation win rates | Prometheus (queries via PromQL) |

### Data Flow

**Training Data Flow (per pipeline run):**

1. **setup-generation** reads the latest champion genome (or nothing for first run) from the Genome Store and writes a config file + seed genome to the shared PVC workspace.
2. **run-training** starts BizHawk in a container with Xvfb. The Lua script reads config from the workspace, initializes or loads the NEAT population, and runs N generations. Each generation: load save state -> run fight -> read memory for fitness -> select/crossover/mutate. Genomes and fitness logs are written to the workspace. Key metrics are pushed to Prometheus Pushgateway via HTTP from a small wrapper script (since Lua HTTP support is limited, a sidecar or shell wrapper handles the push).
3. **evaluate-champion** loads the best genome from the workspace, runs it through M evaluation fights, and writes win rate + stats to workspace.
4. **store-results** copies the champion genome and generation snapshots from workspace to the Genome Store with versioned paths (e.g., `/genomes/run-003/gen-0150/champion.json`).
5. **decide-continue** reads evaluation results. If win rate < threshold, it creates a new PipelineRun pointing to the current run's latest genome as the seed. If threshold met, it marks the run complete.

**Observability Data Flow:**

1. During training, a wrapper script in the BizHawk container reads fitness log files written by Lua and pushes metrics to Prometheus Pushgateway every N generations.
2. Prometheus scrapes the Pushgateway on its standard interval.
3. Grafana dashboards query Prometheus for fitness curves, species counts, and evaluation results.

**Genome Versioning Data Flow:**

1. Genomes are serialized as JSON by the Lua script (node genes + connection genes + fitness metadata).
2. The store-results task copies them to a structured directory in MinIO/S3 or a dedicated PVC.
3. The setup-generation task queries the store for the latest champion of a given run to resume training.

## Patterns to Follow

### Pattern 1: Batched Generation Execution
**What:** Run NEAT for a fixed batch of N generations per Tekton pipeline run, rather than one generation per run or an infinite loop.
**When:** Always. This is the core execution pattern.
**Why:** One generation per pipeline run has too much overhead (pod startup, BizHawk boot, ROM load). An infinite loop inside a single Task loses the orchestration benefits. Batching (e.g., 50 generations per run) balances overhead against checkpointing frequency.
```lua
-- In the Lua NEAT script
local GENERATIONS_PER_BATCH = 50
for gen = 1, GENERATIONS_PER_BATCH do
    evaluateGeneration(population)
    evolvePopulation(population)
    serializeCheckpoint(population, gen)
end
serializeChampion(population)
```

### Pattern 2: JSON Genome Serialization
**What:** Serialize NEAT genomes as JSON files with full topology (nodes, connections, weights, enabled flags) plus metadata (generation, fitness, species ID).
**When:** Every checkpoint and at end of each batch.
**Why:** JSON is human-readable, diffable, and parseable from both Lua and any Task container language. Avoid binary formats that couple you to a specific Lua library.
```json
{
  "genome_id": 42,
  "generation": 150,
  "fitness": 2847.5,
  "species": 3,
  "nodes": [
    {"id": 1, "type": "input", "label": "player_health"},
    {"id": 25, "type": "hidden", "activation": "sigmoid"},
    {"id": 30, "type": "output", "label": "button_A"}
  ],
  "connections": [
    {"in": 1, "out": 25, "weight": 0.73, "enabled": true, "innovation": 101}
  ]
}
```

### Pattern 3: Save State Anchoring
**What:** Always start each genome evaluation from the same BizHawk save state (the moment a fight begins).
**When:** Every fitness evaluation.
**Why:** Deterministic starting conditions are essential for fair fitness comparison across genomes. The save state should capture the exact frame where the fight starts, with both characters at full health.

### Pattern 4: Sidecar Metrics Push
**What:** Use a sidecar container or post-execution shell wrapper to push metrics from the training container to Prometheus Pushgateway, rather than implementing HTTP directly in Lua.
**When:** During run-training Task execution.
**Why:** BizHawk Lua's HTTP/socket support is limited and fragile. Writing metrics to a file and having a sidecar process read and push them is more robust.
```yaml
# Tekton Task step for metrics sidecar
steps:
  - name: run-bizhawk
    image: saiyan-trainer/bizhawk:latest
    script: |
      xvfb-run ./EmuHawkMono.sh --lua=/workspace/neat.lua /workspace/rom.gba
  - name: push-metrics
    image: prom/pushgateway-cli:latest
    script: |
      # Read fitness log from shared volume, push to pushgateway
      cat /workspace/metrics.prom | curl --data-binary @- http://pushgateway:9091/metrics/job/neat-training
```

### Pattern 5: Continuation via PipelineRun Chaining
**What:** The decide-continue Task creates a new PipelineRun (via `kubectl` or Tekton CLI) that references the output genome of the just-completed run.
**When:** When training has not yet reached the fitness/win-rate threshold.
**Why:** This gives clean per-batch boundaries with full Kubernetes-level observability of each batch, allows manual intervention between batches, and avoids long-running pods that risk OOM or eviction.

## Anti-Patterns to Avoid

### Anti-Pattern 1: Running NEAT in Python Outside BizHawk
**What:** Implementing NEAT in Python and communicating with BizHawk via sockets for game state.
**Why bad:** Adds a network hop per frame (60fps = 60 round trips/second), introduces synchronization complexity, and breaks the proven MarI/O pattern where NEAT + game interaction is a tight loop in Lua. Socket communication latency would make training orders of magnitude slower.
**Instead:** Keep NEAT entirely in Lua inside BizHawk, following the MarI/O architecture. The Lua script controls everything: memory reads, neural network forward pass, joypad writes, fitness evaluation, population management.

### Anti-Pattern 2: One Tekton Task Per Generation
**What:** Creating a separate pipeline run or task for each NEAT generation.
**Why bad:** Each Task means a new pod. BizHawk startup (Mono boot + ROM load + save state) takes seconds. With populations of 300 genomes and hundreds of generations, the overhead would dwarf actual training time.
**Instead:** Batch 25-100 generations per Task execution. Checkpoint to workspace between batches.

### Anti-Pattern 3: Storing Genomes Only in PVC Workspace
**What:** Relying on the Tekton workspace PVC as the long-term genome store.
**Why bad:** Workspace PVCs are ephemeral to the PipelineRun lifecycle. VolumeClaimTemplates create PVCs that are cleaned up with the PipelineRun. Even persistent PVCs are at risk of accidental deletion.
**Instead:** Copy genomes to a durable store (MinIO bucket or a dedicated long-lived PVC) in the store-results Task. The workspace is scratch space only.

### Anti-Pattern 4: Pixel-Based Inputs
**What:** Using screen capture / pixel data as neural network inputs.
**Why bad:** Requires a vision pipeline, massively inflates input dimensionality, and is unnecessary when BizHawk provides direct memory access to structured game state. Already ruled out in PROJECT.md but worth reinforcing architecturally.
**Instead:** Read game state directly from GBA memory map: health values, positions, attack states, energy levels.

### Anti-Pattern 5: Trying to Run BizHawk Without Xvfb in Containers
**What:** Attempting to run EmuHawk in a container without a virtual framebuffer.
**Why bad:** BizHawk/EmuHawk requires a display (GTK/OpenGL). Without Xvfb, it will crash on startup. There is no official headless mode.
**Instead:** Always use `xvfb-run` in the container entrypoint. This is well-established for running GUI applications in CI/Docker.

## Key Architectural Decisions

### Decision 1: BizHawk Container Image Strategy
**Recommendation:** Build a single Docker image containing BizHawk, Mono, Xvfb, Lua 5.4, OpenAL, and all GTK dependencies. The ROM and save states are mounted at runtime (never baked into the image for legal reasons). The Lua NEAT script is also mounted via workspace or ConfigMap so it can be iterated without rebuilding the image.

**Base image:** `debian:bookworm-slim` (BizHawk has best Linux support on Debian-based distros).

**Confidence:** MEDIUM -- BizHawk on Linux in containers is not a heavily-trodden path. The Xvfb approach is standard for GUI-in-Docker but BizHawk-specific issues may surface (OpenGL/Mesa compatibility, Mono version conflicts). Expect iteration here.

### Decision 2: Genome Storage Backend
**Recommendation:** Use MinIO (S3-compatible object storage) deployed in the Kubernetes cluster. Genomes are small (KB-sized JSON), but organizing them by run/generation with proper naming makes object storage a natural fit. MinIO is simple to deploy on Kubernetes and provides an S3 API that any language can use.

**Alternative considered:** Git repository for genomes. Rejected because git is not designed for high-frequency automated commits, and Tekton Tasks would need git credentials management.

**Confidence:** HIGH -- MinIO on Kubernetes is well-established.

### Decision 3: Metrics Strategy
**Recommendation:** Prometheus + Pushgateway + Grafana. Training is a batch job (not a long-running service), so the Pushgateway pattern is appropriate -- the training container pushes metrics at the end of each generation batch, and Prometheus scrapes the Pushgateway.

Key metrics to track:
- `neat_generation` (counter): Current generation number
- `neat_fitness_max` (gauge): Highest fitness in current generation
- `neat_fitness_avg` (gauge): Average fitness across population
- `neat_species_count` (gauge): Number of active species
- `neat_population_size` (gauge): Total genomes in population
- `eval_win_rate` (gauge): Champion win rate in evaluation fights
- `eval_avg_damage_dealt` (gauge): Average damage per fight
- `eval_avg_survival_time` (gauge): Average frames survived

**Confidence:** HIGH -- Prometheus + Pushgateway for batch jobs is a standard Kubernetes pattern.

### Decision 4: GBA Memory Map as API Contract
**Recommendation:** Treat the GBA memory addresses for DBZ Supersonic Warriors as a formal API contract. Document them in a dedicated file (e.g., `memory_map.lua`) with named constants. This is the interface between the game and the neural network.

Expected memory values to read:
- Player 1 health, Player 2 health
- Player 1 X/Y position, Player 2 X/Y position
- Player 1 attack state, Player 2 attack state
- Player 1 energy/ki, Player 2 energy/ki
- Current frame/timer
- Fight result (win/loss/draw)

**Confidence:** LOW -- Memory addresses are game-specific and must be discovered through reverse engineering. This is a research-heavy task that blocks NEAT input design.

## Build Order (Dependencies Between Components)

The architecture implies a strict build order based on component dependencies:

```
Phase 1: Emulation Foundation
  memory_map.lua (discover GBA addresses) -- BLOCKS EVERYTHING
  BizHawk local setup (manual, not containerized yet)
  Save state creation (fight start state)

Phase 2: NEAT Core in Lua
  neat.lua (NEAT algorithm: population, speciation, crossover, mutation)
  neural_network.lua (forward pass, activation functions)
  game_interface.lua (reads memory map, writes joypad)
  fitness.lua (scoring function)
  -- All developed and tested locally in BizHawk first

Phase 3: Containerization
  Dockerfile for BizHawk (Debian + Mono + Xvfb + Lua + deps)
  Validate BizHawk + Lua script runs in container with xvfb-run
  Genome serialization to JSON (already in Lua, but formalize format)

Phase 4: Tekton Pipeline
  Tekton Tasks (setup, run-training, evaluate, store, decide)
  PVC workspace configuration
  Pipeline definition connecting tasks
  MinIO deployment for genome storage

Phase 5: Observability
  Prometheus + Pushgateway deployment
  Metrics wrapper script in BizHawk container
  Grafana dashboards for training progress

Phase 6: Automation & Iteration
  PipelineRun chaining (decide-continue triggers next run)
  Retraining from versioned genomes
  Parameter tuning (mutation rates, population size)
```

**Critical path:** Phase 1 (memory map discovery) is the highest-risk, highest-uncertainty task and blocks Phase 2. Phase 2 (NEAT in Lua) is the core intellectual work. Phase 3 (containerization) is the first integration risk. Phases 4 and 5 are standard Kubernetes patterns with lower risk.

## Scalability Considerations

| Concern | Single Training Run | Parallel Experiments | Large-Scale Search |
|---------|--------------------|--------------------|-------------------|
| **Compute** | 1 pod running BizHawk (CPU-bound, not GPU) | Multiple PipelineRuns with different hyperparams | Node pool with dedicated training nodes |
| **Storage** | Single PVC + MinIO bucket | Partitioned by run ID in MinIO | Same, genomes are tiny (KB each) |
| **Emulator speed** | ~10-60x real-time with frame skip in BizHawk | Linear scaling with more pods | Limited by cluster node count |
| **Metrics cardinality** | Low (< 20 time series) | Moderate (labeled by run ID) | Still manageable |

**Note:** NEAT training is inherently sequential within a generation (evaluate all genomes, then select/reproduce). Parallelism is across experiments (different hyperparameters, different opponents), not within a single population. Do not try to parallelize a single NEAT population across pods -- the coordination overhead would negate any speedup.

## Sources

- [MarI/O NEAT architecture (SethBling original)](https://glenn-roberts.com/posts/2015/07/08/neuroevolution-with-mario/) - MEDIUM confidence
- [Neat-Genetic-Mario (updated fork)](https://github.com/mam91/Neat-Genetic-Mario) - MEDIUM confidence
- [MarioKart64NEAT Lua implementation](https://github.com/nicknlsn/MarioKart64NEAT) - MEDIUM confidence
- [Tekton MLOps Pipeline with Buildpacks](https://towardsdatascience.com/automate-models-training-an-mlops-pipeline-with-tekton-and-buildpacks/) - MEDIUM confidence
- [Tekton Pipelines v1.9.0 LTS (Feb 2026)](https://tekton.dev/blog/2026/02/02/tekton-pipelines-v1.9.0-lts-continued-innovation-and-stability/) - HIGH confidence
- [Tekton Workspaces documentation](https://tekton.dev/docs/pipelines/workspaces/) - HIGH confidence
- [BizHawk command line args (--lua flag)](https://github.com/TASEmulators/BizHawk/issues/32) - MEDIUM confidence
- [BizHawk GitHub repository](https://github.com/TASEmulators/BizHawk) - HIGH confidence
- [BizHawk Linux setup and dependencies](https://tasvideos.org/Bizhawk) - HIGH confidence
- [NEAT-Python genome interface](https://neat-python.readthedocs.io/en/latest/genome-interface.html) - MEDIUM confidence (reference for genome structure, not used directly)
- [Platform fighting game NEAT bot](https://medium.com/@mikecazzinaro/teaching-ai-to-play-a-platform-fighting-game-using-neural-networks-ef9316c34f52) - LOW confidence
- [Multi-objective NEAT for fighting games (academic)](https://link.springer.com/article/10.1007/s00521-020-04794-x) - MEDIUM confidence
- [Prometheus Pushgateway pattern for batch jobs](https://grafana.com/blog/2021/08/02/how-basisai-uses-grafana-and-prometheus-to-monitor-model-drift-in-machine-learning-workloads/) - MEDIUM confidence
- [Tekton workspace best practices](https://oneuptime.com/blog/post/2026-02-02-tekton-workspaces/view) - MEDIUM confidence
