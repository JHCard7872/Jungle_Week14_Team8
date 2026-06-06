-- =============================================================================
-- MissionManager — 미션 발급/추적/완료 (require 모듈)
-- [역할] 임계치 방식 미션의 전부. 미션 상태(current)는 이 모듈이 소유한다 —
--        HUD는 GetCurrent()로 읽기만 (Session에 미션 필드 없음).
-- [사용법] PlayScene.BeginPlay에서 Start().
--          수거 시 TruckBehavior가 NotifyRecovered(actor) 호출.
--          HUD: local m = MissionManager.GetCurrent() → m.text, m.got, m.need
--          (HUD 연결은 아직 미구현 — 현재 GetCurrent 소비처는 Test 스크립트뿐이라
--           미션은 화면에 안 보이고, 달성 시 점수 증가로만 관측된다)
-- [특이사항] 발급 규칙(달성 불가능한 미션 방지):
--            1순위 — 살아있는 수 >= minCount인 타입 중 랜덤, 목표 = minCount
--            2순위 — 충족 타입이 없으면 최다 보유 타입, 목표 = 그 보유 수
--            한 마리도 없으면 발급 보류(nil) — 다음 수거 때 재시도.
--            즉 판 시작 직후 스폰 전이면 미션 없이 시작하고, 첫 수거에서 발급된다.
--            달성 시 보상 = 목표 수 × MissionData.rewardPerBody — AddBonus로 지급되어
--            결과 화면의 "긴급 요청 처리 실적"(result.urgentScore)으로 집계. 즉시 재발급.
--            집계(countAlive)와 진행 판정 모두 타입 태그 기반 —
--            태그는 스폰 시 GOIncRagdollSpawnManager가 단다 (없으면 미션이 영영 보류됨).
-- =============================================================================

local Ragdolls = require("Data/RagdollData")
local Mission  = require("Data/MissionData")
local ScoreMgr = require("Manager/ScoreManager")

local M = {}
local current = nil   -- { target, need, got, text } / 발급 보류면 nil

-- 살아있는 래그돌을 타입별로 집계 (스폰 매니저가 단 타입 태그 기준)
local function countAlive()
    local counts = {}
    local list = World.FindActorsByTag("Ragdoll")
    if list then
        for _, actor in pairs(list) do
            local id = ScoreMgr.FindType(actor)
            if id then counts[id] = (counts[id] or 0) + 1 end
        end
    end
    return counts
end

function M.Start()
    current = nil
    M.IssueNext()
end

function M.IssueNext()
    local counts = countAlive()

    -- 1순위: minCount 이상 보유한 타입들 중 랜덤
    local candidates = {}
    for id, n in pairs(counts) do
        if n >= Mission.minCount then
            candidates[#candidates + 1] = id
        end
    end

    local target, need
    if #candidates > 0 then
        target = candidates[math.random(#candidates)]
        need   = Mission.minCount
    else
        -- 2순위: 최다 보유 타입을 보유 수만큼
        local bestId, bestN = nil, 0
        for id, n in pairs(counts) do
            if n > bestN then bestId, bestN = id, n end
        end
        if not bestId then
            current = nil   -- 래그돌이 한 마리도 없음 — 보류
            return
        end
        target, need = bestId, bestN
    end

    current = {
        target = target,
        need   = need,
        got    = 0,
        text   = string.format("%s %d체 수거", Ragdolls[target].displayName, need),
    }
end

function M.NotifyRecovered(actor)
    if not current then
        M.IssueNext()   -- 보류 상태였다면 재시도 — 이번 수거는 새 미션에 세지 않는다
        return
    end

    local id = ScoreMgr.FindType(actor)
    if id ~= current.target then return end

    current.got = current.got + 1
    if current.got >= current.need then
        ScoreMgr.AddBonus(current.need * Mission.rewardPerBody)
        -- TODO: 미션 달성 사운드 키가 AudioData에 추가되면 여기서 재생
        M.IssueNext()
    end
end

-- HUD 전용 읽기 getter (쓰지 말 것)
function M.GetCurrent()
    return current
end

return M
