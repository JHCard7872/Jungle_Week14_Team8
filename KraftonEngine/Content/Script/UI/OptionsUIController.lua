-- =============================================================================
-- OptionsUIController — 옵션 화면 UI 컨트롤러
-- [역할] 화면을 30% 어둡게 덮고 Sound Volume / Input Mode 설정과
--        Back / Confirm 버튼을 띄운다.
-- [사용법] 메뉴/일시정지 화면 등에서 Create로 만들고, Show/Hide로
--          표시 여부만 토글한다. 실제 값 저장/적용은 호출하는 쪽이
--          onConfirm/onBack 콜백과 GetSettings/ApplySettings로 담당한다.
-- =============================================================================

local UserSettings = require("Data/UserSettings")

local UI_DOCUMENT_PATH = "Content/UI/Options/options.rml"
-- Pause(220)보다 위에 뜨도록
local OPTIONS_Z_ORDER = 230

local UI_CLICK_KEY = "sfx_ui_click"
local UI_HOVER_KEY = "sfx_ui_hover"

local MIN_VOLUME = 0
local MAX_VOLUME = 10
local DEFAULT_SFX_VOLUME = 8
local DEFAULT_BGM_VOLUME = 8
local DEFAULT_INPUT_MODE = "mouse_key"

local INPUT_MODE_ROW_IDS = {
    mouse_key = "input_mode_mouse_key",
    gamepad = "input_mode_gamepad",
}

local M = {}

local widget = nil
local bindings_initialized = false
local visible = false

-- Confirm/Back 버튼 클릭 시 호출할 콜백
local on_confirm = nil
local on_back = nil

-- 현재 화면에 표시 중인 설정값
local settings = {
    sfxVolume = DEFAULT_SFX_VOLUME,
    bgmVolume = DEFAULT_BGM_VOLUME,
    inputMode = DEFAULT_INPUT_MODE,
}

local function clamp(value, min_value, max_value)
    if value < min_value then
        return min_value
    end

    if value > max_value then
        return max_value
    end

    return value
end

local function set_display(element_id, is_visible)
    if widget == nil then
        return
    end

    widget:SetProperty(element_id, "display", is_visible and "block" or "none")
end

local function set_text(element_id, value)
    if widget == nil then
        return
    end

    widget:SetText(element_id, tostring(value))
end

-- "selected" 여부에 따라 class 속성 전체를 다시 써서 .selected RCSS를 토글한다
-- (UserWidget에는 SetClass가 없고 SetAttribute만 있다)
local function set_input_mode_row_selected(element_id, is_selected)
    if widget == nil then
        return
    end

    local class_value = is_selected and "input_mode_row selected" or "input_mode_row"
    widget:SetAttribute(element_id, "class", class_value)
end

-- 화면에서 조정 중인 sfxVolume 값을 그대로 사용 — 볼륨 +/- 클릭음이 곧 미리듣기가 된다
local function play_ui_click()
    AudioManager.Play(UI_CLICK_KEY, UserSettings.VolumeToScalar(settings.sfxVolume))
end

local function play_ui_hover()
    AudioManager.Play(UI_HOVER_KEY, UserSettings.VolumeToScalar(settings.sfxVolume))
end

local function on_button_click(callback)
    return function()
        play_ui_click()
        callback()
    end
end

local function bind_hover_sound(element_id)
    if widget == nil or widget.bind_hover == nil then
        return
    end

    widget:bind_hover(element_id, function()
        play_ui_hover()
    end)
end

-- 화면에 표시되는 볼륨 숫자/입력 모드 선택 표시를 settings 값에 맞춰 갱신한다
local function apply_settings_to_view()
    if widget == nil then
        return
    end

    set_text("sfx_volume_value", settings.sfxVolume)
    set_text("bgm_volume_value", settings.bgmVolume)

    for mode, element_id in pairs(INPUT_MODE_ROW_IDS) do
        set_input_mode_row_selected(element_id, mode == settings.inputMode)
    end
end

local function set_sfx_volume(value)
    settings.sfxVolume = clamp(value, MIN_VOLUME, MAX_VOLUME)
    apply_settings_to_view()
end

local function set_bgm_volume(value)
    settings.bgmVolume = clamp(value, MIN_VOLUME, MAX_VOLUME)
    apply_settings_to_view()
end

local function set_input_mode(mode)
    if INPUT_MODE_ROW_IDS[mode] == nil then
        return
    end

    settings.inputMode = mode
    apply_settings_to_view()
end

