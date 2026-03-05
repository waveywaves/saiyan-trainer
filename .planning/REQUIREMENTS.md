# Requirements: Saiyan Trainer

**Defined:** 2026-03-06
**Core Value:** A working, public demonstration that Tekton can orchestrate real ML workloads end-to-end — using a neuroevolution fighting game bot as a fun, visual example.

## v1 Requirements

### Memory & Emulation

- [ ] **MEM-01**: Lua script reads player 1 health from GBA memory map in real-time
- [ ] **MEM-02**: Lua script reads player 2 health from GBA memory map in real-time
- [ ] **MEM-03**: Lua script reads player 1 position (x, y) from GBA memory map
- [ ] **MEM-04**: Lua script reads player 2 position (x, y) from GBA memory map
- [ ] **MEM-05**: Lua script reads player 1 ki/energy level from GBA memory map
- [ ] **MEM-06**: Lua script reads player 2 ki/energy level from GBA memory map
- [ ] **MEM-07**: Lua script reads current attack/animation state for both players
- [ ] **MEM-08**: Lua script reads round state (in-progress, round-over, match-over)
- [ ] **MEM-09**: Lua script reads match timer value
- [ ] **MEM-10**: All memory addresses documented in a memory map reference file

### Controller

- [ ] **CTRL-01**: Lua script translates NEAT output neurons to GBA button presses each frame
- [ ] **CTRL-02**: Controller supports simultaneous button combinations (e.g., Down+B for special moves)

### NEAT Algorithm

- [ ] **NEAT-01**: NEAT population initialization with configurable population size
- [ ] **NEAT-02**: Neural network forward pass computes outputs from memory map inputs
- [ ] **NEAT-03**: Speciation groups genomes by structural compatibility distance
- [ ] **NEAT-04**: Selection within species based on adjusted fitness
- [ ] **NEAT-05**: Crossover produces offspring from two parent genomes
- [ ] **NEAT-06**: Structural mutation adds new nodes and connections
- [ ] **NEAT-07**: Weight mutation perturbs connection weights
- [ ] **NEAT-08**: Innovation number tracking prevents structural duplication
- [ ] **NEAT-09**: Stagnation detection removes species that stop improving

### Fitness

- [ ] **FIT-01**: Fitness rewards damage dealt to opponent
- [ ] **FIT-02**: Fitness penalizes damage taken from opponent
- [ ] **FIT-03**: Fitness gives large bonus for winning a round
- [ ] **FIT-04**: Fitness gives large penalty for losing a round
- [ ] **FIT-05**: Fitness penalizes excessive time without action (anti-stalling)
- [ ] **FIT-06**: Fitness depends on bot's own actions, not opponent self-destruction

### Training Loop

- [ ] **LOOP-01**: Generation loop evaluates all genomes in population against CPU opponent
- [ ] **LOOP-02**: Each genome evaluation starts from an identical save state
- [ ] **LOOP-03**: Genome serialization saves full population state to JSON
- [ ] **LOOP-04**: Training can resume from a saved JSON checkpoint
- [ ] **LOOP-05**: Best genome of each generation is preserved (elitism)
- [ ] **LOOP-06**: Training runs locally in BizHawk without Kubernetes

### Visualization

- [ ] **VIS-01**: Neural network overlay displays evolved topology on BizHawk screen during gameplay
- [ ] **VIS-02**: Overlay shows which neurons are active and connection weights
- [ ] **VIS-03**: Species timeline graph shows species emergence, growth, and extinction over generations

### Multi-Opponent

- [ ] **OPP-01**: Training rotates through multiple CPU difficulty levels across generations
- [ ] **OPP-02**: Training can be configured to use different opponent characters

### Combo Analysis

- [ ] **COMBO-01**: Input logger records button sequences during evaluation fights
- [ ] **COMBO-02**: Analysis tool identifies most frequent button patterns used by trained bot
- [ ] **COMBO-03**: Analysis reports whether bot learned real fighting strategies vs button mashing

### Containerization

- [ ] **CONT-01**: Docker image packages BizHawk with Xvfb for headless operation
- [ ] **CONT-02**: Container runs NEAT training script without display
- [ ] **CONT-03**: Container reads ROM and save states from mounted volumes
- [ ] **CONT-04**: Container writes genome checkpoints to filesystem
- [ ] **CONT-05**: Frame advance speed in container is validated as acceptable for training

### Tekton Pipeline

- [ ] **TKN-01**: Tekton Pipeline definition with setup, train, evaluate, store tasks
- [ ] **TKN-02**: Training Task runs containerized BizHawk NEAT for N generations per PipelineRun
- [ ] **TKN-03**: Evaluation Task loads best genome and runs automated fights, reports win rate
- [ ] **TKN-04**: Storage Task copies genome artifacts to persistent object storage
- [ ] **TKN-05**: Pipeline can be triggered manually via PipelineRun
- [ ] **TKN-06**: Pipeline timeout configured for long-running training (no silent kills)
- [ ] **TKN-07**: Tasks share data via PVC workspace with proper affinity configuration

### Retraining & Versioning

- [ ] **RET-01**: New PipelineRun can resume training from a previously stored genome checkpoint
- [ ] **RET-02**: Each training run's best genome is tagged with generation, fitness, opponent, and date
- [ ] **RET-03**: Stored genomes are retrievable by version tag from object storage
- [ ] **RET-04**: PipelineRun chaining auto-continues training when fitness threshold not met

