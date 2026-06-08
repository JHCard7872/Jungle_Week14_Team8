-- =============================================================================
-- CursorSpriteUtil — RmlUi 커스텀 커서 공통 유틸
-- [역할] OS 커서를 숨긴 화면에서 cursor.png / cursor_click.png 스프라이트를
--        같은 방식으로 위치시키고 클릭 상태에 맞춰 토글한다.
-- [사용처] MainMenu, Pause, Result action buttons, Common question modal.
-- =============================================================================

local M = {}

local DEFAULT_CURSOR_SIZE = 150
local VK_LBUTTON = 0x01

local function set_display(widget, element_id, is_visible)
    if widget == nil or element_id == nil then
        return
    end

    widget:SetProperty(element_id, "display", is_visible and "block" or "none")
end

function M.GetDefaultSize()
    return DEFAULT_CURSOR_SIZE
end

function M.Hide(widget, normal_id, click_id)
    set_display(widget, normal_id, false)
    set_display(widget, click_id, false)
end

function M.Update(widget, normal_id, click_id, options)
    if widget == nil then
        return
    end

    options = options or {}
    if options.visible == false then
        M.Hide(widget, normal_id, click_id)
        return
    end

    local size = tonumber(options.size) or DEFAULT_CURSOR_SIZE
    local hotspot_x = options.hotspotX
    local hotspot_y = options.hotspotY

    if hotspot_x == nil then
        hotspot_x = size / 2
    end
    if hotspot_y == nil then
        hotspot_y = size / 2
    end

    local left = string.format("%dpx", Input.GetMouseX() - hotspot_x)
    local top = string.format("%dpx", Input.GetMouseY() - hotspot_y)

    widget:SetProperty(normal_id, "left", left)
    widget:SetProperty(normal_id, "top", top)
    widget:SetProperty(click_id, "left", left)
    widget:SetProperty(click_id, "top", top)

    local is_click = Input.GetKey(VK_LBUTTON)
    set_display(widget, normal_id, not is_click)
    set_display(widget, click_id, is_click)
end

return M