local function bind_actions()
    if widget == nil or bindings_initialized or widget.bind_click == nil then
        return
    end

    widget:bind_click("options_back_button", on_button_click(function()
        if on_back ~= nil then
            on_back()
        end
    end))

    widget:bind_click("options_confirm_button", on_button_click(function()
        if on_confirm ~= nil then
            on_confirm(settings)
        end
    end))

    widget:bind_click("sfx_volume_down", on_button_click(function()
        set_sfx_volume(settings.sfxVolume - 1)
    end))

    widget:bind_click("sfx_volume_up", on_button_click(function()
        set_sfx_volume(settings.sfxVolume + 1)
    end))

    widget:bind_click("bgm_volume_down", on_button_click(function()
        set_bgm_volume(settings.bgmVolume - 1)
    end))

    widget:bind_click("bgm_volume_up", on_button_click(function()
        set_bgm_volume(settings.bgmVolume + 1)
    end))

    widget:bind_click("input_mode_mouse_key", on_button_click(function()
        set_input_mode("mouse_key")
    end))

    widget:bind_click("input_mode_gamepad", on_button_click(function()
        set_input_mode("gamepad")
    end))

    bind_hover_sound("options_back_button")
    bind_hover_sound("options_confirm_button")
    bind_hover_sound("sfx_volume_down")
    bind_hover_sound("sfx_volume_up")
    bind_hover_sound("bgm_volume_down")
    bind_hover_sound("bgm_volume_up")
    bind_hover_sound("input_mode_mouse_key")
    bind_hover_sound("input_mode_gamepad")

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

    widget:SetWantsMouse(visible)

    if widget.IsInViewport == nil or not widget:IsInViewport() then
        widget:AddToViewportZ(OPTIONS_Z_ORDER)
    end

    bind_actions()
    set_display("options_root", visible)
    apply_settings_to_view()

    return widget
end

-- 옵션 UI 생성 진입점
-- options.initialSettings = { sfxVolume, bgmVolume, inputMode } (선택)
-- options.onConfirm = function(settings) end
-- options.onBack = function() end
function M.Create(options)
    options = options or {}
    on_confirm = options.onConfirm
    on_back = options.onBack

    local initial = options.initialSettings
    if initial ~= nil then
        settings.sfxVolume = clamp(tonumber(initial.sfxVolume) or DEFAULT_SFX_VOLUME, MIN_VOLUME, MAX_VOLUME)
        settings.bgmVolume = clamp(tonumber(initial.bgmVolume) or DEFAULT_BGM_VOLUME, MIN_VOLUME, MAX_VOLUME)
        settings.inputMode = INPUT_MODE_ROW_IDS[initial.inputMode] ~= nil and initial.inputMode or DEFAULT_INPUT_MODE
    end

    if ensure_widget() == nil then
        return nil
    end

    return widget
end

-- 옵션 화면을 띄운다 (어둡게 덮기 + 옵션 패널)
function M.Show()
    visible = true

    if ensure_widget() == nil then
        return
    end

    widget:SetWantsMouse(true)
    set_display("options_root", true)
end

-- 옵션 화면을 닫는다
function M.Hide()
    visible = false

    if widget == nil then
        return
    end

    widget:SetWantsMouse(false)
    set_display("options_root", false)
end

function M.IsVisible()
    return visible
end

-- 현재 화면에 표시 중인 설정값을 반환한다 ({ sfxVolume, bgmVolume, inputMode })
function M.GetSettings()
    return {
        sfxVolume = settings.sfxVolume,
        bgmVolume = settings.bgmVolume,
        inputMode = settings.inputMode,
    }
end

-- 외부 설정값을 화면에 반영한다 (예: 저장된 값 불러오기)
function M.ApplySettings(new_settings)
    if new_settings == nil then
        return
    end

    if new_settings.sfxVolume ~= nil then
        settings.sfxVolume = clamp(tonumber(new_settings.sfxVolume) or settings.sfxVolume, MIN_VOLUME, MAX_VOLUME)
    end

    if new_settings.bgmVolume ~= nil then
        settings.bgmVolume = clamp(tonumber(new_settings.bgmVolume) or settings.bgmVolume, MIN_VOLUME, MAX_VOLUME)
    end

    if new_settings.inputMode ~= nil and INPUT_MODE_ROW_IDS[new_settings.inputMode] ~= nil then
        settings.inputMode = new_settings.inputMode
    end

    apply_settings_to_view()
end

-- 옵션 UI 제거 및 내부 상태 초기화
function M.Destroy()
    if widget ~= nil then
        widget:RemoveFromParent()
    end

    widget = nil
    bindings_initialized = false
    visible = false
    on_confirm = nil
    on_back = nil
    settings.sfxVolume = DEFAULT_SFX_VOLUME
    settings.bgmVolume = DEFAULT_BGM_VOLUME
    settings.inputMode = DEFAULT_INPUT_MODE
end

return M
