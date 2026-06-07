-- ==========================================================================
-- CollectorBehavior — 래그돌 수거함 (포탈/쓰레기박스 액터의 LuaScriptComponent에 부착)
-- [역할] 트리거 박스에 "Ragdoll" 태그 액터가 닿으면 수거 — 점수/미션 통보 후 Destroy.
--        TruckBehavior의 수거 처리와 동일하되, 이동 없는 고정형이라 Tick이 없다.
-- [사용법] ASummonPortalActor / AGOIncTrashBox가 InitDefaultComponents에서 자동 부착.
--          + 자식 UBoxComponent(QueryOnly·Kinematic·GenerateOverlapEvents) 필요
-- ==========================================================================

local ScoreMgr     = require("Manager/ScoreManager")
local MissionMgr   = require("Manager/MissionManager")
local UserSettings = require("Data/UserSettings")
local ParticleFX   = require("ParticleFX")

local collectFxPath = "Content/Data/Buble.uasset" -- 수거 "뾰로롱" — TruckData와 같은 에셋
local collectFxLife = 1.5                         -- 수거 파티클 자동 정리 수명(초)

function BeginPlay()
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
        print("[Collector] 경고: GenerateOverlapEvents=true인 컴포넌트가 없음 — 수거 트리거가 동작하지 않음")
    end
end

-- 수거: "Ragdoll" 태그 액터만. 래그돌은 본마다 셰입이라 같은 액터로 중복 이벤트가
-- 올 수 있다 — 첫 처리에서 Destroy되면 다음 이벤트는 IsValid에서 걸러진다
function OnOverlap(other_actor, overlapped_component, other_comp)
    if not other_actor or not other_actor:IsValid() then return end
    if not other_actor:HasTag("Ragdoll") then return end

    ScoreMgr.AddForRagdoll(other_actor)
    MissionMgr.NotifyRecovered(other_actor)   -- 태그를 읽으므로 Destroy 전에 호출
    AudioManager.Play("sfx_collect", UserSettings.GetSfxVolumeScalar())
    ParticleFX.Burst(collectFxPath, other_actor.Location, collectFxLife) -- Destroy 전에 위치를 읽는다
    other_actor:Destroy()                     -- 트리거 디스패치 중 Destroy 안전 (엔진 보장)
end
