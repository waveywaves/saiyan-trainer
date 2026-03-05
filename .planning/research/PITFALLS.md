# Pitfalls Research

**Domain:** Neuroevolution (NEAT) game bot + MLOps with Tekton on Kubernetes
**Researched:** 2026-03-06
**Confidence:** MEDIUM (domain-specific pitfalls well-understood; DBZ-specific memory map is LOW confidence due to lack of public documentation)

## Critical Pitfalls

### Pitfall 1: Platformer Fitness Function Applied to a Fighting Game

**What goes wrong:**
Directly porting MarI/O's fitness function (rightward progress over time) to a fighting game produces agents that do nothing useful. The agent learns to run away, spam one move, or stand still -- because the fitness signal does not capture what "winning a fight" actually means. Multi-objective fitness (damage dealt, damage taken, health remaining, rounds won) is required, but naive weighted sums collapse objectives and cause the population to converge on degenerate strategies like "always block" or "always jump-kick."

**Why it happens:**
MarI/O's elegant simplicity (fitness = max X position) makes it tempting to pick a single metric. Fighting games have inherently multi-objective outcomes: you must deal damage AND avoid damage AND manage ki AND land combos. A single scalar fitness flattens this into a deceptive landscape where local optima are easy to reach but globally terrible. The Sonic 2 NEAT adaptation saw similar issues -- the AI learned to hold one button because it was locally optimal.

**How to avoid:**
- Start with a multi-component fitness: `fitness = (damage_dealt * W1) - (damage_taken * W2) + (round_won_bonus * W3) + (ki_efficiency * W4)`. Tune weights empirically.
- Consider Pareto-based multi-objective NEAT (like NEAT-MODS or MM-NEAT) which maintain a Pareto front instead of collapsing to a scalar. Research shows these produce more diverse and generalizable fighting game agents.
- Include a "time alive" penalty that increases over time to prevent passive/stalling strategies.
- Test fitness function against known behaviors: a fitness function is wrong if "always block" scores higher than "fight and sometimes lose."

**Warning signs:**
- All agents in a generation converge to the same behavior (e.g., all jump, all block, all spam one button)
- Fitness plateaus early (within 10-20 generations) at a value far below the theoretical maximum
- Agents beat the easiest CPU difficulty but fail completely at medium difficulty
- Population diversity metrics (number of species, average genetic distance) collapse

**Phase to address:** Phase 1 (NEAT core implementation). The fitness function is the single most important design decision and must be validated before any pipeline work begins.

---

### Pitfall 2: BizHawk Cannot Run Headless in Containers Without Significant Engineering

**What goes wrong:**
BizHawk is a Windows/.NET GUI application. It has no official `--headless` flag. Attempting to run it in a Docker container on Linux for Kubernetes-orchestrated training hits multiple walls: it requires Mono/.NET runtime, a virtual framebuffer (Xvfb) for the GUI it insists on rendering, Lua 5.4 runtime, OpenAL for audio, and x86-64 architecture. Teams waste weeks trying to containerize BizHawk before realizing it was never designed for server-side headless operation.

**Why it happens:**
BizHawk is the standard for TAS/bot projects because of its excellent Lua scripting and memory access APIs. The MarI/O precedent makes it seem like the obvious choice. But MarI/O ran on a desktop, not in a container orchestration system. The leap from "works on my Windows desktop" to "works in a Kubernetes pod" is enormous for a GUI-dependent emulator.

