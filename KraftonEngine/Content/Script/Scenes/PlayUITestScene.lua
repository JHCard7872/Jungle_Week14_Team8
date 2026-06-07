local AudioData = require("Data/AudioData")
local HUD = require("UI/HUDController")

local function is_looping_audio_key(key)
    return key:find("^bgm_") ~= nil or key == "sfx_time_passing"
end

function BeginPlay()
    StopAllCoroutines()
    AudioManager.StopAllLoops()

    for key, path in pairs(AudioData) do
        AudioManager.Load(key, path, is_looping_audio_key(key))
    end

    HUD.Create({
        showDebugPanel = true,
        wantsMouse = true,
    })

    HUD.SetTimeSeconds(135)
    HUD.SetScore(12850)
    HUD.SetServerLoad(67)
    HUD.SetGunMode("collect")
    HUD.SetGunEnergy(100)
    HUD.ShowTargetInfo({
        name = "Red Plumber",
        weightText = "12.5kg",
        scoreText = "+300",
        imagePath = "../../Sprite/ragdoll/ragdoll_sample.png",
    })
    HUD.SetMissionState({
        active = true,
        target = "red-plumber",
        need = 3,
        got = 1,
        text = "빨간 배관공 3체 수거",
    })

    Engine.SetCursorVisible(true)
    Engine.SetOnEscape(function()
        Engine.LoadScene("Title")
    end)
end

function Tick(dt)
    HUD.Update(dt)
end

function EndPlay()
    StopAllCoroutines()
    AudioManager.StopAllLoops()
    HUD.Destroy()
    Engine.SetCursorVisible(true)
end
