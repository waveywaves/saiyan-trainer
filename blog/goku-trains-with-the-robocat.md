# Goku Trains with the RoboCat: Teaching a Neural Network to Fight (and What It Taught Me About MLOps on Tekton)

## From College Project to Cloud-Native Experiment

Back in college, I built a NEAT neuroevolution bot to play Dragon Ball Z: Supersonic Warriors on Game Boy Advance. It was inspired by SethBling's MarI/O project—watching neural networks learn to play games through evolution was fascinating. My bot learned basic combos, figured out special moves, and occasionally won fights. It was a fun project, I learned a lot about evolutionary algorithms, and then it sat in a GitHub repo gathering dust.

Fast forward a few years: I'm working on Tekton Pipelines, building CI/CD infrastructure on Kubernetes. One day, a thought occurred to me: **what if I revisited that old college project, but used it as a vehicle to explore what MLOps actually needs from Tekton?**

Most discussions about "ML on Kubernetes" point you toward Kubeflow or Argo Workflows. But what if you already have Tekton running your CI/CD? What would it take to run ML training workloads on the same infrastructure? What primitives are missing? What patterns would emerge?

I needed a real ML workload to test this—not a toy example, but something with actual training loops, checkpoint management, convergence detection, and all the messiness of real experimentation. My old fighting game bot was perfect.

This is the story of how I taught Goku to fight using Tekton Pipelines, built a new feature for Tekton along the way, and discovered what cloud-native MLOps actually looks like when you strip away the specialized platforms.

---

## The Challenge: Iteration Doesn't Fit CI/CD Primitives

Training a neuroevolution model looks nothing like a CI/CD pipeline:

```
CI/CD Pipeline:
  checkout → build → test → deploy
  (linear, deterministic, completes in minutes)

ML Training Loop:
  initialize → evaluate → breed → evaluate → breed → ...
  (iterative, convergent, runs for hours)
```

Tekton has amazing primitives for linear workflows: Tasks execute steps, Pipelines chain Tasks together, parameters flow through the DAG. But it doesn't have a **loop primitive**. If you want iteration, you're supposed to use Tekton Triggers—an external event system that watches for pipeline completions and launches new runs.

I tried it. It's the wrong abstraction.

Triggers are designed for event-driven workflows: a git push triggers a build, a Docker image push triggers deployment. They're heavyweight (separate controller, event listeners, TriggerBindings, TriggerTemplates) and add latency between iterations. For ML training that needs to run 100+ generations with tight feedback loops, this is a non-starter.

**What I needed**: A native loop primitive that could iterate inside a single PipelineRun, pass state between iterations, and stop when convergence criteria were met.

**What existed**: Triggers (too heavyweight) or Matrix (parallel fan-out, not iteration).

So I built it.

---

## Building Tekton Loop: Iteration as a First-Class Primitive

I forked `tektoncd/pipeline` and created a feature branch called `feat/pipeline-iteration`. The goal: add a `loop` field to Tasks that would enable iteration with:

- **Bounded repetition**: `maxIterations: 20` (safety limit)
- **Convergence detection**: `until: "'$(loop.previousResult.converged)' == 'true'"` (stop early if goal reached)
- **State passing**: `$(loop.iteration)` and `$(loop.previousResult.*)` for inter-iteration communication
- **Progress tracking**: Loop state stored in PipelineRun status for observability

Here's what the final API looks like:

```yaml
tasks:
  - name: train-batch
    loop:
      maxIterations: 20
      until: "'$(loop.previousResult.converged)' == 'true'"
      iterationParams:
        - name: batch-number
          value: "$(loop.iteration)"
    taskSpec:
      results:
        - name: best-fitness
        - name: generation
        - name: converged
      steps:
        - name: train
          script: |
            # Train N generations
            # Write fitness to $(results.best-fitness.path)
            # Write "true" to $(results.converged.path) if threshold met
```

Each iteration runs as a separate TaskRun. The controller waits for completion, reads the results, evaluates the `until` condition, and either continues or stops. Progress is visible in `kubectl get pipelineruns`, and loop state survives controller restarts because it's stored in the PipelineRun status.

After 12+ commits, the feature worked. I deployed it on a local Kind cluster with the alpha feature flag enabled:

