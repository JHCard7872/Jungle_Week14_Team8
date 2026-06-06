local UI_ROOT_PATH = "Content/UI/"
local MAIN_MENU_RELATIVE_PATH = "MainMenu/main_menu.rml"
local MAIN_MENU_Z_ORDER = 100
local CURSOR_HOTSPOT_X = 8
local CURSOR_HOTSPOT_Y = 6
local VK_LBUTTON = 0x01

local MAIN_BGM_KEY = "bgm_main_0"
local UI_CLICK_KEY = "sfx_ui_click"
local UI_HOVER_KEY = "sfx_ui_hover"
local MENU_BGM_VOLUME = 0.6
local SFX_VOLUME = 1.0
local MENU_FADE_DURATION = 0.45
local PRESS_BLINK_SPEED = 3.2

local main_menu_widget = nil
local bindings_initialized = false
local title_screen_active = true
local menu_fade_elapsed = 0.0
local press_blink_elapsed = 0.0

local function build_ui_path(relative_path)
    return UI_ROOT_PATH .. relative_path
end

local function set_element_display(element_id, is_visible)
    if main_menu_widget == nil then
        return
    end

    main_menu_widget:SetProperty(element_id, "display", is_visible and "block" or "none")
end

local function set_element_opacity(element_id, alpha)
    if main_menu_widget == nil then
        return
    end

    local clamped = math.max(0.0, math.min(1.0, alpha))
    main_menu_widget:SetProperty(element_id, "opacity", string.format("%.3f", clamped))
end

local function set_cursor_hidden()
    if main_menu_widget == nil then
        return
    end

    set_element_display("cursor_normal", false)
    set_element_display("cursor_click", false)
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

    if main_menu_widget.IsInViewport == nil or not main_menu_widget:IsInViewport() then
        main_menu_widget:AddToViewportZ(MAIN_MENU_Z_ORDER)
    end

    return main_menu_widget
end

local function play_ui_click()
    AudioManager.Play(UI_CLICK_KEY, SFX_VOLUME)
end

local function play_ui_hover()
    AudioManager.Play(UI_HOVER_KEY, SFX_VOLUME)
end

local function on_menu_button_click(callback)
    return function()
        play_ui_click()
        callback()
    end
end

local function bind_hover_sound(widget, element_id)
    widget:bind_hover(element_id, function()
        play_ui_hover()
    end)
end

local function bind_menu_actions(widget)
    if bindings_initialized or widget == nil then
        return
    end

    widget:bind_click("menu_help", on_menu_button_click(function()
        print("[TitleMainMenuUI] menu_help clicked")
    end))

    widget:bind_click("menu_option", on_menu_button_click(function()
        print("[TitleMainMenuUI] menu_option clicked")
    end))

    widget:bind_click("menu_play", on_menu_button_click(function()
        Engine.LoadScene("Play")
    end))

    widget:bind_click("menu_scoreboard", on_menu_button_click(function()
        print("[TitleMainMenuUI] menu_scoreboard clicked")
    end))

    widget:bind_click("menu_credits", on_menu_button_click(function()
        print("[TitleMainMenuUI] menu_credits clicked")
    end))

    widget:bind_click("menu_back_to_title", on_menu_button_click(function()
        Engine.LoadScene("Title")
    end))

    bind_hover_sound(widget, "menu_help")
    bind_hover_sound(widget, "menu_option")
    bind_hover_sound(widget, "menu_play")
    bind_hover_sound(widget, "menu_scoreboard")
    bind_hover_sound(widget, "menu_credits")
    bind_hover_sound(widget, "menu_back_to_title")

    bindings_initialized = true
end

local function set_title_screen_state()
    if main_menu_widget == nil then
        return
    end

    title_screen_active = true
    menu_fade_elapsed = 0.0

    main_menu_widget:SetWantsMouse(false)
    set_element_display("menu_content", true)
    set_element_opacity("menu_content", 0.0)
    set_element_display("title_overlay", true)
    set_element_opacity("title_overlay", 1.0)
    set_element_display("press_any_button", true)
    set_cursor_hidden()
end

local function activate_main_menu()
    if main_menu_widget == nil or not title_screen_active then
        return
    end

    title_screen_active = false
    menu_fade_elapsed = 0.0
    play_ui_click()
    AudioManager.PlayBGM(MAIN_BGM_KEY, MENU_BGM_VOLUME)
    set_element_display("menu_content", true)
    set_element_display("title_overlay", true)
end

local function is_any_start_button_pressed()
    for vk = 1, 255 do
        if vk ~= Key.Escape and Input.GetKeyDown(vk) then
            return true
        end
    end

    return false
end

local function update_press_prompt(dt)
    if main_menu_widget == nil then
        return
    end

    press_blink_elapsed = press_blink_elapsed + dt
    local blink = 0.5 + 0.5 * math.sin(press_blink_elapsed * math.pi * PRESS_BLINK_SPEED)
    local alpha = 0.25 + blink * 0.75
    set_element_opacity("press_any_button", alpha)
end

local function update_menu_fade(dt)
    if main_menu_widget == nil then
        return
    end

    menu_fade_elapsed = math.min(menu_fade_elapsed + dt, MENU_FADE_DURATION)
    local alpha = menu_fade_elapsed / MENU_FADE_DURATION

    set_element_opacity("menu_content", alpha)
    set_element_opacity("title_overlay", 1.0 - alpha)

    if alpha >= 1.0 then
        set_element_display("title_overlay", false)
        main_menu_widget:SetWantsMouse(true)
        update_cursor_position()
        set_cursor_state(Input.GetKey(VK_LBUTTON))
        return true
    end

    set_cursor_hidden()
    return false
end

function BeginPlay()
    local widget = ensure_widget()
    bind_menu_actions(widget)

    Engine.SetCursorVisible(false)
    press_blink_elapsed = 0.0
    set_title_screen_state()
end

function Tick(dt)
    if main_menu_widget == nil then
        return
    end

    if title_screen_active then
        update_press_prompt(dt)
        if is_any_start_button_pressed() then
            activate_main_menu()
        end
        return
    end

    if not update_menu_fade(dt) then
        return
    end

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
    title_screen_active = true
    menu_fade_elapsed = 0.0
    press_blink_elapsed = 0.0
end
