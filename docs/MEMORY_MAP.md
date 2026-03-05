# Memory Map: DBZ Supersonic Warriors (USA) - GBA

This document is the human-readable reference for all memory addresses used by Saiyan Trainer to read game state from Dragon Ball Z: Supersonic Warriors (USA) on Game Boy Advance.

All addresses use the **System Bus** domain in BizHawk, which matches cheat-code database conventions.

The authoritative source for addresses in code is `lua/memory_map.lua`. This document mirrors that file and adds discovery notes, methodology, and context.

## Address Table

| Name | Address (System Bus) | Size | Type | Description | Verified | Notes |
|------|---------------------|------|------|-------------|----------|-------|
| `p1_health` | `0x03002700` | 2 | u16_le | P1 Health (expected range 0-100 or 0-1000) | No | Placeholder -- discover via RAM Search |
| `p1_ki` | `0x0300274A` | 2 | u16_le | P1 Ki Energy | **Yes** | Seed from CodeBreaker `8300274A 6400` (100 = full) |
| `p1_x` | `0x03002710` | 2 | s16_le | P1 X Position (signed, increases moving right) | No | Placeholder |
| `p1_y` | `0x03002712` | 2 | s16_le | P1 Y Position (signed, changes during jumps/flight) | No | Placeholder |
| `p1_state` | `0x03002720` | 1 | u8 | P1 Attack/Animation State (state machine byte) | No | Placeholder -- hardest to discover |
| `p2_health` | `0x03002800` | 2 | u16_le | P2 Health | No | Placeholder |
| `p2_ki` | `0x03002802` | 2 | u16_le | P2 Ki Energy | No | Placeholder |
| `p2_x` | `0x03002810` | 2 | s16_le | P2 X Position | No | Placeholder |
| `p2_y` | `0x03002812` | 2 | s16_le | P2 Y Position | No | Placeholder |
| `p2_state` | `0x03002820` | 1 | u8 | P2 Attack/Animation State | No | Placeholder |
| `round_state` | `0x03002826` | 1 | u8 | Round/match outcome state | **Yes** | Seed from CodeBreaker `33002826 0000` (instant win) |
| `timer` | `0x03002830` | 2 | u16_le | Match timer countdown value | No | Placeholder |

## How to Discover Addresses

Use BizHawk's built-in **RAM Search** tool (Tools > RAM Search). Always set the domain to **System Bus**.

### Finding Health (P1 and P2)

1. Open RAM Search. Set Size = **2 Byte**, Type = **Unsigned**, Domain = **System Bus**.
2. Click **Reset** to start with all candidate addresses.
3. Start a fight. Both characters should have full health.
4. Search: **Specific Value** = the expected full-health value (try 100, 1000, or other round numbers).
5. Let the opponent hit you so P1 health drops.
6. Search: **Previous Value** > **Greater Than** (the old value was larger than the new value).
7. Repeat steps 5-6 with different amounts of damage to narrow candidates.
8. When only a few candidates remain, add them to **RAM Watch** and verify visually.
9. Update `lua/memory_map.lua` with the confirmed address and set `verified = true`.

### Finding Ki (Verify Known Seed)

1. The address `0x0300274A` is a known seed from cheat databases.
2. Open RAM Watch, add address `0x0300274A`, set to 2-byte unsigned, System Bus.
3. Start a fight and observe the value. Full Ki should read ~100 (0x0064).
4. Use a special move that consumes Ki -- the value should decrease.
5. If confirmed, the address in `memory_map.lua` is already correct.

### Finding Position (X and Y)

1. Open RAM Search. Set Size = **2 Byte**, Type = **Signed** (positions can be negative).
2. Move character **right** -- Search: **Greater Than** previous value.
3. Move character **left** -- Search: **Less Than** previous value.
4. Repeat to narrow candidates for X position.
5. For Y position: **jump or fly up** -- search for changing values. Land -- search again.
6. DBZ:SW characters can fly, so Y values will change significantly.

### Finding Timer

1. Open RAM Search. Set Size = **2 Byte**, Type = **Unsigned**.
2. During an active fight, the timer counts down.
3. Search: **Less Than** previous value (value decreases each tick).
4. Wait a few seconds, repeat the search.
5. Alternatively, search for the specific number shown on the timer display.

### Finding Attack/Animation State

This is the **hardest** address to discover.

1. Open RAM Search. Set Size = **1 Byte**, Type = **Unsigned**.
2. Stand idle -- Search: **Equal To** previous value (value stays the same while idle).
3. Perform an attack -- Search: **Not Equal To** previous value (value changed).
4. Return to idle -- Search: **Not Equal To** previous value again.
5. Repeat across different attacks (punch, kick, special, block).
6. The correct address will show distinct values for each animation state.

### Finding Round State

1. The address `0x03002826` is a known seed (instant-win cheat writes 0x00 here).
2. Open RAM Watch, add `0x03002826`, 1-byte unsigned, System Bus.
3. Observe the value during: fight in progress, round end, match end, character select.
4. Map each observed value to a game state (e.g., 0 = P1 wins, 1 = in progress, etc.).

## Known Address Seeds from Cheat Databases

These addresses are decoded from publicly available CodeBreaker cheat codes:

| Address | Type | Cheat Code | Effect | Confidence |
|---------|------|------------|--------|------------|
| `0x0300274A` | u16_le | `8300274A 6400` | Sets Ki to 100 (full) | MEDIUM |
| `0x03002826` | u8 | `33002826 0000` | Instant win (sets round outcome to 0) | MEDIUM |
| `0x03004D58` | u16_le | `43004D58 FFFF` | Unlock all characters | LOW (not fight state) |

**CodeBreaker format reference:**
- Code type `3` = 8-bit write: `3AAAAAAA 00VV` writes byte VV to address 0x0AAAAAAA
- Code type `8` = 16-bit write: `8AAAAAAA VVVV` writes halfword VVVV to address 0x0AAAAAAA
- Code type `4` = slide code (multi-address write)

## Address Conventions

- **Domain:** All addresses use **System Bus** domain in BizHawk.
- **IWRAM range:** `0x03000000` - `0x03007FFF` (32KB). All game-state variables live here.
- **System Bus vs IWRAM:** System Bus address `0x0300274A` equals IWRAM address `0x0000274A`. We always use System Bus to match cheat databases and avoid confusion.
- **P1/P2 offset:** P1 and P2 data may be at a fixed offset from each other. Discover both independently, then verify whether the offset is consistent across all fields.
- **Fight-only addresses:** Most addresses are only valid during active fights. Values may be garbage on menus, character select, or between rounds.

## After Discovery

When you discover a real address using RAM Search:

1. Open `lua/memory_map.lua`.
2. Find the entry (e.g., `p1_health`).
3. Replace the placeholder `addr` value with the real address.
4. Set `verified = true`.
5. Update this document's Address Table with the new address and change Verified to **Yes**.
6. Add any notes about value range, behavior, or quirks.

Run `lua/memory_reader.lua` in BizHawk to verify -- verified addresses display in **green**, unverified in **yellow**.
