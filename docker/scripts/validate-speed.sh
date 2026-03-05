#!/bin/bash
# validate-speed.sh - Benchmark BizHawk frame advance speed inside the container
#
# Usage: /opt/scripts/validate-speed.sh [ROM_PATH]
#
# Runs BizHawk with a minimal Lua script that calls emu.frameadvance() 1000 times,
# measures elapsed time, reports FPS, and prints PASS/WARNING status.
# GBA native is 59.73 fps; anything above 100 fps is acceptable for training.

set -euo pipefail

ROM="${1:-${ROM_PATH:-/data/roms/rom.gba}}"

if [ ! -f "$ROM" ]; then
    echo "ERROR: ROM not found at $ROM"
    echo "Usage: $0 [ROM_PATH]"
    exit 1
fi

FRAMES=1000
echo "Benchmarking BizHawk frame advance speed ($FRAMES frames)..."
echo "ROM: $ROM"

# Create a minimal Lua benchmark script
cat > /tmp/benchmark.lua << 'EOF'
local start_time = os.clock()
local frames = 1000
for i = 1, frames do
    emu.frameadvance()
end
local elapsed = os.clock() - start_time
local fps = frames / elapsed
print(string.format("Benchmark: %d frames in %.2f seconds = %.1f fps", frames, elapsed, fps))
-- GBA native is 59.73 fps; anything above 100 fps is acceptable for training
if fps > 100 then
    print("PASS: Frame advance speed is acceptable for training")
else
    print("WARNING: Frame advance is slow. Consider frame-skip or performance tuning.")
end
client.exit()
EOF

/opt/bizhawk/EmuHawkMono.sh \
    --chromeless \
    --lua=/tmp/benchmark.lua \
    "$ROM"
