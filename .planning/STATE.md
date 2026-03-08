---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: executing
last_updated: "2026-03-08T07:30:00Z"
progress:
  total_phases: 6
  completed_phases: 4
  total_plans: 11
  completed_plans: 11
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-06)

**Core value:** A working, public demonstration that Tekton can orchestrate real ML workloads end-to-end -- using a neuroevolution fighting game bot as a fun, visual example.
**Current focus:** Training working on Kubernetes, tuning NEAT parameters, blog post planned

## Current Position

Phase: 5 of 6 - Blog Post (not yet planned)
Status: Training working with real fitness progression, tuned run active (saiyan-tuned-8xgl4)
Last activity: 2026-03-08 -- P2 HP address fixed, fitness function rewritten, training confirmed working

Progress: [████████░░] 85% (11/11 original plans + Phase 5 pending)

### Session 2026-03-08 Accomplishments (earlier)
- Built native Tekton Loop feature (12 commits on tektoncd/pipeline)
- Tested Loop on Kind cluster (10-iteration pipeline succeeded)
- NEAT training running on Kubernetes via Tekton Loop pipeline
- 99-issue code review completed, all critical/high/medium issues fixed
- Dashboard redesigned (professional dark theme, sidebar navigation, Tekton-only)
- Training metrics (JSON + Prometheus /metrics endpoint)
- VNC live observation from Tekton pods via dashboard

### Session 2026-03-08 Accomplishments (current)
- Fixed P2 HP address: 0x03004C30 (broken, constant 72) -> 0x03002826 (working)
  - Derived via struct stride analysis: P2 Ki - P1 Ki = stride 0xE8
  - "Instant win" cheat at 0x03002826 was actually P2 HP=0 (KO)
- Fixed fitness function: removed -1 floor, added survival+diversity gradient signals
- Fixed lastDamageFrame initialization (was 0, now nil)
- Reduced W_TIMEOUT_WIN 200->50 to break character-switching local optimum
- Tuned NEAT: Population 40, Timeout 600, StaleSpecies 12, NodeMutation 0.35
- Training confirmed working: Gen 0 fitness=65 -> Gen 1 fitness=265 (4x improvement)
- Bot dealing 20 damage to P2, discovering character switch strategy
- 6 commits pushed to origin/main

## Performance Metrics

**Velocity:**
- Total plans completed: 2
- Average duration: -
- Total execution time: 0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| - | - | - | - |

**Recent Trend:**
- Last 5 plans: -
- Trend: -

