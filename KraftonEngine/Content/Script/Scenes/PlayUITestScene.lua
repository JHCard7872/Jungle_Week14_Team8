local HUD = require("UI/HUDController")

function BeginPlay()
    StopAllCoroutines()
    AudioManager.StopAllLoops()

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
