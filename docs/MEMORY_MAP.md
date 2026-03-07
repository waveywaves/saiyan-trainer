# Memory Map: DBZ Supersonic Warriors (USA) - GBA

This document is the human-readable reference for all memory addresses used by Saiyan Trainer to read game state from Dragon Ball Z: Supersonic Warriors (USA) on Game Boy Advance.

All addresses are GBA System Bus addresses in the IWRAM range (`0x03000000`-`0x03007FFF`). In mGBA, these are read directly without a domain parameter.

The authoritative source for addresses in code is `lua/memory_map.lua`. This document mirrors that file and adds discovery notes, methodology, and context.

## Address Table

### Player 1 (CONFIRMED)

| Name | Address | Size | Type | Range | Verified | Source |
|------|---------|------|------|-------|----------|--------|
| `p1_health` | `0x0300273E` | 1 | u8 | 0-255 | **Yes** | GS decrypt + CB `3300273E` + old VBA code |
| `p1_health_max` | `0x0300273F` | 1 | u8 | 0-255 | **Yes** | GS decrypt + CB `3300273F` |
| `p1_ki` | `0x0300274A` | 2 | u16 | see note | **Yes** | CB `8300274A 6400` + GS decrypt |
| `p1_ki_int` | `0x0300274B` | 1 | u8 | 0-100 | **Yes** | High byte of Ki u16 = integer % |
| `p1_power_level` | `0x03002738` | 1 | u8 | 0-3 | **Yes** | GS decrypt of "All Chars Stronger" code |

### Player 2 (from old VBA code, UNVERIFIED)

| Name | Address | Size | Type | Range | Verified | Source |
|------|---------|------|------|-------|----------|--------|
| `p2_health` | `0x03004C30` | 1 | u8 | 0-255 | No | Old VBA code (different region than P1) |
| `p2_ki` | `0x03002833` | 2 | u16 | -- | No | Old VBA code |

### Spatial (from old VBA code, UNVERIFIED)

| Name | Address | Size | Type | Range | Verified | Source |
|------|---------|------|------|-------|----------|--------|
| `dist_x` | `0x03002CD4` | 2 | u16 | 0-630 | No | Old VBA code |
| `dist_y` | `0x03002CD8` | 2 | u16 | 0-630 | No | Old VBA code |
| `polar_dir` | `0x0300288C` | 1 | u8 | 0-32 | No | Old VBA code (direction quadrant) |

### Match State

| Name | Address | Size | Type | Range | Verified | Source |
|------|---------|------|------|-------|----------|--------|
| `round_state` | `0x03002826` | 1 | u8 | -- | **Yes** | CB `33002826 0000` + GS decrypt |
| `timer` | `0x03002830` | 2 | u16 | -- | No | Placeholder |

### Shop / Unlock (not used in fights)

| Name | Address | Size | Type | Range | Verified | Source |
|------|---------|------|------|-------|----------|--------|
| `shop_points` | `0x03004DB4` | 2 | u16 | 0-9999 | **Yes** | GS decrypt of "Unlimited Points" |
| `unlock_flags` | `0x03004D58` | 2x4 | u16 | bitmask | **Yes** | CB slide `43004D58 FFFF x4` |

## P1 Struct Analysis

The P1 data structure appears to be based around `0x03002700` in IWRAM. Known field offsets from this hypothetical base:

```
Base: 0x03002700 (hypothesis)

Offset  Address      Size  Field              Confirmed
------  -----------  ----  -----------------  ---------
+0x38   0x03002738   u8    Power Level/Form   YES (GS decrypt)
+0x3E   0x0300273E   u8    Current HP         YES (GS decrypt + CB + VBA)
+0x3F   0x0300273F   u8    Max HP             YES (GS decrypt + CB)
+0x4A   0x0300274A   u16   Ki (full word)     YES (CB + GS decrypt)
+0x4B   0x0300274B   u8    Ki integer (0-100) YES (derived)

Unknown offsets (need RAM search):
+0x00-0x03  Character ID / sprite index?
+0x04-0x07  X position (s16) + Y position (s16)?
+0x08-0x0B  X velocity (s16) + Y velocity (s16)?
+0x0C-0x0F  Facing direction, flags?
+0x10-0x37  Animation state, combo counter, timers?
+0x39-0x3D  Unknown (between power level and HP)
+0x40-0x49  Unknown (between max HP and Ki)
```

