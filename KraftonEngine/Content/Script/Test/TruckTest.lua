-- ===========================================================================
-- TruckTest — 트럭 스모크: 대기↔순회 사이클·사운드·수거 검증 (TruckTest 씬에서 Play)
-- 기대 출력은 각 print 끝의 "기대:" 주석 참고 — 다르면 보고할 것.
-- 전체 시나리오: waitTime 대기 → 1회 순회(순회 중 FakeRagdoll 수거) → 재대기
-- 진입 → 종합 판정(all OK / FAIL 목록). 기본값으로 ~90초 소요.
-- 빨리 보려면 TruckData.waitTime을 잠시 줄여서 실행.
-- 트랙 조절 확인: TruckData.waypoints를 바꿔 저장하면 트럭이 새 트랙을 돈다.
-- ===========================================================================

local Session  = require("GameSession")
local Config   = require("Data/GameConfig")
local Truck    = require("Data/TruckData")
local ScoreMgr = require("Manager/ScoreManager")
local MissionM = require("Manager/MissionManager")

local elapsed = 0
local truckActor = nil
local lastPos = nil
local movedDist = 0
local backwardFail = false
local minDist = {}          -- 웨이포인트별 최소 접근 거리

local soundChecked = false
local waitChecked = false
local departed = false
local collectReported = false
local lapReported = false
local stillTime = 0
local cycleReported = false
local finalReported = false

local results = {}          -- 종합 판정용 — 각 검사가 통과 시점에 true로 채움

