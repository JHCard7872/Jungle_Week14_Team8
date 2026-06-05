-- ==========================================================================
-- ScoreManager — 점수 규칙 (require 모듈)
-- [역할] 수거 점수 계산만: baseScore × 금/은 배수 → Session.score에 쓴다.
--        수거 카운트(result.collectedCount)도 여기서만 올린다.
-- [사용법] 수거 시 CollectionZoneBehavior가 AddForRagdoll(actor) 호출,
--          MissionManager가 달성 보너스로 AddBonus(n) 호출.
-- [특이사항] Session에 공유 값을 저장하지 않는다 — GetScore() 같은 건 없고
--            HUD는 Session.score를 직독한다. 타입 판별 헬퍼 FindType은
--            MissionManager도 재사용한다.
-- ==========================================================================

local Session  = require("GameSession")
local Ragdolls = require("Data/RagdollData")
local Score    = require("Data/ScoreData")

local M = {}

-- 모듈은 씬을 넘어 살아남으므로 매 판 호출 (지금은 리셋할 내부 상태가 없지만 공통 규약)
function M.Start()
end

-- 액터의 태그 중 RagdollData 키와 일치하는 첫 타입을 반환. 없으면 nil
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

    Session.score = Session.score + math.floor(points)
    Session.result.collectedCount = Session.result.collectedCount + 1
end

function M.AddBonus(n)
    Session.score = Session.score + n
end

return M
