# Feature Landscape

**Domain:** Neuroevolution game bot with MLOps pipeline (NEAT + BizHawk + Tekton on Kubernetes)
**Researched:** 2026-03-06

## Table Stakes

Features users expect. Missing = the demo does not work or is not credible as an MLOps example.

### Neuroevolution Core

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| GBA memory map reader (Lua) | Foundation -- without reading HP, positions, attack states from RAM the bot has no inputs | Med | Must reverse-engineer DBZ Supersonic Warriors memory addresses for both P1 and P2. SSF2-AI and MarI/O both do this. |
| Controller input writer (Lua) | Foundation -- NEAT outputs must translate to GBA button presses each frame | Low | BizHawk joypad API is well-documented; MarI/O pattern works directly. |
| NEAT implementation in Lua | Core algorithm -- evolves neural network topology and weights | High | MarI/O provides a working Lua NEAT. Adapt for fighting game (different input/output space). Start from MarI/O's codebase rather than writing from scratch. |
| Fitness function (offense + defense) | Without fitness, evolution has no selection pressure | Med | Must reward damage dealt, penalize damage taken, and bonus for winning rounds. Research shows pure win/loss is too sparse; need shaped rewards. Critical: fitness must depend on the bot's own actions, not opponent self-destruction (a known pitfall from fighting game neuroevolution research). |
| Save state management | Each genome evaluation must start from identical game state | Low | BizHawk save states are standard. Save a "fight start" state, load before each evaluation. |
| Genome serialization (save/load) | Cannot lose training progress across runs | Med | MarI/O uses .pool files. Lua equivalent must serialize species, genomes, innovation numbers. Use JSON or custom text format for portability. |
| Generation loop with population | Core NEAT loop: evaluate population, select, crossover, mutate, repeat | Med | Standard NEAT flow. Population of 150-300 genomes is typical starting point. |
| Speciation | NEAT requires speciation to protect innovation through compatibility distance | Med | Part of NEAT algorithm. Without it, novel topologies get eliminated before they can optimize. |

### MLOps Pipeline Core

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Tekton Pipeline definition (YAML) | The entire point of the project is demonstrating Tekton for ML | Med | Pipeline with Tasks: setup -> train -> evaluate -> store. Must be declarative Kubernetes resources. |
| Training Task | Runs the NEAT training loop inside a container on K8s | High | Needs BizHawk running headless in a container (or Lua NEAT separated from emulator). This is the hardest integration point. |
| Evaluation Task | Automated fights against CPU to measure trained model quality | Med | Load best genome, run N fights, report win rate. Separate from training so it can run independently. |
| Model storage Task | Store trained genomes/checkpoints in persistent storage | Low | Could be a PVC, S3-compatible store, or OCI artifact. Needs to be retrievable for retraining. |
| Pipeline triggers / manual run | User must be able to kick off training | Low | Tekton PipelineRun or trigger. Manual is fine for a demo. |
| Basic training metrics output | Must show that training is progressing (generation, best fitness, species count) | Low | Log output from training task. Without this, the demo is a black box. |

### Developer Experience

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| README with setup instructions | Open-source project needs clear onboarding | Low | ROM sourcing (user provides), BizHawk setup, K8s/Tekton prereqs. |
| Reproducible local run (no K8s) | Contributors need to iterate without a cluster | Low | Lua script runnable directly in BizHawk for local NEAT development. |
| ROM not included (legal) | Legal requirement -- ROM must be gitignored | Low | Already in PROJECT.md constraints. Provide clear instructions for user to supply ROM. |

## Differentiators