**How to avoid:**
- **Option A (recommended for demo):** Run BizHawk training locally or on a dedicated VM with Xvfb, and use Tekton only for orchestration metadata (triggering runs, collecting results, versioning models). The emulator runs outside Kubernetes; the pipeline coordinates.
- **Option B (harder but pure):** Use `mgba-sdl` (the CLI/headless build of mGBA) instead of BizHawk. mGBA has a command-line frontend that needs no display server. It provides scripting via its own API. Trade-off: mGBA's scripting API differs from BizHawk's Lua API, so MarI/O code cannot be directly ported.
- **Option C (middle ground):** Containerize BizHawk with Xvfb in a Docker image. Use `Xvfb :99 -screen 0 1024x768x24 & export DISPLAY=:99` before launching EmuHawkMono.sh. This works but is fragile, slow to build, and the image will be 1-2 GB.
- Whichever option is chosen, validate containerized emulator operation BEFORE building any Tekton pipelines around it.

**Warning signs:**
- Docker build takes 30+ minutes and produces multi-GB images
- Emulator crashes silently in container (no display server errors hidden in logs)
- Lua scripts that work on desktop fail in container due to path or runtime differences
- Frame advance is 10x slower in container than on desktop (Xvfb overhead)

**Phase to address:** Phase 1-2 (Environment setup). This is a go/no-go decision that shapes the entire architecture. Must be validated as a standalone spike before any pipeline integration.

---

### Pitfall 3: No Public RAM Map Exists for DBZ Supersonic Warriors

**What goes wrong:**
The project assumes it can read game state (health, ki, positions, attack states) from GBA memory. But unlike popular ROM-hacking targets (Pokemon, Mario), Dragon Ball Z: Supersonic Warriors has virtually no publicly documented RAM map. Teams start coding the Lua memory-reading layer and discover they must reverse-engineer every single address from scratch using trial-and-error RAM searching. This can take weeks per variable.

**Why it happens:**
Less popular games have smaller ROM hacking communities. The only addresses found in public databases are a handful of Codebreaker cheat codes (e.g., Ki appears to be around `0300274A`), which give hints but are not a comprehensive map. GameHacking.org has a page for this game but no detailed RAM documentation. The game's fighting mechanics (positions, attack state machines, combo counters, invincibility frames) live in memory addresses that nobody has publicly documented.

**How to avoid:**
- Budget significant time (1-2 weeks minimum) for RAM discovery using BizHawk's RAM Search and Hex Editor tools. This is Phase 1 work that blocks everything else.
- Start with the easiest values to find: Player 1 HP, Player 2 HP, Ki gauge, timer. These have visible on-screen indicators making RAM search straightforward (search for "value decreased" when HP drops).
- Use Codebreaker/GameShark codes as starting points -- the address `0300274A` for Ki suggests game state lives in IWRAM (0x03000000-0x03007FFF range), which is the fast 32KB internal RAM.
- Document every discovered address immediately in a structured format. Create a `memory_map.lua` file that is the single source of truth.
- Accept that some state (exact animation frame, invincibility flags, combo counters) may be too hard to find and design the NEAT inputs to work without them.

**Warning signs:**
- After a week of RAM searching, fewer than 5 reliable addresses have been found
- Addresses that work on one screen/mode break on another (dynamic memory allocation)
- Values at discovered addresses change meaning between game modes (menu vs fight)

**Phase to address:** Phase 1 (Memory map discovery). This is prerequisite work that must complete before NEAT input design can begin. It is the highest-risk unknown in the project.

---

### Pitfall 4: GBA Memory Domain Confusion in BizHawk (IWRAM vs EWRAM vs System Bus)

**What goes wrong:**
BizHawk exposes GBA memory through multiple "domains": System Bus, IWRAM, EWRAM, and Combined WRAM. Developers use addresses from cheat code databases (which use System Bus addresses like `0x0300274A`) but read from the IWRAM domain (which is zero-based, so the same address would be `0x0000274A`). Every read returns garbage. Hours are lost debugging what appears to be wrong addresses when it is actually a domain offset issue.

**Why it happens:**
GBA System Bus maps IWRAM at `0x03000000` and EWRAM at `0x02000000`. When BizHawk exposes these as separate memory domains, it strips the base offset. So System Bus address `0x03001234` becomes IWRAM domain address `0x00001234`. Cheat code databases, GBATEK documentation, and most online resources use System Bus addressing. BizHawk's Lua `memory.readbyte()` function reads from the currently selected domain, which defaults to whatever BizHawk last used.

