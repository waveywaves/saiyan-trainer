# Training Analysis — 2026-03-08 15:45 IST

## Check 1: Gen 26 (All Islands)

### Island 1 — "The Late Bloomer"
**Status**: Breakthrough | **Best**: 158.4 | **P2 Damage**: 34 | **Species**: 3

Island 1 took its time. For 17 generations it sat at the 20-damage plateau like everyone else, slowly growing its network from 8 to 28 genes. Then at **Gen 18**, something clicked — damage jumped to 26. By **Gen 23**, it hit 34 damage with fitness 158.4. Interestingly, at Gen 23 the P1 delta dropped to +0 (no character switching), meaning this genome learned to fight WITHOUT relying on the char-switch HP trick. It's winning purely on offense now. The network has 32 genes with only 1 hidden node — it found a way to deal more damage with a relatively simple topology. Entropy is 1.37 with 6 unique patterns — it's not just mashing one button.

**Key moment**: Gen 18 (damage 20->26) was the breakthrough. The genome found a second attack pattern that lands hits.

### Island 2 — "The Conservative"
**Status**: Plateaued | **Best**: 115.8 | **P2 Damage**: 20 | **Species**: 3

Island 2 is the cautious one. It has been stuck at exactly 20 P2 damage for all 26 generations. The population quickly converged (species 40->3) and settled on the same strategy: deal 20 damage, char-switch for HP, win on timeout. Entropy is a modest 0.78 with 8 unique patterns. The network grew from 9 to ~13 genes but never developed hidden nodes that stuck. This island's population got trapped in the local optimum and doesn't have enough diversity to escape. StaleSpecies=12 should be purging non-improving species, but with only 3 species left, there's not enough variety to generate novel topologies.

**Verdict**: Stuck. Would benefit from island migration receiving genomes from Island 1 or 3.

### Island 3 — "The Fighter" (LEADER)
**Status**: Leading breakthrough | **Best**: 160.5 | **P2 Damage**: 34 | **Species**: 1 | **Entropy**: 3.51

The most exciting island. Island 3 was the FIRST to break the 20-damage ceiling at **Gen 14** (21 damage), then steadily climbed: 21 -> 29 (Gen 19) -> 30 (Gen 23) -> 34 (Gen 25). What makes it remarkable is the **entropy of 3.51 with 58 unique button patterns** at Gen 25. This genome is pressing wildly different button combinations across frames — not random mashing, but a diverse attack repertoire that lands more hits.

The network grew aggressively: 8 genes at Gen 0 to 48 genes with 5 hidden nodes by Gen 25. This is the most complex network across all islands and it's paying off. The population collapsed to a single species — every genome is now a variant of this successful aggressive strategy.

It also maintained P1 delta=+27 throughout, meaning it still uses character switching for defense while being more aggressive on offense. Best of both worlds.

**Key moment**: Gen 14 (entropy jumped 0.74->1.39) was when the network first learned varied attacks. Gen 19 (damage 21->29) confirmed the strategy was genuinely better.

### Island 4 — "The Stagnant"
**Status**: Plateaued | **Best**: 116.2 | **P2 Damage**: 20 | **Species**: 3

Similar to Island 2 but even more static. 26 generations of identical 20 P2 damage, identical char-switch strategy. Entropy recently climbed to 1.15 with 12 unique patterns (Gen 25-26), which is a small sign of life — the population might be starting to explore. But fitness has barely moved from 115.0 to 116.2 in 26 generations. The network is small (11-12 genes, no hidden nodes). This island's random initial population may have just been unlucky — it converged on the local optimum too quickly before exploring alternatives.

**Verdict**: Unlikely to break through without external injection of genetic material.

---

## Observations

1. **The every-4th-gen dip**: All islands show P2dmg=0 and P1delta=+0 at generations 4, 8, 12, 16, 20, 24. This is a checkpoint resume artifact — when a new batch starts, the first "generation" is the loaded checkpoint being logged before evaluation begins. Not actual zero-damage evaluations.

2. **Two strategies emerged**:
   - **Conservative** (Islands 2, 4): 20 damage + char-switch = 115 fitness. Simple networks, low entropy.
   - **Aggressive** (Islands 1, 3): 34 damage + varied attacks = 158-160 fitness. Complex networks, high entropy.

3. **Network complexity correlates with damage**: Islands 1 and 3 have 29-48 genes with hidden nodes. Islands 2 and 4 have 11-13 genes with no hidden nodes. The hidden nodes enable more complex input-output mappings that discover additional attack patterns.

4. **Island 3's entropy explosion** at Gen 25 (3.51 with 58 unique patterns) is unprecedented. This genome is essentially playing a different fighting game than the others — pressing varied combos instead of repeating one pattern.

---

*Next check in 5 minutes. Monitoring for: Islands 2/4 breaking through, Islands 1/3 exceeding 34 damage, any KOs (fitness > 2000).*

---

## Check 2 — 2026-03-08T10:18:59Z

| Island | Gen | Fitness | P2 Dmg | Species | Entropy | Unique | Genes | Hidden | P1 Delta |
|--------|-----|---------|--------|---------|---------|--------|-------|--------|----------|
| island-1 | 27 | 158.4 | 34 | 5 | 2.02 | 21 | 45 | 5 | +23 |
| island-2 | 27 | 115.8 | 20 | 9 | 0.81 | 10 | 41 | 5 | +22 |
| island-3 | 27 | 161.6 | 35 | 7 | 1.56 | 18 | 56 | 8 | +27 |
| island-4 | 27 | 116.2 | 20 | 4 | 1.15 | 12 | 54 | 6 | +27 |

### Analysis

**island-1** [Breakthrough]: fitness=158.4, dealing 34 damage, 5 species, entropy=2.02 (21 patterns), network=45 genes/5 hidden, char-switching (+23 P1 HP)

**island-2** [Plateaued]: fitness=115.8, dealing 20 damage, 9 species, entropy=0.81 (10 patterns), network=41 genes/5 hidden, char-switching (+22 P1 HP)

**island-3** (LEADER) [Breakthrough]: fitness=161.6, dealing 35 damage, 7 species, entropy=1.56 (18 patterns), network=56 genes/8 hidden, char-switching (+27 P1 HP)

**island-4** [Exploring]: fitness=116.2, dealing 20 damage, 4 species, entropy=1.15 (12 patterns), network=54 genes/6 hidden, char-switching (+27 P1 HP)


---

## Check 3 — 2026-03-08T10:19:07Z

| Island | Gen | Fitness | P2 Dmg | Species | Entropy | Unique | Genes | Hidden | P1 Delta |
|--------|-----|---------|--------|---------|---------|--------|-------|--------|----------|
| island-1 | 27 | 158.4 | 34 | 5 | 2.02 | 21 | 45 | 5 | +23 |
| island-2 | 27 | 115.8 | 20 | 9 | 0.81 | 10 | 41 | 5 | +22 |
| island-3 | 27 | 161.6 | 35 | 7 | 1.56 | 18 | 56 | 8 | +27 |
| island-4 | 27 | 116.2 | 20 | 4 | 1.15 | 12 | 54 | 6 | +27 |

### Analysis

**island-1** [Breakthrough]: fitness=158.4, dealing 34 damage, 5 species, entropy=2.02 (21 patterns), network=45 genes/5 hidden, char-switching (+23 P1 HP)

**island-2** [Plateaued]: fitness=115.8, dealing 20 damage, 9 species, entropy=0.81 (10 patterns), network=41 genes/5 hidden, char-switching (+22 P1 HP)

**island-3** (LEADER) [Breakthrough]: fitness=161.6, dealing 35 damage, 7 species, entropy=1.56 (18 patterns), network=56 genes/8 hidden, char-switching (+27 P1 HP)

**island-4** [Exploring]: fitness=116.2, dealing 20 damage, 4 species, entropy=1.15 (12 patterns), network=54 genes/6 hidden, char-switching (+27 P1 HP)


---

## Check 4 — 2026-03-08T10:20:39Z

| Island | Gen | Fitness | P2 Dmg | Species | Entropy | Unique | Genes | Hidden | P1 Delta |
|--------|-----|---------|--------|---------|---------|--------|-------|--------|----------|
| island-1 | 28 | 158.4 | 34 | 10 | 0.00 | 0 | 45 | 5 | +0 |
| island-2 | 28 | 115.8 | 20 | 4 | 0.00 | 0 | 44 | 6 | +0 |
| island-3 | 28 | 188.9 | 35 | 10 | 0.00 | 0 | 59 | 8 | +0 |
| island-4 | 28 | 116.2 | 20 | 6 | 1.15 | 12 | 54 | 6 | +27 |

### Analysis

**island-1** [Breakthrough]: fitness=158.4, dealing 34 damage, 10 species, entropy=0.00 (0 patterns), network=45 genes/5 hidden, pure offense (no char-switch)

**island-2** [Plateaued]: fitness=115.8, dealing 20 damage, 4 species, entropy=0.00 (0 patterns), network=44 genes/6 hidden

**island-3** (LEADER) [Breakthrough]: fitness=188.9, dealing 35 damage, 10 species, entropy=0.00 (0 patterns), network=59 genes/8 hidden, pure offense (no char-switch)

**island-4** [Exploring]: fitness=116.2, dealing 20 damage, 6 species, entropy=1.15 (12 patterns), network=54 genes/6 hidden, char-switching (+27 P1 HP)


---

## Check 5 — 2026-03-08T10:24:08Z

| Island | Gen | Fitness | P2 Dmg | Species | Entropy | Unique | Genes | Hidden | P1 Delta |
|--------|-----|---------|--------|---------|---------|--------|-------|--------|----------|
| island-1 | 29 | 158.4 | 34 | 3 | 2.02 | 21 | 45 | 5 | +23 |
| island-2 | 29 | 115.8 | 20 | 3 | 0.82 | 13 | 42 | 5 | +22 |
| island-3 | 29 | 188.9 | 44 | 1 | 1.89 | 19 | 59 | 8 | +7 |
| island-4 | 28 | 116.2 | 20 | 6 | 0.00 | 0 | 54 | 6 | +0 |

### Breakthroughs Detected

- **island-3** Gen 29: P2 damage 35→44 (fitness=188.9, entropy=1.89)

### Analysis

**island-1** [Breakthrough]: fitness=158.4, dealing 34 damage, 3 species, entropy=2.02 (21 patterns), network=45 genes/5 hidden, char-switching (+23 P1 HP)

**island-2** [Plateaued]: fitness=115.8, dealing 20 damage, 3 species, entropy=0.82 (13 patterns), network=42 genes/5 hidden, char-switching (+22 P1 HP)

