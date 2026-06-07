-- ============================================================================
-- TitleScene - entry point for Title.Scene.
-- Keeps title-scene lifecycle setup here, while the menu UI itself is spawned
-- by the separate TitleMainMenuUI actor attached in Title.Scene.
-- ============================================================================

local Session = require("GameSession")
local UserSettings = require("Data/UserSettings")

function BeginPlay()
    StopAllCoroutines()
    AudioManager.StopAllLoops()
    Session.inputEnabled = true

    for key, path in pairs(require("Data/AudioData")) do
        AudioManager.Load(key, path, key:find("^bgm_") ~= nil)
    end
    AudioManager.PlayBGM("bgm_title_0", UserSettings.GetBgmVolumeScalar())

    Engine.SetOnEscape(function()
        Engine.Exit()
    end)
end

function Tick(dt)
    -- Menu input is handled by the dedicated TitleMainMenuUI actor.
end

function EndPlay()
    StopAllCoroutines()
    AudioManager.StopAllLoops()
end
