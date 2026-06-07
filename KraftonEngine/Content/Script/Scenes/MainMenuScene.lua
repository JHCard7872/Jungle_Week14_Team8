-- =============================================================================
-- MainMenuScene - MainMenuScene.Scene 전용.
-- Title.Scene에서 분리된 메인 메뉴 본체. 하위 페이지는 SubMenuPage 성격의
-- SubMenuPageUIController가 공통 오버레이로 담당한다.
-- =============================================================================

local SubMenuPageUI = require("UI/SubMenuPageUIController")
local QuestionPopup = require("UI/QuestionPopupUIController")
local UserSettings = require("Data/UserSettings")
local ScoreStorage = require("Data/ScoreStorage")
local Session = require("GameSession")

local UI_ROOT_PATH = "Content/UI/"
local MAIN_MENU_RELATIVE_PATH = "MainMenu/main_menu.rml"
local MAIN_MENU_Z_ORDER = 100
local CURSOR_SIZE = 150
local VK_LBUTTON = 0x01

local MAIN_BGM_KEY = "bgm_main_0"
local UI_CLICK_KEY = "sfx_ui_click"
local UI_HOVER_KEY = "sfx_ui_hover"
local SUB_PAGE_FADE_DURATION = 0.3
local DEFAULT_MAIN_MENU_FADE_IN_DURATION = 0.0

local main_menu_widget = nil
local bindings_initialized = false
local sub_page_open = false
local sub_page_fading_in = false
local sub_page_fading_out = false
local sub_page_fade_elapsed = 0.0
local main_menu_fading_in = false
local main_menu_fade_elapsed = 0.0
local main_menu_fade_duration = 0.0
local exit_prompt_open = false
local pending_scene_name = nil

local menu_settings = UserSettings.GetSettings()

local function build_ui_path(relative_path)
    return UI_ROOT_PATH .. relative_path
end

local function refresh_menu_settings()
    menu_settings = UserSettings.GetSettings()
end

local function get_sfx_volume_scalar()
    return UserSettings.GetSfxVolumeScalar()
end

local function get_bgm_volume_scalar()
    return UserSettings.GetBgmVolumeScalar()
end

local function apply_menu_settings(settings)
    menu_settings = UserSettings.Apply(settings)
end

local function apply_current_menu_bgm_volume()
    UserSettings.ApplyCurrentBgmVolume(MAIN_BGM_KEY)
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

local function consume_main_menu_fade_in_duration()
    local scene_transition = Session.sceneTransition
    if scene_transition == nil then
        return DEFAULT_MAIN_MENU_FADE_IN_DURATION
    end

    local duration = tonumber(scene_transition.mainMenuFadeInDuration) or DEFAULT_MAIN_MENU_FADE_IN_DURATION
    scene_transition.mainMenuFadeInDuration = 0.0
    return math.max(0.0, duration)
end

local function set_cursor_hidden()
    if main_menu_widget == nil then
        return
    end

    set_element_display("cursor_normal", false)
    set_element_display("cursor_click", false)
end

local function start_main_menu_fade_in(duration)
    if main_menu_widget == nil then
        return
    end

    main_menu_fade_duration = math.max(0.001, duration)
    main_menu_fade_elapsed = 0.0
    main_menu_fading_in = true
    set_element_opacity("menu_fade_overlay", 1.0)
    main_menu_widget:SetWantsMouse(false)
    set_cursor_hidden()
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
    local left = string.format("%dpx", mouse_x - CURSOR_SIZE / 2)
    local top = string.format("%dpx", mouse_y - CURSOR_SIZE / 2)

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

    main_menu_widget:SetWantsMouse(true)
    set_element_display("menu_content", true)
    set_element_opacity("menu_content", 1.0)
    set_element_display("title_overlay", false)
    set_element_opacity("menu_fade_overlay", 0.0)
    update_cursor_position()
    set_cursor_state(Input.GetKey(VK_LBUTTON))

    return main_menu_widget
end

local function play_ui_click()
    AudioManager.Play(UI_CLICK_KEY, get_sfx_volume_scalar())
end

