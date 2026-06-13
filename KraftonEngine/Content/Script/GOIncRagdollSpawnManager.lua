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
local Session = require("GameSession")

local SPAWN_INTERVAL = SpawnCfg.interval
local MAX_SPAWN_COUNT = SpawnCfg.maxCount
local SPAWN_IMMEDIATELY_ON_BEGIN_PLAY = SpawnCfg.immediateFirst
local SPAWN_AREA_TAG = SpawnCfg.spawnAreaTag or "GOIncSpawnArea"
local MAX_LOCATION_RETRY = SpawnCfg.maxLocationRetry or 10
local MIN_DISTANCE_BETWEEN_SPAWNS = SpawnCfg.minDistanceBetweenSpawns or 0.0

local SPAWN_NEAR_PLAYER = SpawnCfg.spawnNearPlayer == true
local NEAR_PLAYER_SAMPLE_COUNT = SpawnCfg.nearPlayerSampleCount or 16
local PLAYER_TAG = SpawnCfg.playerTag or "Player"

local DEFAULT_CHARACTER_ID = SpawnCfg.defaultRagdollId or "blue-speedster"
local RagdollData = nil

local spawnTimer = 0.0
local spawnedCount = 0
local totalSpawnedEver = 0
local spawnedPawns = {}
local spawnAreas = {}
local spawnAreaWeights = {}
local spawnAreaTotalWeight = 0.0
local bPrintedMaxSpawnReached = false
local bPrintedNoSpawnAreas = false
local bPrintedSpawnCandidateSummary = false
local loggedUnregisteredCharacterIds = {}
local bImmediateSpawnPending = false

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

-- 박스의 XY 바닥 면적을 가중치로 쓴다 (스폰은 XY 범위만 사용 — GameLuaBindings MakeRandomPointInBoxComponent).
-- GetScaledBoxExtent()는 월드 반경(half-size)이므로 면적 ∝ extentX * extentY. 상수배는 상대가중에 무의미해 생략.
-- 크기를 못 구하면 1.0으로 폴백해 균등 선택으로 동작한다.
local function spawn_area_weight(box)
    if box == nil or box.GetScaledBoxExtent == nil then
        return 1.0
    end

    local ok, extent = pcall(function() return box:GetScaledBoxExtent() end)
    if not ok or extent == nil then
        return 1.0
    end

    local area = math.abs(number_or(extent.X, 0.0)) * math.abs(number_or(extent.Y, 0.0))
    if area <= 0.0 then
        return 1.0
    end

    return area
end

local function cache_spawn_area_boxes()
    spawnAreas = {}
    spawnAreaWeights = {}
    spawnAreaTotalWeight = 0.0
    bPrintedNoSpawnAreas = false

    if GOInc == nil or GOInc.FindSpawnAreaBoxes == nil then
        print("[GOIncRagdollSpawnManager] Missing GOInc.FindSpawnAreaBoxes binding")
        return
    end

    local ok, boxes = pcall(GOInc.FindSpawnAreaBoxes, SPAWN_AREA_TAG)
    if not ok or boxes == nil then
        print("[GOIncRagdollSpawnManager] Failed to find spawn area boxes. Tag=" .. tostring(SPAWN_AREA_TAG))
        return
    end

    for _, box in ipairs(boxes) do
        if box ~= nil then
            local weight = spawn_area_weight(box)
            table.insert(spawnAreas, box)
            table.insert(spawnAreaWeights, weight)
            spawnAreaTotalWeight = spawnAreaTotalWeight + weight
        end
    end

    print(string.format(
        "[GOIncRagdollSpawnManager] Cached %d spawn area box(es). Tag=%s totalAreaWeight=%.2f",
        #spawnAreas,
        tostring(SPAWN_AREA_TAG),
        spawnAreaTotalWeight))
end

local function print_no_spawn_areas_once()
    if bPrintedNoSpawnAreas then
        return
    end

    bPrintedNoSpawnAreas = true
    print(string.format(
        "[GOIncRagdollSpawnManager] No spawn area boxes cached. Place an Actor with Tag='%s' and at least one BoxComponent.",
        tostring(SPAWN_AREA_TAG)))
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

local function is_location_far_enough(location)
    local minDistance = number_or(MIN_DISTANCE_BETWEEN_SPAWNS, 0.0)
    if minDistance <= 0.0 then
        return true
    end

    local minDistanceSq = minDistance * minDistance

    for _, pawn in ipairs(spawnedPawns) do
        if pawn ~= nil and (pawn.IsValid == nil or pawn:IsValid()) then
            local pawnLocation = pawn.Location
            if pawnLocation ~= nil then
                local dx = location.X - pawnLocation.X
                local dy = location.Y - pawnLocation.Y
                local dz = location.Z - pawnLocation.Z
                local distSq = dx * dx + dy * dy + dz * dz
                if distSq < minDistanceSq then
                    return false
                end
            end
        end
    end

    return true
end

