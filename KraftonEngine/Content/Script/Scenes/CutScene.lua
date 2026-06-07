-- =============================================================================
-- CutScene - 임시 스토리/등록 씬.
-- 현재는 플레이어 이름 입력만 받고 Play.Scene으로 넘긴다.
-- =============================================================================

local Session = require("GameSession")
local UserSettings = require("Data/UserSettings")

local UI_DOCUMENT_PATH = "Content/UI/CutScene/name_entry.rml"
local CUTSCENE_Z_ORDER = 180
local UI_CLICK_KEY = "sfx_ui_click"
local UI_HOVER_KEY = "sfx_ui_hover"
local KEY_ENTER = 0x0D

local widget = nil
local bindings_initialized = false
local loading_play = false
local pending_scene_name = nil

local function request_scene_load(scene_name)
    if pending_scene_name ~= nil then
        return
    end

    pending_scene_name = scene_name
end

local function set_text(element_id, value)
    if widget == nil or widget.SetValue == nil then
        return
    end

    widget:SetValue(element_id, tostring(value or ""))
end

local function get_text(element_id)
    if widget == nil or widget.GetValue == nil then
        return ""
    end

    return tostring(widget:GetValue(element_id) or "")
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
        return false, "이름을 입력해주세요."
    end

    local count = 0
    local i = 1
    while i <= #name do
        local cp
        cp, i = next_codepoint(name, i)

        if cp == nil or not is_allowed_name_codepoint(cp) then
            return false, "한글 또는 알파벳만 사용할 수 있습니다."
        end

        count = count + 1
        if count > 6 then
            return false, "이름은 6글자 이내여야 합니다."
        end
    end

    return true, ""
end

local function show_error(message)
    set_text("name_error_text", message or "")
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

local function confirm_name()
    if loading_play then
        return
    end

    local name = trim(get_text("player_name_input"))
    local ok, error_message = validate_name(name)
    if not ok then
        show_error(error_message)
        return
    end

    loading_play = true
    AudioManager.Play(UI_CLICK_KEY, UserSettings.GetSfxVolumeScalar())
    save_player_name(name)
    request_scene_load("Play")
end

local function bind_actions()
    if widget == nil or bindings_initialized or widget.bind_click == nil then
        return
    end

    widget:bind_click("name_confirm_button", function()
        confirm_name()
    end)

    if widget.bind_hover ~= nil then
        widget:bind_hover("name_confirm_button", function()
            AudioManager.Play(UI_HOVER_KEY, UserSettings.GetSfxVolumeScalar())
        end)
    end

    bindings_initialized = true
end

local function ensure_widget()
    if UI == nil or UI.CreateWidget == nil then
        return nil
    end

    if widget == nil then
        widget = UI.CreateWidget(UI_DOCUMENT_PATH)
    end

    if widget == nil then
        return nil
    end

    if widget.IsInViewport == nil or not widget:IsInViewport() then
        widget:AddToViewportZ(CUTSCENE_Z_ORDER)
    end

    widget:SetWantsMouse(true)
    set_text("name_error_text", "")
    bind_actions()
    return widget
end

function BeginPlay()
    StopAllCoroutines()
    AudioManager.StopAllLoops()
    loading_play = false
    pending_scene_name = nil

    for key, path in pairs(require("Data/AudioData")) do
        AudioManager.Load(key, path, key:find("^bgm_") ~= nil)
    end
    AudioManager.PlayBGM("bgm_main_0", UserSettings.GetBgmVolumeScalar())

    Engine.SetCursorVisible(true)
    ensure_widget()

    Engine.SetOnEscape(function()
        request_scene_load("MainMenu")
    end)
end

function Tick(dt)
    if pending_scene_name ~= nil then
        local scene_name = pending_scene_name
        pending_scene_name = nil
        Engine.LoadScene(scene_name)
        return
    end

    if Input.GetKeyDown(KEY_ENTER) then
        confirm_name()
    end
end

function EndPlay()
    StopAllCoroutines()
    AudioManager.StopAllLoops()

    if widget ~= nil then
        widget:RemoveFromParent()
    end

    Engine.SetCursorVisible(true)
    widget = nil
    bindings_initialized = false
    loading_play = false
    pending_scene_name = nil
end
