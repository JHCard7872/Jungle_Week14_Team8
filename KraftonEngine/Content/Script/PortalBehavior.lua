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

local function pickAndMove()
    local c = Portal.spawnPositions[math.random(#Portal.spawnPositions)]
    obj.Location = Vector.new(c.x, c.y, c.z)
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
    ParticleFX.Burst(Portal.collectFxPath, other_actor.Location, Portal.collectFxLife) -- Destroy 전 위치 읽기
    other_actor:Destroy()                     -- 트리거 디스패치 중 Destroy 안전 (엔진 보장)
end
