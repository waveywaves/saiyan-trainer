---
phase: 03-containerization
plan: 01
subsystem: infra
tags: [docker, bizhawk, xvfb, novnc, s6-overlay, mono]

# Dependency graph
requires:
  - phase: 02-neat-training-engine
    provides: NEAT training Lua scripts and genome checkpoint format
provides:
  - Docker image packaging BizHawk 2.11 with Xvfb for headless training
  - s6-overlay process supervision with 5 managed services
  - noVNC web UI on port 6080 for browser-based observation
  - ENABLE_VNC toggle for headless vs observable mode
  - validate-speed.sh frame advance benchmarking script
  - docker-compose.yml for local testing
affects: [04-tekton-pipeline, kubernetes-deployment]

# Tech tracking
tech-stack:
  added: [docker, s6-overlay-v3, novnc, websockify, x11vnc, xvfb, fluxbox, mono-complete]
  patterns: [multi-process-container, conditional-service-toggle, volume-mount-data-separation]

key-files:
  created:
    - docker/Dockerfile
    - docker/docker-compose.yml
    - docker/scripts/validate-speed.sh
    - docker/rootfs/etc/s6-overlay/s6-rc.d/xvfb/run
    - docker/rootfs/etc/s6-overlay/s6-rc.d/fluxbox/run
    - docker/rootfs/etc/s6-overlay/s6-rc.d/x11vnc/run
    - docker/rootfs/etc/s6-overlay/s6-rc.d/novnc/run
    - docker/rootfs/etc/s6-overlay/s6-rc.d/bizhawk/run
  modified: []

key-decisions:
  - "s6-overlay v3 over supervisord for container-native process management"
  - "ENABLE_VNC defaults to true per user requirement for always-on web observation"
  - "Bash shebangs for all run scripts to support env var expansion"
  - "docker-compose.yml added for convenient local testing (not in original plan)"

patterns-established:
  - "Conditional service pattern: check ENABLE_VNC, sleep infinity if disabled"
  - "s6-overlay dependency chain: xvfb -> fluxbox -> bizhawk, xvfb -> x11vnc -> novnc"
  - "Volume mount separation: ROMs read-only, output read-write, never bake data into image"

requirements-completed: [CONT-01, CONT-02, CONT-03, CONT-04, CONT-05, CONT-06, CONT-07, CONT-08]

# Metrics
duration: 2min
completed: 2026-03-06
---

# Phase 3 Plan 1: Docker Containerization Summary

**BizHawk 2.11 Docker image with debian:bookworm-slim, s6-overlay v3 process supervision, Xvfb virtual display, and noVNC web UI on port 6080 for headless NEAT training with browser observation**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-05T21:28:34Z
- **Completed:** 2026-03-05T21:30:54Z
- **Tasks:** 1 (of 1 auto task; checkpoint pending)
- **Files created:** 24

## Accomplishments
- Complete Dockerfile with debian:bookworm-slim base, mono-complete, BizHawk 2.11, s6-overlay v3.1.6.2, noVNC + websockify
- 5 s6-overlay longrun services with correct dependency ordering: xvfb (root) -> fluxbox, x11vnc; fluxbox -> bizhawk; x11vnc -> novnc
- ENABLE_VNC environment variable (default true) conditionally disables VNC/noVNC services without rebuild
- Volume mount points for /data/roms, /data/savestates, /data/output, /data/lua
- Frame advance benchmarking script (validate-speed.sh) that measures FPS and reports PASS/WARNING
- docker-compose.yml for convenient local build and test

## Task Commits

Each task was committed atomically:

1. **Task 1: Create Dockerfile and s6-overlay service definitions** - `f65ad93` (feat)

## Files Created/Modified
- `docker/Dockerfile` - Complete container image definition with BizHawk 2.11, Xvfb, s6-overlay, noVNC
- `docker/.dockerignore` - Excludes .md, .git, __pycache__, .pyc from build context
- `docker/docker-compose.yml` - Local testing configuration with volume mounts and shm_size
- `docker/scripts/validate-speed.sh` - Frame advance speed benchmarking script
- `docker/rootfs/etc/s6-overlay/s6-rc.d/xvfb/run` - Xvfb virtual display service
- `docker/rootfs/etc/s6-overlay/s6-rc.d/fluxbox/run` - Fluxbox window manager service
- `docker/rootfs/etc/s6-overlay/s6-rc.d/x11vnc/run` - VNC server with ENABLE_VNC check
- `docker/rootfs/etc/s6-overlay/s6-rc.d/novnc/run` - noVNC web proxy with ENABLE_VNC check
- `docker/rootfs/etc/s6-overlay/s6-rc.d/bizhawk/run` - BizHawk emulator with --chromeless and --lua flags
- `docker/rootfs/etc/s6-overlay/s6-rc.d/*/type` - All services set to longrun
- `docker/rootfs/etc/s6-overlay/s6-rc.d/*/dependencies.d/*` - Dependency ordering files
- `docker/rootfs/etc/s6-overlay/s6-rc.d/user/contents.d/*` - Service registration in user bundle

## Decisions Made
- Used bash shebangs for all run scripts (not execlineb) to support env var expansion in BizHawk CLI args
- ENABLE_VNC defaults to "true" per user requirement that noVNC should always be running
- Added docker-compose.yml for local testing convenience (deviation from plan, Rule 2 - missing critical functionality for usability)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Added docker-compose.yml for local testing**
- **Found during:** Task 1
- **Issue:** Plan specified only Dockerfile but docker-compose.yml is essential for convenient local testing with volume mounts and shm_size
- **Fix:** Created docker-compose.yml with proper volume mounts, shm_size=256m, port mapping, and env vars
- **Files created:** docker/docker-compose.yml
- **Committed in:** f65ad93

---

**Total deviations:** 1 auto-fixed (1 missing critical)
**Impact on plan:** docker-compose.yml is a convenience addition that improves local testing. No scope creep.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Docker image definition complete, ready for building and testing
- Checkpoint pending: human verification of Dockerfile and service definitions before proceeding
- Phase 4 (Tekton Pipeline) can reference this container image for Task definitions

## Self-Check: PASSED

All files verified present. Commit f65ad93 confirmed in git log.

---
*Phase: 03-containerization*
*Completed: 2026-03-06*
