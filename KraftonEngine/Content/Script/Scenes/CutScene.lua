-- =============================================================================
-- CutScene - 스토리/사원 등록 씬.
-- BgmCutScene.mp3와 cutscene_player.png 배경을 깔고,
-- common question modal의 입력형 variant로 사원 이름을 입력받는다.
-- =============================================================================

local Session = require("GameSession")
local UserSettings = require("Data/UserSettings")
local QuestionPopup = require("UI/QuestionPopupUIController")

local BG_DOCUMENT_PATH = "Content/UI/CutScene/cutscene_background.rml"
local BG_Z_ORDER = 10
local MODAL_Z_ORDER = 180
local UI_CLICK_KEY = "sfx_ui_click"
local KEY_ENTER = 0x0D
local DEFAULT_EMPLOYEE_NAME = "김사원"
local INVALID_NAME_MESSAGE = "잘못된 형식의 이름입니다. 다시 입력해주세요"

local background_widget = nil
local loading_play = false
local pending_scene_name = nil
local last_input_name = DEFAULT_EMPLOYEE_NAME
local input_modal_open = false

local function request_scene_load(scene_name)
    if pending_scene_name ~= nil then
        return
    end

    pending_scene_name = scene_name
end

local function trim(value)
    value = tostring(value or "")
    value = value:gsub("^%s+", "")
    value = value:gsub("%s+$", "")
    return value
end

local function next_codepoint(text, index)
    local b1 = string.byte(text, index)
    if b1 == nil then
        return nil, index
    end

    if b1 < 0x80 then
        return b1, index + 1
    end

    local b2 = string.byte(text, index + 1) or 0
    if b1 >= 0xC0 and b1 < 0xE0 then
        return (b1 - 0xC0) * 0x40 + (b2 - 0x80), index + 2
    end

    local b3 = string.byte(text, index + 2) or 0
    if b1 >= 0xE0 and b1 < 0xF0 then
        return (b1 - 0xE0) * 0x1000 + (b2 - 0x80) * 0x40 + (b3 - 0x80), index + 3
    end

    local b4 = string.byte(text, index + 3) or 0
    return (b1 - 0xF0) * 0x40000 + (b2 - 0x80) * 0x1000 + (b3 - 0x80) * 0x40 + (b4 - 0x80), index + 4
end

local function is_allowed_name_codepoint(cp)
    local is_alpha = (cp >= 0x41 and cp <= 0x5A) or (cp >= 0x61 and cp <= 0x7A)
    local is_hangul = cp >= 0xAC00 and cp <= 0xD7A3
    return is_alpha or is_hangul
end

local function validate_name(name)
    name = trim(name)

    if name == "" then
        return false
    end

    local count = 0
    local i = 1
    while i <= #name do
        local cp
        cp, i = next_codepoint(name, i)

        if cp == nil or not is_allowed_name_codepoint(cp) then
            return false
        end

        count = count + 1
        if count > 6 then
            return false
        end
    end

    return true
end

local function save_player_name(name)
    Session.playerName = name
    Session.employee = Session.employee or {}
    Session.employee.name = name
    Session.employee.number = Session.employee.number or "GO-2417"
    Session.employee.department = Session.employee.department or "Operations"
    Session.employee.rank = Session.employee.rank or "Contract"

    -- 사용자가 요구한 전역 변수도 같이 저장한다. 실제 코드에서는 GameSession 사용을 권장.
    _G.PlayerName = name
end

local show_name_input

local function show_invalid_name_notice(name)
    input_modal_open = false
    last_input_name = trim(name)
    if last_input_name == "" then
        last_input_name = DEFAULT_EMPLOYEE_NAME
    end

    QuestionPopup.ShowNotice({
        zOrder = MODAL_Z_ORDER,
        title = "입력 오류",
        message = INVALID_NAME_MESSAGE,
        buttonText = "확인",
        showCursor = true,
        onConfirm = function()
            show_name_input(last_input_name)
        end,
    })
end

local function confirm_name(name)
    if loading_play then
        return
    end

    name = trim(name)
    last_input_name = name

    if not validate_name(name) then
        show_invalid_name_notice(name)
        return
    end

    loading_play = true
    AudioManager.Play(UI_CLICK_KEY, UserSettings.GetSfxVolumeScalar())
    save_player_name(name)
    QuestionPopup.Destroy()
    request_scene_load("Play")
end

show_name_input = function(default_name)
    input_modal_open = true
    QuestionPopup.ShowInput({
        zOrder = MODAL_Z_ORDER,
        title = "Employee Registration",
        message = "사원 이름을 입력해주세요.",
        ruleText = "한글 / Alphabet 6글자 이내",
        defaultValue = default_name or DEFAULT_EMPLOYEE_NAME,
        confirmText = "결정",
        showCursor = true,
        onConfirm = confirm_name,
    })
end

local function ensure_background_widget()
    if UI == nil or UI.CreateWidget == nil then
        return nil
    end

    if background_widget == nil then
        background_widget = UI.CreateWidget(BG_DOCUMENT_PATH)
    end

    if background_widget == nil then
        return nil
    end

    if background_widget.IsInViewport == nil or not background_widget:IsInViewport() then
        background_widget:AddToViewportZ(BG_Z_ORDER)
    end

    background_widget:SetWantsMouse(false)
    return background_widget
end

function BeginPlay()
    StopAllCoroutines()
    AudioManager.StopAllLoops()
    loading_play = false
    pending_scene_name = nil
    last_input_name = DEFAULT_EMPLOYEE_NAME
    input_modal_open = false

    for key, path in pairs(require("Data/AudioData")) do
        AudioManager.Load(key, path, key:find("^bgm_") ~= nil)
    end
    AudioManager.PlayBGM("bgm_cutscene", UserSettings.GetBgmVolumeScalar())

    Engine.SetCursorVisible(false)
    ensure_background_widget()
    show_name_input(DEFAULT_EMPLOYEE_NAME)

    -- ESC 비활성화: Play의 Pause 외에는 ESC 무반응. (진행은 Enter/결정 버튼)
    Engine.SetOnEscape(function() end)
end

function Tick(dt)
    if pending_scene_name ~= nil then
        local scene_name = pending_scene_name
        pending_scene_name = nil
        Engine.LoadScene(scene_name)
        return
    end

    if input_modal_open and Input.GetKeyDown(KEY_ENTER) then
        confirm_name(QuestionPopup.GetInputText())
    end
end

function EndPlay()
    StopAllCoroutines()
    AudioManager.StopAllLoops()
    QuestionPopup.Destroy()

    if background_widget ~= nil then
        background_widget:RemoveFromParent()
    end

    Engine.SetCursorVisible(true)
    background_widget = nil
    loading_play = false
    pending_scene_name = nil
    last_input_name = DEFAULT_EMPLOYEE_NAME
    input_modal_open = false
end
