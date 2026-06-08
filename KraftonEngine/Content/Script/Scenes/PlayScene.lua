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
local AudioData  = require("Data/AudioData")
local Config     = require("Data/GameConfig")
local ScoreMgr   = require("Manager/ScoreManager")
local LoadMgr    = require("Manager/ServerLoadManager")
local MissionMgr = require("Manager/MissionManager")
local HUD        = require("UI/HUDController")
local PauseUI    = require("UI/PauseUIController")
local UserSettings = require("Data/UserSettings")

local ended = false   -- 종료 판정 1회 보장 (전환 요청 후 같은 프레임 잔여 Tick 가드)

-- P: 일시정지 진입용 보조 키. Key 테이블에 정의가 없어 VK 코드를 직접 사용한다.
local KEY_P = 0x50
-- 게임패드 Menu(Start) 버튼 — XInput VK 코드 (ESC와 동일하게 일시정지 진입)
local PAD_KEY_MENU = 0xCF
local COUNTDOWN_DIM_OPACITY = 0.3
local COUNTDOWN_FADE_DURATION = 0.3
local COUNTDOWN_GO_HOLD_DURATION = 0.7
local intro_active = false
local gameplay_started = false

local function is_looping_audio_key(key)
    return key:find("^bgm_") ~= nil or key == "sfx_time_passing"
end

local function stop_gameplay_bgm()
    if AudioManager == nil then
        return
    end

    if AudioManager.StopBGM ~= nil then
        AudioManager.StopBGM()
        return
    end

    if AudioManager.Stop ~= nil then
        AudioManager.Stop("bgm_gameplay_0")
        return
    end

    if AudioManager.StopManaged ~= nil then
        AudioManager.StopManaged("bgm_gameplay_0")
    end
end

local function start_gameplay()
    if gameplay_started then
        return
    end

    gameplay_started = true
    intro_active = false
    Session.inputEnabled = true

    AudioManager.PlayBGM("bgm_gameplay_0", UserSettings.GetBgmVolumeScalar())

    ScoreMgr.Start()
    LoadMgr.Start()
    MissionMgr.Start()
    HUD.SetGameplayHudVisible(true)
    HUD.UpdateFromSession(0.0)
end

local function begin_start_countdown()
    intro_active = true
    gameplay_started = false
    Session.inputEnabled = false
    Session.load = 0
    HUD.SetServerLoad(0)
    HUD.SetGameplayHudVisible(false)

    HUD.SetStartCountdownStep("3", COUNTDOWN_DIM_OPACITY)

    StartCoroutine(function()
        AudioManager.Play("sfx_countdown_321_go", UserSettings.GetSfxVolumeScalar())

        HUD.SetStartCountdownStep("3", COUNTDOWN_DIM_OPACITY)
        Wait(1.0)

        HUD.SetStartCountdownStep("2", COUNTDOWN_DIM_OPACITY)
        Wait(1.0)

        HUD.SetStartCountdownStep("1", COUNTDOWN_DIM_OPACITY)
        Wait(1.0)

        HUD.SetStartCountdownStep("GO", COUNTDOWN_DIM_OPACITY)
        start_gameplay()

        local fade_elapsed = 0.0
        while fade_elapsed < COUNTDOWN_FADE_DURATION do
            local frame_dt = WaitFrame()
            fade_elapsed = math.min(fade_elapsed + (frame_dt or 0.0), COUNTDOWN_FADE_DURATION)
            HUD.SetStartCountdownStep("GO", COUNTDOWN_DIM_OPACITY * (1.0 - (fade_elapsed / COUNTDOWN_FADE_DURATION)))
        end

        Wait(COUNTDOWN_GO_HOLD_DURATION)
        HUD.SetStartCountdownVisible(false)
    end)
end

