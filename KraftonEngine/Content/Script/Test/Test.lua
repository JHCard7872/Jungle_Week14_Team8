-- ===========================================================================
-- Test — Phase 2 스모크: Manager 3종 검증 (RagdollTest 씬에서 Play)
-- 가짜 래그돌(빈 액터+태그)로 점수/임계치 미션/부하 샘플링을 확인한다.
-- 기대 출력은 각 print 끝의 "기대:" 주석 참고 — 다르면 보고할 것.
-- ===========================================================================

local Session  = require("GameSession")
local Config   = require("Data/GameConfig")
local ScoreMgr = require("Manager/ScoreManager")
local LoadMgr  = require("Manager/ServerLoadManager")
local MissionM = require("Manager/MissionManager")

local elapsed = 0
local loadReported = false

local function spawnFake(typeTag, extraTag)
    local a = World.SpawnActor("AActor")
    a:AddTag("Ragdoll")
    a:AddTag(typeTag)
    if extraTag then a:AddTag(extraTag) end
    return a
end

function BeginPlay()
    print("[P2] ---- Phase 2 smoke start ----")
    Session.Reset(Config.timeLimit)
    ScoreMgr.Start()

    -- 1) 임계치 미만 fallback: 슬라임 2마리뿐(min=3) → 최다 보유 타입을 보유 수만큼
    spawnFake("green-slime"); spawnFake("green-slime")
    MissionM.Start()
    local m = MissionM.GetCurrent()
    print("[P2] fallback mission: " .. m.text)               -- 기대: 초록 슬라임 2체 수거

    -- 2) 정상 발급: 빨간 배관공 4마리 추가(4 >= min 3) → 후보는 red뿐, 목표 = minCount
    local gold = spawnFake("red-plumber", "Gold")
    spawnFake("red-plumber"); spawnFake("red-plumber"); spawnFake("red-plumber")
    MissionM.IssueNext()
    m = MissionM.GetCurrent()
    print("[P2] normal mission: " .. m.text)                 -- 기대: 빨간 배관공 3체 수거

    -- 3) 점수: 금 래그돌 수거 = 100 x 3.0
    ScoreMgr.AddForRagdoll(gold)
    print("[P2] gold collect: score=" .. Session.score
        .. " collected=" .. Session.result.collectedCount)   -- 기대: score=300 collected=1

    -- 4) 미션 진행/달성: red 3회 수거 통보 → +500 보너스 + 즉시 재발급
    MissionM.NotifyRecovered(gold)
    MissionM.NotifyRecovered(gold)
    print("[P2] progress: " .. MissionM.GetCurrent().got .. "/"
        .. MissionM.GetCurrent().need)                       -- 기대: 2/3
    MissionM.NotifyRecovered(gold)
    print("[P2] after clear: score=" .. Session.score
        .. " next='" .. MissionM.GetCurrent().text .. "'")   -- 기대: score=800 next='빨간 배관공 3체 수거'

    -- 5) 부하: 0.5초 샘플링(코루틴) — Tick에서 1.2초 돌린 뒤 결과 출력
    LoadMgr.Start()
    print("[P2] load sampling... (1.2초 뒤 결과)")
end

function Tick(dt)
    UpdateCoroutines(dt)        -- 샘플링 코루틴 구동 (PlayScene이 하는 역할을 테스트가 대신)
    LoadMgr.Update(dt)

    elapsed = elapsed + dt
    if elapsed > 1.2 and not loadReported then
        loadReported = true
        -- 기대: 래그돌 6마리 x 0.5%/초 x ~0.7초(첫 샘플 0.5초 이후) ≈ 2~4 사이
        print(string.format("[P2] load after %.1fs = %.2f (0보다 크면 통과)", elapsed, Session.load))
        print("[P2] ---- all OK ----")
    end
end

function EndPlay()
end
