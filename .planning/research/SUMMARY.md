# Project Research Summary

**Project:** Saiyan Trainer
**Domain:** Neuroevolution game bot (NEAT) with MLOps pipeline orchestration (Tekton on Kubernetes)
**Researched:** 2026-03-06
**Confidence:** MEDIUM

## Executive Summary

Saiyan Trainer is a neuroevolution project that evolves a neural network to play Dragon Ball Z: Supersonic Warriors (GBA) using the NEAT algorithm, with training orchestrated by Tekton Pipelines on Kubernetes. The established approach for this class of project is the "MarI/O pattern": NEAT implemented entirely in Lua, running inside the BizHawk emulator, reading game state from RAM and writing controller inputs via the joypad API. This pattern is proven across dozens of game bot projects (MarI/O, MarioKart64NEAT, Bizhawk-NEAT-GameSolver). The MLOps layer wraps this with Tekton for pipeline orchestration, SeaweedFS/MinIO for genome artifact storage, and Prometheus for training metrics -- turning a desktop experiment into a Kubernetes-native ML workflow.

The recommended approach is to build in strict dependency order: first discover the GBA RAM map for DBZ Supersonic Warriors (the highest-risk unknown), then implement NEAT in Lua locally in BizHawk, then containerize BizHawk with Xvfb, and finally build the Tekton pipeline around the containerized training. This ordering is non-negotiable because each layer depends on the one below it, and the two riskiest tasks (RAM discovery and BizHawk containerization) must be validated as standalone spikes before investing in pipeline integration.

