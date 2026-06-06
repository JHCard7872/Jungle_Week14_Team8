-- =============================================================================
-- PauseUIController — 일시정지 메뉴 UI 컨트롤러
-- [역할] 화면을 30% 어둡게 덮고 Continue 버튼 하나를 띄운다.
-- [사용법] PlayScene 같은 게임플레이 씬에서 Create로 만들고,
--          Show/Hide로 표시 여부만 토글한다. 실제 pause/resume 처리는
--          호출하는 쪽(onContinue 콜백, Engine.SetOnEscape 등)이 담당한다.
-- =============================================================================

local UI_DOCUMENT_PATH = "Content/UI/Pause/pause_menu.rml"
-- HUD(200)보다 위, Result(250)보다 아래에 뜨도록
local PAUSE_Z_ORDER = 220

local M = {}

local widget = nil
local bindings_initialized = false
local visible = false
-- Continue 버튼 클릭 시 호출할 콜백 (보통 togglePause)
local on_continue = nil

local function set_display(element_id, is_visible)
    if widget == nil then
        return
    end

    widget:SetProperty(element_id, "display", is_visible and "block" or "none")
end

local function bind_actions()
    if widget == nil or bindings_initialized or widget.bind_click == nil then
        return
    end

    widget:bind_click("pause_btn_continue", function()
        if on_continue ~= nil then
            on_continue()
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
        widget:AddToViewportZ(PAUSE_Z_ORDER)
    end

    bind_actions()
    set_display("pause_root", visible)

    return widget
end

-- 일시정지 메뉴 UI 생성 진입점
function M.Create(options)
    options = options or {}
    on_continue = options.onContinue

    if ensure_widget() == nil then
        return nil
    end

    return widget
end

-- 메뉴를 띄운다 (어둡게 덮기 + Continue 버튼)
function M.Show()
    visible = true

    if ensure_widget() == nil then
        return
    end

    widget:SetWantsMouse(true)
    set_display("pause_root", true)
    print("[PauseUI] Show -> WantsMouse=" .. tostring(widget:WantsMouse())
        .. " InViewport=" .. tostring(widget:IsInViewport()))
end

-- 메뉴를 닫는다
function M.Hide()
    visible = false

    if widget == nil then
        return
    end

    widget:SetWantsMouse(false)
    set_display("pause_root", false)
end

function M.IsVisible()
    return visible
end

-- UI 제거 및 내부 상태 초기화
function M.Destroy()
    if widget ~= nil then
        widget:RemoveFromParent()
    end

    widget = nil
    bindings_initialized = false
    visible = false
    on_continue = nil
end

return M
