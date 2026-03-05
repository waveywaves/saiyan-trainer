# Phase 1: Emulation Foundation - Research

**Researched:** 2026-03-06
**Domain:** GBA emulator scripting (BizHawk Lua API), reverse-engineering GBA memory maps, controller input automation
**Confidence:** MEDIUM

## Summary

Phase 1 is the foundation that everything else depends on. It requires three distinct capabilities: (1) reading game state from GBA RAM via BizHawk's Lua API, (2) sending controller inputs including simultaneous button combos, and (3) creating deterministic save states for fight evaluation. The highest-risk task is reverse-engineering the DBZ Supersonic Warriors memory map -- no public RAM map exists, and every address must be discovered manually using BizHawk's RAM Search tool.

The BizHawk Lua API is well-documented and provides all necessary functions: `memory.read_u8/u16_le/u32_le` for reading RAM with explicit domain selection, `joypad.set` for controller input with full simultaneous button support, and `savestate.save/load` for deterministic state management. The GBA has a straightforward memory layout: game state variables live in IWRAM (32KB at System Bus 0x03000000-0x03007FFF). One confirmed address exists from cheat databases: Ki energy at System Bus `0x0300274A` (16-bit value, 100 = full). The "instant win" code writes `0x00` to `0x03002826`, suggesting this address controls round/match outcome state. All other addresses (health, position, attack state, timer) must be discovered through systematic RAM searching.

The local development environment requires BizHawk 2.11 on Windows or Linux (macOS is not supported). BizHawk is launched with CLI arguments `--lua=<script>` to auto-load Lua scripts and the ROM as a positional argument. No Kubernetes dependency exists in this phase -- everything runs locally on the developer's machine.

**Primary recommendation:** Use BizHawk 2.11's RAM Search tool to systematically discover all memory addresses, always use System Bus domain for reads (matches cheat database conventions), and structure all memory access through a single `memory_map.lua` configuration file from day one.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| MEM-01 | Lua script reads P1 health from GBA memory in real-time | BizHawk `memory.read_u16_le(addr, "System Bus")` API; address must be discovered via RAM Search |
| MEM-02 | Lua script reads P2 health from GBA memory in real-time | Same API; P2 health likely at a fixed offset from P1 health address |
| MEM-03 | Lua script reads P1 position (x, y) from GBA memory | Same API; position values likely unsigned 16-bit in IWRAM, discoverable via RAM Search |
| MEM-04 | Lua script reads P2 position (x, y) from GBA memory | Same API; P2 position likely at fixed offset from P1 position |
| MEM-05 | Lua script reads P1 ki/energy level from GBA memory | Known address: `0x0300274A` (16-bit, 0x6400 = 100%); needs verification |
| MEM-06 | Lua script reads P2 ki/energy level from GBA memory | Likely at a fixed offset from P1 ki address |
| MEM-07 | Lua script reads attack/animation state for both players | Must be discovered; likely single-byte state machine value in IWRAM |
| MEM-08 | Lua script reads round state (in-progress, round-over, match-over) | Address `0x03002826` likely related (instant-win code writes 0x00 here); needs investigation |
| MEM-09 | Lua script reads match timer value | Must be discovered; likely 16-bit countdown value in IWRAM |
| MEM-10 | All memory addresses documented in a memory map reference file | Create `memory_map.lua` with named constants, domain, data type, and notes |
| CTRL-01 | Lua script translates NEAT output neurons to GBA button presses | BizHawk `joypad.set({A=true, B=true, Down=true})` supports simultaneous buttons |
| CTRL-02 | Controller supports simultaneous button combinations | `joypad.set` accepts a table with multiple buttons set to `true` per frame |
| DX-02 | NEAT training runs locally in BizHawk without Kubernetes | BizHawk 2.11 runs on Windows/Linux desktop; launch with `EmuHawk --lua=script.lua rom.gba` |
| DX-03 | ROM is gitignored with clear instructions | Add `roms/` to `.gitignore`; document ROM placement in README |
| LOOP-06 | Local training without K8s | Same as DX-02; this phase establishes the local-only development workflow |
</phase_requirements>