*Updated after each plan completion*
| Phase 01 P02 | 2m 4s | 2 tasks | 5 files |
| Phase 02 P01 | ~5m | 2 tasks | 12 files |
| Phase 02 P03 | 2m 37s | 2 tasks | 3 files |
| Phase 03 P01 | 2m | 1 task | 24 files |
| Phase 04 P01 | 2m 32s | 2 tasks | 11 files |
| Phase 04 P03 | 5m17s | 2 tasks | 11 files |
| Phase 02.1 P01 | 2m50s | 2 tasks | 3 files |
| Phase 02.1 P02 | 2m52s | 1 task | 3 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [Roadmap]: 4-phase structure following strict dependency chain -- local emulation first (Phase 1), then NEAT engine (Phase 2), then containerization (Phase 3), then Tekton/MLOps (Phase 4)
- [Roadmap]: Phase 1 is highest risk -- no public RAM map for DBZ Supersonic Warriors exists, must reverse-engineer from scratch
- [Roadmap]: DX-01 (README) deferred to Phase 4 since full docs require completed K8s workflow
- [Phase 01]: 8 GBA buttons for NEAT output mapping, excluded Start/Select
- [Phase 02]: Minimal JSON implementation instead of vendored dkjson for BizHawk compatibility
- [Phase 02]: StaleSpecies=30 (doubled from MarI/O's 15) for fighting game complexity
- [Phase 02]: Dependency injection pattern for NEAT module interconnections
- [Phase 02]: Network display left 132px, HUD top-right, species timeline below HUD on GBA screen
- [Phase 03]: s6-overlay v3 over supervisord for container-native process management
- [Phase 03]: ENABLE_VNC defaults to true per user requirement for always-on web observation
- [Phase 03]: Bash shebangs for all s6 run scripts to support env var expansion
- [Phase 04]: Tekton v1.9.0 LTS with v1 API for all pipeline resources
- [Phase 04]: SeaweedFS over MinIO for S3-compatible storage (Apache 2.0)
- [Phase 04]: Genome path convention genomes/{run-id}/gen-{NNNN}/ for version retrieval
- [Phase 04]: volumeClaimTemplate (ephemeral) + SeaweedFS (persistent) for genome storage
- [Phase 04]: Pushgateway with run_id grouping key for metrics isolation
- [Phase 04]: Dashboard ConfigMaps with k8s-sidecar auto-provisioning
- [Phase 04]: Fight replay recording deferred as stretch goal TODO
- [Phase 02.1]: Standalone tool scripts go in lua/tools/ directory
- [Phase 02.1]: RAM scanner uses decrease-weighted scoring for HP-like behavior identification
- [Phase 02.1]: Project limitations tracked in docs/KNOWN_ISSUES.md with status markers
- [Phase 02.1]: Dual-renderer architecture for vis: Painter API shapes always, FreeType text primary, pixel_draw.lua fallback
- [Phase 02.1]: 132x160 semi-transparent overlay at top-left for network display
- [Phase 02.1]: 5-frame draw interval for overlay updates (~12 FPS visual at 60 FPS game)
- [Training Fix]: P2 HP at 0x03002826 via struct stride 0xE8 (not old VBA address 0x03004C30)
- [Training Fix]: round_state (0x03002826) was actually P2 HP -- "instant win" = P2 HP=0 = KO
- [Training Fix]: Fitness floor removed; 0.001 minimum to separate evaluated from unevaluated
- [Training Fix]: W_TIMEOUT_WIN reduced 200->50 to prevent char-switch local optimum
- [Training Fix]: Survival (5.0) + diversity (1.0) fitness signals for gradient without damage
- [Training Fix]: lastDamageFrame=nil sentinel; stall penalty only after damage dealt
- [Config Tune]: Population 40, TimeoutConstant 600, StaleSpecies 12, NodeMutation 0.35

### Roadmap Evolution

- Phase 02.1 inserted after Phase 02: On-Screen Visualization & Training Fixes (URGENT)
- Phase 05 added: Blog Post documenting the debugging journey and training results

### Pending Todos

- Write blog post about the training debugging journey (Phase 5)

### Blockers/Concerns

- [RESOLVED 2026-03-08] P2 HP address was wrong (0x03004C30 read constant 72). Fixed to 0x03002826 via struct stride analysis. Training now shows real damage dealt.
- [RESOLVED 2026-03-08] Fitness floor (-1) killed all gradient signal. Removed; added survival+diversity signals.
- [RESOLVED 2026-03-08] Fitness plateaued at 775.5 -- root causes fixed (innovation, speciation, complexity).
- [ACTIVE] Character switching local optimum: bot gains HP by switching chars for timeout wins. Mitigated by reducing W_TIMEOUT_WIN from 200 to 50.
- [ACTIVE] Species collapse to 4 within 5 generations. Increased NodeMutationChance to 0.35 and StaleSpecies to 12 for more diversity.
- [ACTIVE] mGBA runs at real-time 60fps (no turbo mode). Each generation ~5min with current config.

## Session Continuity

Last session: 2026-03-08
Stopped at: Training fixes deployed, tuned run active (saiyan-tuned-8xgl4), blog post phase to be planned
Resume file: .planning/phases/02.1-on-screen-visualization-training-fixes/.continue-here.md
