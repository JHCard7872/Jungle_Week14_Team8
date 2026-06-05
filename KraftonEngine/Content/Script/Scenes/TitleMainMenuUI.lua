local UI_ROOT_PATH = "Content/UI/"
local MAIN_MENU_RELATIVE_PATH = "MainMenu/main_menu.rml"
local MAIN_MENU_Z_ORDER = 100
local CURSOR_HOTSPOT_X = 8
local CURSOR_HOTSPOT_Y = 6
local VK_LBUTTON = 0x01

local main_menu_widget = nil
local bindings_initialized = false

local function build_ui_path(relative_path)
    return UI_ROOT_PATH .. relative_path
end

local function set_cursor_state(is_click)
    if main_menu_widget == nil then
        return
    end

    if is_click then
        main_menu_widget:SetProperty("cursor_normal", "display", "none")
        main_menu_widget:SetProperty("cursor_click", "display", "block")
    else
        main_menu_widget:SetProperty("cursor_normal", "display", "block")
        main_menu_widget:SetProperty("cursor_click", "display", "none")
    end
end

local function update_cursor_position()
    if main_menu_widget == nil then
        return
    end

    local mouse_x = Input.GetMouseX()
    local mouse_y = Input.GetMouseY()
    local left = string.format("%dpx", mouse_x - CURSOR_HOTSPOT_X)
    local top = string.format("%dpx", mouse_y - CURSOR_HOTSPOT_Y)

    main_menu_widget:SetProperty("cursor_normal", "left", left)
    main_menu_widget:SetProperty("cursor_normal", "top", top)
    main_menu_widget:SetProperty("cursor_click", "left", left)
    main_menu_widget:SetProperty("cursor_click", "top", top)
end

local function ensure_widget()
    if UI == nil or UI.CreateWidget == nil then
        return nil
    end

    if main_menu_widget == nil then
        main_menu_widget = UI.CreateWidget(build_ui_path(MAIN_MENU_RELATIVE_PATH))
    end

    if main_menu_widget == nil then
        return nil
    end

    main_menu_widget:SetWantsMouse(true)
    if main_menu_widget.IsInViewport == nil or not main_menu_widget:IsInViewport() then
        main_menu_widget:AddToViewportZ(MAIN_MENU_Z_ORDER)
    end

    return main_menu_widget
end

local function bind_menu_actions(widget)
    if bindings_initialized or widget == nil then
        return
    end

    widget:bind_click("menu_help", function()
        print("[TitleMainMenuUI] menu_help clicked")
    end)

    widget:bind_click("menu_option", function()
        print("[TitleMainMenuUI] menu_option clicked")
    end)

    widget:bind_click("menu_play", function()
        Engine.LoadScene("Play")
    end)

    widget:bind_click("menu_scoreboard", function()
        print("[TitleMainMenuUI] menu_scoreboard clicked")
    end)

    widget:bind_click("menu_credits", function()
        print("[TitleMainMenuUI] menu_credits clicked")
    end)

    widget:bind_click("menu_back_to_title", function()
        print("[TitleMainMenuUI] already on the title scene")
    end)

    bindings_initialized = true
end

function BeginPlay()
    local widget = ensure_widget()
    bind_menu_actions(widget)
    Engine.SetCursorVisible(false)
    set_cursor_state(false)
    update_cursor_position()
end

function Tick(dt)
    update_cursor_position()
    set_cursor_state(Input.GetKey(VK_LBUTTON))
end

function EndPlay()
    if main_menu_widget ~= nil then
        main_menu_widget:RemoveFromParent()
    end

    Engine.SetCursorVisible(true)
    main_menu_widget = nil
    bindings_initialized = false
end