## Standard Stack

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| BizHawk (EmuHawk) | 2.11 | GBA emulator with Lua scripting, frame advance, save states, RAM Search | Only emulator with production-grade Lua scripting + memory access + joypad control for GBA; used by all MarI/O-derived projects |
| Lua | 5.4 (BizHawk-bundled) | Scripting language for all emulator interaction | BizHawk 2.11 bundles Lua 5.4; no choice -- emulator dictates version |
| BizHawk RAM Search | built-in | GUI tool for discovering unknown memory addresses | Standard TAS community tool for reverse-engineering game memory |

### Supporting
| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| BizHawk Hex Editor | built-in | Inspecting raw memory values at discovered addresses | When verifying RAM Search findings or exploring adjacent memory |
| BizHawk RAM Watch | built-in | Monitoring discovered addresses in real-time | After discovering an address, add to Watch to confirm behavior |
| BizHawk Lua Console | built-in | Running and debugging Lua scripts | Development and testing of all Lua code |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| BizHawk | mGBA standalone | mGBA has headless mode (good for containers) but lacks BizHawk's Lua scripting API, RAM Search, and joypad control -- would require rewriting all automation code |
| System Bus domain | IWRAM domain directly | IWRAM strips the 0x03000000 base offset, making addresses incompatible with cheat databases -- System Bus is universally compatible |

**Installation:**
```bash
# Linux
sudo apt install mono-complete libopenal1 lua5.4
wget https://github.com/TASEmulators/BizHawk/releases/download/2.11/BizHawk-2.11-linux-x64.tar.gz
tar xzf BizHawk-2.11-linux-x64.tar.gz -C ~/bizhawk

# Launch with Lua script
~/bizhawk/EmuHawkMono.sh "roms/Dragon Ball Z - Supersonic Warriors (USA).gba" --lua=lua/memory_reader.lua

# macOS: NOT supported. Use Linux VM or Windows.
```

## Architecture Patterns

### Recommended Project Structure
```
saiyan-trainer/
  roms/                              # gitignored, user provides ROM
    Dragon Ball Z - Supersonic Warriors (USA).gba
  savestates/                         # committed, deterministic fight-start states
    fight_start.State
  lua/                                # all Lua scripts
    memory_map.lua                   # address constants + read helpers
    memory_reader.lua                # diagnostic script: prints all game state
    controller.lua                   # NEAT output -> joypad.set mapping
    controller_test.lua              # manual test: performs specific moves
    utils.lua                        # shared utilities
  docs/
    MEMORY_MAP.md                    # human-readable memory map documentation
  .gitignore                          # includes roms/
```

### Pattern 1: Memory Map as Config File
**What:** Centralize all discovered memory addresses in a single `memory_map.lua` file with named constants, data types, and domain specification.
**When to use:** Always -- from the first discovered address onward.
**Example:**
```lua
-- Source: BizHawk Lua API docs + manual RAM Search discovery
local DOMAIN = "System Bus"

local MemoryMap = {
    -- Player 1
    p1_health     = { addr = 0x030027XX, size = 2, type = "u16_le", desc = "P1 Health (0-100)" },
    p1_ki         = { addr = 0x0300274A, size = 2, type = "u16_le", desc = "P1 Ki Energy (0-100)" },
    p1_x          = { addr = 0x030027XX, size = 2, type = "u16_le", desc = "P1 X Position" },
    p1_y          = { addr = 0x030027XX, size = 2, type = "u16_le", desc = "P1 Y Position" },
    p1_state      = { addr = 0x030027XX, size = 1, type = "u8",     desc = "P1 Attack/Animation State" },

    -- Player 2 (likely at fixed offset from P1)
    p2_health     = { addr = 0x030027XX, size = 2, type = "u16_le", desc = "P2 Health" },
    p2_ki         = { addr = 0x030027XX, size = 2, type = "u16_le", desc = "P2 Ki Energy" },
    p2_x          = { addr = 0x030027XX, size = 2, type = "u16_le", desc = "P2 X Position" },
    p2_y          = { addr = 0x030027XX, size = 2, type = "u16_le", desc = "P2 Y Position" },
    p2_state      = { addr = 0x030027XX, size = 1, type = "u8",     desc = "P2 Attack/Animation State" },

    -- Match State
    round_state   = { addr = 0x03002826, size = 1, type = "u8",     desc = "Round outcome state" },
    timer         = { addr = 0x030027XX, size = 2, type = "u16_le", desc = "Match timer countdown" },
}

-- Generic reader function
function MemoryMap.read(entry)
    if entry.type == "u8" then
        return memory.read_u8(entry.addr, DOMAIN)
    elseif entry.type == "u16_le" then
        return memory.read_u16_le(entry.addr, DOMAIN)
    elseif entry.type == "u32_le" then
        return memory.read_u32_le(entry.addr, DOMAIN)
    end
end

return MemoryMap
```

