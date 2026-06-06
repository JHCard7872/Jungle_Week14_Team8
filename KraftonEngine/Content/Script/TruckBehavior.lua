-- ==========================================================================
-- TruckBehavior — 수거 트럭 (트럭 액터의 LuaScriptComponent에 부착)
-- [역할] waitTime 대기 ↔ 트랙 1회 순회를 반복하며 엔진음 루프를 재생한다.
--        순회는 달리면서 조향 — 항상 전진 + yaw 회전만, 후진 없음.
--        트리거 박스에 "Ragdoll" 태그 액터가 닿으면 수거 —
--        점수/미션 통보 후 Destroy (매니저 주석의 CollectionZoneBehavior가 이것).
-- [사용법] 씬의 트럭 액터에 LuaScriptComponent → ScriptFile에 "TruckBehavior.lua"
--          + 자식 UBoxComponent(QueryOnly·Kinematic·GenerateOverlapEvents) 필요
-- [특이사항] TruckData는 매 Tick require — 핫리로드가 캐시를 비우면 저장 즉시
--            트랙 반영 (트랙 미정이라 수시 조절 전제). 이동은 XY 평면만
--            (웨이포인트 Z 무시), 회전은 yaw만 쓴다.
-- ==========================================================================

local ScoreMgr   = require("Manager/ScoreManager")
local MissionMgr = require("Manager/MissionManager")

local state = "wait"        -- "wait" 대기 / "drive" 순회 중
local waitTimer = 0
local wpIndex = 1
local visitCount = 0        -- 이번 순회에서 도착한 웨이포인트 수
local engineStarted = false

-- 각도 차이를 -180~180으로 정규화 (코너에서 짧은 쪽으로 돌기 위함)
local function normalizeAngle(deg)
    while deg > 180 do deg = deg - 360 end
    while deg < -180 do deg = deg + 360 end
    return deg
end

-- 현 위치에서 가장 가까운 웨이포인트 인덱스 (XY 평면)
local function nearestWaypoint(D, pos)
    local best, bestSq = 1, math.huge
    for i, wp in ipairs(D.waypoints) do
        local dx, dy = wp[1] - pos.X, wp[2] - pos.Y
        local sq = dx * dx + dy * dy
        if sq < bestSq then best, bestSq = i, sq end
    end
    return best
end

function BeginPlay()
    state = "wait"
    waitTimer = 0
    wpIndex = 1
    visitCount = 0
    engineStarted = false

    -- 트리거 박스 설정 검증 — GenerateOverlapEvents가 꺼져 있으면 OnOverlap이
    -- 바인딩되지 않아 수거가 조용히 죽는다. 씬 설정 실수를 조기에 드러냄
    local hasTrigger = false
    for _, comp in pairs(obj:GetPrimitiveComponents()) do
        if comp:GetGenerateOverlapEvents() then
            hasTrigger = true
            break
        end
    end
    if not hasTrigger then
        print("[Truck] 경고: GenerateOverlapEvents=true인 컴포넌트가 없음 — 수거 트리거가 동작하지 않음")
    end
end

-- 수거: "Ragdoll" 태그 액터만. 래그돌은 본마다 셰입이라 같은 액터로 중복 이벤트가
-- 올 수 있다 — 첫 처리에서 Destroy되면 다음 이벤트는 IsValid에서 걸러진다
function OnOverlap(other_actor, overlapped_component, other_comp)
    if not other_actor or not other_actor:IsValid() then return end
    if not other_actor:HasTag("Ragdoll") then return end

    ScoreMgr.AddForRagdoll(other_actor)
    MissionMgr.NotifyRecovered(other_actor)   -- 태그를 읽으므로 Destroy 전에 호출
    AudioManager.Play("SfxCollect", 1.0)
    other_actor:Destroy()                     -- 트리거 디스패치 중 Destroy 안전 (엔진 보장)
end

function Tick(dt)
    local D = require("Data/TruckData")

    -- 엔진음은 첫 Tick에 시작 — 씬 오케스트레이터 BeginPlay의 AudioData 로드가
    -- 끝난 뒤임을 보장하기 위함 (액터 BeginPlay 순서에 기대지 않는다)
    if not engineStarted then
        engineStarted = true
        AudioManager.PlayLoop("BgmTruck", "TruckLoop", D.engineVolume)
    end

    -- 대기: waitTime 지나면 가장 가까운 웨이포인트의 다음 지점부터 한 바퀴 시작
    if state == "wait" then
        waitTimer = waitTimer + dt
        if waitTimer >= D.waitTime then
            state = "drive"
            visitCount = 0
            wpIndex = nearestWaypoint(D, obj.Location) % #D.waypoints + 1
        end
        return
    end

    local wp = D.waypoints[wpIndex]
    if not wp then return end   -- waypoints가 비어있으면 정지

    local pos = obj.Location
    local toX, toY = wp[1] - pos.X, wp[2] - pos.Y

    -- 도착 판정 (XY 평면) → 다음 웨이포인트. 한 바퀴(#waypoints회 도착) 돌면 대기로
    if math.sqrt(toX * toX + toY * toY) <= D.arriveDistance then
        wpIndex = wpIndex % #D.waypoints + 1
        visitCount = visitCount + 1
        if visitCount >= #D.waypoints then
            state = "wait"
            waitTimer = 0
        end
        return
    end

    -- 조향: 목표 yaw로 turnRate 제한 회전 (Rotation 벡터 = X:Roll, Y:Pitch, Z:Yaw)
    local targetYaw = Math.Atan2(toY, toX) * Math.RadToDeg
    local yaw = obj.Rotation.Z
    local diff = normalizeAngle(targetYaw - yaw)
    local maxStep = D.turnRate * dt
    if diff > maxStep then diff = maxStep
    elseif diff < -maxStep then diff = -maxStep end
    obj.Rotation = Vector.new(0, 0, yaw + diff)

    -- 전진: 항상 forward 방향 일정속도 (후진 없음)
    obj:AddWorldOffset(obj.Forward * (D.speed * dt))
end

function EndPlay()
    AudioManager.StopLoop("TruckLoop")
end
