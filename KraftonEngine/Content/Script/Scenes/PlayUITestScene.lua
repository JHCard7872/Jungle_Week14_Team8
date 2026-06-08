local AudioData    = require("Data/AudioData")
local HUD          = require("UI/HUDController")
local RagdollData  = require("Data/RagdollData")

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
    local testRagdollId = "red-plumber"
    local testRagdoll   = RagdollData[testRagdollId]
    HUD.ShowTargetInfo({
        ragdollId = testRagdollId,
        name      = testRagdoll.displayName,
        weight    = testRagdoll.mass,
        score     = testRagdoll.baseScore,
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
    UpdateCoroutines(dt)   -- 코루틴 심장 — 없으면 팝업 등 Wait 기반 연출이 첫 프레임에 멈춰 안 사라진다
    HUD.Update(dt)
end

function EndPlay()
    StopAllCoroutines()
    AudioManager.StopAllLoops()
    HUD.Destroy()
    Engine.SetCursorVisible(true)
end
