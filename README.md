# Saiyan Trainer

Train a neural network to fight in Dragon Ball Z: Supersonic Warriors using neuroevolution (NEAT), orchestrated by Tekton Pipelines on Kubernetes.

## Overview

Saiyan Trainer evolves a NEAT (NeuroEvolution of Augmenting Topologies) neural network that learns to play and win fights in Dragon Ball Z: Supersonic Warriors on Game Boy Advance. The model runs inside the BizHawk emulator via Lua scripting, reading game state directly from GBA memory addresses (character positions, health bars, attack states) and outputting controller button presses.

The entire training lifecycle -- data collection, training, evaluation, model versioning, and retraining -- is orchestrated as a full MLOps pipeline using Tekton on Kubernetes. This is not just a game bot: it is a working demonstration that Tekton can orchestrate real ML workloads end-to-end.

```
+-------------------+     +-----------------------+     +----------------+
|   BizHawk + Lua   |     |   Tekton Pipeline     |     |   SeaweedFS    |
|   (NEAT Training) | --> | setup -> train ->      | --> | (Genome Store) |
|   in container    |     | evaluate -> store      |     |                |
+-------------------+     +-----------------------+     +----------------+
         |                         |                           |
         v                         v                           v
+-------------------+     +-----------------------+     +----------------+
|  Prometheus       |     |  Tekton Dashboard     |     |   Grafana      |
|  Pushgateway      | --> |  (Pipeline Runs)      |     |  (Dashboards)  |
+-------------------+     +-----------------------+     +----------------+
```

## Prerequisites

- **Kubernetes cluster** (1.28+) -- local (minikube, kind) or cloud
- **kubectl** and **helm** installed and configured
- **Docker** for building the BizHawk container image
- **Dragon Ball Z: Supersonic Warriors (USA) GBA ROM** -- you must provide your own ROM file (not included for legal reasons)
- **BizHawk 2.11** -- for local development only (not needed for K8s deployment)

## Quick Start

### 1. Clone the repository

```bash
git clone https://github.com/waveywaves/saiyan-trainer.git
cd saiyan-trainer
```

### 2. Provide your ROM

Place your legally obtained GBA ROM in the `roms/` directory:

```bash
cp /path/to/your/rom.gba roms/Dragon\ Ball\ Z\ -\ Supersonic\ Warriors\ \(USA\).gba
```

The `roms/` directory is gitignored. The ROM file is never committed to the repository.

### 3. Build the container image

```bash
cd docker
docker build -t saiyan-trainer/bizhawk:latest .
```

This builds a container with BizHawk, Mono, Xvfb, and all dependencies needed to run NEAT training headlessly. The container also includes a noVNC web UI for live training visualization.

### 4. Install cluster infrastructure

```bash
cd k8s/setup
bash install.sh
```

This installs:
- Tekton Pipelines v1.9.0 LTS, Dashboard, and Triggers
- SeaweedFS (S3-compatible object storage for genome versioning)
- Prometheus + Grafana (kube-prometheus-stack)
- Prometheus Pushgateway (batch job metrics)
- Grafana dashboards (fitness curves, species diversity, evaluation results)
- Workspace PVC for pipeline data sharing

### 5. Apply Tekton resources

```bash
kubectl apply -f k8s/tekton/tasks/
kubectl apply -f k8s/tekton/pipeline.yaml
```

### 6. Trigger a training run

```bash
kubectl create -f k8s/tekton/pipelinerun.yaml
```

### 7. Watch progress

```bash
# Follow pipeline logs
tkn pipelinerun logs saiyan-training-run-001 -f

# Or use kubectl
kubectl get pipelineruns -w
```

### 8. View dashboards

```bash
# Grafana (fitness curves, species diversity, win rates)
kubectl port-forward svc/monitoring-grafana 3000:80
# Open http://localhost:3000 (admin / prom-operator)

# Tekton Dashboard (pipeline runs, task logs)
kubectl port-forward -n tekton-pipelines svc/tekton-dashboard 9097:9097
# Open http://localhost:9097
```