### HP Details

- **Current HP** at `0x0300273E`: Single byte, range 0-255.
- **Max HP** at `0x0300273F`: Single byte, range 0-255. Game caps current HP at this value.
- The "Infinite Vie" (Infinite Health) cheat continuously writes `0xFF` to `0x0300273E`.
- The "Max Vie" (Max Health) cheat writes `0xFF` to `0x0300273F` once.
- To read HP for the NEAT bot: `emu:read8(0x0300273E)` gives current HP as 0-255.

### Ki Details

- Ki is stored as a **16-bit value** at `0x0300274A` in an `8.8 fixed-point` style:
  - **High byte** (`0x0300274B`): Integer part, range 0-100 (percentage).
  - **Low byte** (`0x0300274A`): Fractional/sub-unit part.
- The CodeBreaker code `8300274A 6400` writes `0x6400` as u16, which in little-endian places:
  - `0x00` at `0x0300274A` (fractional = 0)
  - `0x64` at `0x0300274B` (integer = 100 = full Ki)
- For the NEAT bot, read `emu:read8(0x0300274B)` for a simple 0-100 Ki percentage,
  or read `emu:read16(0x0300274A)` for the full fixed-point value.

### Power Level Details

- At `0x03002738`, single byte.
- The "All Characters Are Stronger" cheat writes `0x03`.
- Likely values: 0=base form, 1-3=powered up / transformed.
- Useful for the NEAT bot to detect transformation state.

## P2 Data Layout (OPEN QUESTION)

The old VBA code used these P2 addresses which do NOT follow a simple struct offset from P1:

- P2 HP: `0x03004C30` (P1 HP is at `0x0300273E`, delta = `0x24F2` = 9458 bytes apart)
- P2 Ki: `0x03002833` (P1 Ki is at `0x0300274A`, delta = `-0xFFFFFF17` -- P2 Ki is BEFORE P1 Ki?)

This suggests either:
1. The game uses **non-contiguous** storage for P1 and P2 data.
2. The old VBA addresses are **display/shadow copies** rather than the actual struct fields.
3. The old VBA addresses might be **incorrect** (never fully verified).

**Candidate P2 struct offsets to test** (if assuming contiguous structs starting at 0x03002700):

| Struct Size | P2 Base | P2 HP | P2 Ki |
|-------------|---------|-------|-------|
| 0x74 (116 bytes) | 0x03002774 | 0x030027B2 | 0x030027BE |
| 0x80 (128 bytes) | 0x03002780 | 0x030027BE | 0x030027CA |
| 0xA0 (160 bytes) | 0x030027A0 | 0x030027DE | 0x030027EA |
| 0xC0 (192 bytes) | 0x030027C0 | 0x030027FE | 0x0300280A |
| 0x100 (256 bytes) | 0x03002800 | 0x0300283E | 0x0300284A |

## Cheat Code Decryption Reference

### Raw CodeBreaker Codes (unencrypted, addresses readable directly)

| Raw Code | Address | Value | Effect |
|----------|---------|-------|--------|
| `3300273E 00FF` | `0x0300273E` | `0xFF` | Infinite Health (write current HP) |
| `3300273F 00FF` | `0x0300273F` | `0xFF` | Max Health (write max HP) |
| `8300274A 6400` | `0x0300274A` | `0x6400` | Ki at 100% |
| `33002826 0000` | `0x03002826` | `0x00` | Instant win |
| `83004DB4 270F` | `0x03004DB4` | `0x270F` | Infinite shop points (9999) |
| `43004D58 FFFF 00000004 0002` | `0x03004D58` | `0xFFFF` x4 | Unlock everything |

### Decrypted GameShark v1/v2 Codes (TEA algorithm, seeds: 09F4FBBD/9681884A/352027E9/F3DEE5A7)

