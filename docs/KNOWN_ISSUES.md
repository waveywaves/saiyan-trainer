# Known Issues and Limitations

Tracked limitations, blocked work, and architectural decisions for the Saiyan Trainer project.

## Active Issues

### 1. FPS Uncapping (BLOCKED)

**Status:** BLOCKED -- no known workaround
**Impact:** Training runs at real-time speed (60fps), making large-scale training slow
**Affects:** Training throughput

mGBA Qt runs at a fixed 60fps. Attempts to uncap frame rate have all failed:

- **`-C fpsTarget=9999`**: Breaks script loading entirely. The mGBA scripting engine does not initialize when this flag is used.
- **`qt.ini` modification**: Setting `fpsTarget=0` or high values in the Qt configuration file also breaks script loading.
- **Root cause:** The Qt frontend ties frame limiting to the rendering pipeline. Disabling it disrupts the event loop that drives script callbacks.

**Current impact:**
- Each evaluation: 1800 frames = 30 seconds real time
- With 30 genomes per generation: ~15 minutes per generation
- Acceptable for development and initial testing
- **Not viable for production training** at scale (100+ generations)

**Potential future solutions:**
- mGBA headless mode (if/when available) may bypass Qt frame limiting
- Custom mGBA build with separate script tick rate from render rate
- Running multiple parallel containers (Tekton fan-out) to compensate

### 2. P2 HP Address Unverified

**Status:** OPEN -- requires user interaction to verify
**Impact:** Fitness scores involving P2 damage may be inaccurate
**Affects:** Fitness calculation, training effectiveness

The P2 HP memory address (`0x03004C30`) is from old VBA code and has not been verified against the actual game running in mGBA. The address is 9,458 bytes away from P1 HP (`0x0300273E`), which is unusually far for a mirrored player struct.

**Symptoms if wrong:**
- P2 HP never changes during fights
- All genomes get identical fitness scores
- Fitness values are consistently near -1 (no damage bonus applied)
- Bot shows no learning progress across generations

**How to fix:**
1. Run the P2 HP scanner script: `mgba-qt --script lua/tools/p2_hp_scanner.lua rom.gba`
2. Play the game via noVNC and attack the enemy
3. Watch console output for which candidate address decreases
4. Update `lua/memory_map.lua` with the verified address

See `lua/tools/p2_hp_scanner.lua` for detailed instructions.

### 3. Save State Validity

**Status:** OPEN -- requires user to create a new save state
**Impact:** Training may not produce learning if game is not in active fight
**Affects:** Training effectiveness

The current `fight_start.ss0` save state has P1 HP=44, P2 HP=72, round_state=71. These values suggest the game is NOT in an active fight state (likely a menu, cutscene, or post-fight screen). Training with this save state may produce genomes that learn to navigate menus rather than fight.

**How to fix:**
1. Follow the procedure in `docs/SAVE_STATE_GUIDE.md`
2. Create a new save state during an active VS Mode fight
3. Verify P1 HP is near maximum (~176) and both characters are visible

## Architectural Decisions (Not Bugs)

### 4. Console Output Does Not Reach Docker stdout

**Status:** BY DESIGN
**Why:** mGBA's `console:log()` and Lua `print()` write to the scripting console buffer, not to the process stdout. This is an mGBA architectural limitation.

**Workaround:** All training output is logged to `output/training.log` via file I/O. The training loop opens this file and writes progress updates directly.

### 5. round_state Semantics Are Inverted

**Status:** BY DESIGN -- architectural decision
**Why:** The `round_state` memory address (`0x03002826`) has inverted semantics from what the name suggests:
- `0` = Triggers an instant win (this is a cheat code effect, not a natural game state)
- Non-zero = Normal gameplay in progress

**Consequence:** The training loop does NOT use `round_state` to detect round boundaries. Instead, it uses HP-based detection: a round is over when P1 or P2 HP drops to 0, or when the evaluation timeout (1800 frames) is reached.

### 6. mGBA emu Userdata Is Sealed

**Status:** BY DESIGN -- mGBA limitation
**Why:** The `emu` userdata object in mGBA Lua cannot have its methods overridden (no `__newindex` metamethod). This means coroutine-based approaches to frame stepping do not work.

**Consequence:** The training loop uses a frame-callback state machine pattern instead of coroutines. States: `waiting` -> `init` -> `eval_setup` -> `evaluating` -> `gen_done` -> `complete`. The `callbacks:add("frame", fn)` API drives the state machine, advancing one step per frame tick.

## Resolved Issues

### Crossover Bug
**Status:** RESOLVED
The crossover implementation had incorrect gene alignment causing malformed offspring genomes. Fixed by properly matching genes by innovation number during crossover.

### Innovation Tracking
**Status:** RESOLVED
Innovation numbers were not being tracked globally across generations, leading to duplicate innovation numbers for different structural mutations. Fixed by persisting the global innovation counter.

### Fitness Reporting Bug
**Status:** RESOLVED
Fitness scores were not being reported correctly after evaluation, causing the pool to retain stale fitness values. Fixed by ensuring fitness is written back to the genome immediately after evaluation completes.

## Notes

- **Training config:** Population is set to 30 (testing). Restore to 300 for real training runs. See `lua/neat/config.lua`.
- **Timeout:** TimeoutConstant is 1800 frames / 30 seconds (testing). Restore to 5400 for real training. See `lua/neat/config.lua`.
- **Checkpoints:** Saved to `output/checkpoints/gen_N.json` after each generation.