## Local Development

You can run NEAT training locally in BizHawk without Kubernetes:

1. Install [BizHawk 2.11](https://github.com/TASEmulators/BizHawk/releases)
2. Open your ROM in BizHawk
3. Load the fight start save state from `savestates/`
4. Open the Lua console and load `lua/main.lua`

The Lua scripts handle everything: reading game memory, running the NEAT algorithm, sending controller inputs, and saving the best genomes. See the `lua/` directory for the full training implementation.

### Key Lua modules

| Module | Purpose |
|--------|---------|
| `lua/main.lua` | Entry point -- wires everything together |
| `lua/neat/` | NEAT algorithm (population, species, genome, mutation) |
| `lua/training/` | Training loop, fitness evaluation |
| `lua/memory_reader.lua` | Reads game state from GBA memory addresses |
| `lua/controller.lua` | Translates neural network outputs to button presses |
| `lua/memory_map.lua` | Memory address definitions for DBZ Supersonic Warriors |

## Architecture

Saiyan Trainer is organized in four layers:

### Emulation Layer
BizHawk runs inside a container with Xvfb for headless rendering. The Lua scripts implement the full NEAT algorithm, read game state from memory, and control the fighter. Each training pod runs BizHawk for N generations, producing champion genomes and training metrics.

### Orchestration Layer (Tekton)
A Tekton Pipeline coordinates the training lifecycle:

```
setup-generation --> run-training --> evaluate (Matrix fan-out) --> store-results
                                                                        |
                                                              decide-continue (finally)
                                                                        |
                                                              [trigger next PipelineRun
                                                               if fitness < threshold]
```

- **setup-generation**: Optionally pulls a genome checkpoint from SeaweedFS to resume training
- **run-training**: Runs BizHawk NEAT for N generations, pushes metrics to Pushgateway
- **distributed-eval**: Evaluates genomes in parallel across pods using Tekton Matrix fan-out
- **store-results**: Uploads champion genome, population, and metadata to SeaweedFS
- **decide-continue**: Checks fitness threshold, triggers next PipelineRun via EventListener

Key Tekton features used: Pipeline/Task/PipelineRun v1 API, Matrix for fan-out (TEP-0090), workspace affinity (coschedule), task timeout overrides, keep-pod-on-cancel, Triggers for PipelineRun chaining.

### Storage Layer (SeaweedFS)
Trained genomes are versioned and stored in SeaweedFS (S3-compatible object storage) with metadata sidecars. Each genome is tagged with run ID, generation, fitness score, win rate, and date.

### Observability Layer (Prometheus + Grafana)
Training pods push metrics to Prometheus Pushgateway via curl. Prometheus scrapes the Pushgateway. Three Grafana dashboards visualize training progress:

- **Fitness Curves**: Max and average fitness over generations, generation progress
- **Species Diversity**: Species count over time, population size
- **Evaluation Results**: Win rate by run, total evaluation fights, best fitness trends

## Configuration

### Pipeline Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `run-id` | (required) | Unique identifier for the training run |
| `generations-per-batch` | `50` | Generations to train per PipelineRun |
| `resume-from` | `""` | S3 path to genome checkpoint (empty = fresh start) |
| `fitness-threshold` | `5000` | Target fitness for training completion |

### Container Environment

| Variable | Default | Description |
|----------|---------|-------------|
| `DISPLAY` | `:99` | X11 display for Xvfb |
| `ENABLE_VNC` | `true` | Enable noVNC web UI for live visualization |
| `ROM_PATH` | `/workspace/roms/rom.gba` | Path to the GBA ROM inside the container |

### SeaweedFS

Genome storage credentials are configured via the `seaweedfs-creds` Kubernetes Secret. See `k8s/storage/seaweedfs-secret.yaml`.

## Observability

### Grafana Dashboards

Three dashboards are auto-provisioned via ConfigMap (k8s-sidecar pattern):

| Dashboard | Metrics | Purpose |
|-----------|---------|---------|
| Fitness Curves | `neat_fitness_max`, `neat_fitness_avg`, `neat_generation` | Track training progress |
| Species Diversity | `neat_species_count`, `neat_population_size` | Monitor genetic diversity |
| Evaluation Results | `neat_eval_win_rate`, `neat_eval_total_fights`, `neat_eval_best_fitness` | Measure fight performance |

All dashboards support filtering by `run_id` to compare multiple training runs.

### Prometheus Pushgateway Metrics

Training pods push the following metrics after each batch:

| Metric | Type | Description |
|--------|------|-------------|
| `neat_generation` | gauge | Current generation number |
| `neat_fitness_max` | gauge | Highest fitness in the generation |
| `neat_fitness_avg` | gauge | Average fitness across the population |
| `neat_species_count` | gauge | Number of active NEAT species |

### Tekton Dashboard

The Tekton Dashboard provides real-time visibility into pipeline runs, task logs, and run history. Access it via port-forward on port 9097.

## Memory Address Discovery

Game memory addresses for reading character state (health, position, attack) are documented in [`docs/MEMORY_MAP.md`](docs/MEMORY_MAP.md). This includes the methodology for discovering addresses using BizHawk's RAM Search tool.

## Project Structure

```
saiyan-trainer/
+-- lua/                          # NEAT training Lua scripts
|   +-- main.lua                  # Entry point
|   +-- neat/                     # NEAT algorithm implementation
|   +-- training/                 # Training loop and fitness
|   +-- memory_reader.lua         # GBA memory reading
|   +-- controller.lua            # Neural net -> button presses
|   +-- memory_map.lua            # Memory address definitions
|   +-- vis/                      # Visualization utilities
+-- k8s/                          # Kubernetes manifests
|   +-- tekton/                   # Tekton Pipeline, Tasks, Triggers
|   |   +-- tasks/                # Individual task definitions
|   |   +-- pipeline.yaml         # Main training pipeline
|   |   +-- pipelinerun.yaml      # Manual trigger template
|   |   +-- triggers/             # EventListener for auto-continuation
|   +-- storage/                  # SeaweedFS + workspace PVC
|   +-- observability/            # Prometheus, Pushgateway, Grafana
|   |   +-- grafana/dashboards/   # Dashboard JSON files
|   +-- setup/                    # One-command install script
+-- docker/                       # BizHawk container image
|   +-- Dockerfile                # Container build
|   +-- docker-compose.yml        # Local testing
+-- roms/                         # ROM files (gitignored)
+-- savestates/                   # BizHawk save states
+-- docs/                         # Documentation
    +-- MEMORY_MAP.md             # GBA memory address reference
```

## Strategic Goal

Beyond being a fun game bot project, Saiyan Trainer serves as a **discovery vehicle for identifying what Tekton needs to better support ML/DL workloads**. Pain points, workarounds, and custom tooling built here -- timeout configurations, long-running job patterns, model storage integration, distributed evaluation fan-out, PipelineRun chaining -- become the basis for a potential **Tekton ML toolkit or extension**.

The goal is to package these learnings to help people rely more on Tekton for ML pipelines instead of reaching for Kubeflow or Argo Workflows.

## Contributing

Contributions are welcome. Key areas where help is needed:

- Fighting game fitness function tuning (offense/defense balance)
- Additional NEAT operators (crossover strategies, speciation tweaks)
- Multi-character support (different fighters have different move sets)
- Fight replay recording from containers (stretch goal -- see OBS-05 in planning)

## Acknowledgments

- [MarI/O by SethBling](https://www.youtube.com/watch?v=qv6UVOQ0F44) -- the original NEAT-in-emulator inspiration
- [NEAT paper by Kenneth Stanley](http://nn.cs.utexas.edu/downloads/papers/stanley.ec02.pdf) -- the algorithm behind it all
- [BizHawk](https://github.com/TASEmulators/BizHawk) -- the TAS emulator community
- [Tekton](https://tekton.dev) -- Kubernetes-native CI/CD and pipeline orchestration

## License

This project is open source. ROM files are not included and must be provided by the user.