The key risks are threefold. First, no public RAM map exists for DBZ Supersonic Warriors -- every memory address must be reverse-engineered, which could take 1-2 weeks and blocks all NEAT development. Second, BizHawk was never designed for headless container operation; containerizing it with Xvfb is achievable but fragile and underdocumented. Third, fighting game fitness functions are fundamentally harder than platformer fitness (MarI/O's "go right" does not translate); a poorly designed fitness function will produce agents that spam one move or stand still. All three risks are mitigatable with the right phase ordering and early validation spikes.

## Key Findings

### Recommended Stack

The stack splits into two worlds: the Emulation/NEAT layer (Lua in BizHawk) and the MLOps layer (Tekton on Kubernetes). These worlds connect through containerization -- BizHawk packaged in a Docker image that Tekton Tasks run as pods.

**Core technologies:**
- **BizHawk 2.11** (with bundled Lua 5.4): GBA emulator with Lua scripting, frame advance, save states, and joypad control -- the only viable option for TAS-grade automated game interaction
- **Custom NEAT in Lua** (MarI/O-derived): Fork the MarI/O/NEATEvolve pattern rather than using dead libraries (LuaNEAT) or adding IPC overhead (neat-python via sockets)
- **Tekton Pipelines v1.9.0 LTS**: Pipeline orchestration for training workflows -- project requirement, latest LTS with Pipelines-in-Pipelines support
- **SeaweedFS**: S3-compatible object storage for genome artifacts -- preferred over MinIO due to MinIO's 2025 licensing changes (community binaries no longer distributed)
- **Xvfb**: Virtual framebuffer for running BizHawk headless in containers -- BizHawk has no headless mode; this is the only workaround
- **Prometheus + Pushgateway + Grafana**: Training metrics collection and visualization using standard Kubernetes batch-job observability patterns

**Critical version requirements:** Kubernetes 1.28+ (required by Tekton v1.9.0 LTS). BizHawk 2.11 on Linux requires Mono 6.12+ runtime.

### Expected Features

**Must have (table stakes):**
- GBA memory map reader for DBZ Supersonic Warriors (HP, positions, ki, attack states)
- Controller input writer (NEAT outputs to GBA button presses)
- NEAT implementation in Lua (population, speciation, crossover, mutation)
- Multi-component fitness function (damage dealt, damage taken, round wins, time penalties)
- Save state management (deterministic fight-start state for each evaluation)
- Genome serialization as JSON (save/load training progress)
- Tekton Pipeline definition (setup, train, evaluate, store tasks)
- Basic training metrics output (generation, fitness, species count)
- Reproducible local run without Kubernetes (for NEAT development iteration)

**Should have (differentiators):**
- Neural network visualization overlay (MarI/O's most memorable feature -- visually compelling for demos)
- Pipeline-driven retraining from checkpoint (demonstrates real MLOps iteration pattern)
- Model versioning with generation tagging (makes the Tekton demo feel like real MLOps)
- Recorded fight playback of best genome (visual proof the bot works, shareable)
- Tekton Dashboard integration (low effort, automatic pipeline visibility)

**Defer (v2+):**
- Distributed evaluation across pods (high complexity, tackle after single-pod works)
- Generation progress dashboard with fitness curves (needs real training data first)
- Multi-opponent training curriculum (optimization after basic training succeeds)
- Species visualization over time (nice but not essential)
- Combo/pattern analysis of learned behavior (post-hoc research feature)

### Architecture Approach

The system is a four-layer architecture: Emulation Layer (BizHawk + Lua NEAT in a container), Orchestration Layer (Tekton Pipeline with 5 tasks: setup, train, evaluate, store, decide-continue), Storage Layer (SeaweedFS for genomes, Prometheus for metrics, PVC for save states), and Observability Layer (Grafana dashboards). Tasks share data via PVC workspaces within a PipelineRun, and durable artifacts are copied to object storage. Training runs in batches of N generations per PipelineRun, with automatic continuation via PipelineRun chaining when fitness thresholds are not met.

**Major components:**
1. **Lua NEAT Script** -- Implements NEAT algorithm, reads GBA memory, drives controller inputs, evaluates fitness, serializes genomes. This is the core intellectual work.
2. **BizHawk Container Image** -- Packages EmuHawk + Xvfb + Mono + Lua + dependencies. ROM and save states mounted at runtime (never baked in for legal reasons). The hardest infrastructure deliverable.
3. **Tekton Pipeline (train-generation)** -- Orchestrates training: setup-generation, run-training, evaluate-champion, store-results, decide-continue. Each task is a separate pod sharing a PVC workspace.
4. **Genome Store (SeaweedFS)** -- Persistent, versioned storage for NEAT genome JSON files organized by run and generation.
5. **Observability Stack** -- Prometheus Pushgateway (batch metrics from training), Prometheus (scraping), Grafana (dashboards for fitness curves and evaluation results).

**Key patterns to follow:**
- Batched generation execution (50 generations per PipelineRun, not one-per-task)
- JSON genome serialization (human-readable, cross-language compatible)
- Save state anchoring (deterministic fight start for fair fitness comparison)
- Sidecar metrics push (wrapper script reads Lua output files, pushes to Pushgateway)
- PipelineRun chaining for continuation (clean per-batch boundaries with K8s-level observability)

### Critical Pitfalls

1. **No public RAM map for DBZ Supersonic Warriors** -- Must reverse-engineer every memory address from scratch. Budget 1-2 weeks. Use BizHawk's RAM Search tool, start with visible on-screen values (HP, Ki). Cheat codes suggest game state lives in IWRAM (0x03000000 range). This blocks ALL NEAT development.

2. **Fighting game fitness is fundamentally different from platformer fitness** -- MarI/O's "go right" does not work. Must use multi-component fitness (damage dealt, damage taken, round wins, time penalties). Test that "always block" does not outscore "fight actively." Consider Pareto-based multi-objective NEAT if scalar fitness produces degenerate convergence.

3. **BizHawk containerization is uncharted territory** -- No established Docker images exist. Requires Mono + Xvfb + OpenAL + Lua in a 1-2 GB image. Validate as a standalone spike before building pipelines around it. Fallback: run emulator outside K8s, use Tekton for orchestration metadata only.

4. **GBA memory domain confusion (IWRAM vs System Bus)** -- Cheat databases use System Bus addresses (0x0300XXXX), but BizHawk's IWRAM domain strips the base offset. Always use `memory.read_u16_le(addr, "System Bus")` to avoid hours of debugging garbage reads.

5. **Tekton default timeout kills long-running training** -- Default 1-hour timeout silently kills training pods and deletes logs. Set `timeout: "0"` on both TaskRun and PipelineRun levels. Enable `keep-pod-on-cancel`. Implement checkpointing every N generations.

6. **NEAT population stagnation** -- After 30-50 generations, species converge on degenerate strategies. Increase stagnation limit to 30-50 generations, use dynamic compatibility threshold, add novelty component to fitness, implement curriculum training against increasing CPU difficulty.

7. **Tekton workspace PVC scheduling deadlocks** -- Tasks sharing a PVC get scheduled on different nodes. Use Tekton's Affinity Assistant (enabled by default). Use pre-provisioned ReadWriteMany PVCs for cross-run persistence, not volumeClaimTemplates.

## Implications for Roadmap

Based on research, suggested phase structure:

### Phase 1: Emulation Foundation and Memory Discovery
**Rationale:** Everything depends on reading game state from GBA RAM. This is the highest-risk, highest-uncertainty task. It must be validated before any NEAT code is written. Also establishes the local BizHawk development environment.
**Delivers:** Working `memory_map.lua` with documented RAM addresses for P1/P2 health, ki, positions, attack states, round state, timer. BizHawk local setup with fight-start save state. Proof that game state can be reliably read from Lua.
**Addresses:** GBA memory map reader, save state management, local run capability
**Avoids:** Pitfall 3 (no RAM map), Pitfall 4 (domain confusion)
**Estimated risk:** HIGH -- memory discovery timeline is unpredictable

### Phase 2: NEAT Core in Lua
**Rationale:** With memory map in hand, implement the NEAT algorithm and fighting game fitness function. This is the core intellectual work and must be proven locally before containerization. Fitness function design is the second highest-risk decision.
**Delivers:** Working NEAT training loop in BizHawk: population management, speciation, crossover, mutation, neural network forward pass, multi-component fitness evaluation, genome serialization to JSON. Agents that visibly learn to fight (not spam one move).
**Addresses:** NEAT implementation, fitness function, generation loop, speciation, genome serialization, controller input writer
**Avoids:** Pitfall 1 (platformer fitness applied to fighter), Pitfall 6 (population stagnation)
**Uses:** Custom NEAT in Lua (MarI/O-derived), BizHawk Lua API

### Phase 3: Containerization and Validation
**Rationale:** The bridge between desktop development and Kubernetes orchestration. BizHawk containerization is the second highest-risk infrastructure task. Must be validated as a standalone spike -- if it fails, the architecture must pivot (emulator outside K8s).
**Delivers:** Docker image with BizHawk + Xvfb + Mono + Lua that runs the NEAT training script headless. Verified: Lua scripts execute, memory reads work, frame advance runs at acceptable speed, genomes serialize to the filesystem.
**Addresses:** Containerized training capability
**Avoids:** Pitfall 2 (BizHawk headless containerization)
**Uses:** Mono 6.12+, Xvfb, Debian base image

### Phase 4: Tekton Pipeline and Storage
**Rationale:** With a working container image, build the pipeline orchestration. Tekton patterns are well-documented and lower risk than Phases 1-3. SeaweedFS deployment and PVC workspace configuration are standard Kubernetes operations.
**Delivers:** Complete Tekton Pipeline (setup-generation, run-training, evaluate-champion, store-results, decide-continue). SeaweedFS deployment with genome versioning. PVC workspace with proper affinity configuration. Manual PipelineRun triggering.
**Addresses:** Tekton Pipeline definition, training task, evaluation task, model storage task, pipeline triggers
**Avoids:** Pitfall 5 (timeout kills training), Pitfall 7 (PVC scheduling deadlock)
**Implements:** Orchestration Layer, Storage Layer (genome store)

### Phase 5: Observability and Visualization
**Rationale:** Training works end-to-end; now make it observable. Prometheus + Grafana is standard K8s infrastructure. Neural network visualization is the project's visual signature and increases shareability.
**Delivers:** Prometheus + Pushgateway + Grafana deployment with training dashboards (fitness curves, species count, win rate). Neural network visualization overlay in BizHawk. Fight replay recording capability. Tekton Dashboard integration.
**Addresses:** Training metrics, neural network visualization, recorded fight playback, Tekton Dashboard
**Uses:** Prometheus, Pushgateway, Grafana, BizHawk GUI API

### Phase 6: MLOps Maturity and Automation
**Rationale:** The polish phase that demonstrates real MLOps patterns beyond a simple training script. Retraining from checkpoints and PipelineRun chaining show the iterate-and-improve loop that distinguishes MLOps from one-shot training.
**Delivers:** PipelineRun chaining (automatic continuation when fitness threshold not met). Retraining from versioned genome checkpoints. Model versioning with metadata tagging. Parameter tuning via pipeline parameters.
**Addresses:** Pipeline-driven retraining, model versioning, multi-opponent curriculum (stretch)

### Phase Ordering Rationale

- **Strict dependency chain:** Memory map (Phase 1) blocks NEAT inputs (Phase 2), which blocks containerization validation (Phase 3), which blocks Tekton integration (Phase 4). This is not negotiable.
- **Risk-first ordering:** The two highest-risk unknowns (RAM discovery and BizHawk containerization) are in Phases 1 and 3 respectively. If either fails, the project pivots early rather than discovering blockers after building pipeline infrastructure.
- **Local-first development:** Phases 1-2 require only BizHawk on a desktop. Kubernetes is not needed until Phase 4. This lets NEAT development proceed without cluster infrastructure.
- **MLOps features are additive:** Phases 4-6 layer orchestration, observability, and automation on top of a working training system. Each phase delivers standalone value.

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 1:** RAM discovery for DBZ Supersonic Warriors is completely undocumented. No public memory maps exist. Needs hands-on reverse engineering with BizHawk RAM Search. Cannot be researched further -- must be done empirically.
- **Phase 2:** Fighting game fitness function design is a known hard problem. Consult the multi-objective NEAT paper (Springer, 2020) during implementation. May need iteration.
- **Phase 3:** BizHawk containerization is sparsely documented. No community Docker images to reference. Needs a validation spike before committing to this approach.

Phases with standard patterns (skip research-phase):
- **Phase 4:** Tekton Pipeline definition follows well-documented patterns. The MLOps-with-Tekton tutorial and official docs provide sufficient guidance.
- **Phase 5:** Prometheus + Pushgateway + Grafana on Kubernetes is thoroughly documented. Standard observability stack.
- **Phase 6:** PipelineRun chaining and model versioning are straightforward extensions of Phase 4 patterns.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | BizHawk, Lua, Tekton, and Prometheus are well-established. SeaweedFS replacing MinIO is the only non-obvious choice, but well-justified by MinIO licensing changes. |
| Features | MEDIUM | Table stakes are clear from MarI/O precedent. Fighting game-specific features (fitness function, multi-opponent curriculum) lack established patterns for this specific game. |
| Architecture | MEDIUM | Four-layer architecture is sound and follows established patterns (MarI/O for emulation, Tekton docs for orchestration). BizHawk containerization is the weak link -- the architecture assumes it works. |
| Pitfalls | HIGH | Pitfalls are well-documented across MarI/O forks, fighting game neuroevolution research, and Tekton community experience. The domain-specific pitfalls (RAM discovery, fitness design) are real and verified. |

**Overall confidence:** MEDIUM

The stack and pitfalls are well-understood. The uncertainty is concentrated in two areas: whether DBZ Supersonic Warriors' RAM can be reliably mapped (Phase 1 risk), and whether BizHawk will cooperate in containers (Phase 3 risk). Both are empirical questions that research alone cannot answer -- they require validation spikes.

### Gaps to Address

- **DBZ Supersonic Warriors RAM map:** No public documentation exists. Must be built from scratch. If this takes longer than 2 weeks, consider pivoting to a game with known RAM maps (Pokemon, Mario) as a proof-of-concept, then returning to DBZ.
- **BizHawk container performance:** Unknown whether Xvfb overhead makes containerized training impractically slow. Frame skip can mitigate, but exact performance characteristics are unknown until tested. The fallback (mgba-sdl with native headless support) requires rewriting Lua API calls.
- **Lua 5.4 compatibility with MarI/O code:** Lua 5.4 introduces integer/float distinction. MarI/O code written for Lua 5.1-5.3 may have subtle arithmetic bugs. Must be tested during Phase 2.
- **BizHawk mGBA core memory callback bug (Issue #4631):** NRE crashes when memory callbacks are set. Must verify this is fixed in BizHawk 2.11, or use polling-based memory reads exclusively.
- **GBA input combinations for special moves:** DBZ fighting games require simultaneous button inputs (e.g., Down+B) for special moves. NEAT output layer must support multi-button activation per frame, not just single-button selection.

## Sources

### Primary (HIGH confidence)
- [BizHawk GitHub Repository](https://github.com/TASEmulators/BizHawk) -- emulator capabilities, Linux support, Lua API
- [BizHawk Lua Functions Reference](https://tasvideos.org/Bizhawk/LuaFunctions) -- memory, joypad, savestate, emu APIs
- [Tekton Pipelines v1.9.0 LTS](https://tekton.dev/blog/2026/02/02/tekton-pipelines-v1.9.0-lts-continued-innovation-and-stability/) -- pipeline features, timeout handling, HA
- [Tekton Workspaces Documentation](https://tekton.dev/docs/pipelines/workspaces/) -- PVC sharing, affinity assistant
- [GBA Memory Layout (gbadoc)](https://gbadev.net/gbadoc/memory.html) -- IWRAM/EWRAM addressing
- [GBA Memory Domains (Corrupt.wiki)](https://corrupt.wiki/systems/gameboy-advance/bizhawk-memory-domains) -- BizHawk domain vs System Bus
- [Multi-objective NEAT for fighting games (Springer)](https://link.springer.com/article/10.1007/s00521-020-04794-x) -- fitness function design
- [Neuroevolution in Games survey (arXiv)](https://arxiv.org/pdf/1410.7326) -- domain challenges and patterns

### Secondary (MEDIUM confidence)
- [NEATEvolve (improved MarI/O fork)](https://github.com/SngLol/NEATEvolve) -- save/load bug fixes, reference implementation
- [Bizhawk-NEAT-GameSolver](https://github.com/LionelBergen/Bizhawk-NEAT-GameSolver-ML-AI) -- working BizHawk NEAT project
- [MarioKart64NEAT](https://github.com/nicknlsn/MarioKart64NEAT) -- Lua NEAT adaptation for non-platformer game
- [MLOps Pipeline with Tekton](https://towardsdatascience.com/automate-models-training-an-mlops-pipeline-with-tekton-and-buildpacks/) -- Tekton ML pipeline patterns
- [MarI/O NEAT explanation](https://glenn-roberts.com/posts/2015/07/08/neuroevolution-with-mario/) -- foundational architecture pattern

### Tertiary (LOW confidence)
- [GameHacking.org DBZ:SW page](https://gamehacking.org/game/4393) -- minimal cheat codes, Ki address hint at 0x0300274A
- [Platform fighting game NEAT blog](https://medium.com/@mikecazzinaro/teaching-ai-to-play-a-platform-fighting-game-using-neural-networks-ef9316c34f52) -- anecdotal fighting game NEAT experience

---
*Research completed: 2026-03-06*
*Ready for roadmap: yes*
