-- ==========================================================================
-- Test — Phase 1 스모크: 값/상수 모듈 6개 로드 + Session.Reset 검증
-- 사용법: RagdollTest.Scene에서 Play → 콘솔에서 [P1] 줄 확인 (에러 0이어야 함)
-- ==========================================================================

function BeginPlay()
    print("[P1] ---- Phase 1 smoke start ----")

    local Session  = require("GameSession")
    local Config   = require("Data/GameConfig")
    local Ragdolls = require("Data.RagdollData")   -- 점 표기도 확인 (슬래시와 같은 모듈이어야 함)
    local Score    = require("Data/ScoreData")
    local Mission  = require("Data/MissionData")
    local Audio    = require("Data/AudioData")
    print("[P1] require x6 OK")

    Session.Reset(Config.timeLimit)
    print("[P1] Reset: time=" .. Session.timeRemaining .. " score=" .. Session.score
        .. " load=" .. Session.load .. " input=" .. tostring(Session.inputEnabled))
    print("[P1] gun: mode=" .. Session.gun.mode .. " energy=" .. Session.gun.energy)
    print("[P1] result: collected=" .. Session.result.collectedCount
        .. " reason='" .. Session.result.gameOverReason .. "'")

    for id, r in pairs(Ragdolls) do
        print("[P1] ragdoll '" .. id .. "' = " .. r.displayName
            .. " mass=" .. r.mass .. " score=" .. r.baseScore .. " revive=" .. tostring(r.canRevive))
    end

    local audioCount = 0
    for _ in pairs(Audio) do audioCount = audioCount + 1 end
    print("[P1] gold x" .. Score.goldMultiplier .. " / mission min=" .. Mission.minCount
        .. " reward=" .. Mission.rewardScore .. " / audio keys=" .. audioCount)

    -- 점/슬래시 표기가 같은 인스턴스를 받는지 (false면 require 캐시 분열 — 즉시 보고할 것)
    print("[P1] same-instance check: " .. tostring(require("Data/RagdollData") == Ragdolls))

    print("[P1] ---- all OK ----")
end

function EndPlay()
end

function Tick(dt)
end
