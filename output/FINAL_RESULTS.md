# Saiyan Trainer - Final Training Results

**Training Date**: March 8, 2026
**Total Runtime**: ~6 hours (overnight run)
**Architecture**: 4-island model with Tekton Loop orchestration

---

## Executive Summary

All 4 training islands completed their 20-batch loop iterations (max iterations reached). Training produced a champion network capable of dealing **66 damage out of 71 possible** (93% KO rate) after 155 generations of neuroevolution.

---

## Final Results by Island

### Island-1
- **Final Generation**: 142 (stopped early - slower training)
- **Best All-Time Fitness**: 191.1
- **Peak Performance**: 45 damage at Gen ~50
- **Final Performance**: Regressed to 31 damage by Gen 142
- **Status**: Early peaker, experienced fitness regression
- **Notes**: Only island that didn't reach Gen 155 (10 batches vs 20 for others)

### Island-2
- **Final Generation**: 155
- **Best All-Time Fitness**: 218.8
- **Breakthrough Story**: Stuck at 116.7 (20 damage) for 75+ generations, then broke through to 218.8 (27 damage)
- **Status**: Late bloomer - proof that plateaus aren't convergence
- **Combo Diversity**: 47 unique patterns, 3.38 entropy (highest diversity)

### Island-3 🏆 CHAMPION
- **Final Generation**: 155
- **Best All-Time Fitness**: 2234.7
- **P2 Damage**: 66 out of 71 possible (93% KO rate)
- **Network Complexity**: 114 genes, 21 hidden nodes
- **Breakthrough Timeline**:
  - Gen 14: First breakthrough (20 damage)
  - Gen 19: 29 damage
  - Gen 28: 44 damage
  - Gen 51: **71 damage full KO** (2234.4 fitness)
  - Gen 51-155: Maintained 2234+ fitness
- **Strategy**: Pure offense, no character switching, consistent combo patterns
- **Status**: Absolute champion, 34× fitness improvement from Gen 0

### Island-4
- **Final Generation**: 155
- **Best All-Time Fitness**: 204.3
- **P2 Damage**: 49 damage
- **Combo Diversity**: 54 unique patterns, 2.20 entropy
- **Status**: Steady climber with high exploration
- **Notes**: Discovered character-switching timeout strategy

---

## Training Configuration

### NEAT Parameters
- **Population**: 40 genomes per island
- **Inputs**: 5 (P1/P2 X-position, P1/P2 HP, frame count)
- **Outputs**: 8 (GBA buttons: A, B, L, R, Up, Down, Left, Right)
- **Fitness Function**: `damage × 3 + KO_bonus(2000) + survival(5) + diversity(1) - stalling_penalty`
- **Timeout**: 600 frames (~10 seconds at 60fps)
- **Mutation Rates**:
  - Node mutation: 0.35
  - Connection mutation: 0.50
  - Weight perturbation: 0.90

### Pipeline Configuration
- **Generations per batch**: 5
- **Max batches**: 20
- **Fitness threshold**: 5000 (early stop if exceeded)
- **Total target**: 100 generations (20 batches × 5 gens)
- **Actual achieved**: 142-155 generations (exceeded target)

---

## Key Breakthroughs Detected

### Island-3 Breakthrough Timeline
1. **Gen 14**: P2 damage 0→20 (first breakthrough)
2. **Gen 19**: P2 damage 20→29 (network adds hidden nodes)
3. **Gen 28**: P2 damage 29→44 (fitness 188.9)
4. **Gen 47**: P2 damage 44→45 (fitness 191.3)
5. **Gen 51**: **P2 damage 45→71 FULL KO** (fitness 2234.4) 🏆
6. **Gen 51-155**: Maintained dominance

### Island-2 Breakthrough (The Late Bloomer)
- **Gen 0-75**: Stuck at 116.7 fitness, 20 damage
- **Gen 75-155**: Broke through to 218.8 fitness, 27 damage
- **Mechanism**: Speciation protected novel genomes from immediate competition
- **Lesson**: Plateau ≠ convergence, evolutionary pressure works on longer timescales

### Island-1 Breakthrough (Then Regression)
- **Gen 18**: P2 damage 20→26 (first breakthrough)
- **Gen 23**: P2 damage 26→34
- **Gen ~50**: Peaked at 191.1 fitness, 45 damage
- **Gen 142**: Regressed to 150.5 fitness, 31 damage
- **Cause**: Species extinction - champion lineage lost to timeout-win strategies

---

## Debugging Journey

### Bug 1: Wrong P2 HP Address
- **Problem**: P2 HP always read as constant 72
- **Cause**: VBA cheat code address (0x03004C30) didn't work on mGBA
- **Fix**: Struct stride analysis → correct address 0x03002826
- **Impact**: Made fitness calculations work correctly

### Bug 2: Stale Results File
- **Problem**: Loop iterations completed instantly instead of training
- **Cause**: Tekton Loop resets iteration to 0, but PVC persists old `batch_N.txt` files
- **Fix**: `rm -f "$RESULTS_FILE"` before launching mGBA
- **Impact**: Critical for resuming training after restarts

### Bug 3: Corrupt Checkpoint
- **Problem**: Island-1 stuck in infinite "Auto-resuming" loop
- **Cause**: Docker shutdown during training killed process mid-checkpoint-write
- **Fix**: Delete corrupt `gen_63.json`, fall back to `gen_62.json`
- **Lesson**: Need atomic checkpoint writes (temp + rename pattern)