**island-3** (LEADER) [Breakthrough]: fitness=188.9, dealing 44 damage, 1 species, entropy=1.89 (19 patterns), network=59 genes/8 hidden, char-switching (+7 P1 HP)

**island-4** [Plateaued]: fitness=116.2, dealing 20 damage, 6 species, entropy=0.00 (0 patterns), network=54 genes/6 hidden


---

## Check 6 — 2026-03-08T10:29:10Z

| Island | Gen | Fitness | P2 Dmg | Species | Entropy | Unique | Genes | Hidden | P1 Delta |
|--------|-----|---------|--------|---------|---------|--------|-------|--------|----------|
| island-1 | 30 | 158.4 | 34 | 3 | 1.16 | 8 | 42 | 2 | +22 |
| island-2 | 30 | 115.8 | 20 | 1 | 0.82 | 13 | 42 | 5 | +22 |
| island-3 | 30 | 188.9 | 44 | 5 | 1.89 | 19 | 59 | 8 | +7 |
| island-4 | 30 | 116.2 | 20 | 2 | 1.15 | 12 | 54 | 6 | +27 |

### Analysis

**island-1** [Breakthrough]: fitness=158.4, dealing 34 damage, 3 species, entropy=1.16 (8 patterns), network=42 genes/2 hidden, char-switching (+22 P1 HP)

**island-2** [Plateaued]: fitness=115.8, dealing 20 damage, 1 species, entropy=0.82 (13 patterns), network=42 genes/5 hidden, char-switching (+22 P1 HP)

**island-3** (LEADER) [Breakthrough]: fitness=188.9, dealing 44 damage, 5 species, entropy=1.89 (19 patterns), network=59 genes/8 hidden, char-switching (+7 P1 HP)

**island-4** [Exploring]: fitness=116.2, dealing 20 damage, 2 species, entropy=1.15 (12 patterns), network=54 genes/6 hidden, char-switching (+27 P1 HP)


---

## Check 7 — 2026-03-08T10:34:11Z

| Island | Gen | Fitness | P2 Dmg | Species | Entropy | Unique | Genes | Hidden | P1 Delta |
|--------|-----|---------|--------|---------|---------|--------|-------|--------|----------|
| island-1 | 31 | 158.4 | 34 | 7 | 1.16 | 8 | 42 | 2 | +22 |
| island-2 | 31 | 115.8 | 20 | 5 | 0.82 | 13 | 42 | 5 | +22 |
| island-3 | 31 | 188.9 | 44 | 5 | 1.89 | 19 | 59 | 8 | +7 |
| island-4 | 31 | 158.2 | 34 | 2 | 1.21 | 12 | 63 | 7 | +22 |

### Breakthroughs Detected

- **island-4** Gen 31: P2 damage 20→34 (fitness=158.2, entropy=1.21)

### Analysis

**island-1** [Breakthrough]: fitness=158.4, dealing 34 damage, 7 species, entropy=1.16 (8 patterns), network=42 genes/2 hidden, char-switching (+22 P1 HP)

**island-2** [Plateaued]: fitness=115.8, dealing 20 damage, 5 species, entropy=0.82 (13 patterns), network=42 genes/5 hidden, char-switching (+22 P1 HP)

**island-3** (LEADER) [Breakthrough]: fitness=188.9, dealing 44 damage, 5 species, entropy=1.89 (19 patterns), network=59 genes/8 hidden, char-switching (+7 P1 HP)

**island-4** [Breakthrough]: fitness=158.2, dealing 34 damage, 2 species, entropy=1.21 (12 patterns), network=63 genes/7 hidden, char-switching (+22 P1 HP)


---

## Check 8 — 2026-03-08T10:36:00Z

| Island | Gen | Fitness | P2 Dmg | Species | Entropy | Unique | Genes | Hidden | P1 Delta |
|--------|-----|---------|--------|---------|---------|--------|-------|--------|----------|
| island-1 | 31 | 158.4 | 34 | 7 | 1.16 | 8 | 42 | 2 | +22 |
| island-2 | 31 | 115.8 | 20 | 5 | 0.82 | 13 | 42 | 5 | +22 |
| island-3 | 31 | 188.9 | 44 | 5 | 1.89 | 19 | 59 | 8 | +7 |
| island-4 | 31 | 158.2 | 34 | 2 | 1.21 | 12 | 63 | 7 | +22 |

### Analysis

**island-1** [Breakthrough]: fitness=158.4, dealing 34 damage, 7 species, entropy=1.16 (8 patterns), network=42 genes/2 hidden, char-switching (+22 P1 HP)

**island-2** [Plateaued]: fitness=115.8, dealing 20 damage, 5 species, entropy=0.82 (13 patterns), network=42 genes/5 hidden, char-switching (+22 P1 HP)

**island-3** (LEADER) [Breakthrough]: fitness=188.9, dealing 44 damage, 5 species, entropy=1.89 (19 patterns), network=59 genes/8 hidden, char-switching (+7 P1 HP)

**island-4** [Breakthrough]: fitness=158.2, dealing 34 damage, 2 species, entropy=1.21 (12 patterns), network=63 genes/7 hidden, char-switching (+22 P1 HP)


---

## Check 9 — 2026-03-08T10:39:13Z

| Island | Gen | Fitness | P2 Dmg | Species | Entropy | Unique | Genes | Hidden | P1 Delta |
|--------|-----|---------|--------|---------|---------|--------|-------|--------|----------|
| island-1 | 32 | 158.4 | 34 | 12 | 0.00 | 0 | 42 | 2 | +0 |
| island-2 | 32 | 115.8 | 20 | 5 | 0.00 | 0 | 45 | 5 | +0 |
| island-3 | 32 | 188.9 | 44 | 6 | 0.00 | 0 | 59 | 8 | +0 |
| island-4 | 32 | 158.2 | 34 | 4 | 0.00 | 0 | 64 | 8 | +0 |

### Analysis

**island-1** [Breakthrough]: fitness=158.4, dealing 34 damage, 12 species, entropy=0.00 (0 patterns), network=42 genes/2 hidden, pure offense (no char-switch)

**island-2** [Plateaued]: fitness=115.8, dealing 20 damage, 5 species, entropy=0.00 (0 patterns), network=45 genes/5 hidden

**island-3** (LEADER) [Breakthrough]: fitness=188.9, dealing 44 damage, 6 species, entropy=0.00 (0 patterns), network=59 genes/8 hidden, pure offense (no char-switch)

**island-4** [Breakthrough]: fitness=158.2, dealing 34 damage, 4 species, entropy=0.00 (0 patterns), network=64 genes/8 hidden, pure offense (no char-switch)


---

## Check 10 — 2026-03-08T10:44:14Z

| Island | Gen | Fitness | P2 Dmg | Species | Entropy | Unique | Genes | Hidden | P1 Delta |
|--------|-----|---------|--------|---------|---------|--------|-------|--------|----------|
| island-1 | 33 | 158.4 | 34 | 2 | 1.16 | 8 | 42 | 2 | +22 |
| island-2 | 33 | 115.8 | 20 | 3 | 0.82 | 13 | 45 | 5 | +22 |
| island-3 | 33 | 188.9 | 44 | 3 | 1.89 | 19 | 59 | 8 | +7 |
| island-4 | 33 | 158.2 | 34 | 2 | 1.52 | 15 | 69 | 9 | +27 |

### Analysis

**island-1** [Breakthrough]: fitness=158.4, dealing 34 damage, 2 species, entropy=1.16 (8 patterns), network=42 genes/2 hidden, char-switching (+22 P1 HP)

**island-2** [Plateaued]: fitness=115.8, dealing 20 damage, 3 species, entropy=0.82 (13 patterns), network=45 genes/5 hidden, char-switching (+22 P1 HP)

**island-3** (LEADER) [Breakthrough]: fitness=188.9, dealing 44 damage, 3 species, entropy=1.89 (19 patterns), network=59 genes/8 hidden, char-switching (+7 P1 HP)

**island-4** [Breakthrough]: fitness=158.2, dealing 34 damage, 2 species, entropy=1.52 (15 patterns), network=69 genes/9 hidden, char-switching (+27 P1 HP)


---

## Check 11 — 2026-03-08T10:49:16Z

| Island | Gen | Fitness | P2 Dmg | Species | Entropy | Unique | Genes | Hidden | P1 Delta |
|--------|-----|---------|--------|---------|---------|--------|-------|--------|----------|
| island-1 | 35 | 158.4 | 34 | 4 | 1.16 | 8 | 42 | 2 | +22 |
| island-2 | 35 | 115.8 | 20 | 3 | 0.83 | 14 | 51 | 7 | +22 |
| island-3 | 35 | 188.9 | 44 | 2 | 1.89 | 19 | 59 | 8 | +7 |
| island-4 | 34 | 158.2 | 34 | 2 | 1.52 | 15 | 69 | 9 | +27 |

### Analysis

**island-1** [Breakthrough]: fitness=158.4, dealing 34 damage, 4 species, entropy=1.16 (8 patterns), network=42 genes/2 hidden, char-switching (+22 P1 HP)

**island-2** [Plateaued]: fitness=115.8, dealing 20 damage, 3 species, entropy=0.83 (14 patterns), network=51 genes/7 hidden, char-switching (+22 P1 HP)

**island-3** (LEADER) [Breakthrough]: fitness=188.9, dealing 44 damage, 2 species, entropy=1.89 (19 patterns), network=59 genes/8 hidden, char-switching (+7 P1 HP)

**island-4** [Breakthrough]: fitness=158.2, dealing 34 damage, 2 species, entropy=1.52 (15 patterns), network=69 genes/9 hidden, char-switching (+27 P1 HP)


---

## Check 12 — 2026-03-08T10:54:17Z

| Island | Gen | Fitness | P2 Dmg | Species | Entropy | Unique | Genes | Hidden | P1 Delta |
|--------|-----|---------|--------|---------|---------|--------|-------|--------|----------|
| island-1 | 36 | 158.4 | 34 | 11 | 0.00 | 0 | 42 | 2 | +0 |
| island-2 | 36 | 115.8 | 20 | 6 | 0.00 | 0 | 51 | 7 | +0 |
| island-3 | 36 | 188.9 | 44 | 1 | 0.00 | 0 | 78 | 13 | +0 |
| island-4 | 36 | 158.2 | 34 | 7 | 0.00 | 0 | 69 | 9 | +0 |

### Analysis

**island-1** [Breakthrough]: fitness=158.4, dealing 34 damage, 11 species, entropy=0.00 (0 patterns), network=42 genes/2 hidden, pure offense (no char-switch)

