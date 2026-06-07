-- =============================================================================
-- ModalDialogUIController — 공통 반투명 팝업 UI
-- [역할] Pause / Result 확인 팝업에서 같은 어두운 배경 + 중앙 버튼 스타일을 재사용한다.
-- [사용법]
--   Modal.Create({ title, message, leftText, rightText, onLeft, onRight, zOrder })
--   Modal.Show()
-- =============================================================================

local UI_DOCUMENT_PATH = "Content/UI/Common/modal_dialog.rml"
local DEFAULT_Z_ORDER = 260
local UI_CLICK_KEY = "sfx_ui_click"

local Settings = require("Data/UserSettings")

local M = {}

local widget = nil
local bindings_initialized = false
local visible = false
local current_z_order = DEFAULT_Z_ORDER
local on_left = nil
local on_right = nil

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

    widget:SetText(element_id, tostring(value or ""))
end

local function play_ui_click()
    if AudioManager ~= nil and AudioManager.Play ~= nil then
        AudioManager.Play(UI_CLICK_KEY, Settings.GetSfxVolumeScalar())
    end
end

local function bind_actions()
    if widget == nil or bindings_initialized or widget.bind_click == nil then
        return
    end

    widget:bind_click("modal_button_left", function()
        play_ui_click()
        if on_left ~= nil then
            on_left()
        end
    end)

    widget:bind_click("modal_button_right", function()
        play_ui_click()
        if on_right ~= nil then
            on_right()
        end
    end)

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
        widget:AddToViewportZ(current_z_order)
    end

    bind_actions()
    set_display("modal_root", visible)

    return widget
end

function M.Create(options)
    options = options or {}
    current_z_order = options.zOrder or DEFAULT_Z_ORDER
    on_left = options.onLeft
    on_right = options.onRight

    if ensure_widget() == nil then
        return nil
    end

    set_text("modal_title", options.title or "")
    set_text("modal_message", options.message or "")
    set_text("modal_button_left_label", options.leftText or "OK")
    set_text("modal_button_right_label", options.rightText or "")

    set_display("modal_button_left", options.leftText ~= nil)
    set_display("modal_button_right", options.rightText ~= nil)

    if options.rightText == nil then
        widget:SetProperty("modal_button_left", "left", "50%")
        widget:SetProperty("modal_button_left", "margin-left", "-220px")
    else
        widget:SetProperty("modal_button_left", "left", "40px")
        widget:SetProperty("modal_button_left", "margin-left", "0px")
    end

    return widget
end

function M.Show()
    visible = true

    if ensure_widget() == nil then
        return
    end

    widget:SetWantsMouse(true)
    set_display("modal_root", true)
end

function M.Hide()
    visible = false

    if widget == nil then
        return
    end

    widget:SetWantsMouse(false)
    set_display("modal_root", false)
end

function M.IsVisible()
    return visible
end

function M.Destroy()
    if widget ~= nil then
        widget:RemoveFromParent()
    end

    widget = nil
    bindings_initialized = false
    visible = false
    current_z_order = DEFAULT_Z_ORDER
    on_left = nil
    on_right = nil
end

return M