### Pattern 2: Controller Output Mapping
**What:** Map NEAT output neuron indices to GBA button names, using a threshold to determine press/no-press, supporting simultaneous buttons.
**When to use:** When translating neural network outputs to game inputs.
**Example:**
```lua
-- Source: BizHawk joypad API docs + MarI/O pattern
-- GBA buttons available for fighting game control
local ButtonNames = {
    "A",      -- Attack button 1
    "B",      -- Attack button 2
    "L",      -- Shoulder left
    "R",      -- Shoulder right
    "Up",     -- D-pad up (jump/fly)
    "Down",   -- D-pad down (crouch/dodge)
    "Left",   -- D-pad left (move left)
    "Right",  -- D-pad right (move right)
}
-- Note: Start and Select excluded from NEAT outputs

local function outputsToController(outputs)
    local controller = {}
    for i = 1, #ButtonNames do
        if outputs[i] > 0 then
            controller[ButtonNames[i]] = true
        else
            controller[ButtonNames[i]] = false
        end
    end
    return controller
end

-- Apply to emulator each frame
-- Supports simultaneous combos naturally: {Down=true, B=true} for special moves
joypad.set(controller)
emu.frameadvance()
```

### Pattern 3: Save State Anchoring for Deterministic Evaluation
**What:** Create a save state at the exact frame a fight begins (both characters at full health, timer started). Load this state before every genome evaluation.
**When to use:** Every NEAT fitness evaluation must start from identical game state.
**Example:**
```lua
-- Source: BizHawk savestate API
-- Create fight-start save state (done once manually or via script)
-- Navigate to: Main Menu -> VS Mode -> Select Characters -> Fight Start
-- Save at the frame where the fight countdown finishes and control is given

local SAVE_STATE_PATH = "savestates/fight_start.State"

-- Before each genome evaluation
function resetFight()
    savestate.load(SAVE_STATE_PATH)
    -- Note: Lua script state (variables, tables) survives save state loads
    -- Only emulator state is reset
end

-- Main training loop structure
while true do
    resetFight()
    local fitness = evaluateGenome(currentGenome)
    -- ... NEAT selection/mutation
end
```

### Pattern 4: Frame-Advance Training Loop
**What:** The Lua script controls emulation frame-by-frame using `emu.frameadvance()`. Every frame: read memory, compute neural network, set joypad, advance.
**When to use:** Core loop structure for all NEAT training.
**Example:**
```lua
-- Source: BizHawk Lua API docs
-- BizHawk Lua scripts MUST call emu.frameadvance() or emu.yield()
-- in any loop, or the emulator will freeze

local mm = require("memory_map")

while true do
    -- 1. Read game state
    local p1_health = MemoryMap.read(mm.p1_health)
    local p2_health = MemoryMap.read(mm.p2_health)
    -- ... read all inputs

    -- 2. Check if fight is over
    if isFightOver(mm) then
        break  -- exit to NEAT selection/mutation
    end

    -- 3. Neural network forward pass (Phase 2)
    -- local outputs = evaluateNetwork(inputs, genome)

    -- 4. Set controller
    -- local controller = outputsToController(outputs)
    -- joypad.set(controller)

    -- 5. Advance one frame
    emu.frameadvance()
end
```

