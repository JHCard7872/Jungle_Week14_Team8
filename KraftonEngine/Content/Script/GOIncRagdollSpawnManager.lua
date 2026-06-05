-- GOIncRagdollSpawnManager.lua
--
-- First-pass ragdoll spawner.
-- This script intentionally spawns only one pawn in BeginPlay.
-- Patch 3 will expand this into interval/max-count based spawning.

local SPAWN_MIN_X = -10.0
local SPAWN_MAX_X = 10.0
local SPAWN_MIN_Y = -10.0
local SPAWN_MAX_Y = 10.0
local SPAWN_Z = 1.0

local DEFAULT_RAGDOLL_ID = "blue-speedster"

local RagdollData = nil

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

local function pick_random_ragdoll_id()
    local data = load_ragdoll_data()
    if data == nil then
        return DEFAULT_RAGDOLL_ID
    end

    local totalWeight = 0.0
    for _, config in pairs(data) do
        local weight = number_or(config.spawnWeight, 0.0)
        if weight > 0.0 then
            totalWeight = totalWeight + weight
        end
    end

    if totalWeight <= 0.0 then
        print("[GOIncRagdollSpawnManager] No positive spawnWeight. Fallback: " .. DEFAULT_RAGDOLL_ID)
        return DEFAULT_RAGDOLL_ID
    end

    local roll = random_range(0.0, totalWeight)
    local accumulated = 0.0

    for id, config in pairs(data) do
        local weight = number_or(config.spawnWeight, 0.0)
        if weight > 0.0 then
            accumulated = accumulated + weight
            if roll <= accumulated then
                return id
            end
        end
    end

    return DEFAULT_RAGDOLL_ID
end

local function make_random_spawn_location()
    return Vector.new(
        random_range(SPAWN_MIN_X, SPAWN_MAX_X),
        random_range(SPAWN_MIN_Y, SPAWN_MAX_Y),
        SPAWN_Z
    )
end

local function spawn_one()
    if GOInc == nil or GOInc.SpawnRagdollPawn == nil then
        print("[GOIncRagdollSpawnManager] Missing GOInc.SpawnRagdollPawn binding")
        return nil
    end

    local ragdollId = pick_random_ragdoll_id()
    local location = make_random_spawn_location()
    local pawn = GOInc.SpawnRagdollPawn(ragdollId, location)

    if pawn == nil then
        print("[GOIncRagdollSpawnManager] Failed to spawn ragdoll pawn: " .. tostring(ragdollId))
        return nil
    end

    print(string.format(
        "[GOIncRagdollSpawnManager] Spawned %s at (%.2f, %.2f, %.2f)",
        tostring(ragdollId), location.X, location.Y, location.Z))

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

    spawn_one()
end
