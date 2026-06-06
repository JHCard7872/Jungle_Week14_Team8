-- GOIncRagdollSpawnManager.lua
--
-- Interval/max-count based GOInc ragdoll character spawner.
-- Requires:
--   GOInc.SpawnRagdollCharacter(characterId, location)
--
-- Character-specific mesh/physics/animation settings live in C++ Pawn subclasses.
-- This manager only owns spawn policy: id, displayName, spawnWeight, interval, count, location.
-- spawnWeight <= 0 means the entry will not spawn.
-- canSpawn = false also disables the entry if the field exists.

local SpawnCfg = require("Data.GameConfig").spawn

local SPAWN_MIN_X = SpawnCfg.areaMinX
local SPAWN_MAX_X = SpawnCfg.areaMaxX
local SPAWN_MIN_Y = SpawnCfg.areaMinY
local SPAWN_MAX_Y = SpawnCfg.areaMaxY
local SPAWN_Z = SpawnCfg.z

local SPAWN_INTERVAL = SpawnCfg.interval
local MAX_SPAWN_COUNT = SpawnCfg.maxCount
local SPAWN_IMMEDIATELY_ON_BEGIN_PLAY = SpawnCfg.immediateFirst

local DEFAULT_CHARACTER_ID = SpawnCfg.defaultRagdollId or "blue-speedster"
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
        "RagdollData",
        "Data.RagdollData",
        "Data/RagdollData",
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
        if type(id) == "string" and id ~= "" and is_spawnable_config(config) then
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

local function pick_random_character_entry()
    local candidates, totalWeight = build_spawn_candidates()

    if candidates == nil or #candidates <= 0 or totalWeight <= 0.0 then
        print("[GOIncRagdollSpawnManager] No spawnable character entries. Fallback: " .. DEFAULT_CHARACTER_ID)
        return {
            id = DEFAULT_CHARACTER_ID,
            displayName = DEFAULT_CHARACTER_ID,
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

    if GOInc == nil or GOInc.SpawnRagdollCharacter == nil then
        print("[GOIncRagdollSpawnManager] Missing GOInc.SpawnRagdollCharacter binding")
        return nil
    end

    local entry = pick_random_character_entry()
    local characterId = entry.id
    local location = make_random_spawn_location()
    local pawn = GOInc.SpawnRagdollCharacter(characterId, location)

    if pawn == nil then
        print("[GOIncRagdollSpawnManager] Failed to spawn ragdoll character: " .. tostring(characterId))
        return nil
    end

    spawnedCount = spawnedCount + 1
    spawnedPawns[spawnedCount] = pawn

    print(string.format(
        "[GOIncRagdollSpawnManager] Spawned %s (%s) at (%.2f, %.2f, %.2f) [%d / %d]",
        tostring(characterId),
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
