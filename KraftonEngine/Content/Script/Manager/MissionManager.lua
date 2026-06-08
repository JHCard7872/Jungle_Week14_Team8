-- =============================================================================
-- MissionManager — 미션 발급/추적/완료 (require 모듈)
-- [역할] 임계치 방식 미션의 전부. 미션 상태(current)는 이 모듈이 소유하고,
--        바뀔 때마다 Session.mission에 캐시를 발행한다 (쓰는 주체 = 이 모듈만).
-- [사용법] PlayScene.BeginPlay에서 Start().
--          수거 시 TruckBehavior가 NotifyRecovered(actor) 호출.
--          HUD: Session.mission 직독 → m.active, m.text, m.got, m.need
--          (Session.score/target과 같은 직독 패턴 — HUD 비주얼 연결은 아직 미구현)
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
local Session  = require("GameSession")
local Timer    = require("Manager/TimerManager")

local M = {}
local current = nil   -- { target, need, got, text } / 발급 보류면 nil
local seq     = 0     -- 발급 시퀀스(단조 증가) — 새 미션이 실제로 만들어질 때만 +1, 포탈이 재배치 트리거로 읽는다

-- current가 바뀔 때마다 호출 — HUD가 직독하는 Session.mission 캐시를 갱신한다
local function publish()
    Session.mission = {
        active = current ~= nil,
        target = current ~= nil and current.target or "",
        need   = current ~= nil and current.need or 0,
        got    = current ~= nil and current.got or 0,
        text   = current ~= nil and current.text or "",
        seq    = seq,
    }
end

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
    -- 재발급은 미션이 비었을 때(클리어/보류)만 1초 주기로 시도 — 활성 중엔 싼 nil 체크만 돈다.
    -- 수거마다 돌던 countAlive() 전체 스캔을 이 스로틀이 대체한다.
    Timer.Every(Mission.reissueInterval, function()
        if not current then M.IssueNext() end
    end)
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
            publish()
            return
        end
        target, need = bestId, bestN
    end

    seq = seq + 1   -- 새 미션 발급 — 보류(nil) 분기는 위에서 이미 return하므로 여기까지 오면 실발급
    current = {
        target = target,
        need   = need,
        got    = 0,
        text   = string.format("%s %d체 수거", Ragdolls[target].displayName, need),
    }
    publish()
end

function M.NotifyRecovered(actor)
    if not current then
        return false   -- 보류 상태 — 재발급은 Start의 1초 주기 타이머가 맡는다(이번 수거는 미션 미집계)
    end

    local id = ScoreMgr.FindType(actor)
    if id ~= current.target then
        return false
    end

    current.got = current.got + 1
    if current.got >= current.need then
        ScoreMgr.AddBonus(current.need * Mission.rewardPerBody)
        -- TODO: 미션 달성 사운드 키가 AudioData에 추가되면 여기서 재생
        current = nil   -- 클리어 — 즉시 재발급하지 않고 1초 주기 타이머에 맡긴다
        publish()
        return true
    end
    publish()
    return false
end

-- HUD 전용 읽기 getter (쓰지 말 것)
function M.GetCurrent()
    return current
end

return M