local function play_ui_hover()
    AudioManager.Play(UI_HOVER_KEY, get_sfx_volume_scalar())
end

local function set_main_menu_controls_visible(is_visible)
    set_element_display("menu_help", is_visible)
    set_element_display("menu_option", is_visible)
    set_element_display("menu_play", is_visible)
    set_element_display("menu_scoreboard", is_visible)
    set_element_display("menu_credits", is_visible)
    set_element_display("menu_back_to_title", is_visible)
    set_element_display("menu_exit_game", is_visible)

    if not is_visible then
        set_cursor_hidden()
    end
end

local function do_close_menu_page()
    sub_page_open = false
    sub_page_fading_in = false
    sub_page_fading_out = false
    SubMenuPageUI.Destroy()
    Engine.SetCursorVisible(false)

    if main_menu_widget ~= nil then
        set_main_menu_controls_visible(true)
        main_menu_widget:SetWantsMouse(true)
    end
end

local function close_menu_page()
    if not sub_page_open or sub_page_fading_out then
        return
    end

    sub_page_fading_in = false
    sub_page_fading_out = true
    sub_page_fade_elapsed = 0.0
end

local function open_menu_page(page_type, title)
    if main_menu_widget == nil or sub_page_open then
        return
    end

    sub_page_open = true
    main_menu_widget:SetWantsMouse(false)
    set_main_menu_controls_visible(false)
    set_cursor_hidden()
    Engine.SetCursorVisible(true)

    refresh_menu_settings()

    SubMenuPageUI.Create({
        pageType = page_type,
        title = title,
        initialSettings = menu_settings,
        scoreboardEntries = page_type == "scoreboard" and ScoreStorage.ReadTop(5) or nil,
        onSettingsChanged = function(settings, changed_page_type)
            if changed_page_type == "options" then
                apply_menu_settings(settings)
                apply_current_menu_bgm_volume()
            end
        end,
        onBack = function()
            close_menu_page()
        end,
        onConfirm = function(settings, confirmed_page_type)
            if confirmed_page_type == "options" then
                apply_menu_settings(settings)
            end

            close_menu_page()
        end,
    })

    SubMenuPageUI.Show()
    sub_page_fading_in = true
    sub_page_fade_elapsed = 0.0
end

local function close_exit_prompt()
    exit_prompt_open = false
    QuestionPopup.Destroy()

    if main_menu_widget == nil or sub_page_open then
        return
    end

    main_menu_widget:SetWantsMouse(true)
    update_cursor_position()
    set_cursor_state(Input.GetKey(VK_LBUTTON))
end

local function open_exit_prompt()
    if main_menu_widget == nil or exit_prompt_open or sub_page_open then
        return
    end

    exit_prompt_open = true
    main_menu_widget:SetWantsMouse(false)
    set_cursor_hidden()

    QuestionPopup.ShowConfirm({
        title = "Exit",
        message = "게임을 종료하시겠습니까?",
        showCursor = true,
        onYes = function()
            Engine.Exit()
        end,
        onNo = function()
            close_exit_prompt()
        end,
    })
end

local function request_scene_load(scene_name)
    if pending_scene_name ~= nil then
        return
    end

    pending_scene_name = scene_name
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
        open_menu_page("controls", "Controls")
    end))

    widget:bind_click("menu_option", on_menu_button_click(function()
        open_menu_page("options", "Options")
    end))

    widget:bind_click("menu_play", on_menu_button_click(function()
        request_scene_load("Cut")
    end))

    widget:bind_click("menu_scoreboard", on_menu_button_click(function()
        open_menu_page("scoreboard", "Scoreboard")
    end))

    widget:bind_click("menu_credits", on_menu_button_click(function()
        open_menu_page("credits", "Credits")
    end))

    widget:bind_click("menu_back_to_title", on_menu_button_click(function()
        request_scene_load("Title")
    end))

    widget:bind_click("menu_exit_game", on_menu_button_click(function()
        open_exit_prompt()
    end))

    bind_hover_sound(widget, "menu_help")
    bind_hover_sound(widget, "menu_option")
    bind_hover_sound(widget, "menu_play")
    bind_hover_sound(widget, "menu_scoreboard")
    bind_hover_sound(widget, "menu_credits")
    bind_hover_sound(widget, "menu_back_to_title")
    bind_hover_sound(widget, "menu_exit_game")

    bindings_initialized = true
