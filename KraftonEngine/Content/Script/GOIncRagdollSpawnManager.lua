-- GOIncRagdollSpawnManager_MultiRandom.lua
--
-- Interval/max-count based ragdoll spawner.
-- Requires:
--   GOInc.SpawnRagdollPawn(ragdollId, location)
--   RagdollData.lua entries with spawnWeight
--
-- RagdollData.lua example:
--   ["blue-speedster"] = { displayName = "파란 고슴도치", spawnWeight = 10, ... }
--   ["pink-round"]     = { displayName = "분홍 동글이",   spawnWeight = 8,  ... }
--
-- spawnWeight <= 0 means the entry will not spawn.
-- canSpawn = false also disables the entry if the field exists.

local SPAWN_MIN_X = -10.0
local SPAWN_MAX_X = 10.0
local SPAWN_MIN_Y = -10.0
local SPAWN_MAX_Y = 10.0
local SPAWN_Z = 1.0

local SPAWN_INTERVAL = 2.0
local MAX_SPAWN_COUNT = 10
local SPAWN_IMMEDIATELY_ON_BEGIN_PLAY = true

local DEFAULT_RAGDOLL_ID = "blue-speedster"

local RagdollData = nil

local spawnTimer = 0.0
local spawnedCount = 0
local spawnedPawns = {}
local bPrintedMaxSpawnReached = false

local function number_or(value, fallback)
    if type(value) == "number" then
        return value
    end
    return fallback
end

local function random_range(minValue, maxValue)
    return minValue + (maxValue - minValue) * math.random()
end

local function load_ragdoll_data()
    if RagdollData ~= nil then
        return RagdollData
    end

    local moduleNames = {
        "Data.RagdollData",
        "RagdollData",
    }

    for _, moduleName in ipairs(moduleNames) do
        local ok, result = pcall(require, moduleName)
        if ok and result ~= nil then
            RagdollData = result
            print("[GOIncRagdollSpawnManager] Loaded " .. moduleName)
            return RagdollData
        end
    end

    print("[GOIncRagdollSpawnManager] Failed to load RagdollData.lua")
    return nil
end

local function is_spawnable_config(config)
    if type(config) ~= "table" then
        return false
    end

    if config.canSpawn == false then
        return false
    end

    return number_or(config.spawnWeight, 0.0) > 0.0
end

local function build_spawn_candidates()
    local data = load_ragdoll_data()
    if data == nil then
        return nil, 0.0
    end

    local candidates = {}
    local totalWeight = 0.0

    for id, config in pairs(data) do
        if is_spawnable_config(config) then
            local weight = number_or(config.spawnWeight, 0.0)
            totalWeight = totalWeight + weight

            table.insert(candidates, {
                id = id,
                displayName = config.displayName or id,
                weight = weight,
            })
        end
    end

    return candidates, totalWeight
end

local function pick_random_ragdoll_entry()
    local candidates, totalWeight = build_spawn_candidates()

    if candidates == nil or #candidates <= 0 or totalWeight <= 0.0 then
        print("[GOIncRagdollSpawnManager] No spawnable ragdoll entries. Fallback: " .. DEFAULT_RAGDOLL_ID)
        return {
            id = DEFAULT_RAGDOLL_ID,
            displayName = DEFAULT_RAGDOLL_ID,
            weight = 1.0,
        }
    end

    local roll = random_range(0.0, totalWeight)
    local accumulated = 0.0

    for _, entry in ipairs(candidates) do
        accumulated = accumulated + entry.weight
        if roll <= accumulated then
            return entry
        end
    end

    return candidates[#candidates]
end

local function make_random_spawn_location()
    return Vector.new(
        random_range(SPAWN_MIN_X, SPAWN_MAX_X),
        random_range(SPAWN_MIN_Y, SPAWN_MAX_Y),
        SPAWN_Z
    )
end

local function can_spawn_more()
    if MAX_SPAWN_COUNT <= 0 then
        return true
    end

    return spawnedCount < MAX_SPAWN_COUNT
end

local function print_max_spawn_reached_once()
    if bPrintedMaxSpawnReached then
        return
    end

    bPrintedMaxSpawnReached = true
    print(string.format(
        "[GOIncRagdollSpawnManager] Max spawn count reached: %d / %d",
        spawnedCount, MAX_SPAWN_COUNT))
end

local function spawn_one()
    if not can_spawn_more() then
        print_max_spawn_reached_once()
        return nil
    end

    if GOInc == nil or GOInc.SpawnRagdollPawn == nil then
        print("[GOIncRagdollSpawnManager] Missing GOInc.SpawnRagdollPawn binding")
        return nil
    end

    local entry = pick_random_ragdoll_entry()
    local ragdollId = entry.id
    local location = make_random_spawn_location()
    local pawn = GOInc.SpawnRagdollPawn(ragdollId, location)

    if pawn == nil then
        print("[GOIncRagdollSpawnManager] Failed to spawn ragdoll pawn: " .. tostring(ragdollId))
        return nil
    end

    spawnedCount = spawnedCount + 1
    spawnedPawns[spawnedCount] = pawn

    print(string.format(
        "[GOIncRagdollSpawnManager] Spawned %s (%s) at (%.2f, %.2f, %.2f) [%d / %d]",
        tostring(ragdollId),
        tostring(entry.displayName),
        location.X, location.Y, location.Z,
        spawnedCount,
        MAX_SPAWN_COUNT))

    return pawn
end

function BeginPlay()
    if math.randomseed ~= nil then
        if os ~= nil and os.time ~= nil then
            math.randomseed(os.time())
        else
            math.randomseed(12345)
        end
    end

    -- Warm up the PRNG a little. This helps when several Lua scripts seed at similar times.
    math.random()
    math.random()
    math.random()

    spawnTimer = 0.0
    spawnedCount = 0
    spawnedPawns = {}
    bPrintedMaxSpawnReached = false

    if SPAWN_IMMEDIATELY_ON_BEGIN_PLAY then
        spawn_one()
    end
end

function Tick(deltaTime)
    if not can_spawn_more() then
        print_max_spawn_reached_once()
        return
    end

    local dt = number_or(deltaTime, 0.0)
    if dt <= 0.0 then
        return
    end

    if SPAWN_INTERVAL <= 0.0 then
        spawn_one()
        return
    end

    spawnTimer = spawnTimer + dt

    while spawnTimer >= SPAWN_INTERVAL and can_spawn_more() do
        spawnTimer = spawnTimer - SPAWN_INTERVAL
        spawn_one()
    end
end