```bash
kubectl -n tekton-pipelines patch configmap feature-flags \
  --type merge -p '{"data":{"enable-api-fields":"alpha"}}'
```

### The Path to Upstream: From Alpha Feature to TEP Proposal

Building a feature branch is one thing. Getting it upstream into Tekton is another. The Tekton project has a formal enhancement process—**TEPs (Tekton Enhancement Proposals)**—for introducing new features or significant API changes.

Loop is currently an **alpha feature**, which means:
- It works, but the API may change
- It requires explicit opt-in via feature flags
- It's not guaranteed to be stable or supported
- Community feedback is needed before stabilization

To graduate Loop from alpha to beta (and eventually stable), I need to write a TEP that addresses:

1. **Motivation**: Why does Tekton need iteration primitives? (This blog post is part of that argument)
2. **Design**: API surface, controller implementation, edge cases
3. **Alternatives considered**: Why not Triggers? Why not external orchestration?
4. **User stories**: What workloads does this enable? (ML training, batch processing, ETL)
5. **Open questions**: Nested loops? Break/continue? Dynamic iteration counts?
6. **Migration path**: How do existing users adopt this?

The training experiment you're reading about serves as the **proof-of-concept** for the TEP. It demonstrates:
- Loop works for real iterative workloads (6-hour ML training runs)
- State passing between iterations is essential (`$(loop.previousResult)`)
- Convergence detection enables early stopping (saves compute)
- Progress tracking matters for long-running work (which iteration are we on?)

