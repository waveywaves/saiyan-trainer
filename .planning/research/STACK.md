# Technology Stack

**Project:** Saiyan Trainer
**Researched:** 2026-03-06

## Recommended Stack

### Neuroevolution Core (Lua / BizHawk)

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| BizHawk | 2.11 (latest) | GBA emulator with Lua scripting, frame advance, save states | Only serious option for TAS-grade Lua-scripted emulation. Native mGBA core for GBA. Linux support with Lua scripting confirmed in recent releases. | HIGH |
| Lua | 5.4 (BizHawk-bundled) | Scripting language for NEAT logic and emulator control | BizHawk 2.11 bundles Lua 5.4. All NEAT-in-emulator implementations (MarI/O, NEATendo, MarioKart64NEAT) use BizHawk's embedded Lua. No choice here -- BizHawk dictates the Lua version. | HIGH |
| Custom NEAT (MarI/O-derived) | N/A | NEAT algorithm implementation | Fork SethBling's neatevolve.lua pattern (or the NEATEvolve fork with fixed save/load by SngLol). Do NOT use the LuaNEAT standalone library -- it was last updated 2018, has no genome serialization, and lacks BizHawk-specific integration. The MarI/O pattern is battle-tested across dozens of game bot projects and provides the exact integration points needed (frame advance loop, joypad output, memory reading). | MEDIUM |
| Xvfb | system package | Virtual framebuffer for headless BizHawk | BizHawk has NO headless mode. Running in containers requires `xvfb-run` to provide a virtual X display. This is the standard workaround -- confirmed by community discussions and the fact that EmuHawk is fundamentally a GUI application (.NET/Mono with windowing). | MEDIUM |

### BizHawk Lua API (Key Modules)

| Module | Purpose | Notes |
|--------|---------|-------|
| `memory` / `mainmemory` | Read GBA RAM (health, positions, attack states) | Supports typed reads (byte, word, float). Use `memory.usememorydomain` for GBA IWRAM/EWRAM access. |
| `joypad` | Send controller inputs from NEAT outputs | `joypad.set()` maps model outputs to GBA buttons (A, B, L, R, Up, Down, Left, Right, Start, Select). |
| `savestate` | Save/load emulator state for training resets | Slot-based or file-based. Critical for resetting fights between training episodes. |
| `emu` | Frame advance and emulation control | `emu.frameadvance()` is the heartbeat of the training loop. Every Lua script must call this in its main loop. |
| `comm` | Socket/HTTP communication | Enables Lua-to-external-process communication. Useful if we later need to offload NEAT computation to Python or report metrics. |

### MLOps / Pipeline Orchestration

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| Tekton Pipelines | v1.9.0 LTS | Pipeline orchestration for training workflows | Project requirement. Latest LTS (Feb 2026) with Pipelines-in-Pipelines support, resolver caching, HA improvements. Requires K8s 1.28+. The Pipelines-in-Pipelines feature (TEP-0056) is particularly useful for composing training, evaluation, and promotion stages. | HIGH |
| Tekton Triggers | latest (match Pipelines LTS) | Event-driven pipeline runs | Trigger retraining on model performance thresholds or scheduled intervals. | MEDIUM |
| Tekton Chains | latest | Supply chain security / artifact signing | Built-in SLSA provenance for training artifacts. Nice-to-have for demonstrating MLOps best practices but not critical for MVP. | LOW |

### Kubernetes Infrastructure

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| Kubernetes | 1.28+ | Container orchestration | Required by Tekton. Use 1.30+ if deploying MinIO Operator (v7.1.1+ requirement). | HIGH |
| MinIO | latest (source-build or SeaweedFS alternative) | S3-compatible object storage for genomes and training artifacts | Standard choice for on-cluster artifact storage. BUT: MinIO community binaries are no longer published (2025 change -- source-only distribution now). Options: (1) build from source, (2) use SeaweedFS instead (Apache 2.0, now default in KFP 2.15), (3) use MinIO Operator Helm chart if available. | MEDIUM |
| SeaweedFS | latest | Alternative S3-compatible storage | Now the default in Kubeflow Pipelines 2.15, replacing MinIO. Apache 2.0 licensed. Simpler deployment. Recommend this over MinIO for new projects given MinIO's licensing changes. | MEDIUM |

### Model Versioning and Storage

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| JSON genome format | N/A | Serialize NEAT genomes (nodes + connections + innovation numbers) | NEAT genomes are small (hundreds of connections at most). JSON is human-readable, debuggable, and sufficient. MarI/O uses a custom `.pool` text format; we should modernize to JSON for better tooling integration. Add a schema version field for forward compatibility. | MEDIUM |
| Git + S3 object storage | N/A | Version and store genome generations | Store each generation's best genome(s) as versioned JSON files in S3 (SeaweedFS/MinIO). Use a naming convention like `genomes/run-{id}/gen-{N}/best.json`. Git tracks the training code; S3 tracks the artifacts. | MEDIUM |
| MLflow (optional, Phase 2+) | 2.10+ | Experiment tracking and model registry | Overkill for MVP but valuable later. MLflow on K8s with PostgreSQL backend provides experiment tracking, genome comparison, and metric visualization. Defer to Phase 2 -- NEAT genome tracking can start with simple S3 + metadata JSON files. | LOW |