**island-2** [Plateaued]: fitness=115.8, dealing 20 damage, 6 species, entropy=0.00 (0 patterns), network=51 genes/7 hidden

**island-3** (LEADER) [Breakthrough]: fitness=188.9, dealing 44 damage, 1 species, entropy=0.00 (0 patterns), network=78 genes/13 hidden, pure offense (no char-switch)

**island-4** [Breakthrough]: fitness=158.2, dealing 34 damage, 7 species, entropy=0.00 (0 patterns), network=69 genes/9 hidden, pure offense (no char-switch)


---

## Check 13 — 2026-03-08T10:59:19Z

| Island | Gen | Fitness | P2 Dmg | Species | Entropy | Unique | Genes | Hidden | P1 Delta |
|--------|-----|---------|--------|---------|---------|--------|-------|--------|----------|
| island-1 | 37 | 158.4 | 34 | 2 | 1.16 | 8 | 42 | 2 | +22 |
| island-2 | 37 | 115.9 | 20 | 1 | 0.86 | 14 | 47 | 5 | +22 |
| island-3 | 37 | 191.3 | 45 | 1 | 1.28 | 15 | 84 | 15 | +27 |
| island-4 | 37 | 158.2 | 34 | 1 | 1.69 | 21 | 69 | 9 | +27 |

### Breakthroughs Detected

- **island-3** Gen 37: P2 damage 44→45 (fitness=191.3, entropy=1.28)

### Analysis

**island-1** [Breakthrough]: fitness=158.4, dealing 34 damage, 2 species, entropy=1.16 (8 patterns), network=42 genes/2 hidden, char-switching (+22 P1 HP)

**island-2** [Plateaued]: fitness=115.9, dealing 20 damage, 1 species, entropy=0.86 (14 patterns), network=47 genes/5 hidden, char-switching (+22 P1 HP)

**island-3** (LEADER) [Breakthrough]: fitness=191.3, dealing 45 damage, 1 species, entropy=1.28 (15 patterns), network=84 genes/15 hidden, char-switching (+27 P1 HP)

**island-4** [Breakthrough]: fitness=158.2, dealing 34 damage, 1 species, entropy=1.69 (21 patterns), network=69 genes/9 hidden, char-switching (+27 P1 HP)


---

## Check 14 — 2026-03-08T11:04:20Z

| Island | Gen | Fitness | P2 Dmg | Species | Entropy | Unique | Genes | Hidden | P1 Delta |
|--------|-----|---------|--------|---------|---------|--------|-------|--------|----------|
| island-1 | 38 | 158.4 | 34 | 3 | 2.45 | 20 | 43 | 2 | +27 |
| island-2 | 38 | 116.7 | 20 | 1 | 1.70 | 17 | 50 | 6 | +16 |
| island-3 | 38 | 191.3 | 45 | 1 | 1.28 | 15 | 84 | 15 | +27 |
| island-4 | 38 | 158.2 | 34 | 2 | 1.69 | 21 | 69 | 9 | +27 |

### Analysis

**island-1** [Breakthrough]: fitness=158.4, dealing 34 damage, 3 species, entropy=2.45 (20 patterns), network=43 genes/2 hidden, char-switching (+27 P1 HP)

**island-2** [Exploring]: fitness=116.7, dealing 20 damage, 1 species, entropy=1.70 (17 patterns), network=50 genes/6 hidden, char-switching (+16 P1 HP)

**island-3** (LEADER) [Breakthrough]: fitness=191.3, dealing 45 damage, 1 species, entropy=1.28 (15 patterns), network=84 genes/15 hidden, char-switching (+27 P1 HP)

**island-4** [Breakthrough]: fitness=158.2, dealing 34 damage, 2 species, entropy=1.69 (21 patterns), network=69 genes/9 hidden, char-switching (+27 P1 HP)


---

## Check 15 — 2026-03-08T11:09:21Z

| Island | Gen | Fitness | P2 Dmg | Species | Entropy | Unique | Genes | Hidden | P1 Delta |
|--------|-----|---------|--------|---------|---------|--------|-------|--------|----------|
| island-1 | 39 | 158.4 | 34 | 5 | 2.45 | 20 | 43 | 2 | +27 |
| island-2 | 39 | 116.7 | 20 | 6 | 1.70 | 17 | 50 | 6 | +16 |
| island-3 | 39 | 191.3 | 45 | 4 | 1.28 | 15 | 84 | 15 | +27 |
| island-4 | 39 | 158.2 | 34 | 4 | 1.69 | 21 | 69 | 9 | +27 |

### Analysis

**island-1** [Breakthrough]: fitness=158.4, dealing 34 damage, 5 species, entropy=2.45 (20 patterns), network=43 genes/2 hidden, char-switching (+27 P1 HP)

**island-2** [Exploring]: fitness=116.7, dealing 20 damage, 6 species, entropy=1.70 (17 patterns), network=50 genes/6 hidden, char-switching (+16 P1 HP)

**island-3** (LEADER) [Breakthrough]: fitness=191.3, dealing 45 damage, 4 species, entropy=1.28 (15 patterns), network=84 genes/15 hidden, char-switching (+27 P1 HP)

**island-4** [Breakthrough]: fitness=158.2, dealing 34 damage, 4 species, entropy=1.69 (21 patterns), network=69 genes/9 hidden, char-switching (+27 P1 HP)


---

## Check 16 — 2026-03-08T11:14:23Z

| Island | Gen | Fitness | P2 Dmg | Species | Entropy | Unique | Genes | Hidden | P1 Delta |
|--------|-----|---------|--------|---------|---------|--------|-------|--------|----------|
| island-1 | 41 | 158.4 | 34 | 1 | 2.45 | 20 | 43 | 2 | +27 |
| island-2 | 41 | 116.7 | 20 | 2 | 0.88 | 17 | 59 | 9 | +22 |
| island-3 | 41 | 191.3 | 45 | 1 | 1.28 | 15 | 84 | 15 | +27 |
| island-4 | 40 | 158.2 | 34 | 2 | 0.00 | 0 | 72 | 7 | +0 |

### Analysis

**island-1** [Breakthrough]: fitness=158.4, dealing 34 damage, 1 species, entropy=2.45 (20 patterns), network=43 genes/2 hidden, char-switching (+27 P1 HP)

**island-2** [Plateaued]: fitness=116.7, dealing 20 damage, 2 species, entropy=0.88 (17 patterns), network=59 genes/9 hidden, char-switching (+22 P1 HP)

**island-3** (LEADER) [Breakthrough]: fitness=191.3, dealing 45 damage, 1 species, entropy=1.28 (15 patterns), network=84 genes/15 hidden, char-switching (+27 P1 HP)

**island-4** [Breakthrough]: fitness=158.2, dealing 34 damage, 2 species, entropy=0.00 (0 patterns), network=72 genes/7 hidden, pure offense (no char-switch)


---

## Check 17 — 2026-03-08T11:19:24Z

| Island | Gen | Fitness | P2 Dmg | Species | Entropy | Unique | Genes | Hidden | P1 Delta |
|--------|-----|---------|--------|---------|---------|--------|-------|--------|----------|
| island-1 | 42 | 158.4 | 34 | 5 | 0.76 | 6 | 45 | 2 | +27 |
| island-2 | 42 | 116.7 | 20 | 2 | 0.88 | 17 | 59 | 9 | +22 |
| island-3 | 42 | 191.3 | 45 | 1 | 1.28 | 15 | 84 | 15 | +27 |
| island-4 | 42 | 158.2 | 34 | 1 | 2.07 | 19 | 72 | 7 | +27 |

### Analysis

**island-1** [Breakthrough]: fitness=158.4, dealing 34 damage, 5 species, entropy=0.76 (6 patterns), network=45 genes/2 hidden, char-switching (+27 P1 HP)

**island-2** [Plateaued]: fitness=116.7, dealing 20 damage, 2 species, entropy=0.88 (17 patterns), network=59 genes/9 hidden, char-switching (+22 P1 HP)

**island-3** (LEADER) [Breakthrough]: fitness=191.3, dealing 45 damage, 1 species, entropy=1.28 (15 patterns), network=84 genes/15 hidden, char-switching (+27 P1 HP)

**island-4** [Breakthrough]: fitness=158.2, dealing 34 damage, 1 species, entropy=2.07 (19 patterns), network=72 genes/7 hidden, char-switching (+27 P1 HP)


---

## Check 18 — 2026-03-08T11:24:25Z

| Island | Gen | Fitness | P2 Dmg | Species | Entropy | Unique | Genes | Hidden | P1 Delta |
|--------|-----|---------|--------|---------|---------|--------|-------|--------|----------|
| island-1 | 43 | 158.4 | 34 | 6 | 0.76 | 6 | 45 | 2 | +27 |
| island-2 | 43 | 116.7 | 20 | 1 | 0.88 | 17 | 59 | 9 | +22 |
| island-3 | 43 | 191.3 | 45 | 4 | 1.28 | 15 | 84 | 15 | +27 |
| island-4 | 43 | 158.2 | 34 | 1 | 1.92 | 20 | 75 | 7 | +27 |

### Analysis

**island-1** [Breakthrough]: fitness=158.4, dealing 34 damage, 6 species, entropy=0.76 (6 patterns), network=45 genes/2 hidden, char-switching (+27 P1 HP)

**island-2** [Plateaued]: fitness=116.7, dealing 20 damage, 1 species, entropy=0.88 (17 patterns), network=59 genes/9 hidden, char-switching (+22 P1 HP)

**island-3** (LEADER) [Breakthrough]: fitness=191.3, dealing 45 damage, 4 species, entropy=1.28 (15 patterns), network=84 genes/15 hidden, char-switching (+27 P1 HP)

**island-4** [Breakthrough]: fitness=158.2, dealing 34 damage, 1 species, entropy=1.92 (20 patterns), network=75 genes/7 hidden, char-switching (+27 P1 HP)


---

## Check 19 — 2026-03-08T11:29:27Z

| Island | Gen | Fitness | P2 Dmg | Species | Entropy | Unique | Genes | Hidden | P1 Delta |
|--------|-----|---------|--------|---------|---------|--------|-------|--------|----------|
| island-1 | 44 | 158.4 | 34 | 7 | 0.00 | 0 | 48 | 3 | +0 |
| island-2 | 44 | 116.7 | 20 | 6 | 0.00 | 0 | 59 | 9 | +0 |
| island-3 | 44 | 191.3 | 45 | 5 | 0.00 | 0 | 84 | 15 | +0 |
| island-4 | 44 | 158.2 | 34 | 6 | 0.00 | 0 | 75 | 7 | +0 |