**TEP Status**: Currently drafting. The proposal will be submitted to [tektoncd/community](https://github.com/tektoncd/community/tree/main/teps) once the design is solidified based on feedback from this experiment.

**Follow the TEP**: [TEP-XXXX: Loop Iteration Primitive](https://github.com/tektoncd/community/pull/XXXX) _(link will be updated once submitted)_

---

**The PoC → TEP Journey**:

```
College Project (2020)
    ↓
Idea: "Can I run ML on Tekton?" (2026)
    ↓
Problem: No iteration primitive
    ↓
PoC: Build Loop feature (12+ commits, alpha flag)
    ↓
Validation: Run real experiment (this blog post)
    ↓
TEP Proposal: Formalize design, gather feedback
    ↓
Community Review: API refinement, edge cases
    ↓
Beta Release: Stable API, production-ready
    ↓
GA Release: Loop as stable Tekton primitive
    ↓
Toolkit: Build ML patterns on top of Loop
```

This is open-source development in action: build → validate → propose → iterate → ship.

---

Now I had iteration. Time to prove it works by training Goku.

---

## The Experiment: 4 Islands, 155 Generations, 24,000 Evaluations

I designed the training as a proper experiment with a testable hypothesis:

**Hypothesis**: Tekton Loop can orchestrate long-running iterative ML workloads with the same reliability it brings to CI/CD.

**Method**: Train four isolated neural network populations (islands) to master DBZ combat through neuroevolution, using Tekton Loop to manage iteration, checkpointing, and convergence detection.

### Architecture

**Training Container**: mGBA emulator (GBA emulator) with Lua scripting, VNC for live observation, NEAT algorithm implemented in Lua

**Pipeline Structure**:
- 1 PipelineRun per island (4 total running in parallel)
- Each PipelineRun has a `train-batch` task with Loop (max 20 iterations)
- Each iteration trains 5 NEAT generations inside mGBA
- Results (fitness, generation, converged) written after each iteration
- Loop continues until fitness > 5000 or 20 iterations complete

**State Management**:
- Checkpoints isolated per island: `output/<island-id>/checkpoints/gen_N.json`
- Trainer auto-resumes from latest checkpoint (survives pod restarts)
- Training logs, metrics, and results preserved on PVC

**Island Model**: Each island evolves independently. This is a classic neuroevolution pattern—isolated populations explore different parts of the solution space, and you can optionally migrate top genomes between islands to share discoveries. I didn't implement migration (that's future work), but the isolation alone proved valuable.

### NEAT Configuration

- **Population**: 40 genomes per island
- **Inputs**: 5 (P1/P2 positions, P1/P2 HP, frame count)
- **Outputs**: 8 (GBA buttons: A, B, L, R, Up, Down, Left, Right)
- **Fitness function**: `damage × 3 + KO bonus (2000) + survival (5) + diversity (1) - stalling penalty`
- **Timeout**: 600 frames (~10 seconds at 60fps)

The fitness function evolved through experimentation. Early versions had a floor at -1 for "no damage dealt," which killed all selection pressure. Removing the floor and adding survival + diversity signals gave genomes a gradient to climb even when stuck at 0 damage.

---

## Results: Breakthroughs, Plateaus, and a Champion

After ~6 hours of training (overnight run), all 4 islands completed their 20 loop iterations:

| Island | Final Gen | Best Fitness | P2 Damage | Status |
|--------|-----------|--------------|-----------|---------|
| island-1 | 142 | 191.1 | 31 | Peaked early, regressed |
| island-2 | 155 | 218.8 | 27 | Breakthrough after 75-gen plateau |
| island-3 | 155 | **2234.7** | **66** | Champion (93% KO rate) |
| island-4 | 155 | 204.3 | 49 | Steady climber |

### Island-3: The Champion

Island-3's champion genome achieved **2234.7 fitness** by dealing **66 damage out of 71 possible** (93% KO rate). Here's what makes it special:

- **P2 HP trajectory**: 71 → 5 (leaves opponent with 5 HP, nearly perfect)
- **Network complexity**: 114 genes, 21 hidden nodes (evolved from 5-input, 8-output minimal topology)
- **Combo diversity**: 33 unique button patterns, entropy 2.60 (not button-mashing, structured strategy)
- **Consistency**: Maintained 2234+ fitness from Gen 51 through Gen 155

The breakthrough progression tells the story:
- **Gen 0-13**: Button-mashing, 0 damage, fitness ~65 (survival + diversity signals only)
- **Gen 14**: First damage (20 HP), fitness jumps to 116
- **Gen 19**: 29 damage, network adds hidden nodes
- **Gen 28**: 44 damage, fitness 188
- **Gen 51**: **71 damage full KO**, fitness 2234
- **Gen 51-155**: Maintained dominance with occasional 66-damage near-KOs

### Island-2: The Late Bloomer

Island-2's story is the most interesting from a neuroevolution perspective. It was stuck at **116.7 fitness (20 damage) for 75+ generations**. Most ML practitioners would have stopped training, assuming it hit a local optimum.

But I let it run.

Between Gen 75 and Gen 155, island-2 broke through to **218.8 fitness (27 damage)**—an 87% improvement. This happened through **speciation**: NEAT maintains separate species that protect novel genomes from immediate competition. One of those protected lineages eventually found the mutation sequence that unlocked higher fitness.

**Lesson learned**: Plateau ≠ convergence. Evolutionary pressure works on longer timescales than gradient descent.

### Island-1: The Regression Mystery

Island-1 peaked at 191.1 fitness (45 damage) around Gen 50, then regressed to 150.5 by Gen 142. Looking at the checkpoint history, this appears to be **species extinction**—the champion lineage was outcompeted by genomes that won through timeout strategies (character switching to heal P1 HP) rather than dealing damage.

This is a fitness function design problem. The timeout win bonus (50 points) + character-switch healing created a local optimum that was easier to reach than the aggressive offense strategy. Island-1 found it, Island-3 didn't.

**Lesson learned**: Fitness function design matters enormously. Small reward imbalances create basins of attraction that trap evolution.

### Island-4: The Strategist

Island-4 maintained steady performance at 204.3 fitness (49 damage) with the **highest combo diversity**: 54 unique button patterns, 2.20 entropy. This island explored the solution space broadly rather than converging on one strategy. Valuable for ensemble approaches.

---

## The Debugging Journey: What MLOps on Tekton Actually Looks Like

Building this wasn't smooth sailing. Here are the bugs I hit and what they reveal about MLOps requirements:

### Bug 1: The Wrong Memory Address

**Problem**: P2 HP always read as 72 (constant), so fitness calculations were broken.

**Root cause**: I was using a VBA cheat code address (0x03004C30) from an old GameFAQ forum post. That address worked on VBA emulator in 2010 but not on mGBA in 2026.

**Fix**: Struct stride analysis. I knew P2's Ki address (0x03002833) and P1's Ki address (0x0300274B). The difference is the struct stride: `0xE8` bytes. Applied that offset to P1's HP address (0x0300273E) and got the correct P2 HP address: `0x03002826`.

**Lesson for MLOps**: Data validation at system boundaries is critical. I added diagnostic logging that printed P1 HP, old P2 HP address value, and new P2 HP address value for the first genome of every batch. This immediately surfaced the fix.

### Bug 2: Stale Results File

**Problem**: After restarting a PipelineRun, Loop iterations completed in 2 seconds instead of 20 minutes. Training wasn't happening.

**Root cause**: Tekton Loop resets iteration counter to 0 for each new PipelineRun. But the PVC persists files from previous runs. The training script waits for `batch_0.txt` to appear, finds the old file from yesterday's run, reads stale data, and completes instantly.

**Fix**: Delete the expected results file before launching training:
```bash
RESULTS_FILE="${RESULTS_DIR}/batch_${BATCH_NUMBER}.txt"
rm -f "$RESULTS_FILE"
```

**Lesson for MLOps**: Ephemeral orchestration + persistent storage = synchronization challenges. Any pipeline that uses iteration numbers in filenames needs to handle stale state. Solutions: delete before use, timestamp filenames, or use PipelineRun UID in paths.

### Bug 3: Corrupt Checkpoint

**Problem**: Island-1 got stuck in an infinite loop printing "Auto-resuming from gen_63.json" every frame (60fps spam in logs).

**Root cause**: Docker shutdown during training killed the process mid-checkpoint-write. The file had valid size (649 KB) but invalid content (JSON parse error at byte 0). The Lua trainer tried to load it every frame, failed silently, and stayed in "init" state forever.

**Fix**: Delete the corrupt checkpoint, fall back to gen_62.json. Future fix: use atomic writes (write to temp file, then rename) and defensive `pcall` in the load path.

**Lesson for MLOps**: Checkpoint corruption from crashes is real. ML frameworks should handle it gracefully (fallback to previous checkpoint, clear error messages, automatic corruption detection).

### Bug 4: Timeout Confusion

**Problem**: PipelineRuns completed at 75% progress with "Failed" status after exactly 1 hour.

**Root cause**: Tekton has **two timeout layers**:
- Task-level: `timeout: "0"` (disabled)
- Pipeline-level: default 1 hour (not disabled)

Setting task timeout to 0 didn't prevent the pipeline-level timeout from killing the run.

**Fix**: Add `spec.timeouts.pipeline: "0"` to PipelineRun.

**Lesson for MLOps**: Long-running jobs need explicit timeout configuration at every layer. Defaults optimized for CI/CD (1 hour max) don't work for ML training (hours to days). Platforms need better defaults or auto-detection for workload type.

---

## What Tekton Needs for MLOps: Lessons from the Experiment

After running this experiment end-to-end, here's what I learned about what Tekton needs to be a viable MLOps platform:

### 1. Iteration Primitives (Loop) ✅

**Status**: Built and working as alpha feature

**Why it matters**: ML training is fundamentally iterative. Without native loop support, you're stuck with external orchestration (Triggers) or running everything in a single long-running container (no observability, can't parallelize iterations, no checkpoint resumption).

