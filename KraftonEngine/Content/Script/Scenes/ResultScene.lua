local Session = require("GameSession")
local ResultUI = require("UI/ResultUIController")

function BeginPlay()
    StopAllCoroutines()
    AudioManager.StopAllLoops()
    Session.inputEnabled = false

    for key, path in pairs(require("Data/AudioData")) do
        AudioManager.Load(key, path, key:find("^bgm_") ~= nil)
    end

    Engine.SetCursorVisible(false)
    if ResultUI.Create() == nil then
        Session.inputEnabled = true
    end

    Engine.SetOnEscape(function()
        Engine.LoadScene("Title")
    end)
end

function Tick(dt)
    ResultUI.Update(dt)

    Session.inputEnabled = ResultUI.IsSequenceFinished()
    if Session.inputEnabled and Input.GetKeyDown(Key.Space) then
        Engine.LoadScene("Play")
    end
end

function EndPlay()
    StopAllCoroutines()
    AudioManager.StopAllLoops()
    ResultUI.Destroy()
    Engine.SetCursorVisible(true)
end