### Analysis

**island-1** [Breakthrough]: fitness=158.4, dealing 34 damage, 7 species, entropy=0.00 (0 patterns), network=48 genes/3 hidden, pure offense (no char-switch)

**island-2** [Plateaued]: fitness=116.7, dealing 20 damage, 6 species, entropy=0.00 (0 patterns), network=59 genes/9 hidden

**island-3** (LEADER) [Breakthrough]: fitness=191.3, dealing 45 damage, 5 species, entropy=0.00 (0 patterns), network=84 genes/15 hidden, pure offense (no char-switch)

**island-4** [Breakthrough]: fitness=158.2, dealing 34 damage, 6 species, entropy=0.00 (0 patterns), network=75 genes/7 hidden, pure offense (no char-switch)


---

## Check 20 — 2026-03-08T11:34:28Z

| Island | Gen | Fitness | P2 Dmg | Species | Entropy | Unique | Genes | Hidden | P1 Delta |
|--------|-----|---------|--------|---------|---------|--------|-------|--------|----------|
| island-1 | 46 | 158.4 | 34 | 1 | 2.05 | 11 | 53 | 4 | +22 |
| island-2 | 45 | 116.7 | 20 | 1 | 0.88 | 17 | 59 | 9 | +22 |
| island-3 | 45 | 191.3 | 45 | 1 | 1.28 | 15 | 84 | 15 | +27 |
| island-4 | 45 | 158.2 | 34 | 1 | 1.92 | 20 | 76 | 7 | +27 |

### Analysis

**island-1** [Breakthrough]: fitness=158.4, dealing 34 damage, 1 species, entropy=2.05 (11 patterns), network=53 genes/4 hidden, char-switching (+22 P1 HP)

**island-2** [Plateaued]: fitness=116.7, dealing 20 damage, 1 species, entropy=0.88 (17 patterns), network=59 genes/9 hidden, char-switching (+22 P1 HP)

**island-3** (LEADER) [Breakthrough]: fitness=191.3, dealing 45 damage, 1 species, entropy=1.28 (15 patterns), network=84 genes/15 hidden, char-switching (+27 P1 HP)

**island-4** [Breakthrough]: fitness=158.2, dealing 34 damage, 1 species, entropy=1.92 (20 patterns), network=76 genes/7 hidden, char-switching (+27 P1 HP)


---

## Check 21 — 2026-03-08T11:39:30Z

| Island | Gen | Fitness | P2 Dmg | Species | Entropy | Unique | Genes | Hidden | P1 Delta |
|--------|-----|---------|--------|---------|---------|--------|-------|--------|----------|
| island-1 | 47 | 171.6 | 38 | 8 | 2.65 | 29 | 53 | 4 | +22 |
| island-2 | 47 | 116.7 | 20 | 5 | 0.88 | 17 | 59 | 9 | +22 |
| island-3 | 47 | 191.3 | 45 | 5 | 1.28 | 15 | 84 | 15 | +27 |
| island-4 | 46 | 158.2 | 34 | 1 | 1.92 | 20 | 76 | 7 | +27 |

### Breakthroughs Detected

- **island-1** Gen 47: P2 damage 34→38 (fitness=171.6, entropy=2.65)

### Analysis

**island-1** [Breakthrough]: fitness=171.6, dealing 38 damage, 8 species, entropy=2.65 (29 patterns), network=53 genes/4 hidden, char-switching (+22 P1 HP)

**island-2** [Plateaued]: fitness=116.7, dealing 20 damage, 5 species, entropy=0.88 (17 patterns), network=59 genes/9 hidden, char-switching (+22 P1 HP)

**island-3** (LEADER) [Breakthrough]: fitness=191.3, dealing 45 damage, 5 species, entropy=1.28 (15 patterns), network=84 genes/15 hidden, char-switching (+27 P1 HP)

**island-4** [Breakthrough]: fitness=158.2, dealing 34 damage, 1 species, entropy=1.92 (20 patterns), network=76 genes/7 hidden, char-switching (+27 P1 HP)


---

## Check 22 — 2026-03-08T11:40:01Z

| Island | Gen | Fitness | P2 Dmg | Species | Entropy | Unique | Genes | Hidden | P1 Delta |
|--------|-----|---------|--------|---------|---------|--------|-------|--------|----------|
| island-1 | 47 | 171.6 | 38 | 8 | 2.65 | 29 | 53 | 4 | +22 |
| island-2 | 47 | 116.7 | 20 | 5 | 0.88 | 17 | 59 | 9 | +22 |
| island-3 | 47 | 191.3 | 45 | 5 | 1.28 | 15 | 84 | 15 | +27 |
| island-4 | 47 | 158.2 | 34 | 5 | 1.92 | 20 | 76 | 7 | +27 |

### Analysis

**island-1** [Breakthrough]: fitness=171.6, dealing 38 damage, 8 species, entropy=2.65 (29 patterns), network=53 genes/4 hidden, char-switching (+22 P1 HP)

**island-2** [Plateaued]: fitness=116.7, dealing 20 damage, 5 species, entropy=0.88 (17 patterns), network=59 genes/9 hidden, char-switching (+22 P1 HP)

**island-3** (LEADER) [Breakthrough]: fitness=191.3, dealing 45 damage, 5 species, entropy=1.28 (15 patterns), network=84 genes/15 hidden, char-switching (+27 P1 HP)

**island-4** [Breakthrough]: fitness=158.2, dealing 34 damage, 5 species, entropy=1.92 (20 patterns), network=76 genes/7 hidden, char-switching (+27 P1 HP)


---

## Check 23 — 2026-03-08T11:44:31Z

| Island | Gen | Fitness | P2 Dmg | Species | Entropy | Unique | Genes | Hidden | P1 Delta |
|--------|-----|---------|--------|---------|---------|--------|-------|--------|----------|
| island-1 | 48 | 171.6 | 38 | 5 | 0.00 | 0 | 53 | 4 | +0 |
| island-2 | 48 | 116.7 | 20 | 5 | 0.00 | 0 | 59 | 9 | +0 |
| island-3 | 48 | 191.3 | 45 | 3 | 0.00 | 0 | 106 | 19 | +0 |
| island-4 | 48 | 158.2 | 34 | 4 | 0.00 | 0 | 76 | 7 | +0 |

### Analysis

**island-1** [Breakthrough]: fitness=171.6, dealing 38 damage, 5 species, entropy=0.00 (0 patterns), network=53 genes/4 hidden, pure offense (no char-switch)

**island-2** [Plateaued]: fitness=116.7, dealing 20 damage, 5 species, entropy=0.00 (0 patterns), network=59 genes/9 hidden

**island-3** (LEADER) [Breakthrough]: fitness=191.3, dealing 45 damage, 3 species, entropy=0.00 (0 patterns), network=106 genes/19 hidden, pure offense (no char-switch)

**island-4** [Breakthrough]: fitness=158.2, dealing 34 damage, 4 species, entropy=0.00 (0 patterns), network=76 genes/7 hidden, pure offense (no char-switch)


---

## Check 24 — 2026-03-08T11:49:33Z

| Island | Gen | Fitness | P2 Dmg | Species | Entropy | Unique | Genes | Hidden | P1 Delta |
|--------|-----|---------|--------|---------|---------|--------|-------|--------|----------|
| island-1 | 49 | 171.6 | 38 | 2 | 1.16 | 8 | 55 | 4 | +27 |
| island-2 | 49 | 116.7 | 20 | 1 | 0.88 | 17 | 59 | 9 | +22 |
| island-3 | 49 | 237.1 | 60 | 1 | 2.13 | 18 | 109 | 20 | -6 |
| island-4 | 49 | 158.2 | 34 | 1 | 1.92 | 20 | 76 | 7 | +27 |

### Breakthroughs Detected

- **island-3** Gen 49: P2 damage 45→60 (fitness=237.1, entropy=2.13)

### Analysis

**island-1** [Breakthrough]: fitness=171.6, dealing 38 damage, 2 species, entropy=1.16 (8 patterns), network=55 genes/4 hidden, char-switching (+27 P1 HP)

**island-2** [Plateaued]: fitness=116.7, dealing 20 damage, 1 species, entropy=0.88 (17 patterns), network=59 genes/9 hidden, char-switching (+22 P1 HP)

**island-3** (LEADER) [Breakthrough]: fitness=237.1, dealing 60 damage, 1 species, entropy=2.13 (18 patterns), network=109 genes/20 hidden

**island-4** [Breakthrough]: fitness=158.2, dealing 34 damage, 1 species, entropy=1.92 (20 patterns), network=76 genes/7 hidden, char-switching (+27 P1 HP)


---

## Check 25 — 2026-03-08T11:54:34Z

| Island | Gen | Fitness | P2 Dmg | Species | Entropy | Unique | Genes | Hidden | P1 Delta |
|--------|-----|---------|--------|---------|---------|--------|-------|--------|----------|
| island-1 | 50 | 171.6 | 38 | 2 | 1.16 | 8 | 52 | 3 | +27 |
| island-2 | 50 | 116.7 | 20 | 3 | 0.88 | 17 | 59 | 9 | +22 |
| island-3 | 50 | 237.2 | 60 | 1 | 2.25 | 25 | 112 | 21 | -6 |
| island-4 | 50 | 158.2 | 34 | 3 | 1.92 | 20 | 76 | 7 | +27 |

### Analysis

**island-1** [Breakthrough]: fitness=171.6, dealing 38 damage, 2 species, entropy=1.16 (8 patterns), network=52 genes/3 hidden, char-switching (+27 P1 HP)

**island-2** [Plateaued]: fitness=116.7, dealing 20 damage, 3 species, entropy=0.88 (17 patterns), network=59 genes/9 hidden, char-switching (+22 P1 HP)

**island-3** (LEADER) [Breakthrough]: fitness=237.2, dealing 60 damage, 1 species, entropy=2.25 (25 patterns), network=112 genes/21 hidden

**island-4** [Breakthrough]: fitness=158.2, dealing 34 damage, 3 species, entropy=1.92 (20 patterns), network=76 genes/7 hidden, char-switching (+27 P1 HP)


---

## Check 26 — 2026-03-08T11:59:36Z

| Island | Gen | Fitness | P2 Dmg | Species | Entropy | Unique | Genes | Hidden | P1 Delta |
|--------|-----|---------|--------|---------|---------|--------|-------|--------|----------|
| island-1 | 52 | 171.6 | 38 | 10 | 0.00 | 0 | 63 | 6 | +0 |
| island-2 | 51 | 116.7 | 20 | 3 | 0.88 | 17 | 59 | 9 | +22 |
| island-3 | 51 | 2234.4 | 71 | 1 | 1.62 | 13 | 114 | 21 | -5 |
| island-4 | 51 | 158.2 | 34 | 4 | 1.92 | 20 | 76 | 7 | +27 |

