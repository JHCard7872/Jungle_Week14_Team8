local Session = require("GameSession")
local ResultUI = require("UI/ResultUIController")
local Modal = require("UI/ModalDialogUIController")
local ScoreStorage = require("Data/ScoreStorage")
local UserSettings = require("Data/UserSettings")

local waiting_for_next = false
local save_prompt_open = false
local action_prompt_open = false
local score_saved = false
local sample_name_index = 0

local function is_any_button_pressed()
    for vk = 1, 255 do
        if Input.GetKeyDown(vk) then
            return true
        end
    end

    return false
end

local function build_sample_nickname()
    sample_name_index = sample_name_index + 1
    local seed = os.time ~= nil and os.time() or 0
    return "SAMPLE" .. tostring(seed % 100000) .. "_" .. tostring(sample_name_index)
end

local function show_action_prompt()
    Modal.Destroy()
    save_prompt_open = false
    action_prompt_open = true
    waiting_for_next = false
    -- OS 커서는 숨긴 채 ResultUI의 커서 스프라이트(aim 이미지)가 따라다닌다

    ResultUI.ShowActionButtons(
        function() Engine.LoadScene("Play") end,
        function() Engine.LoadScene("Title") end
    )
end

local function save_current_score()
    if score_saved then
        return
    end

    local result = ResultUI.GetResultData()
    local ok = ScoreStorage.Append({
        nickname = build_sample_nickname(),
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
    -- OS 커서 대신 모달의 커서 스프라이트(showCursor)가 따라다닌다

    Modal.Create({
        zOrder = 270,
        title = "Score Save",
        message = "점수를 저장하시겠습니까?",
        leftText = "YES",
        rightText = "NO",
        showCursor = true,
        onLeft = function()
            save_current_score()
            local msg = score_saved and "저장되었습니다." or "저장에 실패했습니다."
            Modal.Create({
                zOrder = 270,
                title = "Score Save",
                message = msg,
                leftText = "OK",
                showCursor = true,
                onLeft = function()
                    show_action_prompt()
                end,
            })
            Modal.Show()
        end,
        onRight = function()
            show_action_prompt()
        end,
    })
    Modal.Show()
end

function BeginPlay()
    StopAllCoroutines()
    AudioManager.StopAllLoops()
    Session.inputEnabled = false
    waiting_for_next = false
    save_prompt_open = false
    action_prompt_open = false
    score_saved = false

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
            Engine.LoadScene("Title")
        end
    end)
end

function Tick(dt)
    ResultUI.Update(dt)

    if ResultUI.IsSequenceFinished() and not waiting_for_next and not save_prompt_open and not action_prompt_open then
        waiting_for_next = true
        Session.inputEnabled = true
    end

    -- 도장 연출과 Next 깜박임까지 끝난 뒤 아무 버튼을 누르면 저장 여부 팝업을 띄운다.
    if waiting_for_next and is_any_button_pressed() then
        show_save_prompt()
    end
end

function EndPlay()
    StopAllCoroutines()
    AudioManager.StopAllLoops()
    Modal.Destroy()
    ResultUI.Destroy()
    Engine.SetCursorVisible(true)
    waiting_for_next = false
    save_prompt_open = false
    action_prompt_open = false
end
