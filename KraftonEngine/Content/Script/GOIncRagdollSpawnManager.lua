-- GOIncRagdollSpawnManager.lua
--
-- Interval/max-count based GOInc ragdoll character spawner.
-- Requires:
--   GOInc.SpawnRagdollCharacter(characterId, location)
--
-- Character-specific mesh/physics/animation/capsule/movement settings live in C++ Pawn subclasses.
-- RagdollData.lua is used here only as a catalog for spawn policy:
--   id, displayName, canSpawn, spawnWeight, pawnClass.
-- spawnWeight <= 0 means the entry will not spawn.
-- canSpawn must be true to spawn.
-- pawnClass must be non-empty to spawn.
-- MAX_SPAWN_COUNT limits ALIVE pawns, not total spawns — collected (destroyed) pawns free their slot.

local SpawnCfg = require("Data.GameConfig").spawn
local Score = require("Data.ScoreData")

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
local bPrintedSpawnCandidateSummary = false
local loggedUnregisteredCharacterIds = {}

local function number_or(value, fallback)
    if type(value) == "number" then
        return value
    end
    return fallback
end

local function string_or(value, fallback)
    if type(value) == "string" and value ~= "" then
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

    local ok, result = pcall(require, "Data.RagdollData")
    if ok and result ~= nil then
        RagdollData = result
        print("[GOIncRagdollSpawnManager] Loaded Data.RagdollData")
        return RagdollData
    end

    print("[GOIncRagdollSpawnManager] Failed to load Data.RagdollData")
    return nil
end

local function resolve_character_id(tableKey, config)
    local configId = nil
    if type(config) == "table" then
        configId = string_or(config.id, nil)
    end

    return string_or(configId, tableKey)
end

local function is_spawnable_config(config)
    if type(config) ~= "table" then
        return false
    end

    if config.canSpawn ~= true then
        return false
    end

    if string_or(config.pawnClass, "") == "" then
        return false
    end

    return number_or(config.spawnWeight, 0.0) > 0.0
end

local function is_character_registered(characterId)
    if GOInc == nil or GOInc.IsRagdollCharacterRegistered == nil then
        return true
    end

    local ok, result = pcall(GOInc.IsRagdollCharacterRegistered, characterId)
    if not ok then
        print("[GOIncRagdollSpawnManager] GOInc.IsRagdollCharacterRegistered failed for " .. tostring(characterId))
        return false
    end

    return result == true
end

local function print_unregistered_character_once(characterId, pawnClass)
    local key = tostring(characterId)
    if loggedUnregisteredCharacterIds[key] then
        return
    end

    loggedUnregisteredCharacterIds[key] = true
    print(string.format(
        "[GOIncRagdollSpawnManager] Skip unregistered character id: %s (%s)",
        tostring(characterId),
        tostring(pawnClass)))
end

local function sort_spawn_candidates(lhs, rhs)
    local lhsOrder = number_or(lhs.uiOrder, 999999)
    local rhsOrder = number_or(rhs.uiOrder, 999999)

    if lhsOrder ~= rhsOrder then
        return lhsOrder < rhsOrder
    end

    return tostring(lhs.id) < tostring(rhs.id)
end

local function print_spawn_candidate_summary_once(candidates, totalWeight)
    if bPrintedSpawnCandidateSummary then
        return
    end

    bPrintedSpawnCandidateSummary = true
    print(string.format(
        "[GOIncRagdollSpawnManager] Spawn candidates ready: %d entries, totalWeight=%.2f",
        #candidates,
        totalWeight))

    for _, entry in ipairs(candidates) do
        print(string.format(
            "  - %s (%s, %s), weight=%.2f",
            tostring(entry.id),
            tostring(entry.displayName),
            tostring(entry.pawnClass),
            entry.weight))
    end
end

local function build_spawn_candidates()
    local data = load_ragdoll_data()
    if data == nil then
        return nil, 0.0
    end

    local candidates = {}
    local totalWeight = 0.0

    for tableKey, config in pairs(data) do
        if type(tableKey) == "string" and tableKey ~= "" and is_spawnable_config(config) then
            local characterId = resolve_character_id(tableKey, config)
            local weight = number_or(config.spawnWeight, 0.0)

            if is_character_registered(characterId) then
                totalWeight = totalWeight + weight

                table.insert(candidates, {
                    id = characterId,
                    displayName = config.displayName or characterId,
                    pawnClass = config.pawnClass,
                    weight = weight,
                    uiOrder = config.uiOrder,
                })
            else
                print_unregistered_character_once(characterId, config.pawnClass)
            end
        end
    end

    table.sort(candidates, sort_spawn_candidates)
    print_spawn_candidate_summary_once(candidates, totalWeight)

    return candidates, totalWeight