local function pick_random_spawn_area()
    local count = #spawnAreas
    if count <= 0 then
        print_no_spawn_areas_once()
        return nil
    end

    -- 면적 비례 가중 선택 — 넓은 박스일수록 더 자주 뽑혀 단위 면적당 스폰 밀도가 균일해진다.
    -- 가중치가 없거나(모두 폴백) 합이 0이면 균등 선택으로 폴백.
    if spawnAreaTotalWeight > 0.0 then
        local roll = random_range(0.0, spawnAreaTotalWeight)
        local accumulated = 0.0
        for i = 1, count do
            accumulated = accumulated + (spawnAreaWeights[i] or 0.0)
            if roll <= accumulated then
                return spawnAreas[i]
            end
        end
        return spawnAreas[count]
    end

    local index = math.random(1, count)
    return spawnAreas[index]
end

-- 플레이어 액터를 태그로 찾아 위치를 반환. 근처 스폰이 꺼져 있거나 못 찾으면 nil.
local function get_player_location()
    if not SPAWN_NEAR_PLAYER then
        return nil
    end

    if World == nil or World.FindFirstActorByTag == nil then
        return nil
    end

    local ok, player = pcall(World.FindFirstActorByTag, PLAYER_TAG)
    if not ok or player == nil then
        return nil
    end

    if player.IsValid ~= nil and not player:IsValid() then
        return nil
    end

    return player.Location
end

-- 스폰 구역(면적 가중) 한 곳에서 점 하나를 샘플링. 실패하면 nil.
local function sample_one_spawn_point()
    local area = pick_random_spawn_area()
    if area == nil then
        return nil
    end

    if GOInc == nil or GOInc.GetRandomPointInSpawnAreaBox == nil then
        print("[GOIncRagdollSpawnManager] Missing GOInc.GetRandomPointInSpawnAreaBox binding")
        return nil
    end

    local ok, location = pcall(GOInc.GetRandomPointInSpawnAreaBox, area)
    if not ok or location == nil then
        return nil
    end

    return location
end

local function distance_sq_xy(a, b)
    local dx = a.X - b.X
    local dy = a.Y - b.Y
    return dx * dx + dy * dy
end

local function make_random_spawn_location()
    local retryCount = math.max(1, number_or(MAX_LOCATION_RETRY, 10))
    local playerLoc = get_player_location()

    -- 플레이어 위치를 모르면(근처 스폰 off / 미발견) 기존 동작: 최소거리 만족하는 첫 점.
    if playerLoc == nil then
        for _ = 1, retryCount do
            local location = sample_one_spawn_point()
            if location ~= nil and is_location_far_enough(location) then
                return location
            end
        end

        print(string.format(
            "[GOIncRagdollSpawnManager] Failed to find a non-overlapping spawn location after %d attempt(s).",
            retryCount))
        return nil
    end

    -- 플레이어 근처 우선: 후보 N개를 뽑아 최소거리 제약을 만족하는 것 중
    -- 플레이어에게 가장 가까운 점을 고른다. (제약 만족 후보가 없으면 스폰 보류 — 겹침 방지)
    local sampleCount = math.max(1, number_or(NEAR_PLAYER_SAMPLE_COUNT, 16))
    local bestLocation = nil
    local bestDistSq = nil

    for _ = 1, sampleCount do
        local location = sample_one_spawn_point()
        if location ~= nil and is_location_far_enough(location) then
            local distSq = distance_sq_xy(location, playerLoc)
            if bestDistSq == nil or distSq < bestDistSq then
                bestDistSq = distSq
                bestLocation = location
            end
        end
    end

    if bestLocation ~= nil then
        return bestLocation
    end

    print(string.format(
        "[GOIncRagdollSpawnManager] Failed to find a non-overlapping spawn location near player after %d sample(s).",
        sampleCount))
    return nil
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
    if location == nil then
        return nil
    end

    local pawn = GOInc.SpawnRagdollCharacter(characterId, location)

    if pawn == nil then
        print("[GOIncRagdollSpawnManager] Failed to spawn ragdoll character: " .. tostring(characterId))
        return nil
    end

    table.insert(spawnedPawns, pawn)
    spawnedCount = #spawnedPawns
    totalSpawnedEver = totalSpawnedEver + 1

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
        "[GOIncRagdollSpawnManager] Spawned %s (%s, %s) at (%.2f, %.2f, %.2f) [active=%d / %d, total=%d]",
        tostring(characterId),
        tostring(entry.displayName),
        tostring(entry.pawnClass),
        location.X, location.Y, location.Z,
        spawnedCount,
        MAX_SPAWN_COUNT,
        totalSpawnedEver))

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
    totalSpawnedEver = 0
    spawnedPawns = {}
    spawnAreas = {}
    spawnAreaWeights = {}
    spawnAreaTotalWeight = 0.0
    bPrintedMaxSpawnReached = false
    bPrintedNoSpawnAreas = false
    bPrintedSpawnCandidateSummary = false
    loggedUnregisteredCharacterIds = {}
    bImmediateSpawnPending = SPAWN_IMMEDIATELY_ON_BEGIN_PLAY

    cache_spawn_area_boxes()

    if bImmediateSpawnPending and Session.inputEnabled == true then
        spawn_one()
        bImmediateSpawnPending = false
    end
end

function Tick(deltaTime)
    if Session.inputEnabled ~= true then
        return
    end

    if bImmediateSpawnPending then
        spawn_one()
        bImmediateSpawnPending = false
    end

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