### Anti-Patterns to Avoid
- **Hardcoded addresses scattered in code:** Never write `memory.read_u16_le(0x0300274A, "System Bus")` inline. Always use `memory_map.lua` constants. Addresses WILL change during discovery.
- **Omitting domain parameter in memory reads:** `memory.readbyte(addr)` reads from the currently selected domain, which may not be System Bus. Always specify: `memory.read_u8(addr, "System Bus")`.
- **Reading IWRAM domain with System Bus addresses:** IWRAM strips the 0x03000000 base. Address `0x0300274A` in System Bus becomes `0x0000274A` in IWRAM. Pick one convention (System Bus) and stick to it.
- **Forgetting `emu.frameadvance()` in loops:** Script will hang the emulator. Every loop iteration must call `emu.frameadvance()` or `emu.yield()`.
- **Not handling save state load behavior:** Loading a save state triggers `emu.frameadvance()` internally. Use `event.onloadstate` callback if you need to reset Lua variables on state load.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Memory address discovery | Custom memory scanner in Lua | BizHawk's built-in RAM Search GUI tool | RAM Search has comparison operators, data size selection, signed/unsigned modes, and can filter millions of candidates in seconds |
| Cheat code decryption | Manual hex math on GameShark codes | Known raw CodeBreaker format (`8AAAAAAA VVVV` = write VVVV to 0AAAAAAA) | CodeBreaker "8" prefix codes directly contain the System Bus address |
| Save state management | Custom serialization of emulator state | BizHawk `savestate.save/load` with file paths | BizHawk handles all emulator internal state; you cannot replicate this in Lua |
| GUI overlay for debugging | Custom drawing routines | BizHawk `gui.text(x, y, message)` and `gui.drawText` | Built-in, supports positioning, colors, and multiple surfaces |

**Key insight:** BizHawk provides all the heavy infrastructure (emulation, memory access, save states, GUI overlay). Phase 1 code is thin Lua scripts that wire BizHawk's APIs together, not reimplementations of emulator features.

## Common Pitfalls

### Pitfall 1: GBA Memory Domain Confusion (IWRAM vs System Bus)
**What goes wrong:** Cheat databases use System Bus addresses (0x0300274A). Developer uses BizHawk IWRAM domain, which strips the base offset, so the same address is 0x0000274A. Every read returns wrong data.
**Why it happens:** BizHawk presents memory through multiple "domains." The default domain may not be System Bus. `memory.readbyte(addr)` uses whatever domain is currently selected.
**How to avoid:** Always pass domain explicitly: `memory.read_u16_le(addr, "System Bus")`. Create a wrapper: `function readMem(addr) return memory.read_u16_le(addr, "System Bus") end`. Standardize on System Bus for all addresses.
**Warning signs:** Memory reads return 0 or 255 consistently. Values found in BizHawk Hex Editor don't match Lua script reads. Hex Editor shows correct data when "System Bus" domain is selected but Lua reads from IWRAM.

### Pitfall 2: RAM Search Data Size Misconfiguration
**What goes wrong:** RAM Search is set to 1-byte mode when searching for health values that are stored as 16-bit (2-byte) integers. The search finds partial matches or misses the address entirely.
**Why it happens:** GBA games commonly use 16-bit and 32-bit values. RAM Search defaults may not match the game's data storage format.
**How to avoid:** Start RAM Search with 2-byte (16-bit) unsigned for health/ki/timer values. Use 4-byte for positions if 2-byte yields no results. Try both signed and unsigned. Document the data size for each discovered address.
**Warning signs:** Found address value doesn't match on-screen display. Value overflows (wraps around 255) when health is clearly higher.

### Pitfall 3: Addresses Valid Only During Fights
**What goes wrong:** Memory addresses discovered during a fight return garbage on character select, menu, or between rounds. The NEAT training loop reads invalid data during transitions and corrupts fitness calculations.
**Why it happens:** Games reuse memory for different purposes in different screens/modes. The "health" address during a fight may hold menu cursor position on the main menu.
**How to avoid:** Discover a "mode" or "screen state" address that indicates whether a fight is in progress. Only read fight-specific addresses when fight mode is active. Verify addresses across multiple fight scenarios (different characters, different stages, different rounds).
**Warning signs:** Values suddenly jump to seemingly random numbers between rounds. Lua script prints nonsensical values when not in a fight.

