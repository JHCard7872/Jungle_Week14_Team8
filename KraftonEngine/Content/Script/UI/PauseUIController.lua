-- =============================================================================
-- PauseUIController — 일시정지 메뉴 UI 컨트롤러
-- [역할] Result 화면의 Retry/Title 2버튼 오버레이와 같은 형태를 재사용해서
--        Continue / 타이틀로 돌아가기 버튼을 띄운다.
--        타이틀 복귀는 Common Question Modal로 한 번 더 확인한다.
-- =============================================================================

local Cursor = require("UI/CursorSpriteUtil")
local QuestionPopup = require("UI/QuestionPopupUIController")
local Settings = require("Data/UserSettings")

local UI_DOCUMENT_PATH = "Content/UI/Pause/pause_menu.rml"
-- 게임플레이 크로스헤어(z=1000)가 pause 중에도 그려지므로 그 위에 떠야 한다.
-- 확인 모달은 이보다 더 위에 뜬다.
local PAUSE_Z_ORDER = 1100
local QUESTION_Z_ORDER = 1110
local UI_CLICK_KEY = "sfx_ui_click"
local CURSOR_SIZE = Cursor.GetDefaultSize()

local M = {}

local widget = nil
local visible = false
local confirm_open = false
local bindings_initialized = false
local on_continue = nil
local on_go_title = nil

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

local function update_cursor_sprite()
    if widget == nil then
        return
    end

    Cursor.Update(widget, "pause_cursor_normal", "pause_cursor_click", {
        visible = visible and not confirm_open,
        size = CURSOR_SIZE,
    })
end

local function hide_cursor_sprite()
    if widget == nil then
        return
    end

    Cursor.Hide(widget, "pause_cursor_normal", "pause_cursor_click")
end

local function close_confirm_dialog()
    confirm_open = false
    QuestionPopup.Destroy()

    if widget ~= nil and visible then
        widget:SetWantsMouse(true)
        set_display("pause_action_buttons", true)
        update_cursor_sprite()
    end
end

local function show_confirm_dialog()
    if confirm_open then
        return
    end

    confirm_open = true
    if widget ~= nil then
        widget:SetWantsMouse(false)
        set_display("pause_action_buttons", false)
        hide_cursor_sprite()
    end

    QuestionPopup.ShowConfirm({
        zOrder = QUESTION_Z_ORDER,
        title = "타이틀로 돌아가기",
        message = "플레이 중인 데이터가 사라집니다.\n정말로 돌아가시겠습니까?",
        showCursor = true,
        onYes = function()
            if on_go_title ~= nil then
                on_go_title()
            end
        end,
        onNo = function()
            close_confirm_dialog()
        end,
    })
end

local function bind_actions()
    if widget == nil or bindings_initialized or widget.bind_click == nil then
        return
    end

    widget:bind_click("pause_btn_continue", function()
        play_ui_click()
        if on_continue ~= nil then
            on_continue()
        end
    end)

    widget:bind_click("pause_btn_title", function()
        play_ui_click()
        show_confirm_dialog()
    end)

    if widget.bind_mousemove ~= nil then
        widget:bind_mousemove("pause_root", update_cursor_sprite)
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
        widget:AddToViewportZ(PAUSE_Z_ORDER)
    end

    bind_actions()
    return widget
end

function M.Create(options)
    options = options or {}
    on_continue = options.onContinue
    on_go_title = options.onGoTitle

    if ensure_widget() == nil then
        return nil
    end

    set_text("pause_btn_continue_label", options.continueText or "Continue")
    set_text("pause_btn_title_label", options.titleText or "타이틀로 돌아가기")
    set_display("pause_action_buttons", false)
    hide_cursor_sprite()
    widget:SetWantsMouse(false)

    return true
end

function M.Show()
    if ensure_widget() == nil then
        return
    end

    visible = true
    confirm_open = false
    QuestionPopup.Destroy()
    set_display("pause_action_buttons", true)
    widget:SetWantsMouse(true)
    update_cursor_sprite()
end

function M.Hide()
    visible = false
    confirm_open = false
    QuestionPopup.Destroy()

    if widget ~= nil then
        widget:SetWantsMouse(false)
        set_display("pause_action_buttons", false)
        hide_cursor_sprite()
    end
end

function M.IsVisible()
    return visible
end

function M.Destroy()
    QuestionPopup.Destroy()

    if widget ~= nil then
        widget:RemoveFromParent()
    end

    widget = nil
    visible = false
    confirm_open = false
    bindings_initialized = false
    on_continue = nil
    on_go_title = nil
end

return M
