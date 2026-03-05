# Roadmap: Saiyan Trainer

## Overview

Saiyan Trainer evolves a NEAT neural network to play Dragon Ball Z: Supersonic Warriors on GBA, with the full training lifecycle orchestrated by Tekton on Kubernetes. The roadmap follows a strict dependency chain: discover GBA memory and build the emulator integration layer (Phase 1), implement NEAT and the full training loop locally in BizHawk (Phase 2), containerize BizHawk for headless operation (Phase 3), then wire up Tekton pipelines with observability and MLOps automation on Kubernetes (Phase 4). Phases 1-2 are local development with no infrastructure dependencies. Phases 3-4 add containerization and Kubernetes orchestration on top of a proven training system.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3, 4): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Emulation Foundation** - GBA memory map discovery, controller interface, save state setup, and local dev environment
- [ ] **Phase 2: NEAT Training Engine** - Complete NEAT algorithm, fitness function, training loop, visualization, multi-opponent support, and combo analysis running locally in BizHawk
- [ ] **Phase 3: Containerization** - Package BizHawk with Xvfb into a Docker image that runs NEAT training headlessly, with noVNC web UI for live observation
- [ ] **Phase 4: Tekton Pipeline and MLOps** - Full Tekton pipeline orchestration, distributed evaluation, model versioning, retraining, observability dashboards, and documentation

## Phase Details

### Phase 1: Emulation Foundation
**Goal**: Reliable reading of all game state from GBA memory and sending controller inputs, with a documented memory map and local development environment ready for NEAT development
**Depends on**: Nothing (first phase)
**Requirements**: MEM-01, MEM-02, MEM-03, MEM-04, MEM-05, MEM-06, MEM-07, MEM-08, MEM-09, MEM-10, CTRL-01, CTRL-02, DX-02, DX-03, LOOP-06
**Success Criteria** (what must be TRUE):
  1. Running the memory reader Lua script in BizHawk during a DBZ fight prints accurate P1 and P2 health, ki, position, attack state, round state, and timer values that update in real-time as the fight progresses
  2. A controller test Lua script can make the bot character perform specific moves including simultaneous button combinations (e.g., Down+B for special moves)
  3. A fight-start save state exists that reliably loads to an identical game state every time, providing a deterministic starting point for evaluations
  4. A memory map reference file documents every discovered address with its domain, data type, and meaning
  5. NEAT training can be started locally in BizHawk without any Kubernetes dependency, and ROM is gitignored with clear instructions for users to provide their own copy
**Plans**: 2 plans

Plans:
- [x] 01-01-PLAN.md -- Memory map config, diagnostic reader, and reference documentation
- [ ] 01-02-PLAN.md -- Controller interface, save state management, and project setup

### Phase 2: NEAT Training Engine
**Goal**: A working neuroevolution system that visibly learns to fight in DBZ Supersonic Warriors -- populations evolve, fitness improves over generations, and the bot develops observable fighting behavior beyond button mashing
**Depends on**: Phase 1
**Requirements**: NEAT-01, NEAT-02, NEAT-03, NEAT-04, NEAT-05, NEAT-06, NEAT-07, NEAT-08, NEAT-09, FIT-01, FIT-02, FIT-03, FIT-04, FIT-05, FIT-06, LOOP-01, LOOP-02, LOOP-03, LOOP-04, LOOP-05, VIS-01, VIS-02, VIS-03, OPP-01, OPP-02, COMBO-01, COMBO-02, COMBO-03
**Success Criteria** (what must be TRUE):
  1. Running NEAT training for 50+ generations shows measurable fitness improvement across the population -- early generations lose quickly, later generations survive longer and deal more damage
  2. Training can be stopped and resumed from a JSON checkpoint without losing population state (species, innovation numbers, genome weights)
  3. The neural network overlay on BizHawk's screen shows the evolved topology with active neurons and connection weights during gameplay
  4. Combo analysis output identifies the bot's most frequent button patterns and reports whether it learned actual fighting strategies vs random button mashing
  5. Training can be configured to use different CPU difficulty levels and opponent characters across generations
**Plans**: 3 plans

Plans:
- [ ] 02-01-PLAN.md -- NEAT core algorithm, game inputs, and multi-component fitness function
- [ ] 02-02-PLAN.md -- Training loop, checkpoint save/load, combo analysis, and multi-opponent support
- [ ] 02-03-PLAN.md -- Neural network visualization overlay, HUD, and species timeline

### Phase 3: Containerization
**Goal**: BizHawk runs NEAT training headlessly inside a Docker container, producing genome checkpoints on the filesystem. Container exposes BizHawk display via noVNC web UI so user can observe live training from a browser. The bridge between local development and Kubernetes orchestration.
**Depends on**: Phase 2
**Requirements**: CONT-01, CONT-02, CONT-03, CONT-04, CONT-05, CONT-06, CONT-07, CONT-08
**Success Criteria** (what must be TRUE):
  1. Running the Docker container with a mounted ROM and save state directory produces genome checkpoint JSON files on the host filesystem after N generations of training
  2. The container runs with Xvfb providing the virtual framebuffer -- no X11 forwarding needed
  3. Frame advance speed inside the container is validated as fast enough for practical training (documented benchmark vs local BizHawk)
  4. noVNC web UI at http://localhost:6080/vnc.html shows the live BizHawk display (game view + neural network overlay) during training
  5. Setting ENABLE_VNC=false disables VNC/noVNC without rebuilding the container image
**Plans**: 1 plan

Plans:
- [ ] 03-01-PLAN.md -- Dockerfile, s6-overlay services, noVNC web UI, and speed validation

### Phase 4: Tekton Pipeline and MLOps
**Goal**: The complete training lifecycle -- from triggering a PipelineRun to getting a versioned, evaluated genome stored in object storage with metrics visible in Grafana -- runs on Kubernetes with Tekton orchestration and full documentation
**Depends on**: Phase 3
**Requirements**: TKN-01, TKN-02, TKN-03, TKN-04, TKN-05, TKN-06, TKN-07, RET-01, RET-02, RET-03, RET-04, DIST-01, DIST-02, DIST-03, OBS-01, OBS-02, OBS-03, OBS-04, OBS-05, OBS-06, DX-01
**Success Criteria** (what must be TRUE):
  1. A manually triggered PipelineRun executes the full training loop (setup, train N generations, evaluate champion against CPU, store genome artifacts) and completes without timeout or scheduling failures
  2. After a PipelineRun completes, the best genome is stored in object storage tagged with generation number, fitness score, opponent, and date -- and can be retrieved by version tag
  3. A new PipelineRun can resume training from a previously stored genome checkpoint, continuing evolution from where the last run left off
  4. Grafana dashboards show fitness curves over generations, species count and population diversity, and evaluation win rates from completed pipeline runs
  5. Multiple genomes evaluate in parallel across separate pods using Tekton's fan-out pattern, with results aggregated back into the population
**Plans**: TBD

Plans:
- [ ] 04-01: TBD
- [ ] 04-02: TBD
- [ ] 04-03: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3 -> 4

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Emulation Foundation | 1/2 | In Progress|  |
| 2. NEAT Training Engine | 0/3 | Planning complete | - |
| 3. Containerization | 0/1 | Planning complete | - |
| 4. Tekton Pipeline and MLOps | 0/3 | Not started | - |
