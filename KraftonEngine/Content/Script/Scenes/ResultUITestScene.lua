local Session = require("GameSession")
local ResultUI = require("UI/ResultUIController")
local AudioData = require("Data/AudioData")

local CURRENT_PRESET = "F"
local DEBUG_PANEL_VISIBLE = true

local PRESETS = {
    A = {
        score = 1680,
        count = 22,
        baseScore = 1240,
        urgentScore = 440,
    },
    B = {
        score = 1040,
        count = 17,
        baseScore = 760,
        urgentScore = 280,
    },
    C = {
        score = 620,
        count = 13,
        baseScore = 470,
        urgentScore = 150,
    },
    F = {
        score = 220,
        count = 8,
        baseScore = 160,
        urgentScore = 60,
    },
}

local function load_audios()
    for key, path in pairs(AudioData) do
        AudioManager.Load(key, path, key:find("^bgm_") ~= nil)
    end
end

local function apply_preview_preset(rank)
    local preset = PRESETS[rank] or PRESETS.F

    CURRENT_PRESET = rank
    Session.score = preset.score
    Session.employee = {
        number = "GO-2417",
        name = "Kang Hana",
        department = "Operations",
        rank = "Contract",
    }
    Session.result = {
        collectedCount = preset.count,
        baseScore = preset.baseScore,
        urgentScore = preset.urgentScore,
        gameOverReason = "",
        gradeText = "",
    }
end

local function rebuild_result_ui()
    ResultUI.Destroy()
    ResultUI.Create({
        showDebugPanel = DEBUG_PANEL_VISIBLE,
        wantsMouse = DEBUG_PANEL_VISIBLE,
    })
end

function BeginPlay()
    StopAllCoroutines()
    AudioManager.StopAllLoops()

    load_audios()
    apply_preview_preset(CURRENT_PRESET)
    rebuild_result_ui()

    Session.inputEnabled = true
    Engine.SetCursorVisible(true)
    Engine.SetOnEscape(function()
        Engine.LoadScene("Title")
    end)

    print("[ResultUITest] Space/R: replay  A/B/C/F: change rank preview  F1: toggle layout panel")
end

function Tick(dt)
    ResultUI.Update(dt)

    if Input.GetKeyDown(Key.F1) then
        DEBUG_PANEL_VISIBLE = not DEBUG_PANEL_VISIBLE
        ResultUI.SetDebugPanelEnabled(DEBUG_PANEL_VISIBLE)
        return
    end

    if Input.GetKeyDown(Key.Space) or Input.GetKeyDown(Key.R) then
        rebuild_result_ui()
        return
    end

    if Input.GetKeyDown(Key.A) then
        apply_preview_preset("A")
        rebuild_result_ui()
    elseif Input.GetKeyDown(Key.B) then
        apply_preview_preset("B")
        rebuild_result_ui()
    elseif Input.GetKeyDown(Key.C) then
        apply_preview_preset("C")
        rebuild_result_ui()
    elseif Input.GetKeyDown(Key.F) then
        apply_preview_preset("F")
        rebuild_result_ui()
    end
end

function EndPlay()
    StopAllCoroutines()
    AudioManager.StopAllLoops()
    ResultUI.Destroy()
    Engine.SetCursorVisible(true)
end