**How to avoid:**
- Always explicitly specify the memory domain in Lua calls: `memory.read_u16_le(addr, "System Bus")` instead of bare `memory.readbyte(addr)`.
- Alternatively, use System Bus domain for all reads (addresses match cheat databases directly) and avoid IWRAM/EWRAM domains entirely.
- Create a wrapper function early: `function readGameMemory(addr) return memory.read_u16_le(addr, "System Bus") end`
- Document which domain convention the project uses in the memory map file header.
- IWRAM (32KB, `0x03000000-0x03007FFF`) is the CPU's fast internal RAM -- game state variables likely live here. EWRAM (256KB, `0x02000000-0x0203FFFF`) is slower external RAM -- larger data structures, buffers.

**Warning signs:**
- Memory reads return 0 or 255 consistently (reading unmapped regions)
- Values found via BizHawk Hex Editor do not match values read in Lua scripts
- Addresses work for one variable but systematically fail for all others

**Phase to address:** Phase 1 (Memory map discovery). Establish the convention in the first Lua script written.

---

### Pitfall 5: Tekton Default Timeout Kills Long-Running Training

**What goes wrong:**
Tekton PipelineRuns default to a 1-hour timeout. A NEAT training run that evolves 100+ generations will take many hours. The pipeline silently kills the training pod at the 1-hour mark, deleting logs and all intermediate state. The team discovers this after losing their first successful training run.

**Why it happens:**
Tekton is designed for CI/CD where tasks complete in minutes. ML training workloads are fundamentally different -- they run for hours or days. The default timeout is not prominently documented, and the pod deletion behavior (which also destroys logs) is surprising. Additionally, both task-level AND pipeline-level timeouts must be configured -- setting only one is insufficient.

**How to avoid:**
- Set `timeout: "0"` on TaskRuns and PipelineRuns for training workloads (disables timeout entirely).
- Alternatively, set generous explicit timeouts: `timeout: "24h"` on training tasks.
- Configure BOTH `pipeline.spec.timeouts.pipeline` AND individual task timeouts. The pipeline-level timeout caps everything regardless of task-level settings.
- Enable `keep-pod-on-cancel` in Tekton config so that timed-out or cancelled pods retain their logs for debugging.
- Implement checkpointing in the training code: save NEAT population state to the workspace volume every N generations so training can resume after any interruption.

**Warning signs:**
- TaskRun status shows "TaskRunTimeout" with no logs available
- Training runs that worked locally fail in the pipeline after exactly 1 hour
- Pod is deleted but PipelineRun shows "failed" with no useful error message

**Phase to address:** Phase 2-3 (Tekton pipeline setup). Must be configured before the first real training run through the pipeline.

---

### Pitfall 6: NEAT Population Stagnation in Fighting Game Domain

**What goes wrong:**
After 30-50 generations, all species converge to the same behavior. Fitness stops improving. New topological innovations (added nodes/connections) are immediately killed because they reduce fitness in the short term. The population gets stuck in a local optimum like "spam low kick" and never discovers complex strategies like combos or ki attacks.

**Why it happens:**
NEAT's speciation is supposed to protect innovation, but fighting games create deceptive fitness landscapes. A simple strategy (one reliable attack) can achieve moderate fitness quickly, and any structural innovation that temporarily reduces fitness gets eliminated before it can develop. The compatibility distance threshold (`delta_t`) and species stagnation limit are hyperparameters that profoundly affect exploration, but they are rarely tuned for specific domains.

