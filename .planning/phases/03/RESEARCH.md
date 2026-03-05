# Phase 3: Containerization - Research

**Researched:** 2026-03-06
**Domain:** Docker containerization of BizHawk emulator with Xvfb + noVNC for headless training and web-based observation
**Confidence:** MEDIUM

## Summary

Phase 3 bridges local BizHawk development (Phases 1-2) and Kubernetes orchestration (Phase 4) by packaging BizHawk into a Docker container that runs NEAT training headlessly via Xvfb, exposes the emulator display via noVNC for browser-based observation, and writes genome checkpoints to mounted volumes. This is one of the highest-risk infrastructure deliverables in the project because BizHawk was never designed for containerized or headless operation -- no community Docker images exist, and the dependency chain (Mono + Xvfb + OpenAL + Lua 5.4 + x11vnc + noVNC) requires careful assembly.

The container must run multiple processes simultaneously: Xvfb (virtual display), BizHawk/EmuHawk (emulator), x11vnc (VNC server), and noVNC/websockify (web proxy). This is a well-established pattern in the Docker ecosystem for running GUI applications in containers, with process supervision handled by either supervisord or s6-overlay. The noVNC layer must be toggleable via environment variable so the container can run in pure headless mode (no VNC overhead) or with web UI access for observation.