### Breakthroughs Detected

- **island-3** Gen 51: P2 damage 60→71 (fitness=2234.4, entropy=1.62)

### Analysis

**island-1** [Breakthrough]: fitness=171.6, dealing 38 damage, 10 species, entropy=0.00 (0 patterns), network=63 genes/6 hidden, pure offense (no char-switch)

**island-2** [Plateaued]: fitness=116.7, dealing 20 damage, 3 species, entropy=0.88 (17 patterns), network=59 genes/9 hidden, char-switching (+22 P1 HP)

**island-3** (LEADER) [Breakthrough]: fitness=2234.4, dealing 71 damage, 1 species, entropy=1.62 (13 patterns), network=114 genes/21 hidden

**island-4** [Breakthrough]: fitness=158.2, dealing 34 damage, 4 species, entropy=1.92 (20 patterns), network=76 genes/7 hidden, char-switching (+27 P1 HP)


---

## Check 27 — 2026-03-08T12:04:38Z

| Island | Gen | Fitness | P2 Dmg | Species | Entropy | Unique | Genes | Hidden | P1 Delta |
|--------|-----|---------|--------|---------|---------|--------|-------|--------|----------|
| island-1 | 53 | 171.6 | 38 | 1 | 1.11 | 4 | 63 | 6 | +27 |
| island-2 | 53 | 116.7 | 20 | 1 | 0.88 | 17 | 59 | 9 | +22 |
| island-3 | 52 | 2234.4 | 71 | 10 | 0.00 | 0 | 114 | 21 | +0 |
| island-4 | 52 | 158.2 | 34 | 3 | 0.00 | 0 | 77 | 7 | +0 |

### Analysis

**island-1** [Breakthrough]: fitness=171.6, dealing 38 damage, 1 species, entropy=1.11 (4 patterns), network=63 genes/6 hidden, char-switching (+27 P1 HP)

**island-2** [Plateaued]: fitness=116.7, dealing 20 damage, 1 species, entropy=0.88 (17 patterns), network=59 genes/9 hidden, char-switching (+22 P1 HP)

**island-3** (LEADER) [Breakthrough]: fitness=2234.4, dealing 71 damage, 10 species, entropy=0.00 (0 patterns), network=114 genes/21 hidden, pure offense (no char-switch)

**island-4** [Breakthrough]: fitness=158.2, dealing 34 damage, 3 species, entropy=0.00 (0 patterns), network=77 genes/7 hidden, pure offense (no char-switch)


---

## Check 28 — 2026-03-08T12:09:39Z

| Island | Gen | Fitness | P2 Dmg | Species | Entropy | Unique | Genes | Hidden | P1 Delta |
|--------|-----|---------|--------|---------|---------|--------|-------|--------|----------|
| island-1 | 54 | 171.6 | 38 | 4 | 1.11 | 4 | 63 | 6 | +27 |
| island-2 | 54 | 116.7 | 20 | 2 | 0.88 | 17 | 59 | 9 | +22 |
| island-3 | 54 | 2234.4 | 71 | 1 | 1.62 | 13 | 114 | 21 | -5 |
| island-4 | 54 | 158.2 | 34 | 1 | 2.27 | 23 | 79 | 7 | +27 |

### Analysis

**island-1** [Breakthrough]: fitness=171.6, dealing 38 damage, 4 species, entropy=1.11 (4 patterns), network=63 genes/6 hidden, char-switching (+27 P1 HP)

**island-2** [Plateaued]: fitness=116.7, dealing 20 damage, 2 species, entropy=0.88 (17 patterns), network=59 genes/9 hidden, char-switching (+22 P1 HP)

**island-3** (LEADER) [Breakthrough]: fitness=2234.4, dealing 71 damage, 1 species, entropy=1.62 (13 patterns), network=114 genes/21 hidden

**island-4** [Breakthrough]: fitness=158.2, dealing 34 damage, 1 species, entropy=2.27 (23 patterns), network=79 genes/7 hidden, char-switching (+27 P1 HP)


---

## Check 29 — 2026-03-08T12:14:41Z

| Island | Gen | Fitness | P2 Dmg | Species | Entropy | Unique | Genes | Hidden | P1 Delta |
|--------|-----|---------|--------|---------|---------|--------|-------|--------|----------|
| island-1 | 55 | 171.6 | 38 | 2 | 1.16 | 9 | 65 | 6 | +27 |
| island-2 | 55 | 116.7 | 20 | 3 | 0.88 | 17 | 59 | 9 | +22 |
| island-3 | 55 | 2234.4 | 71 | 3 | 1.62 | 13 | 114 | 21 | -5 |
| island-4 | 55 | 158.2 | 34 | 1 | 2.27 | 23 | 79 | 7 | +27 |

### Analysis

**island-1** [Breakthrough]: fitness=171.6, dealing 38 damage, 2 species, entropy=1.16 (9 patterns), network=65 genes/6 hidden, char-switching (+27 P1 HP)

**island-2** [Plateaued]: fitness=116.7, dealing 20 damage, 3 species, entropy=0.88 (17 patterns), network=59 genes/9 hidden, char-switching (+22 P1 HP)

**island-3** (LEADER) [Breakthrough]: fitness=2234.4, dealing 71 damage, 3 species, entropy=1.62 (13 patterns), network=114 genes/21 hidden

**island-4** [Breakthrough]: fitness=158.2, dealing 34 damage, 1 species, entropy=2.27 (23 patterns), network=79 genes/7 hidden, char-switching (+27 P1 HP)


---

## Check 30 — 2026-03-08T12:19:42Z

| Island | Gen | Fitness | P2 Dmg | Species | Entropy | Unique | Genes | Hidden | P1 Delta |
|--------|-----|---------|--------|---------|---------|--------|-------|--------|----------|
| island-1 | 56 | 171.6 | 38 | 11 | 0.00 | 0 | 65 | 6 | +0 |
| island-2 | 56 | 116.7 | 20 | 4 | 0.00 | 0 | 59 | 9 | +0 |
| island-3 | 56 | 2234.4 | 71 | 5 | 0.00 | 0 | 114 | 21 | +0 |
| island-4 | 56 | 158.2 | 34 | 6 | 0.00 | 0 | 79 | 7 | +0 |

### Analysis

**island-1** [Breakthrough]: fitness=171.6, dealing 38 damage, 11 species, entropy=0.00 (0 patterns), network=65 genes/6 hidden, pure offense (no char-switch)

**island-2** [Plateaued]: fitness=116.7, dealing 20 damage, 4 species, entropy=0.00 (0 patterns), network=59 genes/9 hidden

**island-3** (LEADER) [Breakthrough]: fitness=2234.4, dealing 71 damage, 5 species, entropy=0.00 (0 patterns), network=114 genes/21 hidden, pure offense (no char-switch)

**island-4** [Breakthrough]: fitness=158.2, dealing 34 damage, 6 species, entropy=0.00 (0 patterns), network=79 genes/7 hidden, pure offense (no char-switch)


---

## Check 31 — 2026-03-08T12:24:44Z

| Island | Gen | Fitness | P2 Dmg | Species | Entropy | Unique | Genes | Hidden | P1 Delta |
|--------|-----|---------|--------|---------|---------|--------|-------|--------|----------|
| island-1 | 58 | 171.6 | 38 | 1 | 1.16 | 9 | 65 | 6 | +27 |
| island-2 | 57 | 116.7 | 20 | 1 | 0.88 | 17 | 59 | 9 | +22 |
| island-3 | 57 | 2234.4 | 71 | 1 | 1.64 | 13 | 122 | 24 | -5 |
| island-4 | 57 | 158.2 | 34 | 1 | 2.27 | 23 | 79 | 7 | +27 |

### Analysis

**island-1** [Breakthrough]: fitness=171.6, dealing 38 damage, 1 species, entropy=1.16 (9 patterns), network=65 genes/6 hidden, char-switching (+27 P1 HP)

**island-2** [Plateaued]: fitness=116.7, dealing 20 damage, 1 species, entropy=0.88 (17 patterns), network=59 genes/9 hidden, char-switching (+22 P1 HP)

**island-3** (LEADER) [Breakthrough]: fitness=2234.4, dealing 71 damage, 1 species, entropy=1.64 (13 patterns), network=122 genes/24 hidden

**island-4** [Breakthrough]: fitness=158.2, dealing 34 damage, 1 species, entropy=2.27 (23 patterns), network=79 genes/7 hidden, char-switching (+27 P1 HP)


---

## Check 32 — 2026-03-08T12:29:45Z

| Island | Gen | Fitness | P2 Dmg | Species | Entropy | Unique | Genes | Hidden | P1 Delta |
|--------|-----|---------|--------|---------|---------|--------|-------|--------|----------|
| island-1 | 59 | 191.1 | 45 | 12 | 1.06 | 12 | 68 | 7 | +27 |
| island-2 | 59 | 116.7 | 20 | 3 | 1.16 | 7 | 82 | 11 | +27 |
| island-3 | 58 | 2234.4 | 71 | 3 | 1.64 | 13 | 122 | 24 | -5 |
| island-4 | 58 | 158.2 | 34 | 1 | 2.27 | 23 | 79 | 7 | +27 |

### Breakthroughs Detected

- **island-1** Gen 59: P2 damage 38→45 (fitness=191.1, entropy=1.06)

### Analysis

**island-1** [Breakthrough]: fitness=191.1, dealing 45 damage, 12 species, entropy=1.06 (12 patterns), network=68 genes/7 hidden, char-switching (+27 P1 HP)

**island-2** [Exploring]: fitness=116.7, dealing 20 damage, 3 species, entropy=1.16 (7 patterns), network=82 genes/11 hidden, char-switching (+27 P1 HP)

**island-3** (LEADER) [Breakthrough]: fitness=2234.4, dealing 71 damage, 3 species, entropy=1.64 (13 patterns), network=122 genes/24 hidden

**island-4** [Breakthrough]: fitness=158.2, dealing 34 damage, 1 species, entropy=2.27 (23 patterns), network=79 genes/7 hidden, char-switching (+27 P1 HP)


---

## Check 33 — 2026-03-08T12:34:47Z

