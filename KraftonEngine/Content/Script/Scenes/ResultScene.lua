-- ===========================================================================
-- ResultScene — 결과 씬 시작점 (Result.Scene의 빈 액터에 부착)
-- [역할] 결과 표시(UI 호출) + 재시작/타이틀 분기. 점수는 별도 전달 없이
--        Session.score를 그대로 읽는다 — require 모듈은 씬을 넘어 살아남고,
--        Reset은 Play 진입 때만 하므로 결과 화면 동안 값이 유지된다.
-- [사용법] Result.Scene에 빈 액터 하나 → LuaScriptComponent → ScriptFile에
--          "Scenes/ResultScene.lua"
-- [특이사항] BeginPlay/EndPlay 정리 구문은 빼면 안 됨 (TitleScene 주석 참고).
--            종료 프레임에 ESC가 끼어들어 inputEnabled=false로 넘어오는 경우가
--            있어 복원한다.
-- ===========================================================================

local Session = require("GameSession")

function BeginPlay()
    StopAllCoroutines()
    AudioManager.StopAllLoops()
    Session.inputEnabled = true

    for key, path in pairs(require("Data/AudioData")) do
        AudioManager.Load(key, path, key:find("^Bgm") ~= nil)
    end
    AudioManager.PlayBGM("BgmResult", 0.6)

    -- TODO(UI): ResultUIController.Create() — Session.score / Session.result 직독
    -- UI가 붙기 전까지 결과를 콘솔로 확인 (UI 합류 후 이 print 제거)
    print(string.format("[Result] score=%d collected=%d reason=%s",
        Session.score, Session.result.collectedCount, Session.result.gameOverReason))

    Engine.SetOnEscape(function()
        Engine.LoadScene("Title")
    end)
end

function Tick(dt)
    -- TODO(UI): 임시 입력 — Retry 버튼이 붙으면 이 블록 제거
    if Input.GetKeyDown(Key.Space) then
        Engine.LoadScene("Play")
    end
end

function EndPlay()
    StopAllCoroutines()
    AudioManager.StopAllLoops()
end
