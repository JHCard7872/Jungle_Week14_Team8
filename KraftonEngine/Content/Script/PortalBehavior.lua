-- ==========================================================================
-- PortalBehavior — 소환 포탈 (ASummonPortalActor의 LuaScriptComponent에 부착)
-- [역할] (1) 미션이 새로 발급될 때마다(Session.mission.seq 변화) PortalData 좌표 중
--        하나로 재배치. (2) "Ragdoll" 태그 액터가 트리거에 닿으면 수거 —
--        점수/미션 통보 후 흡수. 미션 카운트는 포탈에서만 한다(수거함은 점수만).
-- [사용법] ASummonPortalActor가 InitDefaultComponents에서 자동 부착하고,
--          판 시작 시 GOInc.SpawnSummonPortal()로 1개 코드 스폰된다(수동 배치 없음).
-- ==========================================================================

local ScoreMgr     = require("Manager/ScoreManager")
local MissionMgr   = require("Manager/MissionManager")
local UserSettings = require("Data/UserSettings")
local ParticleFX   = require("ParticleFX")
local Session      = require("GameSession")
local Portal       = require("Data/PortalData")

local lastSeq = 0   -- 마지막으로 반영한 미션 발급 시퀀스 — 변하면 재배치
-- 흡수 축소 연출 토글. ⚠️ false 고정: true면 ShrinkAndDestroy가 시뮬레이션된 래그돌을 스케일하다
-- 엔진을 세그폴트시킨다(연속 흡수 시). false면 물리 정지 + 파티클 + 즉시 Destroy(안정). 비스케일
-- 축소 연출이 마련되면 그때 켤 것 — 지금 true로 바꾸면 크래시한다.
local USE_SHRINK = false

local function pickAndMove()
    local c = Portal.spawnPositions[math.random(#Portal.spawnPositions)]
    obj.Location = Vector.new(c.x, c.y, c.z)
end

-- 흡수 축소 코루틴. ⚠️ 현재 USE_SHRINK=false로 비활성. 시뮬레이션된 래그돌 액터를 스케일하면
-- (a.Scale = SetActorScale, 루트 변환이라도) 엔진이 세그폴트한다 — 첫 흡수는 통과하나 연속
-- 흡수에서 죽음(ragdoll 물리 바디 스케일 취약성, 메모리 ragdoll-scale-bug 계열). 스케일 대신
-- 포탈로 가라앉히는 등 비스케일 연출이 생기기 전까지 호출 금지. yield 전후 IsValid로 소멸 가드.
local function ShrinkAndDestroy(a)
    local t = 0.0
    while t < Portal.shrinkDuration do
        if not a or not a:IsValid() then return end
        local dt = WaitFrame()
        t = t + dt
        if not a or not a:IsValid() then return end   -- yield 직후 재검증(프레임 사이 소멸 가드)
        local f = math.min(t / Portal.shrinkDuration, 1.0)
        local s = 1.0 + (Portal.shrinkTargetRatio - 1.0) * f   -- 1.0 → 0.1 선형 보간
        a.Scale = Vector.new(s, s, s)
    end
    if a and a:IsValid() then a:Destroy() end
end

function BeginPlay()
    -- 트리거 박스 설정 검증 — GenerateOverlapEvents가 꺼져 있으면 OnOverlap이
    -- 바인딩되지 않아 수거가 조용히 죽는다 (씬 설정 실수를 조기에 드러냄)
    local hasTrigger = false
    for _, comp in pairs(obj:GetPrimitiveComponents()) do
        if comp:GetGenerateOverlapEvents() then
            hasTrigger = true
            break
        end
    end
    if not hasTrigger then
        print("[Portal] 경고: GenerateOverlapEvents=true인 컴포넌트가 없음 — 수거 트리거가 동작하지 않음")
    end

    lastSeq = (Session.mission and Session.mission.seq) or 0
    pickAndMove()   -- 스폰 직후 첫 배치
end

-- 미션이 새로 발급되면(seq 변화) 다른 좌표로 순간이동. 프레임당 정수 비교 1회.
function Tick(dt)
    local s = (Session.mission and Session.mission.seq) or 0
    if s ~= lastSeq then
        lastSeq = s
        pickAndMove()
    end
end

-- 수거: "Ragdoll" 태그 액터만. 래그돌은 본마다 셰입이라 같은 액터로 중복 이벤트가
-- 올 수 있다 — 첫 처리에서 태그를 떼면 다음 이벤트는 HasTag에서 걸러진다.
-- (FindType/AddForRagdoll은 타입 태그를 읽으므로 "Ragdoll"을 먼저 떼도 안전)
function OnOverlap(other_actor, overlapped_component, other_comp)
    if not other_actor or not other_actor:IsValid() then return end
    if not other_actor:HasTag("Ragdoll") then return end

    other_actor:RemoveTag("Ragdoll")          -- 중복 이벤트·타 수거함 재수거 차단 (맨 먼저)
    ScoreMgr.AddForRagdoll(other_actor)
    MissionMgr.NotifyRecovered(other_actor)   -- 타입 태그를 읽으므로 Destroy 전에 호출
    AudioManager.Play("sfx_collect", UserSettings.GetSfxVolumeScalar())

    -- 물리 정지 — 축소 전 필수. 정지 안 하면 컨스트레인트가 스케일 변화와 싸워 폭발한다.
    local pawn = nil
    if other_actor.AsGOIncRagdollPawn ~= nil then pawn = other_actor:AsGOIncRagdollPawn() end
    local mesh = pawn and pawn:GetRagdollMeshComponent() or nil
    if mesh then mesh:SetAllBodiesSimulatePhysics(false) end

    ParticleFX.Burst(Portal.collectFxPath, other_actor.Location, Portal.collectFxLife) -- Destroy 전 위치 읽기

    -- 축소 흡수: 물리 정지 후 액터 루트 스케일만 보간해 줄이고 소멸. 폭발 시 USE_SHRINK=false 폴백.
    if USE_SHRINK and mesh then
        StartCoroutine(function() ShrinkAndDestroy(other_actor) end)
    else
        other_actor:Destroy()                 -- 트리거 디스패치 중 Destroy 안전 (엔진 보장)
    end
end