| Island | Gen | Fitness | P2 Dmg | Species | Entropy | Unique | Genes | Hidden | P1 Delta |
|--------|-----|---------|--------|---------|---------|--------|-------|--------|----------|
| island-1 | 60 | 191.1 | 45 | 4 | 0.00 | 0 | 68 | 7 | +0 |
| island-2 | 60 | 116.7 | 20 | 7 | 0.00 | 0 | 82 | 11 | +0 |
| island-3 | 60 | 2234.4 | 71 | 8 | 1.65 | 11 | 126 | 25 | -5 |
| island-4 | 60 | 158.2 | 34 | 8 | 0.00 | 0 | 79 | 7 | +0 |

### Analysis

**island-1** [Breakthrough]: fitness=191.1, dealing 45 damage, 4 species, entropy=0.00 (0 patterns), network=68 genes/7 hidden, pure offense (no char-switch)

**island-2** [Plateaued]: fitness=116.7, dealing 20 damage, 7 species, entropy=0.00 (0 patterns), network=82 genes/11 hidden

**island-3** (LEADER) [Breakthrough]: fitness=2234.4, dealing 71 damage, 8 species, entropy=1.65 (11 patterns), network=126 genes/25 hidden

**island-4** [Breakthrough]: fitness=158.2, dealing 34 damage, 8 species, entropy=0.00 (0 patterns), network=79 genes/7 hidden, pure offense (no char-switch)


---

## Check 34 — 2026-03-08T12:39:49Z

| Island | Gen | Fitness | P2 Dmg | Species | Entropy | Unique | Genes | Hidden | P1 Delta |
|--------|-----|---------|--------|---------|---------|--------|-------|--------|----------|
| island-1 | 61 | 191.1 | 45 | 2 | 1.06 | 13 | 70 | 7 | +27 |
| island-2 | 61 | 116.7 | 20 | 1 | 1.16 | 7 | 82 | 11 | +27 |
| island-3 | 61 | 2234.4 | 71 | 1 | 1.65 | 11 | 126 | 25 | -5 |
| island-4 | 61 | 158.2 | 34 | 1 | 2.27 | 23 | 79 | 7 | +27 |

### Analysis

**island-1** [Breakthrough]: fitness=191.1, dealing 45 damage, 2 species, entropy=1.06 (13 patterns), network=70 genes/7 hidden, char-switching (+27 P1 HP)

**island-2** [Exploring]: fitness=116.7, dealing 20 damage, 1 species, entropy=1.16 (7 patterns), network=82 genes/11 hidden, char-switching (+27 P1 HP)

**island-3** (LEADER) [Breakthrough]: fitness=2234.4, dealing 71 damage, 1 species, entropy=1.65 (11 patterns), network=126 genes/25 hidden

**island-4** [Breakthrough]: fitness=158.2, dealing 34 damage, 1 species, entropy=2.27 (23 patterns), network=79 genes/7 hidden, char-switching (+27 P1 HP)


---

## Check 35 — 2026-03-08T12:44:51Z

| Island | Gen | Fitness | P2 Dmg | Species | Entropy | Unique | Genes | Hidden | P1 Delta |
|--------|-----|---------|--------|---------|---------|--------|-------|--------|----------|
| island-1 | 62 | 191.1 | 45 | 3 | 1.06 | 13 | 70 | 7 | +27 |
| island-2 | 62 | 116.7 | 20 | 4 | 1.16 | 7 | 82 | 11 | +27 |
| island-3 | 62 | 2234.4 | 71 | 1 | 1.65 | 11 | 126 | 25 | -5 |
| island-4 | 62 | 158.2 | 34 | 2 | 2.27 | 23 | 79 | 7 | +27 |

### Analysis

**island-1** [Breakthrough]: fitness=191.1, dealing 45 damage, 3 species, entropy=1.06 (13 patterns), network=70 genes/7 hidden, char-switching (+27 P1 HP)

**island-2** [Exploring]: fitness=116.7, dealing 20 damage, 4 species, entropy=1.16 (7 patterns), network=82 genes/11 hidden, char-switching (+27 P1 HP)

**island-3** (LEADER) [Breakthrough]: fitness=2234.4, dealing 71 damage, 1 species, entropy=1.65 (11 patterns), network=126 genes/25 hidden

**island-4** [Breakthrough]: fitness=158.2, dealing 34 damage, 2 species, entropy=2.27 (23 patterns), network=79 genes/7 hidden, char-switching (+27 P1 HP)


---

## Check 36 — 2026-03-08T12:49:52Z

| Island | Gen | Fitness | P2 Dmg | Species | Entropy | Unique | Genes | Hidden | P1 Delta |
|--------|-----|---------|--------|---------|---------|--------|-------|--------|----------|
| island-1 | 62 | 191.1 | 45 | 3 | 1.06 | 13 | 70 | 7 | +27 |
| island-2 | 62 | 116.7 | 20 | 4 | 1.16 | 7 | 82 | 11 | +27 |
| island-3 | 62 | 2234.4 | 71 | 1 | 1.65 | 11 | 126 | 25 | -5 |
| island-4 | 62 | 158.2 | 34 | 2 | 2.27 | 23 | 79 | 7 | +27 |

### Analysis

**island-1** [Breakthrough]: fitness=191.1, dealing 45 damage, 3 species, entropy=1.06 (13 patterns), network=70 genes/7 hidden, char-switching (+27 P1 HP)

**island-2** [Exploring]: fitness=116.7, dealing 20 damage, 4 species, entropy=1.16 (7 patterns), network=82 genes/11 hidden, char-switching (+27 P1 HP)

**island-3** (LEADER) [Breakthrough]: fitness=2234.4, dealing 71 damage, 1 species, entropy=1.65 (11 patterns), network=126 genes/25 hidden

**island-4** [Breakthrough]: fitness=158.2, dealing 34 damage, 2 species, entropy=2.27 (23 patterns), network=79 genes/7 hidden, char-switching (+27 P1 HP)


---

## Check 37 — 2026-03-08T14:16:48Z

| Island | Gen | Fitness | P2 Dmg | Species | Entropy | Unique | Genes | Hidden | P1 Delta |
|--------|-----|---------|--------|---------|---------|--------|-------|--------|----------|
| island-1 | 62 | 191.1 | 45 | 3 | 1.06 | 13 | 70 | 7 | +27 |
| island-2 | 62 | 116.7 | 20 | 4 | 1.16 | 7 | 82 | 11 | +27 |
| island-3 | 62 | 2234.4 | 71 | 1 | 1.65 | 11 | 126 | 25 | -5 |
| island-4 | 62 | 158.2 | 34 | 2 | 2.27 | 23 | 79 | 7 | +27 |

### Analysis

**island-1** [Breakthrough]: fitness=191.1, dealing 45 damage, 3 species, entropy=1.06 (13 patterns), network=70 genes/7 hidden, char-switching (+27 P1 HP)

**island-2** [Exploring]: fitness=116.7, dealing 20 damage, 4 species, entropy=1.16 (7 patterns), network=82 genes/11 hidden, char-switching (+27 P1 HP)

**island-3** (LEADER) [Breakthrough]: fitness=2234.4, dealing 71 damage, 1 species, entropy=1.65 (11 patterns), network=126 genes/25 hidden

**island-4** [Breakthrough]: fitness=158.2, dealing 34 damage, 2 species, entropy=2.27 (23 patterns), network=79 genes/7 hidden, char-switching (+27 P1 HP)


---

## Check 38 — 2026-03-08T14:17:03Z

| Island | Gen | Fitness | P2 Dmg | Species | Entropy | Unique | Genes | Hidden | P1 Delta |
|--------|-----|---------|--------|---------|---------|--------|-------|--------|----------|
| island-1 | 63 | 191.1 | 45 | 2 | 1.03 | 9 | 70 | 7 | +22 |
| island-2 | 62 | 116.7 | 20 | 4 | 0.00 | 0 | 82 | 11 | +0 |
| island-3 | 62 | 2234.4 | 71 | 1 | 0.00 | 0 | 126 | 25 | +0 |
| island-4 | 62 | 158.2 | 34 | 2 | 0.00 | 0 | 79 | 7 | +0 |

### Analysis

**island-1** [Breakthrough]: fitness=191.1, dealing 45 damage, 2 species, entropy=1.03 (9 patterns), network=70 genes/7 hidden, char-switching (+22 P1 HP)

**island-2** [Plateaued]: fitness=116.7, dealing 20 damage, 4 species, entropy=0.00 (0 patterns), network=82 genes/11 hidden

**island-3** (LEADER) [Breakthrough]: fitness=2234.4, dealing 71 damage, 1 species, entropy=0.00 (0 patterns), network=126 genes/25 hidden, pure offense (no char-switch)

**island-4** [Breakthrough]: fitness=158.2, dealing 34 damage, 2 species, entropy=0.00 (0 patterns), network=79 genes/7 hidden, pure offense (no char-switch)


---

## Check 39 — 2026-03-08T14:21:52Z

| Island | Gen | Fitness | P2 Dmg | Species | Entropy | Unique | Genes | Hidden | P1 Delta |
|--------|-----|---------|--------|---------|---------|--------|-------|--------|----------|
| island-1 | 63 | 191.1 | 45 | 2 | 1.03 | 9 | 70 | 7 | +22 |
| island-2 | 62 | 116.7 | 20 | 4 | 0.00 | 0 | 82 | 11 | +0 |
| island-3 | 62 | 2234.4 | 71 | 1 | 0.00 | 0 | 126 | 25 | +0 |
| island-4 | 62 | 158.2 | 34 | 2 | 0.00 | 0 | 79 | 7 | +0 |

### Analysis

**island-1** [Breakthrough]: fitness=191.1, dealing 45 damage, 2 species, entropy=1.03 (9 patterns), network=70 genes/7 hidden, char-switching (+22 P1 HP)

**island-2** [Plateaued]: fitness=116.7, dealing 20 damage, 4 species, entropy=0.00 (0 patterns), network=82 genes/11 hidden

**island-3** (LEADER) [Breakthrough]: fitness=2234.4, dealing 71 damage, 1 species, entropy=0.00 (0 patterns), network=126 genes/25 hidden, pure offense (no char-switch)

**island-4** [Breakthrough]: fitness=158.2, dealing 34 damage, 2 species, entropy=0.00 (0 patterns), network=79 genes/7 hidden, pure offense (no char-switch)


---

## Check 40 — 2026-03-08T14:26:53Z