### Distributed Evaluation

- [ ] **DIST-01**: Multiple genomes can be evaluated in parallel across separate pods
- [ ] **DIST-02**: Fan-out pattern in Tekton distributes genome evaluations
- [ ] **DIST-03**: Results from parallel evaluations are aggregated back into the population

### Observability

- [ ] **OBS-01**: Prometheus Pushgateway receives training metrics from batch jobs
- [ ] **OBS-02**: Grafana dashboard shows fitness curves over generations
- [ ] **OBS-03**: Grafana dashboard shows species count and population diversity
- [ ] **OBS-04**: Grafana dashboard shows evaluation win rates
- [ ] **OBS-05**: BizHawk can record fight replays of best genome as video
- [ ] **OBS-06**: Tekton Dashboard installed and shows pipeline runs

### Developer Experience

- [ ] **DX-01**: README documents project setup, ROM sourcing, and local development
- [ ] **DX-02**: NEAT training runs locally in BizHawk without Kubernetes
- [ ] **DX-03**: ROM is gitignored with clear instructions for users to provide their own

## v2 Requirements

### Advanced Training

- **ADV-01**: Hyperparameter sweep via pipeline parameters (population size, mutation rates)
- **ADV-02**: Novelty search component in fitness to encourage behavioral diversity

### Extended Observability

- **EOBS-01**: Web-based generation progress dashboard (standalone, not Grafana)
- **EOBS-02**: Combo/pattern heatmap visualization

## Out of Scope

| Feature | Reason |
|---------|--------|
| Pixel/vision-based input (CNN) | Memory map provides structured data; no GPU/vision model needed |
| Deep RL (DQN, PPO, A3C) | Different paradigm, doesn't run in Lua on BizHawk |
| Web frontend for training control | CLI/pipeline-driven; Tekton Dashboard provides visibility |
| Real-time multiplayer / online play | Training is against CPU opponents |
| Custom model serving endpoint | Model runs inside BizHawk, not as a REST API |
| OpenShift-specific features | Targeting plain Kubernetes for broader audience |
| Kubeflow Pipelines | Tekton alone is the point of the demo |
| Multi-game support | Focus on DBZ Supersonic Warriors; depth over breadth |
| GUI configuration tool | Lua config file or environment variables suffice |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| MEM-01 | — | Pending |
| MEM-02 | — | Pending |
| MEM-03 | — | Pending |
| MEM-04 | — | Pending |
| MEM-05 | — | Pending |
| MEM-06 | — | Pending |
| MEM-07 | — | Pending |
| MEM-08 | — | Pending |
| MEM-09 | — | Pending |
| MEM-10 | — | Pending |
| CTRL-01 | — | Pending |
| CTRL-02 | — | Pending |
| NEAT-01 | — | Pending |
| NEAT-02 | — | Pending |
| NEAT-03 | — | Pending |
| NEAT-04 | — | Pending |
| NEAT-05 | — | Pending |
| NEAT-06 | — | Pending |
| NEAT-07 | — | Pending |
| NEAT-08 | — | Pending |
| NEAT-09 | — | Pending |
| FIT-01 | — | Pending |
| FIT-02 | — | Pending |
| FIT-03 | — | Pending |
| FIT-04 | — | Pending |
| FIT-05 | — | Pending |
| FIT-06 | — | Pending |
| LOOP-01 | — | Pending |
| LOOP-02 | — | Pending |
| LOOP-03 | — | Pending |
| LOOP-04 | — | Pending |
| LOOP-05 | — | Pending |
| LOOP-06 | — | Pending |
| VIS-01 | — | Pending |
| VIS-02 | — | Pending |
| VIS-03 | — | Pending |
| OPP-01 | — | Pending |
| OPP-02 | — | Pending |
| COMBO-01 | — | Pending |
| COMBO-02 | — | Pending |
| COMBO-03 | — | Pending |
| CONT-01 | — | Pending |
| CONT-02 | — | Pending |
| CONT-03 | — | Pending |
| CONT-04 | — | Pending |
| CONT-05 | — | Pending |
| TKN-01 | — | Pending |
| TKN-02 | — | Pending |
| TKN-03 | — | Pending |
| TKN-04 | — | Pending |
| TKN-05 | — | Pending |
| TKN-06 | — | Pending |
| TKN-07 | — | Pending |
| RET-01 | — | Pending |
| RET-02 | — | Pending |
| RET-03 | — | Pending |
| RET-04 | — | Pending |
| DIST-01 | — | Pending |
| DIST-02 | — | Pending |
| DIST-03 | — | Pending |
| OBS-01 | — | Pending |
| OBS-02 | — | Pending |
| OBS-03 | — | Pending |
| OBS-04 | — | Pending |
| OBS-05 | — | Pending |
| OBS-06 | — | Pending |
| DX-01 | — | Pending |
| DX-02 | — | Pending |
| DX-03 | — | Pending |

**Coverage:**
- v1 requirements: 63 total
- Mapped to phases: 0
- Unmapped: 63 ⚠️

---
*Requirements defined: 2026-03-06*
*Last updated: 2026-03-06 after initial definition*