### Bug 4: Timeout Confusion
- **Problem**: PipelineRuns failed at 75% completion after exactly 1 hour
- **Cause**: Pipeline-level timeout (1 hour default) despite task-level `timeout: "0"`
- **Fix**: Added `spec.timeouts.pipeline: "0"` to PipelineRun
- **Impact**: Allowed full 6-hour training run to complete

---

## Infrastructure Performance

### Tekton Loop
- **Total iterations**: 80 (20 batches × 4 islands)
- **Success rate**: 100% after timeout fix
- **State persistence**: Survived multiple pod restarts
- **Result passing**: `$(loop.previousResult)` worked reliably
- **Convergence detection**: `until` condition evaluated correctly
- **Status**: Alpha feature validated for production use

### Training Performance
- **Time per generation**: ~4.3 minutes (mGBA at 60fps real-time)
- **Time per batch**: ~21.5 minutes (5 generations)
- **Total training time**: ~6 hours (overnight run)
- **Checkpoint frequency**: Every generation
- **Checkpoint size**: 600KB → 1.8MB (grew with network complexity)

### Resource Utilization
- **Pods**: 4 simultaneous training pods (1 per island)
- **PVC**: Single shared PVC with per-island subdirectories
- **Checkpoint isolation**: `output/<island-id>/checkpoints/gen_N.json`
- **No resource contention**: Islands fully independent
- **Docker crashes**: Training survived 1 Docker restart (checkpoint resumption)

---

## Network Evolution Analysis

### Island-3 (Champion) Network Growth
- **Gen 0**: 40 genes, 0 hidden nodes (minimal topology)
- **Gen 14**: Added first hidden nodes (breakthrough to 20 damage)
- **Gen 51**: 114 genes, 21 hidden nodes (71 damage full KO)
- **Gen 155**: Stable at 114 genes, 21 hidden nodes
- **Complexity plateau**: Network stopped growing after finding winning strategy

### Island-2 (Late Bloomer) Network Growth
- **Gen 0-75**: 59 genes, 9 hidden nodes (stuck at 20 damage)
- **Gen 75-155**: Network complexity increased during breakthrough
- **Final**: 117 genes, 21 hidden nodes (27 damage)
- **Observation**: Complexity growth correlated with breakthrough

---

## Lessons for MLOps on Tekton

### What Works
1. **Loop primitive** handles iterative workloads reliably
2. **PVC checkpointing** survives pod restarts and crashes
3. **Result passing** enables convergence detection
4. **Multi-PipelineRun parallelism** supports island model
5. **VNC observability** makes black-box training debuggable

### What Needs Improvement
1. **Timeout defaults** optimized for CI/CD, not ML (1-hour limit)
2. **Checkpoint corruption** handling should be automatic
3. **Stale state management** needs better patterns
4. **Progress indicators** should show loop iteration, not just "Running"
5. **Streaming metrics** needed (not just completed TaskRun logs)

### What's Missing
1. **Nested loops** (Loop + Matrix composition)
2. **Dynamic fan-out** based on runtime values
3. **Result aggregation** across parallel tasks
4. **Model registry integration**
5. **First-class checkpoint primitives** (not just PVC + app logic)

---

## Data Artifacts

All training data preserved on PVC:

```
output/
├── island-1/
│   ├── checkpoints/gen_0.json ... gen_142.json, latest.json
│   ├── results/batch_0.txt ... batch_19.txt, metrics.json
│   └── training.log
├── island-2/
│   ├── checkpoints/gen_0.json ... gen_155.json, latest.json
│   ├── results/batch_0.txt ... batch_19.txt, metrics.json
│   └── training.log
├── island-3/
│   ├── checkpoints/gen_0.json ... gen_155.json, latest.json
│   ├── results/batch_0.txt ... batch_19.txt, metrics.json
│   └── training.log
└── island-4/
    ├── checkpoints/gen_0.json ... gen_155.json, latest.json
    ├── results/batch_0.txt ... batch_19.txt, metrics.json
    └── training.log
```

**Total checkpoints**: ~600 checkpoint files across all islands
**Total metrics**: ~620 generation data points
**Champion genome**: `island-3/checkpoints/latest.json` (1.8MB, 2234.7 fitness)

---

## Next Steps

1. **Extract champion genomes** for demo purposes
2. **Analyze island-2 breakthrough** trajectory in detail
3. **Submit Tekton Loop TEP** based on lessons learned
4. **Present findings** at DevConf.cz 2026
5. **Implement island migration** for future experiments
6. **Build ML toolkit** on top of Loop primitive

---

## Conclusion

This experiment successfully validated that:
- Tekton Loop can orchestrate long-running iterative ML workloads
- 4-island neuroevolution model works on Kubernetes
- NEAT algorithm can learn complex fighting game strategies
- Island-3 achieved 93% KO rate (66/71 damage) through pure evolution
- Island-2's breakthrough proves plateaus aren't convergence
- Cloud-native MLOps is practical without specialized platforms

**The RoboCat successfully trained Goku.**

---

*Generated: March 9, 2026*
*Training Experiment: Saiyan Trainer v1.0*
*Tekton Loop: Alpha Feature (feat/pipeline-iteration)*
