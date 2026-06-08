local Session = require("GameSession")
local UserSettings = require("Data/UserSettings")

local TITLE_UI_PATH = "Content/UI/TitleScreen/title_screen.rml"
local TITLE_UI_Z_ORDER = 100
local PRESS_BLINK_SPEED_IDLE = 3.2
local PRESS_BLINK_SPEED_FAST = 12.0
local START_SFX_KEY = "sfx_game_start"
local START_SFX_DURATION = 2.0
local TITLE_FADE_DURATION = 1.0
local MAIN_MENU_FADE_IN_DURATION = 0.5

local title_widget = nil
local press_blink_elapsed = 0.0
local waiting_for_input = false
local pending_scene_name = nil
local transition_phase = "idle"
local transition_elapsed = 0.0
local transition_duration = 0.0

local function request_scene_load(scene_name)
    if pending_scene_name ~= nil then
        return
    end

    pending_scene_name = scene_name
end

local function is_any_button_pressed()
    for vk = 1, 255 do
        if Input.GetKeyDown(vk) then
            return true
        end
    end

    return false
end

local function set_element_opacity(element_id, alpha)
    if title_widget == nil then
        return
    end

    local clamped = math.max(0.0, math.min(1.0, alpha))
    title_widget:SetProperty(element_id, "opacity", string.format("%.3f", clamped))
end

local function set_fade_overlay_opacity(alpha)
    set_element_opacity("title_fade_overlay", alpha)
end

local function stop_title_bgm()
    if AudioManager == nil then
        return
    end
    if AudioManager.StopBGM ~= nil then
        AudioManager.StopBGM()
        return
    end
    if AudioManager.Stop ~= nil then
        AudioManager.Stop("bgm_title_0")
    end
    if AudioManager.StopManaged ~= nil then
        AudioManager.StopManaged("bgm_title_0")
    end
end

local function ensure_title_widget()
    if UI == nil or UI.CreateWidget == nil then
        return nil
    end

    if title_widget == nil then
        title_widget = UI.CreateWidget(TITLE_UI_PATH)
    end

    if title_widget == nil then
        return nil
    end

    if title_widget.IsInViewport == nil or not title_widget:IsInViewport() then
        title_widget:AddToViewportZ(TITLE_UI_Z_ORDER)
    end

    title_widget:SetWantsMouse(true)
    return title_widget
end

local function update_press_prompt(dt, blink_speed)
    press_blink_elapsed = press_blink_elapsed + dt
    local blink = 0.5 + 0.5 * math.sin(press_blink_elapsed * math.pi * blink_speed)
    set_element_opacity("press_any_button", 0.25 + blink * 0.75)
end

local function consume_title_transition_fade_in_duration()
    local scene_transition = Session.sceneTransition
    if scene_transition == nil then
        return 0.0
    end

    local duration = tonumber(scene_transition.titleFadeInDuration) or 0.0
    scene_transition.titleFadeInDuration = 0.0
    return math.max(0.0, duration)
end

local function begin_title_fade_in(duration)
    transition_phase = "fade_in"
    transition_elapsed = 0.0
    transition_duration = math.max(0.001, duration)
    waiting_for_input = false
    set_fade_overlay_opacity(1.0)
end

local function begin_main_menu_transition()
    if pending_scene_name ~= nil or transition_phase ~= "idle" then
        return
    end

    waiting_for_input = false
    Session.sceneTransition = Session.sceneTransition or {}
    Session.sceneTransition.mainMenuFadeInDuration = MAIN_MENU_FADE_IN_DURATION
    stop_title_bgm()
    request_scene_load("MainMenu")
    transition_phase = "start_sfx"
    transition_elapsed = 0.0
    transition_duration = START_SFX_DURATION
    AudioManager.Play(START_SFX_KEY, UserSettings.GetSfxVolumeScalar())
end

local function complete_scene_load()
    if pending_scene_name == nil then
        return
    end

    local scene_name = pending_scene_name
    pending_scene_name = nil
    Engine.LoadScene(scene_name)
end

local function update_transition(dt)
    if transition_phase == "idle" then
        return false
    end

    transition_elapsed = math.min(transition_elapsed + dt, transition_duration)
    local t = transition_duration <= 0.0 and 1.0 or (transition_elapsed / transition_duration)

    if transition_phase == "fade_in" then
        update_press_prompt(dt, PRESS_BLINK_SPEED_IDLE)
        set_fade_overlay_opacity(1.0 - t)
        if t >= 1.0 then
            transition_phase = "idle"
            transition_elapsed = 0.0
            transition_duration = 0.0
            waiting_for_input = true
            press_blink_elapsed = 0.0
            set_fade_overlay_opacity(0.0)
        end
        return true
    end

    if transition_phase == "start_sfx" then
        update_press_prompt(dt, PRESS_BLINK_SPEED_FAST)
        set_fade_overlay_opacity(0.0)
        if t >= 1.0 then
            transition_phase = "fade_out"
            transition_elapsed = 0.0
            transition_duration = TITLE_FADE_DURATION
        end
        return true
    end

    if transition_phase == "fade_out" then
        set_element_opacity("press_any_button", 1.0)
        set_fade_overlay_opacity(t)
        if t >= 1.0 then
            complete_scene_load()
        end
        return true
    end

    return false
end

function BeginPlay()
    StopAllCoroutines()
    AudioManager.StopAllLoops()
    pending_scene_name = nil
    waiting_for_input = false
    press_blink_elapsed = 0.0
    transition_phase = "idle"
    transition_elapsed = 0.0
    transition_duration = 0.0

    for key, path in pairs(require("Data/AudioData")) do
        AudioManager.Load(key, path, key:find("^bgm_") ~= nil)
    end
    AudioManager.PlayBGM("bgm_title_0", UserSettings.GetBgmVolumeScalar())

    Engine.SetCursorVisible(false)
    local widget = ensure_title_widget()
    if widget ~= nil then
        set_fade_overlay_opacity(0.0)
        set_element_opacity("press_any_button", 1.0)

        local fade_in_duration = consume_title_transition_fade_in_duration()
        if fade_in_duration > 0.0 then
            begin_title_fade_in(fade_in_duration)
        else
            waiting_for_input = true
        end
    end

    Engine.SetOnEscape(function()
        Engine.Exit()
    end)
end

function Tick(dt)
    if title_widget == nil then
        return
    end

    if update_transition(dt) then
        return
    end

    update_press_prompt(dt, PRESS_BLINK_SPEED_IDLE)

    if waiting_for_input and is_any_button_pressed() then
        begin_main_menu_transition()
    end
end

function EndPlay()
    StopAllCoroutines()
    AudioManager.StopAllLoops()
    if title_widget ~= nil then
        title_widget:RemoveFromParent()
    end
    title_widget = nil
    pending_scene_name = nil
    waiting_for_input = false
    press_blink_elapsed = 0.0
    transition_phase = "idle"
    transition_elapsed = 0.0
    transition_duration = 0.0
end
