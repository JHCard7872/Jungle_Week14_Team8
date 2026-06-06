-- GOIncRagdollSpawnManager.lua
--
-- Interval/max-count based GOInc ragdoll character spawner.
-- Requires:
--   GOInc.SpawnRagdollCharacter(characterId, location)
--
-- Character-specific mesh/physics/animation settings live in C++ Pawn subclasses.
-- This manager only owns spawn policy: id, displayName, weight, interval, count, location.

local SPAWN_MIN_X = -10.0
local SPAWN_MAX_X = 10.0
local SPAWN_MIN_Y = -10.0
local SPAWN_MAX_Y = 10.0
local SPAWN_Z = 1.0

local SPAWN_INTERVAL = 2.0
local MAX_SPAWN_COUNT = 10
local SPAWN_IMMEDIATELY_ON_BEGIN_PLAY = true

local DEFAULT_CHARACTER_ID = "blue-speedster"

-- 캐릭터별 mesh/physics/animation 데이터는 각 C++ Pawn subclass가 가진다.
-- SpawnManager는 어떤 characterId를 어떤 weight로 뽑을지만 관리한다.
local SpawnTable = {
    {
        id = "blue-speedster",
        displayName = "파란 고슴도치",
        weight = 10.0,
        canSpawn = true,
    },
    {
        id = "pink-round",
        displayName = "분홍 동글이",
        weight = 8.0,
        canSpawn = true,
    },
}

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

local function is_spawnable_entry(entry)
    if type(entry) ~= "table" then
        return false
    end

    if entry.canSpawn == false then
        return false
    end

    if type(entry.id) ~= "string" or entry.id == "" then
        return false
    end

    return number_or(entry.weight, 0.0) > 0.0
end

local function build_spawn_candidates()
    local candidates = {}
    local totalWeight = 0.0

    for _, entry in ipairs(SpawnTable) do
        if is_spawnable_entry(entry) then
            local weight = number_or(entry.weight, 0.0)
            totalWeight = totalWeight + weight

            table.insert(candidates, {
                id = entry.id,
                displayName = entry.displayName or entry.id,
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