BizHawk 2.11 on Linux requires Mono (not .NET Core), and provides the `--chromeless` flag to strip window chrome, plus the `--lua` flag for auto-loading training scripts. The `--chromeless` flag does NOT make BizHawk headless -- Xvfb is still required. The mGBA core (used for GBA emulation) has a known memory callback bug (Issue #4631) that causes NullReferenceExceptions on core reboot -- this is fixed in 2.11.1 dev builds, so either use polling-based memory reads or use a 2.11.1 dev build.

**Primary recommendation:** Build a Debian bookworm-slim based Docker image with Mono, Xvfb, x11vnc, noVNC, and s6-overlay for process supervision. Use `--chromeless` and `--lua` flags to auto-start training. Toggle noVNC via an `ENABLE_VNC` environment variable in the entrypoint script.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| CONT-01 | Docker image packages BizHawk with Xvfb for headless operation | Dockerfile pattern with debian:bookworm-slim + mono-complete + xvfb + BizHawk 2.11; s6-overlay for process management |
| CONT-02 | Container runs NEAT training script without display | `xvfb-run` or Xvfb daemon + `DISPLAY=:99` + `EmuHawkMono.sh --chromeless --lua=/path/to/neat.lua rom.gba` |
| CONT-03 | Container reads ROM and save states from mounted volumes | Mount `/data/roms` and `/data/savestates` as Docker volumes; use `--load-state` CLI flag for save state |
| CONT-04 | Container writes genome checkpoints to filesystem | Lua script writes JSON to `/data/output/` which is a mounted volume; verified pattern from architecture research |
| CONT-05 | Frame advance speed in container is validated as acceptable | Must benchmark Xvfb overhead vs bare metal; use `--chromeless` to reduce rendering; expect 3-5x slowdown with Xvfb |
| CONT-06 | Container exposes BizHawk display via noVNC web UI | Xvfb + x11vnc + noVNC/websockify on port 6080; standard Docker noVNC pattern |
| CONT-07 | User can observe live training through the web UI | noVNC renders the Xvfb display showing BizHawk game view + neural network overlay at `http://host:6080/vnc.html` |
| CONT-08 | Visual access can be toggled via environment variable | `ENABLE_VNC=true/false` env var controls whether x11vnc and noVNC processes start; Xvfb always runs regardless |
</phase_requirements>

## Standard Stack

### Core
| Component | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| debian:bookworm-slim | 12 | Base Docker image | Stable, small, Mono and all dependencies available in apt; BizHawk has best Linux support on Debian |
| mono-complete | 6.12+ (apt) | .NET runtime for BizHawk on Linux | BizHawk 2.11 requires Mono, NOT .NET Core/.NET 8; official requirement |
| BizHawk | 2.11 | GBA emulator with Lua scripting | Project requirement; latest stable release (Sep 2025) |
| Xvfb | system package | Virtual X11 framebuffer | BizHawk requires a display server; Xvfb provides one without hardware; always needed even when VNC is disabled |
| x11vnc | system package | VNC server that captures Xvfb display | Bridges Xvfb to VNC protocol; standard pairing with Xvfb in Docker |
| noVNC + websockify | latest (git clone) | HTML5 VNC client + WebSocket proxy | Exposes VNC stream as web page accessible from any browser on port 6080 |
| s6-overlay | v3.x | Multi-process container init/supervisor | Purpose-built for containers; proper PID 1, signal forwarding, graceful shutdown, dependency ordering; recommended over supervisord |

### Supporting
| Component | Version | Purpose | When to Use |
|-----------|---------|---------|-------------|
| fluxbox | system package | Lightweight window manager | Needed for proper X11 window management within Xvfb; without it BizHawk may not render correctly |
| libopenal-dev | system package | Audio library | BizHawk dependency; required even in headless mode |
| lua5.4 + liblua5.4-dev | 5.4 | Lua runtime | BizHawk dependency for Lua scripting |
| lsb-release | system package | Linux Standard Base | BizHawk dependency for system detection |
| mesa-utils + libgtk2.0-0 | system package | OpenGL + GTK | BizHawk GUI rendering dependencies |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| s6-overlay | supervisord | Supervisord is simpler to configure but does not handle container lifecycle correctly (does not exit on child failure, poor signal forwarding). s6-overlay is purpose-built for containers. |
| s6-overlay | bash script with `&` and `wait` | Fragile; no process restart, no dependency ordering, no proper signal handling. Only acceptable for prototyping. |
| debian:bookworm-slim | mono:6.12 official image | The mono image is larger and less customizable. Building from debian-slim gives more control over installed packages and image size. |
| debian:bookworm-slim | ubuntu:22.04 | Ubuntu works too but Debian is slightly smaller and BizHawk community examples favor Debian. Either works. |
| x11vnc | TigerVNC | x11vnc can capture an existing Xvfb display; TigerVNC requires its own X server. x11vnc is the standard for Xvfb capture. |

**Installation (within Dockerfile):**
```bash
apt-get update && apt-get install -y \
    mono-complete \
    xvfb \
    x11vnc \
    fluxbox \
    libopenal-dev \
    lua5.4 liblua5.4-dev \
    lsb-release \
    mesa-utils libgtk2.0-0 libsdl2-2.0-0 \
    wget unzip git python3 \
    && rm -rf /var/lib/apt/lists/*
```

## Architecture Patterns

### Recommended Container Structure
```
docker/
├── Dockerfile                  # Multi-stage BizHawk container image
├── rootfs/
│   ├── etc/
│   │   └── s6-overlay/
│   │       └── s6-rc.d/
│   │           ├── xvfb/
│   │           │   ├── type        # "longrun"
│   │           │   └── run         # Starts Xvfb
│   │           ├── x11vnc/
│   │           │   ├── type        # "longrun"
│   │           │   ├── run         # Starts x11vnc (conditional on ENABLE_VNC)
│   │           │   └── dependencies.d/
│   │           │       └── xvfb    # Depends on Xvfb
│   │           ├── novnc/
│   │           │   ├── type        # "longrun"
│   │           │   ├── run         # Starts websockify+noVNC (conditional)
│   │           │   └── dependencies.d/
│   │           │       └── x11vnc  # Depends on x11vnc
│   │           ├── fluxbox/
│   │           │   ├── type        # "longrun"
│   │           │   ├── run         # Starts fluxbox
│   │           │   └── dependencies.d/
│   │           │       └── xvfb
│   │           └── bizhawk/
│   │               ├── type        # "longrun"
│   │               ├── run         # Starts BizHawk with --lua and --chromeless
│   │               └── dependencies.d/
│   │                   ├── xvfb
│   │                   └── fluxbox
│   └── entrypoint.sh              # Sets up env vars, conditionally enables VNC services
├── scripts/
│   └── validate-speed.sh          # Frame advance benchmarking script
└── .dockerignore
```

### Pattern 1: Multi-Process Container with s6-overlay
**What:** Use s6-overlay as PID 1 to manage Xvfb, x11vnc, noVNC, fluxbox, and BizHawk as supervised services with dependency ordering.
**When to use:** Always for this container -- BizHawk requires Xvfb, and noVNC requires x11vnc requires Xvfb.
**Example:**
```bash
# s6-overlay service: rootfs/etc/s6-overlay/s6-rc.d/xvfb/run
#!/command/execlineb -P
Xvfb :99 -screen 0 1024x768x24 -ac +extension GLX +render -noreset
```

```bash
# s6-overlay service: rootfs/etc/s6-overlay/s6-rc.d/bizhawk/run
#!/command/execlineb -P
export DISPLAY :99
cd /opt/bizhawk
/opt/bizhawk/EmuHawkMono.sh
  --chromeless
  --lua=/data/lua/main.lua
  --load-state=/data/savestates/fight-start.state
  /data/roms/rom.gba
```

### Pattern 2: Conditional VNC Toggle via Environment Variable
**What:** Use an environment variable `ENABLE_VNC` (default: `false`) to control whether x11vnc and noVNC services start. Xvfb always runs because BizHawk needs it.
**When to use:** Always -- training runs should skip VNC overhead; observation mode enables it.
**Example:**
```bash
# s6-overlay service: rootfs/etc/s6-overlay/s6-rc.d/x11vnc/run
#!/bin/bash
if [ "${ENABLE_VNC}" != "true" ]; then
    # Service is disabled; sleep forever to satisfy s6
    exec sleep infinity
fi
exec x11vnc -display :99 -forever -shared -rfbport 5900 -nopw
```

```bash
# s6-overlay service: rootfs/etc/s6-overlay/s6-rc.d/novnc/run
#!/bin/bash
if [ "${ENABLE_VNC}" != "true" ]; then
    exec sleep infinity
fi
exec /usr/share/novnc/utils/novnc_proxy --vnc localhost:5900 --listen 6080
```

### Pattern 3: Volume Mounting for ROMs, Save States, and Output
**What:** Mount three volumes for data that must not be baked into the image.
**When to use:** Always -- ROMs cannot be distributed, save states vary, and genome output must persist.
**Example:**
```bash
docker run \
  -v /host/roms:/data/roms:ro \
  -v /host/savestates:/data/savestates:ro \
  -v /host/output:/data/output \
  -v /host/lua:/data/lua:ro \
  -e ENABLE_VNC=true \
  -p 6080:6080 \
  saiyan-trainer/bizhawk:latest
```

### Anti-Patterns to Avoid
- **Baking ROMs into the image:** Illegal distribution. Always mount at runtime.
- **Running BizHawk without Xvfb:** EmuHawk crashes immediately without a display server. The `--chromeless` flag only hides window chrome, it does NOT eliminate the display requirement.
- **Using supervisord instead of s6-overlay:** Supervisord does not exit when child processes fail, misleading Kubernetes liveness probes. s6-overlay is container-aware.
- **Skipping fluxbox:** Without a window manager, some GUI applications (including potentially BizHawk) may not render correctly in Xvfb. Fluxbox is tiny and prevents this class of bugs.
- **Running Xvfb with too-high resolution:** Higher resolution means more memory and CPU for the virtual framebuffer. Use 1024x768x24 for training, not 1920x1080.
- **Ignoring `--shm-size`:** Docker's default shared memory (64MB) is too small for Xvfb. Use `--shm-size=256m` or mount `/dev/shm` as tmpfs.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Multi-process supervision | Bash script with `&` background processes | s6-overlay | Proper signal forwarding, dependency ordering, graceful shutdown, container exit on failure |
| Web-accessible display | Custom WebSocket streaming | noVNC + x11vnc + websockify | Battle-tested, maintained, zero configuration, HTML5 compatible |
| Virtual display | GPU passthrough / Wayland hacks | Xvfb | Standard, zero hardware requirements, works everywhere including Kubernetes |
| VNC server | TigerVNC with custom X server | x11vnc | x11vnc captures existing Xvfb display; no need for a second X server |
| Container health checks | Custom monitoring | s6-overlay health + Docker HEALTHCHECK | Container-native health reporting |

**Key insight:** The Xvfb + x11vnc + noVNC + supervisord/s6-overlay pattern is a solved problem with dozens of production Docker images. Do not invent a custom approach. The only novel part is integrating BizHawk into this pattern.

## Common Pitfalls

### Pitfall 1: BizHawk Crashes Silently Without Display
**What goes wrong:** EmuHawk starts, finds no `$DISPLAY`, and exits with a cryptic Mono exception. No useful error in logs.
**Why it happens:** BizHawk is a GUI application that initializes GTK/OpenGL on startup. Without a valid display, initialization fails.
**How to avoid:** Always start Xvfb BEFORE BizHawk. Use s6-overlay dependency ordering (`bizhawk` depends on `xvfb`). Verify `DISPLAY=:99` is set in BizHawk's environment.
**Warning signs:** Container exits immediately with code 1, Mono `TypeInitializationException` in logs.

### Pitfall 2: Docker Default Shared Memory Too Small
**What goes wrong:** Xvfb or BizHawk crashes with "ShmGet failed" or SIGBUS errors.
**Why it happens:** Docker containers default to 64MB `/dev/shm`. Xvfb with a 1024x768x24 framebuffer needs more.
**How to avoid:** Always use `--shm-size=256m` in docker run, or `shm_size: 256m` in docker-compose.
**Warning signs:** Random segfaults in Xvfb, "Xlib: extension "MIT-SHM" missing" errors.

### Pitfall 3: mGBA Memory Callback NullReferenceException
**What goes wrong:** BizHawk crashes with NRE when Lua script uses `event.on_bus_write()` or similar memory callbacks, especially on core reboot (save state load).
**Why it happens:** BizHawk Issue #4631 -- mGBA core's memory callback system has a bug in callback removal during reboot. Fixed in 2.11.1 dev builds only.
**How to avoid:** Option A: Use BizHawk 2.11.1 dev build instead of 2.11 stable. Option B: Use polling-based memory reads (`memory.read_u16_le()`) exclusively instead of event-based callbacks. Polling is sufficient for NEAT training since reads happen every frame anyway.
**Warning signs:** NRE at `MGBAMemoryCallbackSystem.Remove()` in stack trace, crash on save state load.

### Pitfall 4: Frame Advance Much Slower in Container
**What goes wrong:** Training that takes 1 hour locally takes 3-5 hours in the container.
**Why it happens:** Xvfb adds rendering overhead even for virtual frames. BizHawk's OpenGL/GDI rendering path is exercised even when nobody is watching.
**How to avoid:** Use `--chromeless` to minimize rendering. Consider frame-skip if BizHawk supports it for GBA. Benchmark early and document the overhead ratio. Use lower Xvfb resolution (800x600 vs 1920x1080).
**Warning signs:** `emu.frameadvance()` calls take consistently longer than bare metal.

### Pitfall 5: Lua Script Paths Broken in Container
**What goes wrong:** BizHawk loads but the Lua script fails with "file not found" errors.
**Why it happens:** `EmuHawkMono.sh` changes the working directory to the BizHawk install dir. Relative paths in `--lua` resolve relative to the install dir, not the mount point.
**How to avoid:** Always use absolute paths in `--lua` and in Lua `dofile()`/`require()` calls. Set paths via environment variables injected into the container.
**Warning signs:** "Cannot find file" errors for files that exist at the mount point.

### Pitfall 6: noVNC Connection Shows Black Screen
**What goes wrong:** noVNC connects but shows only a black screen, no BizHawk window visible.
**Why it happens:** BizHawk started before fluxbox, or `DISPLAY` variable mismatch between processes, or Xvfb resolution mismatch.
**How to avoid:** Ensure s6-overlay dependency chain: Xvfb -> fluxbox -> BizHawk. All processes must use the same `DISPLAY` value (`:99`). Start Xvfb with sufficient color depth (24-bit).
**Warning signs:** x11vnc shows "connected" but black output, `xdpyinfo` reports wrong display.

## Code Examples

### Complete Dockerfile
```dockerfile
# Source: Assembled from verified Docker noVNC patterns + BizHawk Linux requirements
FROM debian:bookworm-slim

ARG S6_OVERLAY_VERSION=3.1.6.2
ARG BIZHAWK_VERSION=2.11

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    mono-complete \
    xvfb \
    x11vnc \
    fluxbox \
    libopenal-dev \
    lua5.4 liblua5.4-dev \
    lsb-release \
    mesa-utils libgtk2.0-0 libsdl2-2.0-0 \
    wget unzip git python3 xz-utils \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install s6-overlay
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz /tmp
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-x86_64.tar.xz /tmp
RUN tar -C / -Jxpf /tmp/s6-overlay-noarch.tar.xz \
    && tar -C / -Jxpf /tmp/s6-overlay-x86_64.tar.xz \
    && rm /tmp/s6-overlay-*.tar.xz

# Install noVNC + websockify
RUN git clone --depth 1 https://github.com/novnc/noVNC.git /usr/share/novnc \
    && git clone --depth 1 https://github.com/novnc/websockify.git /usr/share/novnc/utils/websockify \
    && ln -sf /usr/share/novnc/vnc.html /usr/share/novnc/index.html

# Download and install BizHawk
RUN mkdir -p /opt/bizhawk \
    && wget -q "https://github.com/TASEmulators/BizHawk/releases/download/${BIZHAWK_VERSION}/BizHawk-${BIZHAWK_VERSION}-linux-x64.tar.gz" \
       -O /tmp/bizhawk.tar.gz \
    && tar xzf /tmp/bizhawk.tar.gz -C /opt/bizhawk --strip-components=1 \
    && rm /tmp/bizhawk.tar.gz \
    && chmod +x /opt/bizhawk/EmuHawkMono.sh

# Create data directories
RUN mkdir -p /data/roms /data/savestates /data/output /data/lua

# Copy s6-overlay service definitions
COPY rootfs/ /

# Environment
ENV DISPLAY=:99 \
    ENABLE_VNC=false \
    VNC_PORT=5900 \
    NOVNC_PORT=6080 \
    XVFB_RESOLUTION=1024x768x24

EXPOSE 6080

ENTRYPOINT ["/init"]
```

### s6-overlay Xvfb Service
```bash
# rootfs/etc/s6-overlay/s6-rc.d/xvfb/type
longrun

# rootfs/etc/s6-overlay/s6-rc.d/xvfb/run
#!/command/execlineb -P
Xvfb :99 -screen 0 ${XVFB_RESOLUTION} -ac +extension GLX +render -noreset
```

### s6-overlay BizHawk Service
```bash
# rootfs/etc/s6-overlay/s6-rc.d/bizhawk/type
longrun

# rootfs/etc/s6-overlay/s6-rc.d/bizhawk/run
#!/bin/bash
exec /opt/bizhawk/EmuHawkMono.sh \
    --chromeless \
    --lua="${LUA_SCRIPT:-/data/lua/main.lua}" \
    --load-state="${SAVE_STATE:-/data/savestates/fight-start.state}" \
    "${ROM_PATH:-/data/roms/rom.gba}"
```

### s6-overlay Conditional VNC Service
```bash
# rootfs/etc/s6-overlay/s6-rc.d/x11vnc/run
#!/bin/bash
if [ "${ENABLE_VNC}" != "true" ]; then
    echo "VNC disabled (ENABLE_VNC=${ENABLE_VNC})"
    exec sleep infinity
fi
exec x11vnc -display :99 -forever -shared -rfbport ${VNC_PORT} -nopw -noxdamage

# rootfs/etc/s6-overlay/s6-rc.d/novnc/run
#!/bin/bash
if [ "${ENABLE_VNC}" != "true" ]; then
    echo "noVNC disabled (ENABLE_VNC=${ENABLE_VNC})"
    exec sleep infinity
fi
exec /usr/share/novnc/utils/novnc_proxy \
    --vnc localhost:${VNC_PORT} \
    --listen ${NOVNC_PORT}
```

### Docker Run Commands
```bash
# Headless training (no VNC)
docker run --rm \
    --shm-size=256m \
    -v $(pwd)/roms:/data/roms:ro \
    -v $(pwd)/savestates:/data/savestates:ro \
    -v $(pwd)/lua:/data/lua:ro \
    -v $(pwd)/output:/data/output \
    saiyan-trainer/bizhawk:latest

# Training with web observation
docker run --rm \
    --shm-size=256m \
    -e ENABLE_VNC=true \
    -p 6080:6080 \
    -v $(pwd)/roms:/data/roms:ro \
    -v $(pwd)/savestates:/data/savestates:ro \
    -v $(pwd)/lua:/data/lua:ro \
    -v $(pwd)/output:/data/output \
    saiyan-trainer/bizhawk:latest
# Then open http://localhost:6080/vnc.html in browser
```

### Kubernetes Volume Mount Pattern
```yaml
# For Phase 4 -- how this container integrates with Tekton
apiVersion: v1
kind: Pod
metadata:
  name: neat-training
spec:
  containers:
  - name: bizhawk
    image: saiyan-trainer/bizhawk:latest
    env:
    - name: ENABLE_VNC
      value: "false"
    volumeMounts:
    - name: rom-volume
      mountPath: /data/roms
      readOnly: true
    - name: workspace
      mountPath: /data/output
    - name: savestates
      mountPath: /data/savestates
      readOnly: true
    resources:
      requests:
        memory: "1Gi"
        cpu: "1"
      limits:
        memory: "2Gi"
        cpu: "2"
    securityContext:
      runAsUser: 0  # Xvfb may need root
  volumes:
  - name: rom-volume
    persistentVolumeClaim:
      claimName: rom-pvc
  - name: workspace
    persistentVolumeClaim:
      claimName: training-workspace
  - name: savestates
    persistentVolumeClaim:
      claimName: savestate-pvc
```

### Frame Advance Speed Validation Script
```bash
#!/bin/bash
# scripts/validate-speed.sh
# Run inside the container to benchmark frame advance speed

FRAMES=1000
echo "Benchmarking BizHawk frame advance speed ($FRAMES frames)..."

START=$(date +%s%N)

# Run a minimal Lua script that just advances frames
cat > /tmp/benchmark.lua << 'EOF'
local start_time = os.clock()
local frames = 1000
for i = 1, frames do
    emu.frameadvance()
end
local elapsed = os.clock() - start_time
local fps = frames / elapsed
print(string.format("Benchmark: %d frames in %.2f seconds = %.1f fps", frames, elapsed, fps))
-- GBA native is 59.73 fps; anything above 100 fps is acceptable for training
if fps > 100 then
    print("PASS: Frame advance speed is acceptable for training")
else
    print("WARNING: Frame advance is slow. Consider frame-skip or performance tuning.")
end
client.exit()
EOF

/opt/bizhawk/EmuHawkMono.sh \
    --chromeless \
    --lua=/tmp/benchmark.lua \
    /data/roms/rom.gba
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| supervisord for multi-process containers | s6-overlay | 2023-2025 trend | Proper container lifecycle, signal forwarding, exit-on-failure. Selenium, LinuxServer.io, and many others migrating. |
| Custom VNC + Java applet viewers | noVNC (HTML5 canvas) | 2015+ | No plugins needed, works in any modern browser |
| BizHawk Lua engine: LuaInterface | NLua+Lua (BizHawk 2.9+) | 2023 | NLua works on Linux; old LuaInterface crashed on Mono. Non-issue for 2.11. |
| BizHawk Windows-only | BizHawk Linux support | 2.6+ (2020) | Near feature-parity on Linux. Mono required, not .NET Core. |

**Deprecated/outdated:**
- **LuaInterface engine:** Crashed on Linux/Mono. Replaced by NLua+Lua in BizHawk 2.9+. Not relevant for 2.11.
- **supervisord for new container projects:** Still works but s6-overlay is the recommended modern choice.
- **Mono mono:6.12 Docker image as base:** Larger and less flexible than building from debian-slim.

## Open Questions

1. **Exact BizHawk download URL format for 2.11 Linux**
   - What we know: Release exists on GitHub (Sep 20, 2024), named `BizHawk-2.11-linux-x64.tar.gz` based on convention
   - What's unclear: The exact asset URL -- GitHub release page had loading errors during research
   - Recommendation: Verify URL during Dockerfile build by checking `https://github.com/TASEmulators/BizHawk/releases/tag/2.11` and looking at assets. Fall back to wget with redirect following.

2. **BizHawk frame advance speed under Xvfb**
   - What we know: No published benchmarks exist for BizHawk GBA frame advance in Docker/Xvfb. Community reports suggest GUI apps in Xvfb are 3-5x slower than native display.
   - What's unclear: Exact FPS achievable for GBA emulation. Whether `--chromeless` reduces Xvfb overhead.
   - Recommendation: Build the image first, then run the benchmarking script (provided above) as an early validation gate. If unacceptable (<100 fps), investigate frame-skip options.

3. **BizHawk 2.11 vs 2.11.1 dev for mGBA memory callbacks**
   - What we know: Issue #4631 (NRE on memory callbacks with mGBA core reboot) is fixed in 2.11.1 dev builds only.
   - What's unclear: Whether the project uses memory callbacks or polling-based reads. If Phase 2 used polling, this is a non-issue.
   - Recommendation: Use polling-based `memory.read_u16_le()` rather than event callbacks. This sidesteps Issue #4631 entirely and is the safer approach.

4. **s6-overlay with execlineb vs bash for service scripts**
   - What we know: s6-overlay natively uses execlineb syntax, but bash scripts work too.
   - What's unclear: Whether execlineb handles environment variable expansion for BizHawk's CLI args correctly.
   - Recommendation: Use bash for service `run` scripts that need env var expansion. Only use execlineb for simple services like Xvfb.

5. **Container image size**
   - What we know: mono-complete alone is ~500MB. BizHawk is ~200MB. Total image will be 1-2GB.
   - What's unclear: Whether multi-stage build can reduce this (unlikely given Mono runtime requirement).
   - Recommendation: Accept the large image size. This is a development/training tool, not a production microservice. Focus on correctness over size.

## Sources

### Primary (HIGH confidence)
- [BizHawk GitHub Repository](https://github.com/TASEmulators/BizHawk) -- Linux requirements, CLI args, release info
- [BizHawk ArgParser.cs](https://github.com/TASEmulators/BizHawk/blob/master/src/BizHawk.Client.Common/ArgParser.cs) -- Complete CLI flag documentation: `--chromeless`, `--lua`, `--load-state`, `--load-slot`, `--fullscreen`, `--config`
- [BizHawk Command Line (TASVideos)](https://tasvideos.org/Bizhawk/CommandLine) -- CLI usage on Linux, `--help` support since 2.10
- [BizHawk Issue #4631](https://github.com/TASEmulators/BizHawk/issues/4631) -- mGBA memory callback NRE, fixed in 2.11.1 dev
- [s6-overlay GitHub](https://github.com/just-containers/s6-overlay) -- Installation, service configuration, PID 1 handling
- [Docker multi-process documentation](https://docs.docker.com/engine/containers/multi-service_container/) -- Official guidance on multi-process containers
- [noVNC GitHub](https://github.com/novnc/noVNC) -- HTML5 VNC client
- [websockify GitHub](https://github.com/novnc/websockify) -- WebSocket to TCP proxy

### Secondary (MEDIUM confidence)
- [theasp/docker-novnc](https://github.com/theasp/docker-novnc) -- Reference Docker image for Xvfb + x11vnc + noVNC pattern, environment variables, docker-compose integration
- [DEV Community: Firefox in Docker with noVNC (2025)](https://dev.to/danielcristho/running-firefox-in-docker-yes-with-a-gui-and-novnc-5fk) -- Complete Dockerfile + supervisord.conf for Xvfb + x11vnc + noVNC; verified pattern
- [zaoqi/x11-novnc-docker](https://github.com/zaoqi/x11-novnc-docker) -- Base Docker image for X11 apps via noVNC
- [Steam Deck BizHawk Setup](https://gist.github.com/SpenserHaddad/417a772aea5be99d563fe73295bb62fb) -- BizHawk in Debian container (Distrobox), confirmed packages: mono-complete, lua5.4, mesa-utils, libgtk2.0-0
- [BizHawk 2.11 Release (retro-replay.com)](https://retro-replay.com/bizhawk-2-11-released-new-cores-fixes-and-features-arrive-in-september-2025/) -- Release notes, new cores, Sep 2025
- [Mono Install Guide](https://www.mono-project.com/docs/getting-started/install/linux/) -- Mono on Debian/Ubuntu

### Tertiary (LOW confidence)
- [BizHawk Speed (TASVideos)](https://tasvideos.org/Bizhawk/Speed) -- General performance notes, no Linux/Xvfb benchmarks
- [noVNC Issue #1022](https://github.com/novnc/noVNC/issues/1022) -- Xvfb + x11vnc + openbox + noVNC in a container; community discussion

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- BizHawk Linux deps are well-documented; Xvfb + noVNC is a solved pattern with many reference implementations
- Architecture: MEDIUM -- No existing BizHawk Docker images to reference; pattern assembly is novel but individual components are proven
- Pitfalls: MEDIUM -- Container-specific pitfalls (shm, display, paths) are well-known; BizHawk-specific container issues are speculative since nobody has published this setup
- Performance: LOW -- No benchmarks exist for BizHawk GBA in Xvfb; speed validation is empirical work that must happen during implementation

**Research date:** 2026-03-06
**Valid until:** 2026-04-06 (30 days; BizHawk and noVNC are stable, s6-overlay actively maintained)