-- PauseUI.Show/Hide가 widget:SetWantsMouse를 토글하면 GameViewportClient가
-- 자동으로 커서 캡처/중앙 고정을 풀거나 다시 건다 (AnyViewportWidgetWantsMouse 참고).
-- OS 커서는 pause 중에도 계속 숨긴다 — 모달의 커서 스프라이트(aim 이미지, showCursor 옵션)가
-- 마우스를 대신 따라다닌다 (Title 메뉴와 같은 방식).
-- ESC/P는 진입 전용이다 — 다시 눌러도 풀리지 않으며, Continue 버튼만이 해제 수단이다.
local function enterPause()
    print("[Pause] enterPause() called, IsPaused=" .. tostring(Engine.IsPaused()))
    if Engine.IsPaused() then return end

    Engine.PauseGame()
    Session.inputEnabled = false
    PauseUI.Show()
    Engine.SetCursorVisible(false)   -- OS 화살표 숨김 — 모달의 커서 스프라이트가 대신한다
end

local function exitPause()
    print("[Pause] exitPause() called, IsPaused=" .. tostring(Engine.IsPaused())
        .. " mouse=(" .. tostring(Input.GetMouseX()) .. "," .. tostring(Input.GetMouseY()) .. ")")
    if not Engine.IsPaused() then return end

    Engine.ResumeGame()
    Session.inputEnabled = true
    PauseUI.Hide()
end

function BeginPlay()
    StopAllCoroutines()           -- 엔진의 씬 전환 코루틴 정리가 현재 동작 안 해서 직접 청소
    AudioManager.StopAllLoops()   -- 루프음(빔/차량)은 씬과 함께 꺼지지 않음
    ended = false
    intro_active = false
    gameplay_started = false

    Session.Reset(Config.timeLimit)   -- 이전 판 값 청소 (inputEnabled=true 포함)
    Session.inputEnabled = false

    for key, path in pairs(AudioData) do
        AudioManager.Load(key, path, is_looping_audio_key(key))
    end
    HUD.Create()
    HUD.SetGameplayHudVisible(false)
    HUD.SetServerLoad(0)
    HUD.UpdateFromSession()
    PauseUI.Create({
        onContinue = exitPause,
        onGoTitle = function()
            ended = true
            Engine.ResumeGame()
            Engine.LoadScene("Title")
        end,
    })
    HUD.SetStartCountdownVisible(false)

    Engine.SetOnEscape(enterPause)   -- 씬마다 재등록 (전역 단일 콜백이라 안 하면 이전 씬 것이 남음)

    begin_start_countdown()
    -- 스폰은 Play.Scene의 RagdollSpawnManager 액터(GOIncRagdollSpawnManager.lua)가,
    -- 수거는 AGOIncTruck 액터(TruckBehavior.lua)가 자체 Tick으로 담당 —
    -- pause 시 액터 Tick이 멈추므로 스폰/주행도 같이 멈춘다
end

function Tick(dt)
    UpdateCoroutines(dt)   -- 코루틴 심장 — 반드시 첫 줄
    if ended then return end

    if intro_active then
        HUD.Update(dt)
        return
    end

    -- P/패드 Menu: 일시정지 진입 전용 (pause 중엔 이 Tick 자체가 멈추므로 재입력으로는 못 푼다 — Continue 버튼만 해제 가능)
    if Input.GetKeyDown(KEY_P) or Input.GetKeyDown(PAD_KEY_MENU) then
        enterPause()
    end

    if Engine.IsPaused ~= nil and Engine.IsPaused() then
        return
    end

    Session.timeRemaining = Session.timeRemaining - dt
    LoadMgr.Update(dt)

    HUD.UpdateFromSession(dt)

    -- 종료 판정: 시간 초과 또는 서버 과부하
    if Session.timeRemaining <= 0 or Session.load >= Config.maxServerLoad then
        ended = true
        Session.result.gameOverReason =
            Session.timeRemaining <= 0 and "시간 초과" or "서버 과부하"
        stop_gameplay_bgm()
        AudioManager.Play("sfx_game_over", UserSettings.GetSfxVolumeScalar())
        HUD.ShowGameOverOverlay(function()
            Engine.LoadScene("Result")
        end)
    end
end

function EndPlay()
    StopAllCoroutines()
    stop_gameplay_bgm()
    AudioManager.StopAllLoops()
    HUD.Destroy()
    PauseUI.Destroy()
end