**How to avoid:**
- Increase the species stagnation limit from the typical 15 generations to 30-50 for fighting games. Innovations need more time to optimize in complex domains.
- Use a dynamic compatibility threshold that adjusts to maintain a target number of species (e.g., 10-15 species in a population of 150).
- Add a novelty component to fitness: reward agents that exhibit new behaviors (different button patterns, new positions reached) even if they lose. This prevents premature convergence.
- Implement curriculum training: start against the easiest CPU opponent, only advance difficulty when win rate exceeds 80%. This provides a gradient for learning rather than a cliff.
- Run multiple independent populations and periodically exchange best individuals (island model).

**Warning signs:**
- Number of species drops below 3-4 in a population of 150
- Best fitness has not improved in 20+ generations
- All top-performing genomes have nearly identical topology
- Watching replays shows all agents doing the same sequence of moves

**Phase to address:** Phase 1 (NEAT implementation). Speciation parameters and stagnation handling must be tunable from the start. Curriculum training can be added iteratively.

---

### Pitfall 7: Tekton Workspace PVC Scheduling Deadlocks

**What goes wrong:**
Training pipeline tasks that share a PersistentVolumeClaim (PVC) workspace get scheduled on different availability zones. The second task cannot mount the PVC because it is zone-locked to the first task's node. The PipelineRun hangs indefinitely waiting for the pod to schedule.

**Why it happens:**
Kubernetes PersistentVolumes are often zonal (especially on cloud providers). Tekton creates separate pods for each task, and the Kubernetes scheduler does not inherently understand that these pods need to co-locate. Tekton's Affinity Assistant feature exists to solve this but must be properly configured. If using `volumeClaimTemplate` (auto-created PVCs), the lifecycle is tied to the PipelineRun -- data disappears when the run completes.

**How to avoid:**
- Use Tekton's Affinity Assistant (enabled by default in recent versions) which forces tasks sharing a workspace to schedule on the same node.
- For model storage that must persist across runs, use a pre-provisioned PVC with `ReadWriteMany` access mode (backed by NFS or a cloud file store), not `volumeClaimTemplate`.
- For single-node dev clusters (minikube, kind), this is not an issue -- but document the requirement for multi-node clusters.
- Separate concerns: use `volumeClaimTemplate` for ephemeral build artifacts, and a persistent PVC or object storage (MinIO/S3) for model artifacts that must survive across pipeline runs.

**Warning signs:**
- Pods stuck in `Pending` state with events showing "volume node affinity conflict"
- PipelineRun succeeds on single-node cluster but fails on multi-node
- Model files from a completed training run are gone when the next pipeline tries to load them