**What's next**:
- Graduate Loop from alpha to beta
- Add break/continue semantics
- Support nested loops for hyperparameter grids

### 2. Long-Running Pod Patterns

**Status**: Possible but requires manual configuration

**Why it matters**: Training runs for hours to days. Default timeout assumptions (1 hour) and lack of clear guidance on timeout layering causes failures.

**What's needed**:
- Workload-aware timeout defaults (or no default for Loop tasks)
- Better documentation on task vs pipeline vs taskrun timeouts
- Health checks that don't kill pods just for running long

### 3. Checkpoint Management

**Status**: Manual (PVC + application-level logic)

**Why it matters**: Training must survive pod evictions, node failures, and deliberate stops. Checkpointing is the only way to make progress resumable.

**What's needed**:
- First-class checkpoint primitives (not just PVC + hope)
- Atomic checkpoint writes (temp + rename pattern)
- Checkpoint versioning and garbage collection
- Integration with object storage (S3, GCS) not just PVC

### 4. Result Passing and State Management

**Status**: Loop.previousResult works but limited

**Why it matters**: Each iteration needs data from previous iterations (fitness scores, convergence metrics, hyperparameters to try next).

**What's needed**:
- Richer result types (not just strings)
- Arrays of results (for distributed evaluation)
- Aggregation functions (max, min, average across parallel tasks)
- Persistent state between PipelineRuns (not just within)

