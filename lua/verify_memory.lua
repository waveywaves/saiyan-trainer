-- verify_memory.lua
-- Standalone script for verifying memory addresses.
-- Loads the game and draws a live overlay showing all memory values.
-- Play the game via VNC and watch the values to confirm addresses are correct.
--
-- Usage:
--   mgba-qt --script lua/verify_memory.lua rom.gba
--
-- What to look for:
--   - p1_health: should decrease when P1 takes damage (0-255)
--   - p2_health: should decrease when P2 takes damage (0-255)
--   - p1_ki / p2_ki: should change during combat (ki charges/specials)
--   - dist_x / dist_y: should change as players move apart
--   - polar_dir: should change based on relative position (0-32)
--   - round_state: should be 0 during fight, non-zero when round ends
--   - timer: should count down during the match

-- Resolve project root for dofile paths
local script_path = debug.getinfo(1, "S").source:match("^@(.+)$") or ""
local project_root = script_path:match("^(.*)/lua/verify_memory%.lua$") or "."
if project_root ~= "." then
    local _dofile = dofile
    dofile = function(path)
        if path:sub(1,1) ~= "/" then
            return _dofile(project_root .. "/" .. path)
        end
        return _dofile(path)
    end
end

print("========================================")
print("  Memory Address Verification Mode")
print("  Play the game and watch the overlay!")
print("========================================")
print("")
print("Color code:")
print("  YELLOW = verified (cheat code confirmed)")
print("  RED    = unverified (needs visual confirmation)")
print("")

-- Load the overlay (it registers its own frame callback)
dofile("lua/vis/mem_overlay.lua")

print("Overlay active. Play the game normally.")
print("Watch the values change as you fight!")
