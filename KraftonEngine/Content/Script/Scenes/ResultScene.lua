local Session = require("GameSession")
local ResultUI = require("UI/ResultUIController")
local QuestionPopup = require("UI/QuestionPopupUIController")
local ScoreStorage = require("Data/ScoreStorage")
local UserSettings = require("Data/UserSettings")

local waiting_for_next = false
local save_prompt_open = false
local action_prompt_open = false
local score_saved = false
local sample_name_index = 0
local pending_scene_name = nil

local function request_scene_load(scene_name)
    if pending_scene_name ~= nil then
        return
    end

    Session.sceneTransition = Session.sceneTransition or {}
    if scene_name == "Title" then
        Session.sceneTransition.titleFadeInDuration = 1.5
    else
        Session.sceneTransition.titleFadeInDuration = 0.0
    end

    pending_scene_name = scene_name
end

local function is_any_button_pressed()
    for vk = 1, 255 do
        if Input.GetKeyDown(vk) then
            return true
        end
    end

    return false
end

local function build_score_nickname()
    local employee = Session.employee or {}
    local name = tostring(employee.name or Session.playerName or _G.PlayerName or "")

    if name ~= "" and name ~= "Employee" then
        return name
    end

    sample_name_index = sample_name_index + 1
    local seed = os.time ~= nil and os.time() or 0
    return "SAMPLE" .. tostring(seed % 100000) .. "_" .. tostring(sample_name_index)
end

local function show_action_prompt()
    QuestionPopup.Destroy()
    save_prompt_open = false
    action_prompt_open = true
    waiting_for_next = false

    ResultUI.ShowActionButtons(
        function() request_scene_load("Play") end,
        function() request_scene_load("Title") end
    )
end

local function save_current_score()
    if score_saved then
        return
    end

    local result = ResultUI.GetResultData()
    local ok = ScoreStorage.Append({
        nickname = build_score_nickname(),
        totalScore = result.totalScore,
        collectedCount = result.collectedCount,
        savedAt = os.time ~= nil and os.time() or 0,
    })

    score_saved = ok == true
end

local function show_save_prompt()
    if save_prompt_open or action_prompt_open then
        return
    end

    waiting_for_next = false
    save_prompt_open = true
    ResultUI.SetWantsMouse(false)
    ResultUI.SetPrePopupShadowVisible(false)

    QuestionPopup.ShowConfirm({
        zOrder = 270,
        title = "Score Save",
        message = "점수를 저장하시겠습니까?",
        showCursor = true,
        onYes = function()
            save_current_score()
            QuestionPopup.ShowNotice({
                zOrder = 270,
                title = "Score Save",
                message = score_saved and "저장되었습니다." or "저장에 실패했습니다.",
                showCursor = true,
                onConfirm = function()
                    show_action_prompt()
                end,
            })
        end,
        onNo = function()
            show_action_prompt()
        end,
    })
end

function BeginPlay()
    StopAllCoroutines()
    AudioManager.StopAllLoops()
    Session.inputEnabled = false
    waiting_for_next = false
    save_prompt_open = false
    action_prompt_open = false
    score_saved = false
    pending_scene_name = nil

    for key, path in pairs(require("Data/AudioData")) do
        AudioManager.Load(key, path, key:find("^bgm_") ~= nil)
    end
    AudioManager.PlayBGM("bgm_result_0", UserSettings.GetBgmVolumeScalar())

    Engine.SetCursorVisible(false)
    if ResultUI.Create() == nil then
        Session.inputEnabled = true
    end

    Engine.SetOnEscape(function()
        if ResultUI.IsSequenceFinished() and not save_prompt_open and not action_prompt_open then
            show_save_prompt()
        elseif action_prompt_open then
            request_scene_load("Title")
        end
    end)
end

function Tick(dt)
    if pending_scene_name ~= nil then
        local scene_name = pending_scene_name
        pending_scene_name = nil
        Engine.LoadScene(scene_name)
        return
    end

    ResultUI.Update(dt)

    if ResultUI.IsSequenceFinished() and not waiting_for_next and not save_prompt_open and not action_prompt_open then
        waiting_for_next = true
        Session.inputEnabled = true
    end

    if waiting_for_next and is_any_button_pressed() then
        show_save_prompt()
    end
end

function EndPlay()
    StopAllCoroutines()
    AudioManager.StopAllLoops()
    QuestionPopup.Destroy()
    ResultUI.Destroy()
    Engine.SetCursorVisible(true)
    waiting_for_next = false
    save_prompt_open = false
    action_prompt_open = false
    pending_scene_name = nil
end