end

local function update_sub_page_fade(dt)
    if not sub_page_open then
        return false
    end

    set_cursor_hidden()
    sub_page_fade_elapsed = math.min(sub_page_fade_elapsed + dt, SUB_PAGE_FADE_DURATION)
    local t = sub_page_fade_elapsed / SUB_PAGE_FADE_DURATION

    if sub_page_fading_in then
        SubMenuPageUI.SetOpacity(t)
        if t >= 1.0 then
            sub_page_fading_in = false
        end
    elseif sub_page_fading_out then
        SubMenuPageUI.SetOpacity(1.0 - t)
        if t >= 1.0 then
            do_close_menu_page()
        end
    end

    return true
end

local function update_main_menu_fade_in(dt)
    if not main_menu_fading_in then
        return false
    end

    set_cursor_hidden()
    main_menu_fade_elapsed = math.min(main_menu_fade_elapsed + dt, main_menu_fade_duration)
    local t = main_menu_fade_duration <= 0.0 and 1.0 or (main_menu_fade_elapsed / main_menu_fade_duration)
    set_element_opacity("menu_fade_overlay", 1.0 - t)

    if t >= 1.0 then
        main_menu_fading_in = false
        main_menu_fade_elapsed = 0.0
        main_menu_fade_duration = 0.0
        main_menu_widget:SetWantsMouse(true)
        update_cursor_position()
        set_cursor_state(Input.GetKey(VK_LBUTTON))
    end

    return true
end

function BeginPlay()
    StopAllCoroutines()
    AudioManager.StopAllLoops()

    for key, path in pairs(require("Data/AudioData")) do
        AudioManager.Load(key, path, key:find("^bgm_") ~= nil)
    end
    AudioManager.PlayBGM(MAIN_BGM_KEY, get_bgm_volume_scalar())

    local widget = ensure_widget()
    bind_menu_actions(widget)

    Engine.SetCursorVisible(false)
    sub_page_open = false
    sub_page_fading_in = false
    sub_page_fading_out = false
    sub_page_fade_elapsed = 0.0
    main_menu_fading_in = false
    main_menu_fade_elapsed = 0.0
    main_menu_fade_duration = 0.0
    exit_prompt_open = false
    pending_scene_name = nil

    local fade_in_duration = consume_main_menu_fade_in_duration()
    if widget ~= nil and fade_in_duration > 0.0 then
        start_main_menu_fade_in(fade_in_duration)
    end

    Engine.SetOnEscape(function()
        if sub_page_open then
            close_menu_page()
        elseif exit_prompt_open then
            close_exit_prompt()
        else
            open_exit_prompt()
        end
    end)
end

function Tick(dt)
    if pending_scene_name ~= nil then
        local scene_name = pending_scene_name
        pending_scene_name = nil
        Engine.LoadScene(scene_name)
        return
    end

    if main_menu_widget == nil then
        return
    end

    if exit_prompt_open then
        set_cursor_hidden()
        return
    end

    if update_main_menu_fade_in(dt) then
        return
    end

    if update_sub_page_fade(dt) then
        return
    end

    update_cursor_position()
    set_cursor_state(Input.GetKey(VK_LBUTTON))
end

function EndPlay()
    SubMenuPageUI.Destroy()
    QuestionPopup.Destroy()

    if main_menu_widget ~= nil then
        main_menu_widget:RemoveFromParent()
    end

    Engine.SetCursorVisible(true)
    main_menu_widget = nil
    bindings_initialized = false
    sub_page_open = false
    sub_page_fading_in = false
    sub_page_fading_out = false
    sub_page_fade_elapsed = 0.0
    main_menu_fading_in = false
    main_menu_fade_elapsed = 0.0
    main_menu_fade_duration = 0.0
    exit_prompt_open = false
    pending_scene_name = nil
end
