-- =============================================================================
-- ModalDialogUIController — 공통 반투명 팝업 UI
-- [역할] Pause / Result 확인 팝업에서 같은 어두운 배경 + 중앙 버튼 스타일을 재사용한다.
-- [사용법]
--   Modal.Create({ title, message, leftText, rightText, onLeft, onRight, zOrder })
--   Modal.Show()
-- =============================================================================

local Settings = require("Data/UserSettings")
local Cursor = require("UI/CursorSpriteUtil")

local UI_DOCUMENT_PATH = "Content/UI/Common/modal_dialog.rml"
local DEFAULT_Z_ORDER = 260
local UI_CLICK_KEY = "sfx_ui_click"
-- rcss .modal_cursor_image의 width/height와 같은 값 — 이미지 중앙을 클릭 지점에 맞추는 데 쓴다
local CURSOR_SIZE = Cursor.GetDefaultSize()

local M = {}

local widget = nil
local bindings_initialized = false
local visible = false
local current_z_order = DEFAULT_Z_ORDER
local on_left = nil
local on_right = nil
local current_button_style = "image"
local current_button_count = 1
local current_input_enabled = false
-- 커서 스프라이트 사용 여부 (Pause처럼 OS 커서를 숨긴 채 뜨는 모달이 켠다)
local show_cursor = false
-- 제목 유무 (제목이 없으면 modal_no_title 클래스로 문구를 위로 올린다 — 컷씬 모달)
local current_has_title = true

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

local function set_value(element_id, value)
    if widget == nil or widget.SetValue == nil then
        return
    end

    widget:SetValue(element_id, tostring(value or ""))
end

local function get_value(element_id)
    if widget == nil or widget.GetValue == nil then
        return ""
    end

    return tostring(widget:GetValue(element_id) or "")
end

local function set_button_style(element_id, style_name)
    if widget == nil then
        return
    end

    local class_value = "modal_button ui_horizontal_button_small"
    if style_name == "text_only" then
        class_value = class_value .. " text_only"
    end

    widget:SetAttribute(element_id, "class", class_value)
end

local function set_root_class(button_count)
    if widget == nil then
        return
    end

    local class_value = visible and "" or "modal_hidden"

    if button_count <= 1 then
        class_value = class_value .. " modal_one_button"
    else
        class_value = class_value .. " modal_two_buttons"
    end

    if current_input_enabled then
        class_value = class_value .. " modal_with_input"
    end

    if not current_has_title then
        class_value = class_value .. " modal_no_title"
    end

    widget:SetAttribute("modal_root", "class", class_value)
end

local function play_ui_click()
    if AudioManager ~= nil and AudioManager.Play ~= nil then
        AudioManager.Play(UI_CLICK_KEY, Settings.GetSfxVolumeScalar())
    end
end

-- 커서 스프라이트를 마우스 위치(중앙 핫스팟)로 옮기고 클릭 상태에 맞는 한 장만 켠다.
-- 일시정지 중엔 씬 Tick이 멈추므로 mousemove 이벤트(아래 bind_actions)로만 갱신된다.
local function update_cursor_sprite()
    if widget == nil then
        return
    end

    Cursor.Update(widget, "modal_cursor_normal", "modal_cursor_click", {
        visible = show_cursor and visible,
        size = CURSOR_SIZE,
    })
end

local function hide_cursor_sprite()
    Cursor.Hide(widget, "modal_cursor_normal", "modal_cursor_click")
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

    -- modal_root가 전체 화면이라 모든 마우스 이동이 여기로 버블된다
    if widget.bind_mousemove ~= nil then
        widget:bind_mousemove("modal_root", update_cursor_sprite)
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
    current_button_style = options.buttonStyle or "image"
    current_input_enabled = options.input == true
    show_cursor = options.showCursor == true
    current_has_title = options.title ~= nil and options.title ~= ""

    if ensure_widget() == nil then
        return nil
    end

    set_text("modal_title", options.title or "")
    set_text("modal_message", options.message or "")
    set_text("modal_button_left_label", options.leftText or "OK")
    set_text("modal_button_right_label", options.rightText or "")
    set_text("modal_input_rule", options.inputRule or "")
    set_text("modal_input_error", options.inputError or "")
    set_value("modal_text_input", options.inputValue or "")
    set_display("modal_input_area", current_input_enabled)

    set_button_style("modal_button_left", current_button_style)
    set_button_style("modal_button_right", current_button_style)

    local has_left_button = options.leftText ~= nil
    local has_right_button = options.rightText ~= nil
    set_display("modal_button_left", has_left_button)
    set_display("modal_button_right", has_right_button)
    current_button_count = has_right_button and 2 or 1
    set_root_class(current_button_count)

    return widget
end

function M.Show()
    visible = true

    if ensure_widget() == nil then
        return
    end

    widget:SetWantsMouse(true)
    set_display("modal_root", true)
    -- display를 직접 켠 뒤에도 class를 한 번 더 갱신해서 modal_hidden을 제거한다.
    set_root_class(current_button_count)
    update_cursor_sprite()   -- 마우스가 안 움직여도 첫 위치는 보여야 한다
end

function M.Hide()
    visible = false

    if widget == nil then
        return
    end

    widget:SetWantsMouse(false)
    set_display("modal_root", false)
    set_root_class(current_button_count)
    hide_cursor_sprite()
end

function M.IsVisible()
    return visible
end

function M.GetInputText()
    return get_value("modal_text_input")
end

function M.SetInputText(value)
    set_value("modal_text_input", value)
end

function M.SetInputError(value)
    set_text("modal_input_error", value or "")
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
    current_button_style = "image"
    current_button_count = 1
    current_input_enabled = false
    show_cursor = false
    current_has_title = true
end

return M