### Pitfall 4: Player Structure Offset Assumption
**What goes wrong:** Developer assumes P1 and P2 data are at a fixed offset (e.g., P2 = P1 + 0x100). Offset is wrong, and P2 reads are garbage.
**Why it happens:** Many games do use fixed offsets between player structures, but the exact offset varies per game. Some games interleave P1/P2 data rather than using separate blocks.
**How to avoid:** Discover P1 and P2 addresses independently using RAM Search. After finding both, calculate the actual offset and verify it holds for ALL field types (health, ki, position, state). Document the offset if it's consistent.
**Warning signs:** P2 health reads work but P2 position reads are wrong (offset is not uniform across all fields).

### Pitfall 5: BizHawk macOS Incompatibility
**What goes wrong:** Developer on macOS cannot run BizHawk. BizHawk does not support macOS.
**Why it happens:** BizHawk is a .NET/Mono application with Windows and Linux builds only.
**How to avoid:** Use a Linux VM (e.g., UTM on Apple Silicon, or VirtualBox/VMware on Intel Mac). Alternatively, use a Windows machine or cloud Linux instance for BizHawk development.
**Warning signs:** EmuHawk binary won't execute on macOS, no macOS release on GitHub.

### Pitfall 6: Lua 5.4 Integer/Float Distinction
**What goes wrong:** Lua 5.4 distinguishes integers from floats (unlike 5.1-5.3). Division of two integers returns an integer, not a float. MarI/O code that depends on `5/2 == 2.5` gets `5/2 == 2` instead.
**Why it happens:** Lua 5.4 introduced a dual number type system. This is a breaking change from earlier Lua versions used by older BizHawk releases.
**How to avoid:** Use `5.0/2` or `5/2.0` for float division. Test all arithmetic in BizHawk's Lua console before relying on it.
**Warning signs:** Neural network outputs are all 0 or 1 instead of continuous values. Fitness calculations produce unexpected integer results.

## Code Examples

### Reading Memory with Domain Specification
```lua
-- Source: https://tasvideos.org/Bizhawk/LuaFunctions
-- Always specify "System Bus" for GBA games to match cheat database addresses

-- Read unsigned 8-bit value
local value_u8 = memory.read_u8(0x03002826, "System Bus")

-- Read unsigned 16-bit little-endian (most common for GBA)
local health = memory.read_u16_le(0x0300274A, "System Bus")

-- Read unsigned 32-bit little-endian
local value_u32 = memory.read_u32_le(0x03001000, "System Bus")

-- Read signed 16-bit (for positions that can be negative)
local pos_x = memory.read_s16_le(0x030027XX, "System Bus")

-- List all available memory domains
local domains = memory.getmemorydomainlist()
for i, domain in ipairs(domains) do
    console.log(domain)  -- Will show: "System Bus", "IWRAM", "EWRAM", "Combined WRAM", etc.
end

-- Get size of a domain
local size = memory.getmemorydomainsize("IWRAM")  -- Returns 32768 (32KB)
```

### Setting Controller Input with Simultaneous Buttons
```lua
-- Source: https://tasvideos.org/Bizhawk/LuaFunctions
-- joypad.set() accepts a table of button names mapped to true/false
-- Multiple buttons can be true simultaneously for combo inputs

-- Simple single button press
joypad.set({A = true})
emu.frameadvance()

-- Simultaneous combo: Down + B (common special move input)
joypad.set({Down = true, B = true})
emu.frameadvance()

-- Full directional + attack combo
joypad.set({Right = true, A = true, B = true})
emu.frameadvance()

-- Release all buttons (neutral frame)
joypad.set({})
emu.frameadvance()

-- Read current controller state (useful for debugging)
local currentInput = joypad.get(1)  -- Controller 1
-- Returns table: {A=false, B=false, Up=false, Down=false, Left=false, Right=false, L=false, R=false, Start=false, Select=false, Power=false}
```

