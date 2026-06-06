-- ==========================================================================
-- ScoreManager — 점수 규칙 (require 모듈)
-- [역할] 수거 점수 계산만: baseScore × 금/은 배수 → Session.score에 쓴다.
--        수거 카운트(result.collectedCount)도 여기서만 올린다.
--        결과 화면용 분리 집계도 담당: 수거 점수 → result.baseScore,
--        미션 보너스 → result.urgentScore (총점 = base + urgent).
-- [사용법] 수거 시 TruckBehavior가 AddForRagdoll(actor) 호출,
--          MissionManager가 달성 보너스로 AddBonus(n) 호출.
-- [특이사항] Session에 공유 값을 저장하지 않는다 — GetScore() 같은 건 없고
--            HUD는 Session.score를 직독한다. 타입 판별 헬퍼 FindType은
--            MissionManager도 재사용한다.
--            FindType은 스폰 시 GOIncRagdollSpawnManager가 달아준 타입 태그
--            (RagdollData 키)를 전제한다 — 태그가 없으면 점수/카운트 없이
--            조용히 스킵되니, 점수가 0으로 멈춰 보이면 이 태그부터 의심할 것.
--            금/은 배수는 "Gold"/"Silver" 태그가 달린 액터만 적용 — 추첨해서
--            태그를 다는 쪽은 아직 미구현이라 실스폰에서는 발동하지 않는다.
-- ==========================================================================

local Session  = require("GameSession")
local Ragdolls = require("Data/RagdollData")
local Score    = require("Data/ScoreData")

local M = {}

-- 모듈은 씬을 넘어 살아남으므로 매 판 호출 (지금은 리셋할 내부 상태가 없지만 공통 규약)
function M.Start()
end

-- 액터의 태그 중 RagdollData 키와 일치하는 첫 타입을 반환. 없으면 nil
-- (타입 태그는 스폰 시 GOIncRagdollSpawnManager가 단다)
function M.FindType(actor)
    for id, data in pairs(Ragdolls) do
        if actor:HasTag(id) then
            return id, data
        end
    end
    return nil, nil
end

-- 수거 점수: 타입 baseScore × (Gold/Silver 태그면 배수)
function M.AddForRagdoll(actor)
    local _, data = M.FindType(actor)
    if not data then return end   -- 타입 태그 없는 액터는 점수 없음

    local points = data.baseScore
    if actor:HasTag("Gold") then
        points = points * Score.goldMultiplier
    elseif actor:HasTag("Silver") then
        points = points * Score.silverMultiplier
    end

    points = math.floor(points)
    Session.score = Session.score + points
    Session.result.baseScore = Session.result.baseScore + points
    Session.result.collectedCount = Session.result.collectedCount + 1
end

-- 미션 보너스 — 결과 화면의 "긴급 요청 처리 실적"으로 집계된다
function M.AddBonus(n)
    Session.score = Session.score + n
    Session.result.urgentScore = Session.result.urgentScore + n
end

return M