### 5. Live Observability

**Status**: Manual (VNC + metrics extraction via kubectl exec)

**Why it matters**: Black-box training for 6 hours is unacceptable. You need to see progress, detect stalls, and debug issues in real-time.

**What I built**:
- VNC streaming from training pods (noVNC web UI)
- Dashboard with fitness progression charts
- Network topology visualization
- Breakthrough detection system

**What Tekton should provide**:
- Streaming metrics/logs endpoints (not just completed TaskRun logs)
- Dashboard integration for long-running tasks
- Progress indicators beyond "Running" (e.g., "Running: 47/100 iterations")

### 6. Distributed Evaluation

**Status**: Multi-PipelineRun parallelism works (island model)

**Why it matters**: Evaluating 40 genomes serially takes 40× longer than parallel evaluation. For large populations, you need fan-out.

**What's working**: I ran 4 islands in parallel as separate PipelineRuns. Each island was independent (no shared state), which made this easy.

**What's missing**:
- **Pipelines-in-Pipelines** for hierarchical parallelism (Loop × Matrix in the same pipeline)
- **Dynamic fan-out** based on runtime values (e.g., population size determined by previous iteration)
- **Result aggregation** across parallel branches (e.g., collect fitness scores from all workers)

### 7. Model Registry Integration

**Status**: Manual (store-champion task writes to PVC)

**Why it matters**: Trained models need versioning, tagging, and deployment. This is the "artifact management" problem from CI/CD, but for models.

**What's needed**:
- Integration with model registries (MLflow, Seldon, custom)
- Automatic versioning based on PipelineRun metadata
- Model lineage tracking (which data, code, hyperparameters produced this model)

---

## The Bigger Picture: What This Means for Cloud-Native ML

Running this experiment taught me something important: **MLOps isn't actually that different from CI/CD when you strip away the domain specifics.**

Both need:
- Iteration (builds retry on failure, training loops over generations)
- State management (build artifacts persist, model checkpoints persist)
- Convergence detection (tests pass → deploy, fitness threshold met → stop training)
- Observability (build logs, training metrics)
- Artifact storage (Docker images, trained models)

The primitives are the same. The timescales are different (minutes vs hours), and the failure modes are different (flaky tests vs plateau convergence), but the orchestration patterns overlap heavily.

**What this suggests**: Instead of building separate platforms for CI/CD and MLOps, we should be extending existing orchestration tools with the primitives ML needs. Tekton Loop is one example. Checkpoint management, result aggregation, and dynamic fan-out would be others.

The alternative—telling teams "use Tekton for CI/CD and Kubeflow for ML"—means running two orchestration platforms, two sets of RBAC policies, two observability stacks, two sets of resource quotas. That's heavyweight.

If you already have Tekton running your CI/CD, and Loop + a few more primitives can handle your ML workloads, that's a huge operational simplification.

---

## What's Next: From Experiment to Toolkit

This experiment proved that Tekton Loop works for real ML workloads. But proof-of-concept isn't production-ready. Here's the roadmap:

### Step 1: Formalize Loop via TEP (In Progress)

The first priority is getting Loop upstream through the Tekton Enhancement Proposal (TEP) process. The experiment documented in this post provides the evidence needed for the TEP:

- **Real workload validation**: 6-hour training runs, 155 generations, 4 parallel islands
- **Edge case discovery**: Checkpoint corruption, stale state handling, timeout layering
- **API surface validation**: `maxIterations`, `until`, `iterationParams`, `$(loop.previousResult)` all proven necessary
- **Use case demonstration**: ML training, but generalizes to any iterative workload