### Save State Management
```lua
-- Source: https://tasvideos.org/Bizhawk/LuaFunctions
-- File-based save states (recommended for training)
local STATE_PATH = "savestates/fight_start.State"

-- Save current state
savestate.save(STATE_PATH, true)  -- true = suppress OSD message

-- Load saved state
savestate.load(STATE_PATH, true)  -- true = suppress OSD message

-- Slot-based save states (1-10, simpler but less portable)
savestate.saveslot(1, true)
savestate.loadslot(1, true)

-- Register callback for state load events
event.onloadstate(function()
    console.log("Save state loaded -- resetting script variables")
    -- Reset any per-fight tracking variables here
    frameCount = 0
    totalDamageDealt = 0
end)
```

### Diagnostic Memory Reader Script
```lua
-- Full diagnostic script to run in BizHawk during a fight
-- Prints all discovered game state values each frame

local mm = require("memory_map")

local function readAllState()
    local state = {}
    for name, entry in pairs(mm) do
        if type(entry) == "table" and entry.addr then
            state[name] = mm.read(entry)
        end
    end
    return state
end

local function displayState(state)
    local y = 10
    for name, value in pairs(state) do
        gui.text(10, y, string.format("%s: %d", name, value))
        y = y + 15
    end
end

-- Main loop
while true do
    local state = readAllState()
    displayState(state)
    emu.frameadvance()
end
```

### RAM Search Methodology (Step-by-Step)
```
FINDING HEALTH ADDRESS (example):
1. Open BizHawk > Tools > RAM Search
2. Set Size to "2 Byte" (16-bit), Signed = "Unsigned"
3. Set Domain to "System Bus"
4. Click "Reset" to start with all addresses
5. Start a fight -- both characters have full health
6. Search: "Specific Value" = 100 (or whatever full health is)
   -> This filters to addresses currently holding value 100
7. Take damage (let opponent hit you)
8. Search: "Previous Value" > "Greater Than" current value
   (i.e., the old value was greater than the new value)
   -> Filters to addresses that decreased when health decreased
9. Repeat steps 7-8 with different amounts of damage
10. When only a few candidates remain, add to RAM Watch
11. Verify by watching the value change in real-time during fights
12. Record the confirmed address in memory_map.lua

FINDING TIMER ADDRESS:
1. Same setup as above
2. Search for "Changes by: 1" each frame during countdown
3. Or search for specific timer value shown on screen

FINDING POSITION ADDRESS:
1. Set Size to "2 Byte", try both Signed and Unsigned
2. Move character left -> Search "Less Than" previous
3. Move character right -> Search "Greater Than" previous
4. Repeat until only a few candidates remain
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| BizHawk 2.9 with Lua 5.1 | BizHawk 2.11 with Lua 5.4 | Sept 2025 | Lua 5.4 integer/float distinction may break ported MarI/O code |
| `memory.readbyte(addr)` without domain | `memory.read_u8(addr, "System Bus")` with explicit domain | BizHawk 2.x | Prevents silent wrong-domain bugs |
| mGBA core memory callback bug (#4631) | Fixed in BizHawk 2.11.1 dev builds | Late 2025 | Memory callbacks now safe to use with mGBA GBA core |
| `memory.read_bytes_as_array()` only | `memory.read_bytes()` as string added | BizHawk 2.11 | Easier bulk memory reading with string library |

**Deprecated/outdated:**
- **Lua 5.1 syntax assumptions:** MarI/O and older forks assume Lua 5.1. BizHawk 2.11 uses Lua 5.4. Integer division (`//`) is new; `5/2` returns `2` not `2.5`.
- **`mainmemory` module:** Still works but `memory` module with explicit domain is preferred for clarity and correctness.

## Open Questions

1. **Exact health addresses for P1 and P2**
   - What we know: Ki is at `0x0300274A`. Health is likely nearby in IWRAM. P1 and P2 probably have a fixed offset between them.
   - What's unclear: Exact addresses, data format (u8 vs u16), value range (0-100? 0-255? 0-1000?).
   - Recommendation: Use RAM Search during a fight. Search for decreasing values when health bar drops. Budget 2-4 hours for health discovery.