### Container Images

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| Mono / .NET | 6.12+ (Mono) | Runtime for BizHawk in Linux containers | BizHawk on Linux runs via Mono. The container image needs: Mono runtime, OpenAL, Lua 5.4, Xvfb, and BizHawk itself. This is the trickiest part of the stack -- building a working BizHawk container image. | MEDIUM |
| Buildpacks or Dockerfile | N/A | Container image for training workloads | Use a Dockerfile (not Buildpacks) for the BizHawk training image. BizHawk's dependencies (Mono, OpenAL, virtual framebuffer) are too specialized for Buildpacks auto-detection. Use a multi-stage build: base image with BizHawk runtime, then copy in Lua scripts and ROM. | MEDIUM |

### Observability

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| Tekton Dashboard | latest | Pipeline run visualization | Shows pipeline execution, logs, status. Built for Tekton. | HIGH |
| Prometheus + Grafana | standard K8s stack | Training metrics (generation, fitness, win rate) | Lua scripts write metrics to a file or stdout; a sidecar or post-step scrapes them. Standard K8s observability pattern. | MEDIUM |

## Alternatives Considered

| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| NEAT Implementation | Custom MarI/O-derived Lua | LuaNEAT library | Last updated 2018, no serialization, no BizHawk integration. Dead project. |
| NEAT Implementation | Custom MarI/O-derived Lua | neat-python (Python) | Would require socket bridge between Python and BizHawk Lua. Adds complexity. The MarI/O pattern runs NEAT entirely in Lua, avoiding IPC overhead. Only consider Python NEAT if training needs to scale beyond what Lua can handle. |
| NEAT Implementation | Custom MarI/O-derived Lua | NEAT-Python + LuaSocket bridge | Proven by neat_py project for Flappy Bird. But adds networking complexity and latency per frame. For a fighting game with tight timing, keep everything in Lua. |
| Object Storage | SeaweedFS | MinIO | MinIO community binaries no longer distributed (2025). Source-only distribution makes deployment harder. SeaweedFS is now the Kubeflow default. |
| Object Storage | SeaweedFS | Cloud S3 (AWS/GCS) | Project targets plain K8s, not cloud-specific. On-cluster storage keeps the demo self-contained. |
| Model Registry | JSON files in S3 | MLflow | MLflow is too heavy for MVP. NEAT genomes are simple structured data. Start simple, add MLflow later if needed. |
| Pipeline Orchestration | Tekton | Argo Workflows | Project requirement is Tekton. Argo is a valid alternative but not what this project demonstrates. |
| Pipeline Orchestration | Tekton | Kubeflow Pipelines on Tekton (KFP-Tekton) | KFP-Tekton provides a Python SDK for pipeline authoring, which is nice. But it adds a heavy dependency (Kubeflow control plane). For this project, raw Tekton YAML is sufficient and keeps the stack lean. |
| Emulator | BizHawk | mGBA standalone | BizHawk wraps mGBA for GBA but adds Lua scripting, save states, frame advance, and joypad control. mGBA alone lacks the Lua automation layer. |
| Genome Format | JSON | Protocol Buffers | Protobuf is faster and smaller but NEAT genomes are tiny. JSON's human-readability wins for a demo/educational project. |
| Headless Rendering | Xvfb | GPU passthrough | GPU passthrough in K8s is complex and unnecessary. BizHawk GBA emulation is CPU-only. Xvfb + software rendering is sufficient. |

## What NOT to Use

| Technology | Why Not |
|------------|---------|
| Deep RL (DQN, PPO, A3C) | Project scope explicitly excludes deep RL. NEAT is the algorithm choice. |
| OpenAI Gym / Gymnasium | Designed for Python RL agents, not Lua-based emulator bots. Wrong abstraction layer. |
| TensorFlow / PyTorch | NEAT does not use gradient descent. Neural network weights evolve via genetic algorithms, not backpropagation. These frameworks add massive overhead for zero benefit. |
| Docker Compose for orchestration | Project targets Kubernetes with Tekton. Docker Compose is for local dev only. |
| Kubeflow full stack | Too heavy. Tekton alone provides pipeline orchestration. Adding the full Kubeflow control plane is unnecessary for this use case. |
| OpenShift-specific features | Project explicitly targets plain Kubernetes for broader audience. |
| LuaNEAT | Dead library (2018). No serialization. No BizHawk awareness. |

## Setup / Installation

### BizHawk Container Image (Dockerfile skeleton)