local function reportFinal()
    if finalReported then return end
    finalReported = true
    local items = {
        { "사운드",     results.sound },
        { "대기",       results.wait },
        { "출발",       results.depart },
        { "수거",       results.collect },
        { "순회",       results.lap and not backwardFail },
        { "재대기",     results.cycle },
        { "오감지없음", results.prop },
    }
    local fails = {}
    for _, item in ipairs(items) do
        if not item[2] then fails[#fails + 1] = item[1] end
    end
    if #fails == 0 then
        print("[TRUCK] ---- all OK ----")
    else
        print("[TRUCK] ---- FAIL: " .. table.concat(fails, ", ") .. " ----")
    end
end

function BeginPlay()
    print("[TRUCK] ---- truck smoke start ----")
    AudioManager.StopAllLoops()   -- 루프음은 씬과 함께 꺼지지 않음 (PlayScene과 동일한 방어)
    Session.Reset(Config.timeLimit)

    -- 사운드 일괄 등록 (각 씬 BeginPlay의 공통 규약 — AudioData.lua 참고)
    for key, path in pairs(require("Data/AudioData")) do
        AudioManager.Load(key, path, key:find("^Bgm") ~= nil)
    end

    -- 점수/미션 가동 (FakeRagdoll 1마리뿐 → fallback 미션 "빨간 배관공 1체 수거" 발급)
    ScoreMgr.Start()
    MissionM.Start()
    local m = MissionM.GetCurrent()
    print("[TRUCK] 발급 미션: " .. (m and m.text or "없음"))
    -- 기대: 빨간 배관공 1체 수거

    truckActor = World.FindActorByName("Truck")
    if not truckActor then
        print("[TRUCK] FAIL: Truck 액터를 못 찾음")
        return
    end
    lastPos = truckActor.Location
    for i = 1, #Truck.waypoints do minDist[i] = 1e9 end
end

function Tick(dt)
    if not truckActor or not truckActor:IsValid() then return end
    elapsed = elapsed + dt

    local pos = truckActor.Location
    local dx, dy = pos.X - lastPos.X, pos.Y - lastPos.Y
    local frameMove = math.sqrt(dx * dx + dy * dy)

    -- 전진성: 이동 벡터와 Forward의 내적이 음수면 후진 (요구: 후진 없음)
    local fwd = truckActor.Forward
    local dot = dx * fwd.X + dy * fwd.Y
    if dot < -0.001 and not backwardFail then
        backwardFail = true
        print("[TRUCK] FAIL: 후진 감지 (dot=" .. dot .. ")")
    end
    movedDist = movedDist + frameMove
    lastPos = pos

    -- 웨이포인트별 최소 접근 거리 갱신 (순회 판정용)
    for i, wp in ipairs(Truck.waypoints) do
        local wx, wy = wp[1] - pos.X, wp[2] - pos.Y
        local d = math.sqrt(wx * wx + wy * wy)
        if d < minDist[i] then minDist[i] = d end
    end

    -- 1) 사운드: 대기 중에도 엔진음 루프는 재생
    if elapsed > 2 and not soundChecked then
        soundChecked = true
        results.sound = AudioManager.IsLoopPlaying("TruckLoop")
        print("[TRUCK] engine loop playing = " .. tostring(results.sound))
        -- 기대: true (BgmCollectorTruck.mp3 로드 실패면 false — Load 실패 로그 확인)
    end

    -- 2) 출발 전 대기: waitTime 절반 시점까지 이동량 0이어야 함
    if elapsed > Truck.waitTime * 0.5 and not waitChecked then
        waitChecked = true
        results.wait = movedDist < 0.1
        print(string.format("[TRUCK] 대기 확인 (%.1fs 이동량 %.2f)", elapsed, movedDist))
        -- 기대: 이동량 0.00
    end

    -- 3) 출발: waitTime 경과 직후 이동 시작
    if movedDist > 0.5 and not departed then
        departed = true
        results.depart = true
        print(string.format("[TRUCK] 출발 감지 (%.1fs)", elapsed))
        -- 기대: waitTime(기본 60초) 직후
    end

    -- 4) 수거: 트럭이 FakeRagdoll 위를 지나면 Destroy + 점수/미션 보너스
    if departed and not collectReported and World.FindActorByName("FakeRagdoll") == nil then
        collectReported = true
        results.collect = (Session.score == 600 and Session.result.collectedCount == 1)
        print(string.format("[TRUCK] 수거 OK (%.1fs) score=%d collected=%d",
            elapsed, Session.score, Session.result.collectedCount))
        -- 기대: 출발 후 십수 초, score=600 (기본 100 + 미션달성 보너스 500), collected=1
    end

    -- 5) 순회: 모든 웨이포인트에 arriveDistance*2 이내로 접근했으면 한 바퀴 인정
    if departed and not lapReported then
        local allVisited = true
        for i = 1, #Truck.waypoints do
            if minDist[i] > Truck.arriveDistance * 2 then
                allVisited = false
                break
            end
        end
        if allVisited then
            lapReported = true
            results.lap = true
            print(string.format("[TRUCK] 순회 OK (%.1fs, 후진=%s)",
                elapsed, backwardFail and "있음(FAIL)" or "없음"))
            -- 기대: waitTime + ~25초, 후진=없음
        end
    end

    -- 6) 순회 후 재대기: 3초 연속 정지하면 사이클 검증 완료
    if lapReported and not cycleReported then
        if frameMove < 0.001 then
            stillTime = stillTime + dt
        else
            stillTime = 0
        end
        if stillTime > 3 then
            cycleReported = true
            results.cycle = true
            print(string.format("[TRUCK] 재대기 진입 OK (%.1fs)", elapsed))
            -- 기대: 순회 종료 웨이포인트에서 정지한 채 출력

            -- 7) 오감지 없음: 태그 없는 FakeProp은 살아있어야 한다
            local prop = World.FindActorByName("FakeProp")
            results.prop = (prop ~= nil)
            print(string.format("[TRUCK] FakeProp 생존 = %s, 최종 score=%d",
                tostring(results.prop), Session.score))
            -- 기대: 생존 = true, score=600

            reportFinal()
        end
    end

    -- 8) 시간 초과 안전망: 검사가 어딘가에서 멈춰도 판정은 반드시 출력
    if not finalReported and elapsed > Truck.waitTime + 90 then
        print(string.format("[TRUCK] 시간 초과 (%.1fs) — 미완료 검사 있음", elapsed))
        reportFinal()
    end
end

function EndPlay()
end