Features that set this project apart from other NEAT game bots or MLOps demos. Not expected, but make it valuable as an open-source reference.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Real-time neural network visualization overlay | Shows the evolved network topology on screen during gameplay -- visually compelling, makes the project shareable/demo-able. MarI/O's most memorable feature. | Med | Draw nodes and connections on BizHawk GUI. MarI/O does this; adapt for fighting game inputs. |
| Generation progress dashboard | Fitness curves, species count over generations, best genome stats -- makes training observable beyond log lines | Med | Could be a simple web UI reading metrics from stored data, or TensorBoard-style. Adds MLOps credibility. |
| Multi-opponent training curriculum | Train against multiple CPU difficulty levels or characters sequentially. Research shows single-opponent training leads to overfitting. | Med | Rotate opponents across generations. Significantly improves generalization. |
| Pipeline-driven retraining from checkpoint | Resume training from a stored genome checkpoint via a new PipelineRun. Demonstrates a real MLOps pattern (model iteration). | Med | Load checkpoint from storage, continue NEAT evolution. Key MLOps differentiator vs one-shot training scripts. |
| Model versioning with generation tagging | Each training run and its best genome tagged with metadata (generation, fitness, opponent, date). Enables comparing models across runs. | Med | Store as OCI artifacts or in a simple model registry. Makes the Tekton demo feel like real MLOps. |
| Recorded fight playback (best genome vs CPU) | Save a replay of the best genome fighting. Visual proof the bot works. Shareable on social media. | Low | BizHawk can record AVI. Run best genome, capture output. Low effort, high impact for demos. |
| Species visualization over time | Graph showing how species emerge, grow, and die over generations. Unique to NEAT and visually interesting. | Med | Track species lineage data during training, render as a timeline/treemap. |
| Combo/pattern analysis of learned behavior | Analyze what button sequences the trained bot uses most. Reveals if it learned real fighting game strategies (blocking, combos) vs button mashing. | Med | Post-hoc analysis of input logs from evaluation fights. Interesting for blog posts / talks. |
| Tekton Dashboard integration | Tekton has a dashboard for pipeline visualization. Showing training pipelines there adds polish. | Low | Tekton Dashboard is a standard add-on. Just install it -- pipelines show up automatically. |
| Distributed evaluation (parallel genome fitness) | Evaluate multiple genomes in parallel across pods. Demonstrates K8s scaling for ML. | High | Each genome evaluation is independent. Fan-out pattern in Tekton. Significantly speeds training but adds orchestration complexity. |

## Anti-Features

Features to explicitly NOT build. These add complexity without supporting the core value proposition.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Pixel/vision-based input (CNN) | Massively increases complexity, requires GPU, defeats the simplicity of memory-map approach. PROJECT.md explicitly excludes this. | Read game state from GBA memory map. Structured data is faster and sufficient. |
| Deep RL (DQN, PPO, A3C) | Different paradigm, requires gradient computation infrastructure, does not run in Lua on BizHawk. PROJECT.md explicitly excludes this. | Use NEAT neuroevolution. It works in Lua, is proven with MarI/O, and evolves topology. |
| Web frontend for training control | Over-engineering for a demo. Adds frontend stack, auth, state management. | Use Tekton PipelineRuns (kubectl/tkn CLI) and Tekton Dashboard for pipeline visibility. |
| Real-time multiplayer / online play | Completely different problem domain. Latency, networking, matchmaking. | Train against CPU opponents. This is a training/MLOps demo, not a game service. |
| Custom model serving endpoint (inference API) | The model runs inside BizHawk, not as a REST API. Serving infrastructure is irrelevant. | Load genome into Lua in BizHawk for inference. No HTTP needed. |
| OpenShift-specific features | Limits audience. PROJECT.md targets plain Kubernetes. | Target vanilla K8s + Tekton. Works on any cluster including minikube/kind. |
| Kubeflow Pipelines integration | Adds heavy dependency (Kubeflow control plane). Tekton alone is the point. | Use raw Tekton Pipelines. The demo proves Tekton can handle ML without Kubeflow. |
| Hyperparameter optimization service (Katib) | Over-engineering. NEAT hyperparams (population size, mutation rates) can be tuned manually for this scale. | Document sensible defaults. Allow overriding via pipeline parameters. |
| Multi-game support | Generalizing across games dilutes the demo and massively increases scope. | Focus on DBZ Supersonic Warriors. Depth over breadth. |
| GUI configuration tool for NEAT parameters | Nice-to-have that delays shipping. | Use a Lua config file or environment variables. |

## Feature Dependencies

```
Memory Map Reader -> Controller Input Writer -> NEAT Lua Implementation
                                                       |
                                              Fitness Function
                                                       |
                                              Generation Loop (with Speciation)
                                                       |
                                              Genome Serialization (Save/Load)
                                                       |
                                    +------------------+------------------+
                                    |                                     |
                          Local BizHawk Run                    Containerized Training
                          (dev iteration)                      (BizHawk in Docker)
                                                                         |
                                                              Tekton Training Task
                                                                         |
                                                    +--------------------+--------------------+
                                                    |                    |                    |
                                          Evaluation Task       Model Storage Task    Pipeline Definition
                                                    |                    |                    |
                                                    +--------------------+--------------------+
                                                                         |
                                                              Pipeline Triggers / Manual Run
                                                                         |
                                              +-----+--------+----------+----------+
                                              |              |                     |
                                    Training Metrics    Retraining from       Model Versioning
                                         Output         Checkpoint
                                              |              |                     |
                                    Generation Dashboard  Multi-opponent      Fight Playback
                                              |           Curriculum           Recording
                                    Species Visualization
                                              |
                                    Combo/Pattern Analysis
```