**TEP Status**: Currently drafting based on lessons from this experiment. Will be submitted to [tektoncd/community](https://github.com/tektoncd/community/tree/main/teps) for review.

**What the TEP will propose**:
- Graduate Loop from alpha → beta with API stability guarantees
- Define iteration semantics (ordering, state passing, failure handling)
- Address open questions (nested loops, dynamic iteration counts, break/continue)
- Provide migration path for users currently using Triggers for iteration

### Step 2: Build the Toolkit

Once Loop is stable, the next step is packaging ML patterns into reusable components.

**Potential components**:

1. **Tekton ML Task Library**
   - Pre-built Tasks for common ML operations (train, evaluate, checkpoint, deploy)
   - Reference implementations for popular frameworks (PyTorch, TensorFlow, NEAT)

2. **Checkpoint Patterns**
   - Atomic checkpoint writes
   - S3/GCS integration
   - Automatic garbage collection

3. **Observability Dashboard**
   - Training metrics visualization
   - Real-time progress tracking
   - Breakthrough detection

4. **Model Registry Integration**
   - MLflow backend
   - Automatic versioning
   - Lineage tracking

5. **Distributed Evaluation Patterns**
   - Loop + Matrix composition
   - Dynamic fan-out
   - Result aggregation

If this sounds interesting to you, here's how to get involved:

**Follow the work**:
- **Training code**: [github.com/waveywaves/saiyan-trainer](https://github.com/waveywaves/saiyan-trainer)
- **Tekton Loop PoC**: `feat/pipeline-iteration` branch on my `tektoncd/pipeline` fork
- **TEP Proposal**: [TEP-XXXX: Loop Iteration Primitive](https://github.com/tektoncd/community/pull/XXXX) _(being drafted, link will update when submitted)_
- **Talk**: DevConf.cz 2026 - "Goku Trains with the RoboCat"

**Contribute**:
- Review the TEP when it's submitted (feedback needed on API design, edge cases, use cases)
- Try Loop on your own workloads (ML training, batch processing, ETL, anything iterative)
- Share your patterns and pain points

I'd love to hear from others running ML on Tekton—what patterns work for you? What primitives are missing? Let's build the toolkit together.

---

## Conclusion: The RoboCat Trained Goku (and Taught Me About MLOps)

When I started this project, I had a simple question: *What would it take to run my old college project on Tekton?*

The answer turned out to be: **Build a new feature, run a real experiment, debug a lot of edge cases, and discover that MLOps on cloud-native infrastructure is more practical than people think.**

After 155 generations of evolution, island-3 achieved 2234.7 fitness by dealing 66 damage out of 71 possible—a 93% KO rate. That's a neural network that learned to fight through pure evolution, orchestrated entirely by Tekton Pipelines.

More importantly, this experiment validated that Tekton Loop works for iterative ML workloads. It survived 6-hour training runs, handled checkpoint corruption gracefully (after I fixed the bugs), scaled to 4 parallel islands, and provided real-time observability through VNC and metrics dashboards.

The RoboCat (Tekton's mascot) successfully trained Goku. And in the process, it taught me what cloud-native MLOps actually needs:
- Native iteration primitives
- Long-running pod patterns
- First-class checkpoint management
- Rich result passing
- Streaming observability
- Distributed evaluation support
- Model registry integration

Some of these exist (Loop). Some need to be built. All of them are achievable without creating a separate ML platform.

If you're running Tekton for CI/CD and wondering whether it can handle ML workloads: yes, it can. But it needs a few more primitives. Let's build them together.

---

**Acknowledgments**: Thanks to the Tekton community for building such a solid foundation, to SethBling for the [MarI/O project](https://www.youtube.com/watch?v=qv6UVOQ0F44) that inspired this experiment years ago, and to Kenneth O. Stanley and Risto Miikkulainen for the [original NEAT paper](https://nn.cs.utexas.edu/downloads/papers/stanley.ec02.pdf) (2002) that made it all possible.

**Resources**:
- **Code**: [github.com/waveywaves/saiyan-trainer](https://github.com/waveywaves/saiyan-trainer)
- **Loop PoC**: `feat/pipeline-iteration` branch (alpha feature, works but not upstream yet)
- **TEP Proposal**: [TEP-XXXX: Loop Iteration Primitive](https://github.com/tektoncd/community/pull/XXXX) _(in progress)_
- **Talk**: DevConf.cz 2026 - "Goku Trains with the RoboCat: Multi-Island Neuroevolution on Tekton Pipelines"

**The Journey Ahead**:
1. **PoC → TEP**: Submit formal enhancement proposal for Loop (in progress)
2. **Alpha → Beta**: Stabilize API based on community feedback
3. **Beta → GA**: Graduate Loop to stable once battle-tested
4. **Build the toolkit**: Package ML patterns for reuse
5. **Island migration**: Let the champions share their strategies

The RoboCat trained Goku. Now let's make sure other Tekton users can train their own champions.