2. **Position coordinate format**
   - What we know: Positions are in IWRAM. GBA screen is 240x160 but game may use larger world coordinates.
   - What's unclear: Whether positions are signed (allowing negative values for left-of-screen), 16-bit or 32-bit, and what coordinate system the game uses.
   - Recommendation: Search for values that increase when moving right, decrease when moving left. Try both signed and unsigned 16-bit.

3. **Attack/animation state encoding**
   - What we know: Fighting games typically use a state machine byte where each value represents a state (idle, attacking, blocking, hitstun, etc.).
   - What's unclear: Whether DBZ:SW uses a single byte or a more complex multi-field structure. What the state values map to.
   - Recommendation: This is the hardest address to find. Use RAM Search to find values that change when attacking, blocking, or getting hit. May need to observe patterns over many fights.

4. **Round state vs match state**
   - What we know: `0x03002826` is related to win/loss (instant-win code writes 0x00 here). DBZ:SW has multi-round matches.
   - What's unclear: Whether this is round state, match state, or both. What values indicate "in progress", "round over", "match over".
   - Recommendation: Observe this address across multiple rounds and match outcomes. Map each value to a game state.

5. **GBA button names in BizHawk joypad API for GBA**
   - What we know: GBA has 10 buttons: A, B, L, R, Up, Down, Left, Right, Start, Select. BizHawk uses either bare names or "P1 " prefixed names.
   - What's unclear: Exact key names returned by `joypad.get()` for GBA core in BizHawk 2.11. May be bare ("A") or prefixed ("P1 A").
   - Recommendation: Run `console.log(joypad.getimmediate())` in BizHawk Lua console with GBA ROM loaded to discover exact key names. Document them.

6. **BizHawk on developer's machine (macOS concern)**
   - What we know: BizHawk does NOT support macOS. Only Windows and Linux are supported.
   - What's unclear: Whether the developer uses macOS and needs a VM.
   - Recommendation: If on macOS, use UTM (Apple Silicon) or VirtualBox (Intel) to run a Linux VM. Alternative: remote Linux machine via SSH + X forwarding.

## Known Memory Address Seeds

These addresses are derived from cheat code databases and serve as starting points for RAM exploration:

| Address (System Bus) | Type | Value | Source | Confidence | Notes |
|---------------------|------|-------|--------|------------|-------|
| `0x0300274A` | u16_le | 0x6400 = 100 (full Ki) | CodeBreaker `8300274A 6400` | MEDIUM | CodeBreaker "8" type = 16-bit write to address 0AAAAAAA. Needs verification in BizHawk. |
| `0x03002826` | u8 | 0x00 = instant win | CodeBreaker `33002826 0000` | MEDIUM | CodeBreaker "3" type = 8-bit write to address 0AAAAAAA. Likely round/match outcome flag. |
| `0x03004D58` | u16_le | 0xFFFF = unlock all | CodeBreaker `43004D58 FFFF` | LOW | This is a "4" type (slide code), address may be for unlockables, not fight state. |

**Critical note on CodeBreaker format:** The leading digit is the code type (3 = 8-bit write, 8 = 16-bit write, 4 = slide code, 7 = conditional). The next 7 hex digits are the System Bus address with the leading 0 implied. So `8300274A` = 16-bit write to `0x0300274A`, and `33002826` = 8-bit write to `0x03002826`.

## RAM Search Strategy for DBZ:SW

### Priority Order for Address Discovery
1. **P1 Health** -- most visible, easiest to verify (search for decreasing value when hit)
2. **P2 Health** -- same technique, different player
3. **P1 Ki** -- verify known address `0x0300274A`
4. **P2 Ki** -- calculate offset from P1 Ki, or search independently
5. **Timer** -- search for steadily decreasing value during fight
6. **Round State** -- investigate `0x03002826`, observe during round transitions
7. **P1 Position X** -- search for increasing/decreasing with movement
8. **P1 Position Y** -- search for changing during jumps/flight
9. **P2 Position X/Y** -- same technique or offset from P1
10. **Attack State** -- hardest; search for values changing during attacks