Key dependency chains:
- **Memory reader is foundation**: Everything depends on being able to read game state from GBA RAM.
- **Local run before K8s**: NEAT must work locally in BizHawk before attempting containerization.
- **Containerization is the bridge**: Getting BizHawk + Lua NEAT running in a Docker container is the critical path to Tekton integration.
- **Tekton pipeline unlocks MLOps features**: Model versioning, retraining, evaluation pipelines all depend on having basic Tekton orchestration working.
- **Visualization features are leaf nodes**: Dashboard, species graphs, fight replays can be added independently once core training works.

## MVP Recommendation

Prioritize (in order):

1. **GBA memory map reader for DBZ Supersonic Warriors** -- Without this, nothing else works. Reverse-engineer RAM addresses for P1/P2 health, position, attack state, round state.
2. **Controller input writer** -- Translate NEAT outputs to button presses.
3. **NEAT implementation in Lua** -- Adapt MarI/O's NEAT for fighting game input/output space.
4. **Fitness function** -- Shaped rewards: damage dealt (+), damage taken (-), round win (big +), round loss (big -).
5. **Generation loop with save/load** -- Full training loop that persists progress.
6. **Neural network visualization overlay** -- Early differentiator. Makes local development satisfying and the project visually compelling.
7. **Tekton Pipeline (train -> evaluate -> store)** -- The MLOps integration. Once NEAT works locally, containerize and orchestrate.
8. **Model versioning and retraining pipeline** -- The MLOps payoff. Show the iterate-and-improve loop.

Defer:
- **Distributed evaluation**: High complexity, tackle after single-pod training works end-to-end.
- **Generation dashboard**: Nice but not needed until there are real training runs generating data.
- **Multi-opponent curriculum**: Optimization that matters after basic single-opponent training succeeds.
- **Combo/pattern analysis**: Post-hoc research feature, not needed for a working demo.

## Sources

- [MarI/O (SethBling) - NEAT in Lua on BizHawk](https://glenn-roberts.com/posts/2015/07/08/neuroevolution-with-mario/) - MEDIUM confidence (community documentation)
- [Bizhawk-NEAT-GameSolver](https://github.com/LionelBergen/Bizhawk-NEAT-GameSolver-ML-AI) - MEDIUM confidence (working open-source project)
- [SSF2-AI - Fighting game framework for BizHawk](https://github.com/EHummerston/SSF2-AI) - MEDIUM confidence (most relevant fighting game precedent)
- [Pokemon Battle Factory NEAT](https://github.com/Javen-W/PokemonAI-BattleFactory-NEAT) - MEDIUM confidence (shows parallel evaluation pattern)
- [Multi-objective neuroevolution for fighting games](https://link.springer.com/article/10.1007/s00521-020-04794-x) - HIGH confidence (peer-reviewed research on fighting game fitness)
- [Teaching AI to play a fighting game with NEAT](https://medium.com/@mikecazzinaro/teaching-ai-to-play-a-platform-fighting-game-using-neural-networks-ef9316c34f52) - LOW confidence (single blog post, but relevant domain)
- [NEAT-Python checkpoint documentation](https://neat-python.readthedocs.io/en/latest/_modules/checkpoint.html) - HIGH confidence (official docs, pattern applies to Lua implementation)
- [MLOps Pipeline with Tekton and Buildpacks](https://towardsdatascience.com/automate-models-training-an-mlops-pipeline-with-tekton-and-buildpacks/) - MEDIUM confidence (recent Tekton MLOps tutorial)
- [NEATEvolve - improved MarI/O save/load](https://github.com/SngLol/NEATEvolve) - MEDIUM confidence (addresses save/load bugs in original MarI/O)
- [Neuroevolution in Games: State of the Art and Open Challenges](https://arxiv.org/pdf/1410.7326) - HIGH confidence (survey paper on neuroevolution in games)
- [goNEAT - Go NEAT with visualization formats](https://github.com/yaricom/goNEAT) - MEDIUM confidence (shows CytoscapeJS visualization pattern)