**Phase to address:** Phase 2-3 (Tekton pipeline setup). Storage architecture must be designed before building the training pipeline.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Hardcoded memory addresses in Lua | Fast initial development | Every address change requires code edits; no reuse across game versions | Never -- use a `memory_map.lua` config file from day one |
| Single-scalar fitness function | Simpler implementation | Population converges on degenerate strategies; requires rewrite to multi-objective | Only for the first 24 hours of prototyping to prove memory reads work |
| Running emulator on desktop, not in containers | Avoids containerization complexity | Cannot demonstrate MLOps pipeline end-to-end; demo loses its core value proposition | Acceptable for Phase 1 prototyping, must migrate by Phase 3 |
| Skipping model checkpointing | Faster training loop | Lose all progress on any interruption (timeout, OOM, node failure) | Never -- checkpointing is cheap and critical |
| Using `volumeClaimTemplate` for model storage | No PVC pre-provisioning needed | Models deleted when PipelineRun is cleaned up | Only for throwaway dev runs, never for real training |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| BizHawk Lua API | Using `memory.readbyte()` without specifying domain | Always pass domain: `memory.read_u16_le(addr, "System Bus")` |
| BizHawk frame advance | Calling `emu.frameadvance()` without yielding in Lua | BizHawk Lua scripts must yield control back to the emulator each frame; use coroutine-style loops |
| BizHawk save states | Loading save state resets Lua script state | Store all script state in Lua tables that survive save state loads; use `event.onsavestate` / `event.onloadstate` callbacks |
| Tekton task → task data passing | Using results/params for large data (model files) | Use workspace volumes for file data; results/params are for small strings only |
| Tekton + resource quotas | Not setting resource requests/limits on steps | Kubernetes with quotas requires explicit resource requests on every container, including Tekton's init containers; create a LimitRange to cover init containers |
| BizHawk on Linux | Assuming Linux paths work like Windows | Paths in Lua scripts must be absolute or relative to BizHawk install dir; use `$PWD` expansion in shell scripts |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Reading memory every frame for all inputs | Training runs 5-10x slower than expected | Only read memory addresses that change frequently every frame; cache static values (character ID, stage) at round start | Immediately -- GBA runs at 60fps, reading 20+ addresses per frame in Lua adds measurable overhead |
| Running NEAT population evaluation sequentially | One generation takes hours | Each organism's evaluation (one fight) is independent -- parallelize across multiple emulator instances or use frame-skip | At population sizes > 50 |
| Storing full NEAT genome history in PVC | PVC fills up, pipeline fails | Only store best genome per generation + current population; prune history periodically | After ~500 generations with population of 150 |
| Xvfb rendering overhead in container | Emulation is 3-5x slower in container than bare metal | Use frame-skip (advance multiple frames per render), or use `mgba-sdl` with null video output | Immediately in containerized environments |
| Tekton creating one pod per task in training loop | Pod scheduling overhead dominates short tasks | Batch multiple generations into a single long-running task rather than one task per generation | When generation evaluation time < 30 seconds |

## "Looks Done But Isn't" Checklist

- [ ] **Memory map:** Addresses work during fights -- verify they also work during round transitions, character select, and game over screens (addresses may be invalid outside fight mode)
- [ ] **Fitness function:** Agent beats CPU on easy -- verify it does not achieve this by exploiting a single degenerate strategy (watch replays of top agents)
- [ ] **Save state loading:** Training resumes from save state -- verify the Lua script state (generation counter, population data) also restores correctly, not just the emulator state
- [ ] **Tekton pipeline:** Pipeline completes successfully -- verify model artifacts actually persisted to storage and can be loaded by a fresh evaluation run
- [ ] **Containerized emulator:** Emulator runs in container -- verify Lua scripts execute, memory reads return correct values, and frame advance works at acceptable speed
- [ ] **NEAT speciation:** Multiple species exist -- verify they represent genuinely different strategies, not just numerical noise in compatibility distance
- [ ] **Controller input:** Model outputs map to button presses -- verify GBA input includes D-pad directions AND button combinations (special moves require simultaneous inputs like Down+B)

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Wrong fitness function (degenerate convergence) | MEDIUM | Redesign fitness, restart training from scratch. Previous genomes are useless because they optimized for the wrong objective. |
| Memory domain confusion (all reads return garbage) | LOW | Fix domain parameter in read calls, no retraining needed. Quick code fix. |
| No RAM map (blocked on memory discovery) | HIGH | Budget 1-2 weeks for manual RAM search. Cannot be parallelized. Consider pivoting to a game with known RAM maps if blocked too long. |
| Tekton timeout kills training | LOW-MEDIUM | Set timeout to 0, re-run. If checkpointing was implemented, resume from checkpoint. If not, restart from scratch. |
| PVC scheduling deadlock | LOW | Switch to ReadWriteMany PVC or single-node cluster. Pipeline definition change only. |
| BizHawk won't containerize | HIGH | Pivot to mgba-sdl or restructure architecture so emulator runs outside Kubernetes. Significant rearchitecture. |
| Population stagnation | MEDIUM | Adjust speciation parameters, add novelty search, restart training. Previous genomes may seed the new population. |

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Platformer fitness applied to fighting game | Phase 1: NEAT Core | Watch top-5 agent replays; verify diverse strategies exist |
| BizHawk headless containerization | Phase 1-2: Environment Spike | Run emulator + Lua script in Docker, confirm memory reads and frame advance work |
| No public RAM map for DBZ:SW | Phase 1: Memory Discovery | Document at least: P1 HP, P2 HP, P1 Ki, P2 Ki, P1 position, P2 position, round timer |
| IWRAM/EWRAM domain confusion | Phase 1: First Lua Script | Read a known value (e.g., timer) from both System Bus and domain-specific addresses; confirm they match |
| Tekton timeout kills training | Phase 2: Pipeline Config | Run a 2-hour dummy task through the pipeline; confirm it completes |
| NEAT population stagnation | Phase 1-2: NEAT Tuning | After 100 generations, confirm 5+ species exist with distinct behaviors |
| PVC scheduling deadlock | Phase 2: Pipeline Storage | Test pipeline on a multi-node cluster (or document single-node limitation) |