end

local function pick_random_character_entry()
    local candidates, totalWeight = build_spawn_candidates()

    if candidates == nil or #candidates <= 0 or totalWeight <= 0.0 then
        print("[GOIncRagdollSpawnManager] No spawnable registered character entries. Fallback: " .. DEFAULT_CHARACTER_ID)

        if not is_character_registered(DEFAULT_CHARACTER_ID) then
            print("[GOIncRagdollSpawnManager] Default character id is not registered: " .. tostring(DEFAULT_CHARACTER_ID))
            return nil
        end

        return {
            id = DEFAULT_CHARACTER_ID,
            displayName = DEFAULT_CHARACTER_ID,
            pawnClass = "",
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

-- 수거(Destroy)된 폰을 목록에서 걷어내 spawnedCount를 "살아있는 수"로 유지한다.
-- 자리가 비면 다시 스폰 가능 — 안 하면 누적 10마리 이후 스폰이 영구 정지한다.
local function prune_dead_pawns()
    for i = #spawnedPawns, 1, -1 do
        local pawn = spawnedPawns[i]
        if pawn == nil or (pawn.IsValid ~= nil and not pawn:IsValid()) then
            table.remove(spawnedPawns, i)
        end
    end

    spawnedCount = #spawnedPawns

    -- 자리가 다시 비었으면 "max reached" 안내도 다음 만석 때 다시 찍히게 리셋
    if MAX_SPAWN_COUNT > 0 and spawnedCount < MAX_SPAWN_COUNT then
        bPrintedMaxSpawnReached = false
    end
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
    if entry == nil then
        return nil
    end

    local characterId = entry.id
    if not is_character_registered(characterId) then
        print("[GOIncRagdollSpawnManager] Selected character id is not registered: " .. tostring(characterId))
        return nil
    end

    local location = make_random_spawn_location()
    local pawn = GOInc.SpawnRagdollCharacter(characterId, location)

    if pawn == nil then
        print("[GOIncRagdollSpawnManager] Failed to spawn ragdoll character: " .. tostring(characterId))
        return nil
    end

    table.insert(spawnedPawns, pawn)
    spawnedCount = #spawnedPawns

    -- 점수/미션 식별용 타입 태그 — ScoreManager.FindType이 RagdollData 키와 일치하는
    -- 태그를 찾는다. C++ 생성자는 "Ragdoll" 태그만 달아주므로 타입 태그는 여기서 단다.
    if pawn.AddTag ~= nil then
        pawn:AddTag(characterId)
    else
        print("[GOIncRagdollSpawnManager] Missing AddTag binding — score/mission type tag disabled")
    end

    -- 금/은 변형 추첨 — Gold/Silver 태그만 달면 ScoreManager가 배수(×3/×2)를 자동 적용한다.
    -- 머티리얼 바인딩이 없는 구버전 빌드면 태그도 달지 않는다 (비주얼 없는 배수는 혼란만 줌)
    if pawn.AddTag ~= nil and GOInc.SetRagdollOverrideMaterial ~= nil then
        local roll = math.random()
        if roll < Score.goldChance then
            pawn:AddTag("Gold")
            GOInc.SetRagdollOverrideMaterial(pawn, "Content/Material/Gold.mat")
            print("[GOIncRagdollSpawnManager] Variant: Gold " .. tostring(characterId))
        elseif roll < Score.goldChance + Score.silverChance then
            pawn:AddTag("Silver")
            GOInc.SetRagdollOverrideMaterial(pawn, "Content/Material/Silver.mat")
            print("[GOIncRagdollSpawnManager] Variant: Silver " .. tostring(characterId))
        end
    end

    print(string.format(
        "[GOIncRagdollSpawnManager] Spawned %s (%s, %s) at (%.2f, %.2f, %.2f) [%d / %d]",
        tostring(characterId),
        tostring(entry.displayName),
        tostring(entry.pawnClass),
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
    bPrintedSpawnCandidateSummary = false
    loggedUnregisteredCharacterIds = {}

    if SPAWN_IMMEDIATELY_ON_BEGIN_PLAY then
        spawn_one()
    end
end

function Tick(deltaTime)
    prune_dead_pawns()

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
