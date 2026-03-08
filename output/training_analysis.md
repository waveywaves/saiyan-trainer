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

