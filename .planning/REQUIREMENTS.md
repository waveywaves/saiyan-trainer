# Requirements: Saiyan Trainer

**Defined:** 2026-03-06
**Core Value:** A working, public demonstration that Tekton can orchestrate real ML workloads end-to-end -- using a neuroevolution fighting game bot as a fun, visual example.

## v1 Requirements

### Memory & Emulation

- [x] **MEM-01**: Lua script reads player 1 health from GBA memory map in real-time
- [x] **MEM-02**: Lua script reads player 2 health from GBA memory map in real-time
- [x] **MEM-03**: Lua script reads player 1 position (x, y) from GBA memory map
- [x] **MEM-04**: Lua script reads player 2 position (x, y) from GBA memory map
- [x] **MEM-05**: Lua script reads player 1 ki/energy level from GBA memory map
- [x] **MEM-06**: Lua script reads player 2 ki/energy level from GBA memory map
- [x] **MEM-07**: Lua script reads current attack/animation state for both players
- [x] **MEM-08**: Lua script reads round state (in-progress, round-over, match-over)
- [x] **MEM-09**: Lua script reads match timer value
- [x] **MEM-10**: All memory addresses documented in a memory map reference file

### Controller

- [x] **CTRL-01**: Lua script translates NEAT output neurons to GBA button presses each frame
- [x] **CTRL-02**: Controller supports simultaneous button combinations (e.g., Down+B for special moves)

### NEAT Algorithm

- [x] **NEAT-01**: NEAT population initialization with configurable population size
- [x] **NEAT-02**: Neural network forward pass computes outputs from memory map inputs
- [x] **NEAT-03**: Speciation groups genomes by structural compatibility distance
- [x] **NEAT-04**: Selection within species based on adjusted fitness
- [x] **NEAT-05**: Crossover produces offspring from two parent genomes
- [x] **NEAT-06**: Structural mutation adds new nodes and connections
- [x] **NEAT-07**: Weight mutation perturbs connection weights
- [x] **NEAT-08**: Innovation number tracking prevents structural duplication
- [x] **NEAT-09**: Stagnation detection removes species that stop improving

### Fitness

- [x] **FIT-01**: Fitness rewards damage dealt to opponent
- [x] **FIT-02**: Fitness penalizes damage taken from opponent
- [x] **FIT-03**: Fitness gives large bonus for winning a round
- [x] **FIT-04**: Fitness gives large penalty for losing a round
- [x] **FIT-05**: Fitness penalizes excessive time without action (anti-stalling)
- [x] **FIT-06**: Fitness depends on bot's own actions, not opponent self-destruction

### Training Loop

- [ ] **LOOP-01**: Generation loop evaluates all genomes in population against CPU opponent
- [ ] **LOOP-02**: Each genome evaluation starts from an identical save state
- [ ] **LOOP-03**: Genome serialization saves full population state to JSON
- [ ] **LOOP-04**: Training can resume from a saved JSON checkpoint
- [ ] **LOOP-05**: Best genome of each generation is preserved (elitism)
- [x] **LOOP-06**: Training runs locally in BizHawk without Kubernetes

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
- [ ] **CONT-06**: Container exposes BizHawk display via noVNC web UI accessible from a browser
- [ ] **CONT-07**: User can observe live training (game view + neural network overlay) through the web UI
- [ ] **CONT-08**: Visual access can be toggled via environment variable without rebuilding the container

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
- [x] **DX-02**: NEAT training runs locally in BizHawk without Kubernetes
- [x] **DX-03**: ROM is gitignored with clear instructions for users to provide their own

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
| MEM-01 | Phase 1 | Complete |
| MEM-02 | Phase 1 | Complete |
| MEM-03 | Phase 1 | Complete |
| MEM-04 | Phase 1 | Complete |
| MEM-05 | Phase 1 | Complete |
| MEM-06 | Phase 1 | Complete |
| MEM-07 | Phase 1 | Complete |
| MEM-08 | Phase 1 | Complete |
| MEM-09 | Phase 1 | Complete |
| MEM-10 | Phase 1 | Complete |
| CTRL-01 | Phase 1 | Complete |
| CTRL-02 | Phase 1 | Complete |
| NEAT-01 | Phase 2 | Complete |
| NEAT-02 | Phase 2 | Complete |
| NEAT-03 | Phase 2 | Complete |
| NEAT-04 | Phase 2 | Complete |
| NEAT-05 | Phase 2 | Complete |
| NEAT-06 | Phase 2 | Complete |
| NEAT-07 | Phase 2 | Complete |
| NEAT-08 | Phase 2 | Complete |
| NEAT-09 | Phase 2 | Complete |
| FIT-01 | Phase 2 | Complete |
| FIT-02 | Phase 2 | Complete |
| FIT-03 | Phase 2 | Complete |
| FIT-04 | Phase 2 | Complete |
| FIT-05 | Phase 2 | Complete |
| FIT-06 | Phase 2 | Complete |
| LOOP-01 | Phase 2 | Pending |
| LOOP-02 | Phase 2 | Pending |
| LOOP-03 | Phase 2 | Pending |
| LOOP-04 | Phase 2 | Pending |
| LOOP-05 | Phase 2 | Pending |
| LOOP-06 | Phase 1 | Complete |
| VIS-01 | Phase 2 | Pending |
| VIS-02 | Phase 2 | Pending |
| VIS-03 | Phase 2 | Pending |
| OPP-01 | Phase 2 | Pending |
| OPP-02 | Phase 2 | Pending |
| COMBO-01 | Phase 2 | Pending |
| COMBO-02 | Phase 2 | Pending |
| COMBO-03 | Phase 2 | Pending |
| CONT-01 | Phase 3 | Pending |
| CONT-02 | Phase 3 | Pending |
| CONT-03 | Phase 3 | Pending |
| CONT-04 | Phase 3 | Pending |
| CONT-05 | Phase 3 | Pending |
| CONT-06 | Phase 3 | Pending |
| CONT-07 | Phase 3 | Pending |
| CONT-08 | Phase 3 | Pending |
| TKN-01 | Phase 4 | Pending |
| TKN-02 | Phase 4 | Pending |
| TKN-03 | Phase 4 | Pending |
| TKN-04 | Phase 4 | Pending |
| TKN-05 | Phase 4 | Pending |
| TKN-06 | Phase 4 | Pending |
| TKN-07 | Phase 4 | Pending |
| RET-01 | Phase 4 | Pending |
| RET-02 | Phase 4 | Pending |
| RET-03 | Phase 4 | Pending |
| RET-04 | Phase 4 | Pending |
| DIST-01 | Phase 4 | Pending |
| DIST-02 | Phase 4 | Pending |
| DIST-03 | Phase 4 | Pending |
| OBS-01 | Phase 4 | Pending |
| OBS-02 | Phase 4 | Pending |
| OBS-03 | Phase 4 | Pending |
| OBS-04 | Phase 4 | Pending |
| OBS-05 | Phase 4 | Pending |
| OBS-06 | Phase 4 | Pending |
| DX-01 | Phase 4 | Pending |
| DX-02 | Phase 1 | Complete |
| DX-03 | Phase 1 | Complete |

**Coverage:**
- v1 requirements: 72 total
- Mapped to phases: 72
- Unmapped: 0

---
*Requirements defined: 2026-03-06*
*Last updated: 2026-03-06 after roadmap phase mapping*
