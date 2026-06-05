-- ============================================================================
-- TitleScene — 타이틀 씬 시작점 (Title.Scene의 빈 액터에 부착)
-- [역할] 타이틀 진입 정리 + BGM + UI 생성 호출. 흐름만 굴리고 규칙은 없다.
-- [사용법] Title.Scene에 빈 액터 하나 → LuaScriptComponent → ScriptFile에
--          "Scenes/TitleScene.lua" (슬래시 표기 — 핫리로드 매칭이 슬래시 기준)
-- [특이사항] BeginPlay/EndPlay의 정리 구문은 빼면 안 됨:
--            - 엔진의 씬 전환 코루틴 정리가 현재 동작하지 않아서 직접 청소한다
--              (안 하면 이전 씬 타이머가 살아남아 누적됨)
--            - 루프음(빔/차량)은 씬과 함께 꺼지지 않아서 직접 끈다
--            - inputEnabled는 씬을 넘어 살아남는 값이라 pause 중 전환으로
--              false가 남아있을 수 있어 복원한다
-- ============================================================================

local Session = require("GameSession")

function BeginPlay()
    --- 안정 동작 보장용 정리 구문
    StopAllCoroutines()
    AudioManager.StopAllLoops()
    Session.inputEnabled = true

    -- 사운드 키 일괄 등록 (Bgm 접두 키는 루프 재생이라 loop=true — FMOD는 Load 시점에 고정)
    for key, path in pairs(require("Data/AudioData")) do
        AudioManager.Load(key, path, key:find("^Bgm") ~= nil)
    end
    AudioManager.PlayBGM("BgmTitle", 0.6)

    -- TODO(UI): TitleUIController.Create() — START/QUIT 버튼, 조작 안내도 타이틀 화면에 포함

    Engine.SetOnEscape(function()
        Engine.Exit()
    end)
end

function Tick(dt)
    -- TODO(UI): 임시 입력 — START 버튼이 붙으면 이 블록 제거
    if Input.GetKeyDown(Key.W) then
        print("[Title] Go To Play Scene!")
        Engine.LoadScene("Play")
    end
end

function EndPlay()
    --- 안정 동작 보장용 정리 구문
    StopAllCoroutines()
    AudioManager.StopAllLoops()
end