### Tips for This Specific Game
- DBZ:SW has characters that can fly, so Y position will change significantly (not just ground-level)
- Special moves consume Ki, which helps verify Ki address (Ki should decrease after special)
- Some characters transform (e.g., Goku -> Super Saiyan), which may change memory layout
- The game has 1v1 and team modes; start with simple 1v1 VS mode
- IWRAM is only 32KB (0x03000000-0x03007FFF), so the search space is small and manageable

## Sources

### Primary (HIGH confidence)
- [BizHawk Lua Functions Reference](https://tasvideos.org/Bizhawk/LuaFunctions) -- memory, joypad, savestate, emu API signatures verified
- [BizHawk Command Line](https://tasvideos.org/Bizhawk/CommandLine) -- CLI arguments for `--lua`, `--load-state`, ROM path
- [GBA Memory Domains (Corrupt.wiki)](https://corrupt.wiki/systems/gameboy-advance/bizhawk-memory-domains) -- IWRAM/EWRAM/System Bus domain addressing
- [GBA Memory Layout (gbadoc)](https://gbadev.net/gbadoc/memory.html) -- IWRAM at 0x03000000, 32KB
- [TASVideos RAM Search Documentation](https://tasvideos.org/EmulatorResources/RamSearch) -- step-by-step RAM search methodology
- [BizHawk GitHub Releases](https://github.com/TASEmulators/BizHawk/releases) -- v2.11 release Sept 2025, Lua 5.4, Linux support
- [BizHawk Joypad Table Key Names](https://tasvideos.org/Bizhawk/LuaFunctions/JoypadTableKeyNames) -- button name conventions

### Secondary (MEDIUM confidence)
- [MarI/O NEATEvolve.lua (rodvan fork)](https://github.com/rodvan/MarI-O/blob/master/NEATEvolve.lua) -- joypad.set pattern, ButtonNames table, output-to-controller mapping
- [NEATEvolve (SngLol fork)](https://github.com/SngLol/NEATEvolve) -- fixed save/load functions for MarI/O pattern
- [Bizhawk-NEAT-GameSolver](https://github.com/LionelBergen/Bizhawk-NEAT-GameSolver-ML-AI) -- ROM.lua abstraction pattern for multi-game NEAT
- [GBA CodeBreaker format (doc.kodewerx.org)](https://doc.kodewerx.org/hacking_gba.html) -- code type 8 = 16-bit write, type 3 = 8-bit write
- [Twilio BizHawk Lua Tutorial](https://www.twilio.com/blog/how-to-write-lua-scripts-for-video-games-with-the-bizhawk-emulator) -- practical Lua scripting examples

### Tertiary (LOW confidence)
- [Spanish cheat site: trucosvisualboy](https://trucosvisualboy.wordpress.com/2012/06/04/trucos-dragon-ball-z-supersonic-warriors/) -- raw CodeBreaker codes: Ki `8300274A 6400`, Instant Win `33002826 0000`
- [GameHacking.org DBZ:SW page](https://gamehacking.org/game/4393) -- game page exists but 403 on access; limited codes available
- [RetroAchievements DBZ:SW](https://retroachievements.org/game/756) -- achievement set exists with 31 achievements; memory addresses used in achievement logic could reveal game state addresses but page was not accessible

## Metadata

**Confidence breakdown:**
- Standard stack (BizHawk + Lua API): HIGH -- well-documented, multiple authoritative sources
- Architecture patterns (memory map, controller, save state): HIGH -- proven by MarI/O and derivatives
- Memory address seeds: MEDIUM -- CodeBreaker format decoded, addresses plausible but unverified in BizHawk
- RAM discovery methodology: HIGH -- standard TAS community practice, well-documented
- Pitfalls: HIGH -- domain confusion, data size issues are widely documented by BizHawk community
- macOS incompatibility: HIGH -- confirmed by official BizHawk docs

**Research date:** 2026-03-06
**Valid until:** 2026-04-06 (BizHawk is stable; GBA memory map is permanent once discovered)