```dockerfile
FROM mono:6.12

# System dependencies
RUN apt-get update && apt-get install -y \
    xvfb \
    libopenal1 \
    lua5.4 \
    wget \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Download BizHawk
RUN wget https://github.com/TASEmulators/BizHawk/releases/download/2.11/BizHawk-2.11-linux-x64.tar.gz \
    && tar xzf BizHawk-2.11-linux-x64.tar.gz -C /opt/bizhawk \
    && rm BizHawk-2.11-linux-x64.tar.gz

# Copy Lua scripts (NEAT + game-specific)
COPY lua/ /opt/bizhawk/lua/

# Entry point: run BizHawk headless with Lua script
ENTRYPOINT ["xvfb-run", "/opt/bizhawk/EmuHawkMono.sh"]
```

### Tekton on Kubernetes

```bash
# Install Tekton Pipelines v1.9.0 LTS
kubectl apply --filename https://storage.googleapis.com/tekton-releases/pipeline/previous/v1.9.0/release.yaml

# Install Tekton Dashboard (optional, for UI)
kubectl apply --filename https://storage.googleapis.com/tekton-releases/dashboard/latest/release.yaml

# Install Tekton Triggers (for event-driven runs)
kubectl apply --filename https://storage.googleapis.com/tekton-releases/triggers/latest/release.yaml
```

### SeaweedFS on Kubernetes

```bash
# Via Helm
helm repo add seaweedfs https://seaweedfs.github.io/seaweedfs/helm
helm install seaweedfs seaweedfs/seaweedfs \
    --set master.replicas=1 \
    --set volume.replicas=1 \
    --set s3.enabled=true
```

## Key Technical Risks

1. **BizHawk in containers is uncharted territory.** No established Docker images or community patterns exist. The Mono/.NET + Xvfb + OpenAL dependency chain will require debugging. Budget significant time for this.

2. **BizHawk + mGBA memory callbacks have known bugs.** Issue #4631 documents NRE crashes when memory callbacks are set with the mGBA core. Verify this is fixed in 2.11 before depending on memory callbacks (use polling via `mainmemory.read` instead if needed).

3. **Lua 5.4 integer changes.** Lua 5.4 distinguishes integers from floats (unlike 5.3). MarI/O code may need adjustments. The `//` floor division operator and integer type are new. Test arithmetic carefully.

4. **MinIO licensing upheaval.** MinIO community binaries are dead. SeaweedFS is the safer bet but has less documentation for ML use cases. Test S3 API compatibility with your tools.

## Sources

- [BizHawk GitHub Repository](https://github.com/TASEmulators/BizHawk) - HIGH confidence
- [BizHawk Lua Functions Reference](https://tasvideos.org/Bizhawk/LuaFunctions) - HIGH confidence
- [BizHawk Command Line](https://tasvideos.org/Bizhawk/CommandLine) - HIGH confidence
- [Tekton Pipelines v1.9.0 LTS Blog Post](https://tekton.dev/blog/2026/02/02/tekton-pipelines-v1.9.0-lts-continued-innovation-and-stability/) - HIGH confidence
- [Tekton Pipelines Install Docs](https://tekton.dev/docs/pipelines/install/) - HIGH confidence
- [Tekton Pipelines GitHub Releases](https://github.com/tektoncd/pipeline/releases) - HIGH confidence
- [NEATEvolve (improved MarI/O fork)](https://github.com/SngLol/NEATEvolve) - MEDIUM confidence
- [Bizhawk-NEAT-GameSolver-ML-AI](https://github.com/LionelBergen/Bizhawk-NEAT-GameSolver-ML-AI) - MEDIUM confidence
- [MarioKart64NEAT](https://github.com/nicknlsn/MarioKart64NEAT) - MEDIUM confidence
- [LuaNEAT](https://github.com/grmmhp/LuaNEAT) - MEDIUM confidence (evaluated and rejected)
- [MLflow Model Registry Docs](https://mlflow.org/docs/latest/ml/model-registry/) - HIGH confidence
- [MLflow on Kubernetes Guide](https://oneuptime.com/blog/post/2026-02-09-mlflow-model-registry-kubernetes/view) - MEDIUM confidence
- [MinIO Open Source Status Change (InfoQ)](https://www.infoq.com/news/2025/12/minio-s3-api-alternatives/) - MEDIUM confidence
- [Automate Models Training: MLOps Pipeline with Tekton and Buildpacks](https://towardsdatascience.com/automate-models-training-an-mlops-pipeline-with-tekton-and-buildpacks/) - MEDIUM confidence
- [Kubeflow Pipelines on Tekton](https://github.com/kubeflow/kfp-tekton) - MEDIUM confidence
- [MarI/O Neuroevolution Explanation](https://glenn-roberts.com/posts/2015/07/08/neuroevolution-with-mario/) - MEDIUM confidence
