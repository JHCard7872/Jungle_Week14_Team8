local MenuPageUI = require("UI/MenuPageUIController")
local UserSettings = require("Data/UserSettings")
local ScoreStorage = require("Data/ScoreStorage")

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
local SUB_PAGE_FADE_DURATION = 0.3

local main_menu_widget = nil
local bindings_initialized = false
local title_screen_active = true
local fading_to_title = false
local menu_fade_elapsed = 0.0
local press_blink_elapsed = 0.0
local sub_page_fading_in = false
local sub_page_fading_out = false
local sub_page_fade_elapsed = 0.0
-- 옵션 화면이 떠 있는 동안에는 메인 메뉴 입력/커스텀 커서를 멈춰둔다
local options_open = false

-- 옵션 페이지에서 조정한 값은 UserSettings 모듈에 저장해서 씬을 넘어 유지한다.
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
    UserSettings.ApplyCurrentBgmVolume(title_screen_active and "bgm_title_0" or MAIN_BGM_KEY)
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
    AudioManager.Play(UI_CLICK_KEY, get_sfx_volume_scalar())
end

local function play_ui_hover()
    AudioManager.Play(UI_HOVER_KEY, get_sfx_volume_scalar())
end

-- 옵션 화면을 띄운다: 메인 메뉴 입력/커스텀 커서를 끄고 OS 커서로 전환한다
-- 조작법/스코어보드/크레딧도 같은 공통 페이지 UI를 사용한다
local function set_main_menu_controls_visible(is_visible)
    set_element_display("menu_help", is_visible)
    set_element_display("menu_option", is_visible)
    set_element_display("menu_play", is_visible)
    set_element_display("menu_scoreboard", is_visible)
    set_element_display("menu_credits", is_visible)
    set_element_display("menu_back_to_title", is_visible)

    -- 라벨은 RCSS :hover에서만 제어한다.
    -- 여기서 SetProperty("display", "none")을 걸면 inline style이 남아서
    -- 하위 페이지를 닫은 뒤에도 :hover 규칙이 다시 적용되지 않는다.

    if not is_visible then
        set_cursor_hidden()
    end
end

-- 서브페이지 fade-out 완료 후 실제 정리
local function do_close_menu_page()
    options_open = false
    sub_page_fading_in = false
    sub_page_fading_out = false
    MenuPageUI.Destroy()
    Engine.SetCursorVisible(false)

    if main_menu_widget ~= nil then
        set_main_menu_controls_visible(true)
        main_menu_widget:SetWantsMouse(true)
    end
end

-- 서브페이지 fade-out 시작 (닫기 버튼/Confirm 콜백에서 호출)
local function close_menu_page()
    if not options_open or sub_page_fading_out then
        return
    end

    sub_page_fading_in = false
    sub_page_fading_out = true
    sub_page_fade_elapsed = 0.0
end

