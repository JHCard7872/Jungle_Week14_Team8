-- =============================================================================
-- PlayScene — 게임플레이 씬 오케스트레이터 (Play.Scene의 빈 액터에 부착)
-- [역할] 매 판 초기화 → 매니저 구동 → 카운트다운 → 종료 판정 → Result 전환.
--        게임 규칙은 안 가진다 — Manager들을 호출만 한다.
-- [사용법] Play.Scene에 빈 액터 하나 → LuaScriptComponent → ScriptFile에
--          "Scenes/PlayScene.lua"
-- [특이사항] Tick 순서는 고정이다: 코루틴 구동이 반드시 첫 줄
--            (타이머/스폰/부하 샘플링이 전부 코루틴 기반이라 여기서 심장이 뛴다).
--            pause 중엔 액터 Tick이 멈추므로 카운트다운·스폰·샘플링도 같이 멈춘다
--            (의도된 동작 — 일시정지의 의미론을 공짜로 얻음).
--            BeginPlay의 Session.Reset은 의무 — 모듈은 씬을 넘어 살아남아서
--            안 하면 이전 판 점수가 그대로 남는다.
-- =============================================================================

local Session    = require("GameSession")
local Config     = require("Data/GameConfig")
local ScoreMgr   = require("Manager/ScoreManager")
local LoadMgr    = require("Manager/ServerLoadManager")
local MissionMgr = require("Manager/MissionManager")
local HUD        = require("UI/HUDController")

local ended = false   -- 종료 판정 1회 보장 (전환 요청 후 같은 프레임 잔여 Tick 가드)

-- ESC: 일시정지 토글. 메뉴 입력(ESC)은 pause 중에도 발화한다 (엔진 특성)
local function togglePause()
    if Engine.IsPaused() then
        Engine.ResumeGame()
        Session.inputEnabled = true
        -- 2차: PauseUIController.Hide()
    else
        Engine.PauseGame()
        Session.inputEnabled = false
        -- 2차: PauseUIController.Show()
    end
end

function BeginPlay()
    StopAllCoroutines()           -- 엔진의 씬 전환 코루틴 정리가 현재 동작 안 해서 직접 청소
    AudioManager.StopAllLoops()   -- 루프음(빔/차량)은 씬과 함께 꺼지지 않음
    ended = false

    Session.Reset(Config.timeLimit)   -- 이전 판 값 청소 (inputEnabled=true 포함)

    for key, path in pairs(require("Data/AudioData")) do
        AudioManager.Load(key, path, key:find("^bgm_") ~= nil)
    end
    AudioManager.PlayBGM("bgm_gameplay_0", 0.1)

    HUD.Create()
    HUD.UpdateFromSession()

    Engine.SetOnEscape(togglePause)   -- 씬마다 재등록 (전역 단일 콜백이라 안 하면 이전 씬 것이 남음)

    ScoreMgr.Start()
    LoadMgr.Start()
    MissionMgr.Start()
    -- 스폰은 Play.Scene의 RagdollSpawnManager 액터(GOIncRagdollSpawnManager.lua)가,
    -- 수거는 AGOIncTruck 액터(TruckBehavior.lua)가 자체 Tick으로 담당 —
    -- pause 시 액터 Tick이 멈추므로 스폰/주행도 같이 멈춘다
end

function Tick(dt)
    UpdateCoroutines(dt)   -- 코루틴 심장 — 반드시 첫 줄
    if ended then return end

    Session.timeRemaining = Session.timeRemaining - dt
    LoadMgr.Update(dt)

    HUD.UpdateFromSession()

    -- 종료 판정: 시간 초과 또는 서버 과부하
    if Session.timeRemaining <= 0 or Session.load >= Config.maxServerLoad then
        ended = true
        Session.result.gameOverReason =
            Session.timeRemaining <= 0 and "시간 초과" or "서버 과부하"
        AudioManager.Play("sfx_game_over", 1.0)
        Engine.LoadScene("Result")   -- 이번 프레임 끝(Tick·Render 이후)에 안전 교체
    end
end

function EndPlay()
    StopAllCoroutines()
    AudioManager.StopAllLoops()
    HUD.Destroy()
end
