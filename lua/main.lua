-- main.lua
-- Saiyan Trainer - NEAT Fighting Game AI
-- Entry point script loaded by mGBA.
--
-- Usage:
--   mGBA: mgba-sdl -s lua/main.lua rom.gba
--   Or: Load this script from mGBA's scripting window (Tools > Scripting)

print("========================================")
print("  Saiyan Trainer - NEAT Fighting Game AI")
print("  Neuroevolution for DBZ: Supersonic Warriors")
print("  v0.2.0 - mGBA Edition")
print("========================================")
print("")

-- Load the save state helper to check prerequisites
local SaveState = dofile("lua/savestate_helper.lua")

-- Check for fight-start save state
if not SaveState.hasFightStartState() then
    print("ERROR: Fight start save state not found!")
    print("")
    print("Before training can begin, you need to create a save state:")
    print("  1. Launch the ROM in mGBA")
    print("  2. Go to VS Mode and select your characters")
    print("  3. Start a fight and wait for the countdown to finish")
    print("  4. When the player has control, save state to:")
    print("     " .. SaveState.getFightStartFile())
    print("  5. Or run in scripting window: dofile('lua/savestate_helper.lua').createFightStartState()")
    print("")
    print("Waiting for save state file...")

    -- Wait loop: check every 60 frames (1 second) for the save state
    while not SaveState.hasFightStartState() do
        emu:runFrame()
    end

    print("Save state detected! Starting training...")
end

-- Load the training loop
local TrainingLoop = dofile("lua/training/loop.lua")

-- ============================================================
-- TRAINING CONFIGURATION
-- Edit these options to customize training behavior.
-- ============================================================

local options = {
    -- How many generations to train (0 = run forever)
    generations = 100,

    -- Auto-resume from latest checkpoint if available
    resume = true,

    -- Set to a specific checkpoint path to resume from that file
    -- checkpointFile = "checkpoints/gen_50.json",

    -- Multi-opponent rotation: set to a table of save states
    -- to train against different opponents/difficulties.
    -- Each entry: {file = "path/to/state.State", desc = "Description"}
    opponents = nil,
    -- Example:
    -- opponents = {
    --     {file = "savestates/vs_easy.State",   desc = "Easy CPU"},
    --     {file = "savestates/vs_medium.State", desc = "Medium CPU"},
    --     {file = "savestates/vs_hard.State",   desc = "Hard CPU"},
    -- },

    -- Rotate opponent every N generations (only used if opponents is set)
    opponentRotation = 10,
}

-- ============================================================
-- START TRAINING
-- ============================================================

print("Starting NEAT training...")
TrainingLoop.runTraining(options)