## Sources

- [NEAT Wikipedia](https://en.wikipedia.org/wiki/Neuroevolution_of_augmenting_topologies) -- MEDIUM confidence, speciation/stagnation mechanics
- [Coping with opponents: multi-objective evolutionary neural networks for fighting games](https://link.springer.com/article/10.1007/s00521-020-04794-x) -- HIGH confidence, fighting game NEAT challenges
- [Neuroevolution in Games: State of the Art and Open Challenges](https://arxiv.org/pdf/1410.7326) -- HIGH confidence, foundational survey
- [BizHawk GitHub / Command Line docs](https://tasvideos.org/Bizhawk/CommandLine) -- HIGH confidence, no headless flag confirmed
- [BizHawk Linux compatibility issue #1430](https://github.com/TASEmulators/BizHawk/issues/1430) -- HIGH confidence, Linux runtime requirements
- [GBA Memory Domains - Corrupt.wiki](https://corrupt.wiki/systems/gameboy-advance/bizhawk-memory-domains) -- HIGH confidence, IWRAM/EWRAM/System Bus addressing
- [GBA Memory Layout - gbadoc](https://gbadev.net/gbadoc/memory.html) -- HIGH confidence, authoritative GBA technical reference
- [Tekton TaskRun timeout docs](https://tekton.dev/docs/pipelines/taskruns/) -- HIGH confidence, official documentation
- [Tekton Workspaces docs](https://tekton.dev/docs/pipelines/workspaces/) -- HIGH confidence, official documentation
- [Tekton and Resource Quotas - Red Hat](https://www.redhat.com/en/blog/a-guide-to-tekton-and-resource-quotas) -- MEDIUM confidence, init container resource gotcha
- [Tekton v1.9.0 LTS release notes](https://tekton.dev/blog/2026/02/02/tekton-pipelines-v1.9.0-lts-continued-innovation-and-stability/) -- HIGH confidence, OOM detection and keep-pod-on-cancel
- [mGBA Libretro docs](https://docs.libretro.com/library/mgba/) -- MEDIUM confidence, headless alternative
- [MarI/O NEAT forks: neat-genetic-mario](https://github.com/mam91/neat-genetic-mario), [Sonic 2 NEAT](https://github.com/louisvarley/Sonic-2-Neat-Genetic-bizhawk-genesis-mega-drive) -- MEDIUM confidence, adaptation challenges from platformer to other genres
- [GameHacking.org DBZ:SW page](https://gamehacking.org/game/4393) -- LOW confidence, minimal addresses found; RAM map must be built from scratch
- [Twilio BizHawk Lua tutorial](https://www.twilio.com/en-us/blog/developers/tutorials/building-blocks/how-to-write-lua-scripts-for-video-games-with-the-bizhawk-emulator) -- MEDIUM confidence, Lua scripting patterns

---
*Pitfalls research for: Saiyan Trainer (neuroevolution game bot + Tekton MLOps)*
*Researched: 2026-03-06*