local function open_menu_page(page_type, title)
    if main_menu_widget == nil or options_open then
        return
    end

    options_open = true
    main_menu_widget:SetWantsMouse(false)
    set_main_menu_controls_visible(false)
    set_cursor_hidden()
    Engine.SetCursorVisible(true)

    refresh_menu_settings()

    MenuPageUI.Create({
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

    MenuPageUI.Show()
    sub_page_fading_in = true
    sub_page_fade_elapsed = 0.0
end

local function open_options()
    open_menu_page("options", "Options")
end

local function open_controls()
    open_menu_page("controls", "Controls")
end

local function open_scoreboard()
    open_menu_page("scoreboard", "Scoreboard")
end

local function open_credits()
    open_menu_page("credits", "Credits")
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

local set_title_screen_state = nil
local start_title_return_fade = nil

local function bind_menu_actions(widget)
    if bindings_initialized or widget == nil then
        return
    end

    widget:bind_click("menu_help", on_menu_button_click(function()
        open_controls()
    end))

    widget:bind_click("menu_option", on_menu_button_click(function()
        open_options()
    end))

    widget:bind_click("menu_play", on_menu_button_click(function()
        Engine.LoadScene("Play")
    end))

    widget:bind_click("menu_scoreboard", on_menu_button_click(function()
        open_scoreboard()
    end))

    widget:bind_click("menu_credits", on_menu_button_click(function()
        open_credits()
    end))

    widget:bind_click("menu_back_to_title", on_menu_button_click(function()
        close_menu_page()
        AudioManager.PlayBGM("bgm_title_0", get_bgm_volume_scalar())
        start_title_return_fade()
    end))

    bind_hover_sound(widget, "menu_help")
    bind_hover_sound(widget, "menu_option")
    bind_hover_sound(widget, "menu_play")
    bind_hover_sound(widget, "menu_scoreboard")
    bind_hover_sound(widget, "menu_credits")
    bind_hover_sound(widget, "menu_back_to_title")

    bindings_initialized = true
end

set_title_screen_state = function()
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
    AudioManager.PlayBGM(MAIN_BGM_KEY, get_bgm_volume_scalar())
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

-- 메인 메뉴 → 타이틀 페이드 아웃/인
start_title_return_fade = function()
    if main_menu_widget == nil or fading_to_title then
        return
    end

    fading_to_title = true
    menu_fade_elapsed = 0.0
    main_menu_widget:SetWantsMouse(false)
    set_element_display("menu_content", true)
    set_element_display("title_overlay", true)
    set_element_opacity("menu_content", 1.0)
    set_element_opacity("title_overlay", 0.0)
    set_cursor_hidden()
end

local function update_title_return_fade(dt)
    if main_menu_widget == nil then
        return
    end

    menu_fade_elapsed = math.min(menu_fade_elapsed + dt, MENU_FADE_DURATION)
    local alpha = menu_fade_elapsed / MENU_FADE_DURATION

    set_element_opacity("menu_content", 1.0 - alpha)
    set_element_opacity("title_overlay", alpha)

    if alpha >= 1.0 then
        fading_to_title = false
        title_screen_active = true
        press_blink_elapsed = 0.0
        set_element_display("press_any_button", true)
    end
end

function BeginPlay()
    local widget = ensure_widget()
    bind_menu_actions(widget)


    Engine.SetCursorVisible(false)
    press_blink_elapsed = 0.0
    options_open = false
    set_title_screen_state()
end

function Tick(dt)
    if main_menu_widget == nil then
        return
    end

    if fading_to_title then
        update_title_return_fade(dt)
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

    -- 옵션 화면이 떠 있는 동안에는 메인 메뉴의 커스텀 커서 갱신을 멈춘다 (OS 커서 사용)
    -- 조작법/스코어보드/크레딧 하위 페이지도 동일하게 처리한다
    if options_open then
        set_cursor_hidden()
        sub_page_fade_elapsed = math.min(sub_page_fade_elapsed + dt, SUB_PAGE_FADE_DURATION)
        local t = sub_page_fade_elapsed / SUB_PAGE_FADE_DURATION
        if sub_page_fading_in then
            MenuPageUI.SetOpacity(t)
            if t >= 1.0 then
                sub_page_fading_in = false
            end
        elseif sub_page_fading_out then
            MenuPageUI.SetOpacity(1.0 - t)
            if t >= 1.0 then
                do_close_menu_page()
            end
        end
        return
    end

    update_cursor_position()
    set_cursor_state(Input.GetKey(VK_LBUTTON))
end

function EndPlay()
    MenuPageUI.Destroy()

    if main_menu_widget ~= nil then
        main_menu_widget:RemoveFromParent()
    end

    Engine.SetCursorVisible(true)
    main_menu_widget = nil
    bindings_initialized = false
    options_open = false
    sub_page_fading_in = false
    sub_page_fading_out = false
    sub_page_fade_elapsed = 0.0
    title_screen_active = true
    fading_to_title = false
    menu_fade_elapsed = 0.0
    press_blink_elapsed = 0.0
end