| Encrypted Code | Decrypted Raw | Address | Value | Effect |
|----------------|---------------|---------|-------|--------|
| `B8CE7B32 38AB9D94` | `0300273F 000000FF` | `0x0300273F` | `0xFF` | Max HP (8-bit write) |
| `3EDD7118 5A58A127` | `0300273E 000000FF` | `0x0300273E` | `0xFF` | Infinite HP (8-bit write) |
| `CB1E748C 4A108A48` | `03002738 00000003` | `0x03002738` | `0x03` | All Chars Stronger (power level) |
| `DC4B8E1A AF073E65` | `1300274A 00006400` | `0x0300274A` | `0x6400` | Ki 100% (16-bit write) |
| `B9298C5C 769EFDFB` | `13004DB4 0000270F` | `0x03004DB4` | `0x270F` | Shop Points 9999 (16-bit write) |
| `4734D246 90FE8764` | `D4000130 000003FB` | `0x04000130` | `0x03FB` | If Select pressed (conditional) |
| `9E69DA42 35B196E8` | `03002826 00000000` | `0x03002826` | `0x00` | Instant Win (8-bit write) |

### Code Type Reference

**GameShark v1/v2 raw format:**
- Type `0`: 8-bit write -- `0aaaaaaa 000000xx`
- Type `1`: 16-bit write -- `1aaaaaaa 0000xxxx`
- Type `2`: 32-bit write -- `2aaaaaaa xxxxxxxx`
- Type `D`: 16-bit conditional -- `Daaaaaaa 0000xxxx`

**CodeBreaker raw format:**
- Type `3`: 8-bit write -- `3AAAAAAA 00VV`
- Type `8`: 16-bit write -- `8AAAAAAA VVVV`
- Type `4`: Slide code -- `4AAAAAAA VVVV / count inc`
- Type `7`: 16-bit conditional -- `7AAAAAAA VVVV`

## Address Conventions

- **IWRAM range:** `0x03000000` - `0x03007FFF` (32KB). All game-state variables live here.
- **System Bus vs IWRAM offset:** System Bus address `0x0300274A` equals IWRAM offset `0x0000274A`. We use System Bus addresses throughout.
- **GBA byte order:** Little-endian. A u16 at address A has low byte at A, high byte at A+1.
- **Fight-only addresses:** Most addresses are only valid during active fights. Values may be garbage on menus, character select, or between rounds.

## How to Verify Remaining Addresses

Use mGBA's built-in memory viewer/search, or run mGBA with the scripting console.

### Verifying P1 Health (should already work)

1. Start a fight. Watch `emu:read8(0x0300273E)` -- should show full HP (likely 0xFF or some max).
2. Take damage. Value should decrease.
3. Watch `emu:read8(0x0300273F)` -- should stay constant (max HP).

### Finding P2 Health

1. Start a fight. Read `emu:read8()` at each candidate P2 HP address (see table above).
2. Let the opponent (P2) take damage. The correct address value will decrease.
3. Also test the old VBA address `0x03004C30` -- it may be a display copy.

### Finding Absolute Positions (X/Y)

The old VBA code used relative distances (`dist_x`, `dist_y`) rather than absolute positions. If the game stores pre-computed distances, absolute X/Y per player may not exist in an obvious form. Try:

1. Search for values that change when P1 moves left/right (X) or up/down (Y).
2. Look in the 0x03002700-0x03002738 range (before power level in the P1 struct).
3. Check if the old VBA `dist_x` at `0x03002CD4` and `dist_y` at `0x03002CD8` respond to movement.

### Finding Animation/Attack State

1. Search for a byte that changes value with each different action (idle, punch, kick, block, special).
2. Look in the 0x03002710-0x03002737 range (between position and power level in the P1 struct).
3. The correct address will show distinct stable values for each animation.

## After Discovery

When you discover a real address:

1. Update `lua/memory_map.lua` with the confirmed address and set `verified = true`.
2. Update this document's Address Table.
3. Test with `MemoryMap.readAll()` in the mGBA scripting console.
