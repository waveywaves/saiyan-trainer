---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: executing
last_updated: "2026-03-08T02:30:00Z"
progress:
  total_phases: 5
  completed_phases: 4
  total_plans: 11
  completed_plans: 11
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-06)

**Core value:** A working, public demonstration that Tekton can orchestrate real ML workloads end-to-end -- using a neuroevolution fighting game bot as a fun, visual example.
**Current focus:** Training running on Kubernetes via Tekton Loop pipeline

## Current Position

Phase: All phases complete (01, 02, 02.1, 03, 04)
Status: Training running on Kind cluster with Tekton Loop
Last activity: 2026-03-08 -- 99-issue code review, all fixes applied, dashboard redesigned

Progress: [██████████] 100% (All 11 plans complete)

### Session 2026-03-08 Accomplishments
- Built native Tekton Loop feature (12 commits on tektoncd/pipeline)
- Tested Loop on Kind cluster (10-iteration pipeline succeeded)
- NEAT training running on Kubernetes via Tekton Loop pipeline
- 99-issue code review completed, all critical/high/medium issues fixed
- Dashboard redesigned (professional dark theme, sidebar navigation, Tekton-only)
- Training metrics (JSON + Prometheus /metrics endpoint)
- VNC live observation from Tekton pods via dashboard

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

### Roadmap Evolution

- Phase 02.1 inserted after Phase 02: On-Screen Visualization & Training Fixes (URGENT)

### Pending Todos

None yet.

### Blockers/Concerns

- Phase 1 risk: GBA RAM map for DBZ Supersonic Warriors must be reverse-engineered from scratch. Timeline unpredictable. If >2 weeks, consider pivoting to a game with known RAM maps as proof-of-concept.
- Phase 3 risk: BizHawk containerization with Xvfb is sparsely documented. Needs validation spike. Fallback: run emulator outside K8s.
- [2026-03-07] NEAT TRAINING: Fitness plateaued at 775.5 from Gen 6-16+ (10 generations stagnation). Root causes identified from checkpoint analysis:
  - Innovation counter bug: Checkpoint module creates separate Innovation instance via dofile(), always saves innovation=0. Auto-corrected on load but crossover alignment degrades.
  - Species collapse: target=12 but actual=1 most of the time. No diversity protection. All genomes converge to same local optimum.
  - Over-complexity: ~85 genes, ~11 hidden nodes by Gen 16 — networks too complex for problem. NodeMutationChance=0.50 too high.
  - Population too small: 30 genomes insufficient for meaningful speciation and exploration.
  - Fixes applied: shared Innovation module, tuned speciation params, improved overlay rendering.

## Session Continuity

Last session: 2026-03-08
Stopped at: Session resumed, proceeding to check training status and continue improvements
Resume file: .planning/phases/02.1-on-screen-visualization-training-fixes/.continue-here.md
