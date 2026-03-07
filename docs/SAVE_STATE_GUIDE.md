# Save State Creation Guide

How to create a valid fight-start save state for NEAT training in DBZ: Supersonic Warriors.

## Why It Matters

The NEAT training loop loads a save state at the beginning of each genome evaluation. For training to be meaningful, the save state must capture an **active fight** with both players at full HP. If the save state is in a menu, cutscene, or post-fight screen, the bot cannot learn fighting behavior.

**Current issue:** The existing `fight_start.ss0` save state has P1 HP=44, P2 HP=72, round_state=71, which suggests the game is NOT in an active fight state. Training with this save state may produce genomes that learn to navigate menus rather than fight.

## Prerequisites

- Docker container running (`docker run` with your ROM mounted)
- noVNC enabled (default: `ENABLE_VNC=true`)
- ROM file present at the configured `ROM_PATH`
- Web browser to access noVNC

## Step-by-Step Procedure

### 1. Start the Docker Container

```bash
docker run -d \
  --name saiyan-trainer \
  -p 6080:6080 \
  -v $(pwd)/roms:/data/roms \
  -v $(pwd)/savestates:/data/savestates \
  -v $(pwd)/output:/data/output \
  -e ROM_PATH=/data/roms/your-rom.gba \
  saiyan-trainer/mgba:latest
```

### 2. Open noVNC

Navigate to **http://localhost:6080/vnc.html** in your web browser. You should see the mGBA window running the game.

### 3. Navigate to a Fight

Using the on-screen controls or keyboard input through noVNC:

1. **Title Screen** -- Press Start/Enter
2. **Main Menu** -- Select "VS Mode" (or "Story Mode" if VS Mode is not yet unlocked)
3. **Character Select** -- Choose any character for P1; the CPU will control P2
4. **Stage Select** -- Choose any stage
5. **Wait for fight to start** -- The fight intro animation will play, then both characters will be on screen with full HP bars

### 4. Verify the Fight Is Active

Before saving, confirm:

- Both characters are visible on screen and in fighting stance
- Both HP bars are full (at the top of the screen)
- The match timer is counting down
- You can move your character with the D-pad

### 5. Create the Save State

**Option A: Via mGBA Scripting Console**

If you have a script loaded, you can use the mGBA scripting console to save:

```lua
emu:saveStateFile("/data/savestates/fight_start.ss0")
```

**Option B: Via mGBA Keyboard Shortcut**

In the mGBA window through noVNC:

- Press **Shift+F1** to save to slot 1
- The save state file will be created at mGBA's default save state location

**Option C: Via a Helper Script**

Load a minimal save-state helper script:

```bash
docker exec saiyan-trainer mgba-qt --script /data/lua/save_helper.lua /data/roms/your-rom.gba
```

### 6. Copy the Save State (if using Option B)

If you used the keyboard shortcut, the save state may be in mGBA's internal location. Copy it to the expected path:

```bash
docker exec saiyan-trainer cp /path/to/mgba/savestate /data/savestates/fight_start.ss0
```

### 7. Verify the Save State

After creating the save state, verify it has correct values. Load the P2 HP scanner script to check memory values:

```bash
# In a new terminal, load the scanner
docker exec -it saiyan-trainer mgba-qt --script /data/lua/tools/p2_hp_scanner.lua /data/roms/your-rom.gba
```

Or check values manually via the mGBA scripting console:

```lua
-- These should print expected values for an active fight
print("P1 HP:      " .. emu:read8(0x0300273E))   -- Should be ~176 (full health)
print("P1 HP Max:  " .. emu:read8(0x0300273F))   -- Should be ~176
print("round_state:" .. emu:read8(0x03002826))   -- Should indicate active gameplay
```

**Expected values for a valid fight-start save state:**

| Address | Name | Expected Value | Meaning |
|---------|------|----------------|---------|
| 0x0300273E | P1 HP | ~176 | Full health |
| 0x0300273F | P1 HP Max | ~176 | Maximum HP cap |
| 0x03002826 | round_state | Non-zero | Active gameplay (0 = instant win trigger) |

## Troubleshooting

### HP values are 0

The game is likely in a menu or loading screen. Navigate to an active fight and try again.

### round_state is 0

This means the "instant win" cheat state is active. This happens when `emu:write8(0x03002826, 0)` has been called. Restart the game and navigate to a fight normally.

### Characters are not visible

The game may be in a cutscene, character select screen, or stage transition. Wait for the fight to begin before saving.

### Save state loads but fight ends immediately

The save state was likely captured at the very end of a round. Create a new save state at the beginning of a fight when both players have full HP.

### P1 HP is not ~176

Different characters may have different max HP values. The exact value depends on the character and power level. As long as HP is near its maximum (matching P1 HP Max), the save state is valid.

## File Locations

| File | Container Path | Host Path (default mount) |
|------|---------------|---------------------------|
| Fight start save state | `/data/savestates/fight_start.ss0` | `./savestates/fight_start.ss0` |
| No-CPU training state | `/data/savestates/no_cpu_training_state.ss0` | `./savestates/no_cpu_training_state.ss0` |
| Training log output | `/data/output/training.log` | `./output/training.log` |
