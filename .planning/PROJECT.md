# Saiyan Trainer

## What This Is

An open-source project that trains a neuroevolution (NEAT) model to play and win fights in Dragon Ball Z: Supersonic Warriors on Game Boy Advance. The model runs inside BizHawk emulator via Lua scripting, reading game state from the GBA memory map. The entire training lifecycle (data collection, training, evaluation, model versioning, and deployment) is orchestrated as a full MLOps pipeline using Tekton on Kubernetes.

## Core Value

A working, public demonstration that Tekton can orchestrate real ML workloads end-to-end: from training a neuroevolution model to versioning and retraining it, using a fun, visual, and accessible example (a fighting game bot).

## Requirements

### Validated

(None yet; ship to validate)

### Active

- [ ] NEAT-based neuroevolution model that learns to win fights in DBZ Supersonic Warriors
- [ ] BizHawk Lua script that reads game state from GBA memory map (character positions, health, attack states)
- [ ] BizHawk Lua script that sends controller inputs (model outputs to button presses)
- [ ] MarI/O-style NEAT implementation adapted for a 2D fighting game
- [ ] Fitness function that rewards winning, dealing damage, and penalizes taking damage
- [ ] Tekton Pipeline that orchestrates the full training loop (collect, train, evaluate, store)
- [ ] Model versioning: trained NEAT genomes stored and tagged per generation/run
- [ ] Retraining pipeline: ability to resume or restart training from a versioned model
- [ ] Evaluation pipeline: automated fights against CPU to measure model performance
- [ ] Observable pipeline: training metrics, generation progress, win rates visible
- [ ] Runs on plain Kubernetes with Tekton installed

### Out of Scope

- Screen pixel-based input (using memory map instead for efficiency)
- Real-time multiplayer or online play (training is against CPU opponents)
- Mobile or web frontend (CLI/pipeline-driven workflow)
- OpenShift-specific features (targeting plain Kubernetes)
- Deep RL approaches such as DQN, PPO (using neuroevolution/NEAT instead)

## Context

- **Game:** Dragon Ball Z: Supersonic Warriors (USA) for GBA, a 2D fighting game with multiple characters, special moves, and energy mechanics
- **Emulator:** BizHawk, which supports Lua scripting, memory read/write, frame advance, and save states. Widely used for TAS and bot projects
- **NEAT Precedent:** MarI/O by SethBling demonstrated NEAT in Lua on BizHawk for Super Mario World. This project adapts that approach for a fighting game, which has different challenges (opponent AI, health management, combo timing)
- **ROM location:** `roms/Dragon Ball Z - Supersonic Warriors (USA).gba` (gitignored)
- **Fighting game challenges vs platformers:** Inputs are reactive (opponent-dependent), state space includes two characters, fitness must account for both offense and defense
- **Strategic goal:** Beyond being a demo, this project is a discovery vehicle for identifying what Tekton needs to better support ML/DL workloads. Pain points, workarounds, and custom tooling built here (timeout configs, long-running job patterns, model storage integration, distributed evaluation fan-out, PipelineRun chaining) become the basis for a potential Tekton ML toolkit or extension, packaging these learnings to help people rely more on Tekton for ML pipelines instead of Kubeflow/Argo

## Constraints

- **Emulator:** BizHawk. Lua scripting is the integration layer; model inference must run in Lua or be callable from Lua
- **Platform:** Kubernetes with Tekton, no OpenShift-specific dependencies
- **Model format:** NEAT genome must be serializable and loadable in Lua for BizHawk inference
- **Open source:** All code public, ROM not included (user provides their own)

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| NEAT over Deep RL | Fits Lua/emulator constraints, proven with MarI/O, evolves topology | Working -- Gen 0->1 showed 4x fitness improvement |
| BizHawk over mGBA | Better Lua scripting support, memory access, frame advance, TAS community | Switched to mGBA -- sealed emu model works better for container training |
| Headless + required web UI | Training runs headless but MUST expose BizHawk display via noVNC web UI so user can see live training from a browser at any time | Working -- VNC grid view in dashboard |
| Memory map over pixels | Structured data is more efficient, no vision model needed | Working -- struct stride analysis found correct P2 HP |
| Kubernetes over OpenShift | Broader audience for open-source demo | Working -- Kind cluster with Tekton Loop |
| MarI/O-style Lua NEAT | Proven approach, adapt for fighting game domain | Working -- adapted with KO-focused fitness |
| P2 HP via struct stride | Old VBA address (0x03004C30) read constant 72. Derived correct address (0x03002826) from P2 Ki offset: stride = 0xE8 from P1 struct | Confirmed -- P2 HP now changes during fights |
| Fitness gradient over floor | Floor (-1) eliminated selection pressure. Survival+diversity signals provide gradient even without damage | Confirmed -- fitness differentiation across genomes |
| Tekton Loop over Triggers | Triggers are wrong tool for training loops; native Loop feature provides iteration state | Working -- 12+ commits on tektoncd/pipeline |

---
*Last updated: 2026-03-08 after P2 HP fix and training confirmation*