| Island | Gen | Fitness | P2 Dmg | Species | Entropy | Unique | Genes | Hidden | P1 Delta |
|--------|-----|---------|--------|---------|---------|--------|-------|--------|----------|
| island-1 | 63 | 191.1 | 45 | 2 | 1.03 | 9 | 70 | 7 | +22 |
| island-2 | 63 | 131.9 | 25 | 2 | 1.85 | 13 | 85 | 12 | +19 |
| island-3 | 63 | 2234.4 | 71 | 1 | 1.65 | 11 | 126 | 25 | -5 |
| island-4 | 63 | 158.2 | 34 | 1 | 2.27 | 23 | 79 | 7 | +27 |

### Breakthroughs Detected

- **island-2** Gen 63: P2 damage 20→25 (fitness=131.9, entropy=1.85)

### Analysis

**island-1** [Breakthrough]: fitness=191.1, dealing 45 damage, 2 species, entropy=1.03 (9 patterns), network=70 genes/7 hidden, char-switching (+22 P1 HP)

**island-2** [Breakthrough]: fitness=131.9, dealing 25 damage, 2 species, entropy=1.85 (13 patterns), network=85 genes/12 hidden, char-switching (+19 P1 HP)

**island-3** (LEADER) [Breakthrough]: fitness=2234.4, dealing 71 damage, 1 species, entropy=1.65 (11 patterns), network=126 genes/25 hidden

**island-4** [Breakthrough]: fitness=158.2, dealing 34 damage, 1 species, entropy=2.27 (23 patterns), network=79 genes/7 hidden, char-switching (+27 P1 HP)


---

## Check 41 — 2026-03-08T14:31:55Z

| Island | Gen | Fitness | P2 Dmg | Species | Entropy | Unique | Genes | Hidden | P1 Delta |
|--------|-----|---------|--------|---------|---------|--------|-------|--------|----------|
| island-1 | 63 | 191.1 | 45 | 2 | 1.03 | 9 | 70 | 7 | +22 |
| island-2 | 65 | 131.9 | 25 | 1 | 0.79 | 11 | 90 | 14 | +22 |
| island-3 | 64 | 2234.4 | 71 | 2 | 1.65 | 11 | 126 | 25 | -5 |
| island-4 | 65 | 158.2 | 34 | 3 | 2.27 | 23 | 79 | 7 | +27 |

### Analysis

**island-1** [Breakthrough]: fitness=191.1, dealing 45 damage, 2 species, entropy=1.03 (9 patterns), network=70 genes/7 hidden, char-switching (+22 P1 HP)

**island-2** [Breakthrough]: fitness=131.9, dealing 25 damage, 1 species, entropy=0.79 (11 patterns), network=90 genes/14 hidden, char-switching (+22 P1 HP)

**island-3** (LEADER) [Breakthrough]: fitness=2234.4, dealing 71 damage, 2 species, entropy=1.65 (11 patterns), network=126 genes/25 hidden

**island-4** [Breakthrough]: fitness=158.2, dealing 34 damage, 3 species, entropy=2.27 (23 patterns), network=79 genes/7 hidden, char-switching (+27 P1 HP)


---

## Check 42 — 2026-03-08T14:36:57Z

| Island | Gen | Fitness | P2 Dmg | Species | Entropy | Unique | Genes | Hidden | P1 Delta |
|--------|-----|---------|--------|---------|---------|--------|-------|--------|----------|
| island-1 | 63 | 191.1 | 45 | 2 | 1.03 | 9 | 70 | 7 | +22 |
| island-2 | 66 | 161.1 | 25 | 3 | 0.00 | 0 | 94 | 16 | +0 |
| island-3 | 66 | 2234.4 | 71 | 4 | 0.00 | 0 | 126 | 25 | +0 |
| island-4 | 66 | 158.2 | 34 | 4 | 0.00 | 0 | 79 | 7 | +0 |

### Breakthroughs Detected

- **island-2** Gen 66: fitness 131.9→161.1 (entropy=0.00)

### Analysis

**island-1** [Breakthrough]: fitness=191.1, dealing 45 damage, 2 species, entropy=1.03 (9 patterns), network=70 genes/7 hidden, char-switching (+22 P1 HP)

**island-2** [Breakthrough]: fitness=161.1, dealing 25 damage, 3 species, entropy=0.00 (0 patterns), network=94 genes/16 hidden, pure offense (no char-switch)

**island-3** (LEADER) [Breakthrough]: fitness=2234.4, dealing 71 damage, 4 species, entropy=0.00 (0 patterns), network=126 genes/25 hidden, pure offense (no char-switch)

**island-4** [Breakthrough]: fitness=158.2, dealing 34 damage, 4 species, entropy=0.00 (0 patterns), network=79 genes/7 hidden, pure offense (no char-switch)


---

## Check 43 — 2026-03-08T14:42:00Z

| Island | Gen | Fitness | P2 Dmg | Species | Entropy | Unique | Genes | Hidden | P1 Delta |
|--------|-----|---------|--------|---------|---------|--------|-------|--------|----------|
| island-1 | 63 | 191.1 | 45 | 2 | 1.03 | 9 | 70 | 7 | +22 |
| island-2 | 67 | 161.1 | 35 | 1 | 1.12 | 5 | 94 | 16 | +0 |
| island-3 | 67 | 2234.4 | 71 | 1 | 1.65 | 11 | 126 | 25 | -5 |
| island-4 | 67 | 158.2 | 34 | 1 | 2.45 | 33 | 102 | 10 | +27 |

### Breakthroughs Detected

- **island-2** Gen 67: P2 damage 25→35 (fitness=161.1, entropy=1.12)

### Analysis

**island-1** [Breakthrough]: fitness=191.1, dealing 45 damage, 2 species, entropy=1.03 (9 patterns), network=70 genes/7 hidden, char-switching (+22 P1 HP)

**island-2** [Breakthrough]: fitness=161.1, dealing 35 damage, 1 species, entropy=1.12 (5 patterns), network=94 genes/16 hidden, pure offense (no char-switch)

**island-3** (LEADER) [Breakthrough]: fitness=2234.4, dealing 71 damage, 1 species, entropy=1.65 (11 patterns), network=126 genes/25 hidden

**island-4** [Breakthrough]: fitness=158.2, dealing 34 damage, 1 species, entropy=2.45 (33 patterns), network=102 genes/10 hidden, char-switching (+27 P1 HP)


---

## Check 44 — 2026-03-08T14:47:02Z

| Island | Gen | Fitness | P2 Dmg | Species | Entropy | Unique | Genes | Hidden | P1 Delta |
|--------|-----|---------|--------|---------|---------|--------|-------|--------|----------|
| island-1 | 63 | 191.1 | 45 | 2 | 1.03 | 9 | 70 | 7 | +22 |
| island-2 | 68 | 161.1 | 35 | 2 | 1.12 | 5 | 94 | 16 | +0 |
| island-3 | 68 | 2234.4 | 71 | 3 | 1.65 | 11 | 126 | 25 | -5 |
| island-4 | 68 | 158.2 | 34 | 1 | 2.10 | 23 | 96 | 9 | +27 |

### Analysis

**island-1** [Breakthrough]: fitness=191.1, dealing 45 damage, 2 species, entropy=1.03 (9 patterns), network=70 genes/7 hidden, char-switching (+22 P1 HP)

**island-2** [Breakthrough]: fitness=161.1, dealing 35 damage, 2 species, entropy=1.12 (5 patterns), network=94 genes/16 hidden, pure offense (no char-switch)

**island-3** (LEADER) [Breakthrough]: fitness=2234.4, dealing 71 damage, 3 species, entropy=1.65 (11 patterns), network=126 genes/25 hidden

**island-4** [Breakthrough]: fitness=158.2, dealing 34 damage, 1 species, entropy=2.10 (23 patterns), network=96 genes/9 hidden, char-switching (+27 P1 HP)


---

## Check 45 — 2026-03-08T14:52:03Z

| Island | Gen | Fitness | P2 Dmg | Species | Entropy | Unique | Genes | Hidden | P1 Delta |
|--------|-----|---------|--------|---------|---------|--------|-------|--------|----------|
| island-1 | 63 | 191.1 | 45 | 2 | 1.03 | 9 | 70 | 7 | +22 |
| island-2 | 69 | 161.1 | 35 | 4 | 1.12 | 5 | 94 | 16 | +0 |
| island-3 | 69 | 2234.4 | 71 | 2 | 1.65 | 11 | 126 | 25 | -5 |
| island-4 | 69 | 158.2 | 34 | 1 | 2.10 | 23 | 96 | 9 | +27 |

### Analysis

**island-1** [Breakthrough]: fitness=191.1, dealing 45 damage, 2 species, entropy=1.03 (9 patterns), network=70 genes/7 hidden, char-switching (+22 P1 HP)

**island-2** [Breakthrough]: fitness=161.1, dealing 35 damage, 4 species, entropy=1.12 (5 patterns), network=94 genes/16 hidden, pure offense (no char-switch)

**island-3** (LEADER) [Breakthrough]: fitness=2234.4, dealing 71 damage, 2 species, entropy=1.65 (11 patterns), network=126 genes/25 hidden

**island-4** [Breakthrough]: fitness=158.2, dealing 34 damage, 1 species, entropy=2.10 (23 patterns), network=96 genes/9 hidden, char-switching (+27 P1 HP)


---

## Check 46 — 2026-03-08T14:57:05Z

| Island | Gen | Fitness | P2 Dmg | Species | Entropy | Unique | Genes | Hidden | P1 Delta |
|--------|-----|---------|--------|---------|---------|--------|-------|--------|----------|
| island-1 | 63 | 191.1 | 45 | 2 | 1.03 | 9 | 70 | 7 | +22 |
| island-2 | 70 | 161.1 | 35 | 1 | 0.00 | 0 | 106 | 18 | +0 |
| island-3 | 70 | 2234.4 | 71 | 2 | 0.00 | 0 | 126 | 25 | +0 |
| island-4 | 71 | 158.2 | 34 | 1 | 2.94 | 50 | 110 | 13 | +27 |

### Analysis

**island-1** [Breakthrough]: fitness=191.1, dealing 45 damage, 2 species, entropy=1.03 (9 patterns), network=70 genes/7 hidden, char-switching (+22 P1 HP)

**island-2** [Breakthrough]: fitness=161.1, dealing 35 damage, 1 species, entropy=0.00 (0 patterns), network=106 genes/18 hidden, pure offense (no char-switch)

**island-3** (LEADER) [Breakthrough]: fitness=2234.4, dealing 71 damage, 2 species, entropy=0.00 (0 patterns), network=126 genes/25 hidden, pure offense (no char-switch)

**island-4** [Breakthrough]: fitness=158.2, dealing 34 damage, 1 species, entropy=2.94 (50 patterns), network=110 genes/13 hidden, char-switching (+27 P1 HP)


---

## Check 47 — 2026-03-08T15:02:07Z

