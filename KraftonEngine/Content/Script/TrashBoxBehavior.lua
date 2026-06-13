-- ==========================================================================
-- TrashBoxBehavior — 수거함 (AGOIncTrashBox의 LuaScriptComponent에 부착)
-- [역할] 트리거 박스에 "Ragdoll" 태그 액터가 닿으면 수거 — 점수 + 미션 카운트 후 Destroy.
--        포탈이 순간이동 역할로 바뀌면서 미션 카운트는 이제 수거함이 전담한다
--        (수거함에 넣는 것만으로 미션 카운트). 이동 없는 고정형이라 Tick이 없다.
-- [사용법] AGOIncTrashBox가 InitDefaultComponents에서 자동 부착.
--          + 자식 UBoxComponent(QueryOnly·Kinematic·GenerateOverlapEvents) 필요.
--          씬 배치·스케일·트리거 보정은 수거함 담당자가 한다(로직만 여기 둔다).
-- ==========================================================================

local ScoreMgr     = require("Manager/ScoreManager")
local MissionMgr   = require("Manager/MissionManager")
local LoadMgr      = require("Manager/ServerLoadManager")
local UserSettings = require("Data/UserSettings")
local ParticleFX   = require("ParticleFX")
local TrashBox     = require("Data/TrashBoxData")
local HUD          = require("UI/HUDController")

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
        print("[TrashBox] 경고: GenerateOverlapEvents=true인 컴포넌트가 없음 — 수거 트리거가 동작하지 않음")
    end
end

-- 수거: "Ragdoll" 태그 액터만. 래그돌은 본마다 셰입이라 같은 액터로 중복 이벤트가
-- 올 수 있다 — 첫 처리에서 태그를 떼면 다음 이벤트는 HasTag에서 걸러진다(미션 중복 카운트 방지).
-- 점수 + 미션 통보 — 미션 카운트는 이제 수거함이 전담한다(포탈은 순간이동만).
function OnOverlap(other_actor, overlapped_component, other_comp)
    if not other_actor or not other_actor:IsValid() then return end
    if not other_actor:HasTag("Ragdoll") then return end

    other_actor:RemoveTag("Ragdoll")          -- 중복 이벤트·재수거 차단 (맨 먼저)
    ScoreMgr.AddForRagdoll(other_actor)
    -- 미션 대상 타입이면 NotifyRecovered가 카운트한다(아니면 기본 점수만). Destroy 전 호출(타입 태그 읽음).
    local mission_completed = MissionMgr.NotifyRecovered(other_actor)
    if mission_completed then
        HUD.QueuePopup("MISSION COMPLETE")
    else
        HUD.QueuePopup("COLLECTED")
    end
    LoadMgr.ReduceForPortalCollect()          -- 수거 시 서버 부하 경감(수거 지점이 수거함으로 이동)
    AudioManager.Play("sfx_collect", UserSettings.GetSfxVolumeScalar())
    ParticleFX.Burst(TrashBox.collectFxPath, other_actor.Location, TrashBox.collectFxLife) -- Destroy 전 위치 읽기
    other_actor:Destroy()                     -- 트리거 디스패치 중 Destroy 안전 (엔진 보장)
end