| Island | Gen | Fitness | P2 Dmg | Species | Entropy | Unique | Genes | Hidden | P1 Delta |
|--------|-----|---------|--------|---------|---------|--------|-------|--------|----------|
| island-1 | 63 | 191.1 | 45 | 2 | 1.03 | 9 | 70 | 7 | +22 |
| island-2 | 72 | 161.1 | 35 | 1 | 0.94 | 22 | 116 | 21 | +27 |
| island-3 | 71 | 2234.4 | 71 | 1 | 1.65 | 11 | 126 | 25 | -5 |
| island-4 | 72 | 158.2 | 34 | 1 | 2.89 | 48 | 113 | 13 | +27 |

### Analysis

**island-1** [Breakthrough]: fitness=191.1, dealing 45 damage, 2 species, entropy=1.03 (9 patterns), network=70 genes/7 hidden, char-switching (+22 P1 HP)

**island-2** [Breakthrough]: fitness=161.1, dealing 35 damage, 1 species, entropy=0.94 (22 patterns), network=116 genes/21 hidden, char-switching (+27 P1 HP)

**island-3** (LEADER) [Breakthrough]: fitness=2234.4, dealing 71 damage, 1 species, entropy=1.65 (11 patterns), network=126 genes/25 hidden

**island-4** [Breakthrough]: fitness=158.2, dealing 34 damage, 1 species, entropy=2.89 (48 patterns), network=113 genes/13 hidden, char-switching (+27 P1 HP)


---

## Check 48 — 2026-03-08T15:07:08Z

| Island | Gen | Fitness | P2 Dmg | Species | Entropy | Unique | Genes | Hidden | P1 Delta |
|--------|-----|---------|--------|---------|---------|--------|-------|--------|----------|
| island-1 | 63 | 191.1 | 45 | 2 | 1.03 | 9 | 70 | 7 | +22 |
| island-2 | 73 | 161.1 | 35 | 4 | 1.20 | 33 | 117 | 21 | +27 |
| island-3 | 72 | 2234.4 | 71 | 1 | 1.65 | 11 | 126 | 25 | -5 |
| island-4 | 73 | 158.2 | 34 | 2 | 2.22 | 23 | 111 | 11 | +27 |

### Analysis

**island-1** [Breakthrough]: fitness=191.1, dealing 45 damage, 2 species, entropy=1.03 (9 patterns), network=70 genes/7 hidden, char-switching (+22 P1 HP)

**island-2** [Breakthrough]: fitness=161.1, dealing 35 damage, 4 species, entropy=1.20 (33 patterns), network=117 genes/21 hidden, char-switching (+27 P1 HP)

**island-3** (LEADER) [Breakthrough]: fitness=2234.4, dealing 71 damage, 1 species, entropy=1.65 (11 patterns), network=126 genes/25 hidden

**island-4** [Breakthrough]: fitness=158.2, dealing 34 damage, 2 species, entropy=2.22 (23 patterns), network=111 genes/11 hidden, char-switching (+27 P1 HP)


---

## Check 49 — 2026-03-08T15:12:10Z

| Island | Gen | Fitness | P2 Dmg | Species | Entropy | Unique | Genes | Hidden | P1 Delta |
|--------|-----|---------|--------|---------|---------|--------|-------|--------|----------|
| island-1 | 63 | 191.1 | 45 | 2 | 1.03 | 9 | 70 | 7 | +22 |
| island-2 | 74 | 161.1 | 35 | 6 | 0.00 | 0 | 117 | 21 | +0 |
| island-3 | 74 | 2234.4 | 71 | 4 | 0.00 | 0 | 126 | 25 | +0 |
| island-4 | 74 | 158.2 | 34 | 1 | 0.00 | 0 | 115 | 11 | +0 |

### Analysis

**island-1** [Breakthrough]: fitness=191.1, dealing 45 damage, 2 species, entropy=1.03 (9 patterns), network=70 genes/7 hidden, char-switching (+22 P1 HP)

**island-2** [Breakthrough]: fitness=161.1, dealing 35 damage, 6 species, entropy=0.00 (0 patterns), network=117 genes/21 hidden, pure offense (no char-switch)

**island-3** (LEADER) [Breakthrough]: fitness=2234.4, dealing 71 damage, 4 species, entropy=0.00 (0 patterns), network=126 genes/25 hidden, pure offense (no char-switch)

**island-4** [Breakthrough]: fitness=158.2, dealing 34 damage, 1 species, entropy=0.00 (0 patterns), network=115 genes/11 hidden, pure offense (no char-switch)


---

## Check 50 — 2026-03-08T15:17:11Z

| Island | Gen | Fitness | P2 Dmg | Species | Entropy | Unique | Genes | Hidden | P1 Delta |
|--------|-----|---------|--------|---------|---------|--------|-------|--------|----------|
| island-1 | 63 | 191.1 | 45 | 2 | 1.03 | 9 | 70 | 7 | +22 |
| island-2 | 74 | 161.1 | 35 | 6 | 0.00 | 0 | 117 | 21 | +0 |
| island-3 | 74 | 2234.4 | 71 | 4 | 0.00 | 0 | 126 | 25 | +0 |
| island-4 | 74 | 158.2 | 34 | 1 | 0.00 | 0 | 115 | 11 | +0 |

### Analysis

**island-1** [Breakthrough]: fitness=191.1, dealing 45 damage, 2 species, entropy=1.03 (9 patterns), network=70 genes/7 hidden, char-switching (+22 P1 HP)

**island-2** [Breakthrough]: fitness=161.1, dealing 35 damage, 6 species, entropy=0.00 (0 patterns), network=117 genes/21 hidden, pure offense (no char-switch)

**island-3** (LEADER) [Breakthrough]: fitness=2234.4, dealing 71 damage, 4 species, entropy=0.00 (0 patterns), network=126 genes/25 hidden, pure offense (no char-switch)

**island-4** [Breakthrough]: fitness=158.2, dealing 34 damage, 1 species, entropy=0.00 (0 patterns), network=115 genes/11 hidden, pure offense (no char-switch)


---

## Check 51 — 2026-03-08T16:39:57Z

| Island | Gen | Fitness | P2 Dmg | Species | Entropy | Unique | Genes | Hidden | P1 Delta |
|--------|-----|---------|--------|---------|---------|--------|-------|--------|----------|
| island-1 | 63 | 191.1 | 45 | 2 | 1.03 | 9 | 70 | 7 | +22 |
| island-2 | 74 | 161.1 | 35 | 6 | 0.00 | 0 | 117 | 21 | +0 |
| island-3 | 74 | 2234.4 | 71 | 4 | 0.00 | 0 | 126 | 25 | +0 |
| island-4 | 74 | 158.2 | 34 | 1 | 0.00 | 0 | 115 | 11 | +0 |

### Analysis

**island-1** [Breakthrough]: fitness=191.1, dealing 45 damage, 2 species, entropy=1.03 (9 patterns), network=70 genes/7 hidden, char-switching (+22 P1 HP)

**island-2** [Breakthrough]: fitness=161.1, dealing 35 damage, 6 species, entropy=0.00 (0 patterns), network=117 genes/21 hidden, pure offense (no char-switch)

**island-3** (LEADER) [Breakthrough]: fitness=2234.4, dealing 71 damage, 4 species, entropy=0.00 (0 patterns), network=126 genes/25 hidden, pure offense (no char-switch)

**island-4** [Breakthrough]: fitness=158.2, dealing 34 damage, 1 species, entropy=0.00 (0 patterns), network=115 genes/11 hidden, pure offense (no char-switch)


---

## Check 52 — 2026-03-08T16:40:12Z

| Island | Gen | Fitness | P2 Dmg | Species | Entropy | Unique | Genes | Hidden | P1 Delta |
|--------|-----|---------|--------|---------|---------|--------|-------|--------|----------|
| island-1 | 63 | 191.1 | 45 | 2 | 1.03 | 9 | 70 | 7 | +22 |
| island-2 | 75 | 161.1 | 35 | 1 | 0.00 | 0 | 117 | 21 | +0 |
| island-3 | 75 | 2234.4 | 71 | 1 | 0.00 | 0 | 126 | 25 | +0 |
| island-4 | 75 | 158.2 | 34 | 1 | 0.00 | 0 | 115 | 11 | +0 |

### Analysis

**island-1** [Breakthrough]: fitness=191.1, dealing 45 damage, 2 species, entropy=1.03 (9 patterns), network=70 genes/7 hidden, char-switching (+22 P1 HP)

**island-2** [Breakthrough]: fitness=161.1, dealing 35 damage, 1 species, entropy=0.00 (0 patterns), network=117 genes/21 hidden, pure offense (no char-switch)

**island-3** (LEADER) [Breakthrough]: fitness=2234.4, dealing 71 damage, 1 species, entropy=0.00 (0 patterns), network=126 genes/25 hidden, pure offense (no char-switch)

**island-4** [Breakthrough]: fitness=158.2, dealing 34 damage, 1 species, entropy=0.00 (0 patterns), network=115 genes/11 hidden, pure offense (no char-switch)


---

## Check 53 — 2026-03-08T16:45:12Z

| Island | Gen | Fitness | P2 Dmg | Species | Entropy | Unique | Genes | Hidden | P1 Delta |
|--------|-----|---------|--------|---------|---------|--------|-------|--------|----------|
| island-1 | 63 | 191.1 | 45 | 2 | 1.03 | 9 | 70 | 7 | +22 |
| island-2 | 75 | 161.1 | 35 | 1 | 0.00 | 0 | 117 | 21 | +0 |
| island-3 | 75 | 2234.4 | 71 | 1 | 0.00 | 0 | 126 | 25 | +0 |
| island-4 | 75 | 158.2 | 34 | 1 | 0.00 | 0 | 115 | 11 | +0 |

### Analysis

**island-1** [Breakthrough]: fitness=191.1, dealing 45 damage, 2 species, entropy=1.03 (9 patterns), network=70 genes/7 hidden, char-switching (+22 P1 HP)

**island-2** [Breakthrough]: fitness=161.1, dealing 35 damage, 1 species, entropy=0.00 (0 patterns), network=117 genes/21 hidden, pure offense (no char-switch)

**island-3** (LEADER) [Breakthrough]: fitness=2234.4, dealing 71 damage, 1 species, entropy=0.00 (0 patterns), network=126 genes/25 hidden, pure offense (no char-switch)

**island-4** [Breakthrough]: fitness=158.2, dealing 34 damage, 1 species, entropy=0.00 (0 patterns), network=115 genes/11 hidden, pure offense (no char-switch)

