local Session = require("GameSession")
local RagdollData = require("Data/RagdollData")
local UserSettings = require("Data/UserSettings")

local UI_DOCUMENT_PATH = "Content/UI/PlayHUD/play_hud.rml"
local HUD_Z_ORDER = 200
local SERVER_LOAD_BAR_WIDTH = 520.0
local SERVER_LOAD_DISPLAY_PADDING = 4.0
local SERVER_LOAD_SAFE_THRESHOLD = 30.0
local SERVER_LOAD_WARNING_THRESHOLD = 60.0
local SERVER_LOAD_DANGER_THRESHOLD = 80.0
local SERVER_LOAD_DANGER_BLINK_THRESHOLD = 90.0
local SERVER_LOAD_OPACITY_FADE_DURATION = 0.18
local SERVER_LOAD_RED_BLINK_SPEED = 1.8
local SERVER_LOAD_RED_BLINK_MIN_OPACITY = 0.35
local SERVER_LOAD_SOURCE_IMAGE_WIDTH = 2590.0
local SERVER_LOAD_SOURCE_IMAGE_HEIGHT = 233.0
local TIME_LOW_THRESHOLD = 30.0
local HURRY_UP_THRESHOLD = 10.0
local TIME_PASSING_LOOP_CHANNEL = "PlayHudTimePassingLoop"
local POPUP_SHOW_DURATION = 0.3
local POPUP_BLINK_INTERVAL = 0.1
local POPUP_BLINK_COUNT = 3
local CROSSHAIR_IMAGES = {
    collect = {
        normal = "../../Sprite/aim_collect_normal.png",
        hold = "../../Sprite/aim_collect_shoot.png",
    },
    attack = {
        normal = "../../Sprite/aim_attack_normal.png",
        hold = "../../Sprite/aim_attack_shoot.png",
    },
}
local GUN_MODE_PANEL_IMAGES = {
    collect = "../../Sprite/play_hud_gun_mode_collect.png",
    attack = "../../Sprite/play_hud_gun_mode_attack.png",
}
local POPUP_EVENT_DEFINITIONS = {
    ["COLLECTED"] = {
        imagePath = "../../Sprite/play_hud_popup_collected.png",
        soundKey = "sfx_popup_success",
    },
    ["DANGER"] = {
        imagePath = "../../Sprite/play_hud_popup_danger.png",
        soundKey = "sfx_popup_alert",
    },
    ["HURRY UP"] = {
        imagePath = "../../Sprite/play_hud_popup_hurryup.png",
        soundKey = "sfx_popup_alert",
    },
    ["MISSION COMPLETE"] = {
        imagePath = "../../Sprite/play_hud_popup_mission_complete.png",
        soundKey = "sfx_popup_info",
    },
    ["PORTAL OPEN"] = {
        imagePath = "../../Sprite/play_hud_popup_portal_open.png",
        soundKey = "sfx_popup_info",
    },
    ["REVIVED"] = {
        imagePath = "../../Sprite/play_hud_popup_revived.png",
        soundKey = "sfx_popup_warning",
    },
    ["TIME LOW"] = {
        imagePath = "../../Sprite/play_hud_popup_timelow.png",
        soundKey = "sfx_popup_warning",
    },
    ["WARNING"] = {
        imagePath = "../../Sprite/play_hud_popup_warning.png",
        soundKey = "sfx_popup_warning",
    },
}
local DEFAULT_DEBUG_POPUP_EVENT = "COLLECTED"
local START_COUNTDOWN_IMAGES = {
    ["3"] = "../../Sprite/play_start_countdown_3.png",
    ["2"] = "../../Sprite/play_start_countdown_2.png",
    ["1"] = "../../Sprite/play_start_countdown_1.png",
    ["GO"] = "../../Sprite/play_start_countdown_go.png",
}
local GAMEOVER_BANNER_FULL_WIDTH = 1127.0
local GAMEOVER_REVEAL_SPEED = 0.2   -- ratio per second (20% per second → 5s total)

local M = {}

local widget = nil
local bindings_initialized = false
local debug_panel_enabled = false
local mouse_enabled = false
local crosshair_applied = {}
local popup_queue = {}
local popup_routine = nil
local popup_state = {
    visible = false,
    imagePath = "../../Sprite/play_hud_popup_collected.png",
    opacity = 1.0,
    currentEvent = nil,
}
local start_countdown_state = {
    active = false,
    imagePath = START_COUNTDOWN_IMAGES["3"],
    overlayOpacity = 0.3,
}
local gameover_overlay_state = {
    active = false,
    revealRatio = 0.0,
}
local server_load_visual = {
    activeColor = "red",
    previousColor = nil,
    transitionAlpha = 1.0,
    blinkPhase = 0.0,
}
local event_state = {
    loadBand = "green",
    timeLowTriggered = false,
    hurryUpTriggered = false,
    timePassingLoopPending = false,
    timePassingLoopActive = false,
}

local state = {
    timeSeconds = 135,
    score = 12850,
    serverLoad = 67,
    gunMode = "collect",
    gunEnergy = 100,
    crosshair = {
        visible = true,
        x = nil,
        y = nil,
        hold = false,
        rotation = 0.0,
    },
    target = {
        visible = false,
        name = "Red Plumber",
        weightText = "12.5kg",
        scoreText = "+300",
        imagePath = "../../Sprite/ragdoll/ragdoll_sample.png",
    },
    mission = {
        active = false,
        target = "",
        need = 0,
        got = 0,
        text = "",
        progressText = "목표 0 / 현재 0",
        imagePath = "../../Sprite/ragdoll/ragdoll_sample.png",
    },
    targetState = nil,
}

local function clamp(value, min_value, max_value)
    if value < min_value then
        return min_value
    end
    if value > max_value then
        return max_value
    end
    return value
end

local function round_to_int(value)
    if value >= 0 then
        return math.floor(value + 0.5)
    end
    return math.ceil(value - 0.5)
end

local function format_time(seconds)
    local total = math.max(0, round_to_int(seconds))
    local minutes = math.floor(total / 60)
    local remain = total % 60
    return string.format("%02d:%02d", minutes, remain)
end

local function format_score(score)
    local value = tostring(math.max(0, math.floor(score)))
    local formatted = value

    while true do
        local changed = 0
        formatted, changed = string.gsub(formatted, "^(%-?%d+)(%d%d%d)", "%1,%2")
        if changed == 0 then
            break
        end
    end

    return formatted
end

local function format_load(load)
    return string.format("%d%%", round_to_int(load))
end

local function format_energy(energy)
    return string.format("ENERGY %d%%", round_to_int(energy))
end

local function normalize_mode(mode)
    local lower = string.lower(tostring(mode or "collect"))
    if lower == "attack" or lower == "shock" then
        return "attack"
    end
    return "collect"
end

local function mode_text(mode)
    if normalize_mode(mode) == "attack" then
        return "ATTACK"
    end
    return "COLLECT"
end

local function parse_time_input(text)
    local raw = tostring(text or "")
    local minute_text, second_text = string.match(raw, "^(%d+):(%d+)$")
    if minute_text ~= nil and second_text ~= nil then
        return tonumber(minute_text) * 60 + tonumber(second_text)
    end

    local as_number = tonumber(raw)
    if as_number ~= nil then
        return as_number
    end

    return state.timeSeconds
end

local function parse_target_visible(text)
    local lower = string.lower(tostring(text or ""))
    return lower == "show" or lower == "true" or lower == "1" or lower == "on" or lower == "yes"
end

local function normalize_weight_text(text)
    local raw = tostring(text or "")
    local numeric = tonumber(raw)
    if numeric ~= nil then
        return string.format("%.1fkg", numeric)
    end
    if raw == "" then
        return state.target.weightText
    end
    return raw
end

local function normalize_target_score_text(text)
    local raw = tostring(text or "")
    local numeric = tonumber(raw)
    if numeric ~= nil then
        return string.format("+%d", math.floor(math.abs(numeric)))
    end
    if raw == "" then
        return state.target.scoreText
    end
    if string.sub(raw, 1, 1) == "+" or string.sub(raw, 1, 1) == "-" then
        return raw
    end
    return "+" .. raw
end

local function format_mission_text(target_id, need, text)
    local raw = tostring(text or "")
    if raw ~= "" then
        return raw
    end

    local catalog_entry = target_id ~= nil and RagdollData[target_id] or nil
    if catalog_entry ~= nil and catalog_entry.displayName ~= nil then
        return string.format("%s %d체 수거", catalog_entry.displayName, math.max(0, round_to_int(need or 0)))
    end

    return ""
end

local function format_mission_progress_text(need, got)
    local target_count = math.max(0, round_to_int(need or 0))
    local current_count = math.max(0, round_to_int(got or 0))
    return string.format("목표 %d / 현재 %d", target_count, current_count)
end

local function resolve_mission_image_path(_target_id, fallback_path)
    return fallback_path
end

local function get_sfx_volume_scalar()
    if UserSettings ~= nil and UserSettings.GetSfxVolumeScalar ~= nil then
        return UserSettings.GetSfxVolumeScalar()
    end
    return 1.0
end

local function play_sound(key)
    if key == nil or AudioManager == nil or AudioManager.Play == nil then
        return
    end

    AudioManager.Play(key, get_sfx_volume_scalar())
end

local function play_loop(key, channel)
    if key == nil or channel == nil or AudioManager == nil or AudioManager.PlayLoop == nil then
        return
    end

    AudioManager.PlayLoop(key, channel, get_sfx_volume_scalar())
end

local function stop_loop(channel)
    if channel == nil or AudioManager == nil or AudioManager.StopLoop == nil then
        return
    end

    AudioManager.StopLoop(channel)
end

local function get_server_load_color(load)
    if load < SERVER_LOAD_SAFE_THRESHOLD then
        return "green"
    elseif load < SERVER_LOAD_WARNING_THRESHOLD then
        return "yellow"
    elseif load < SERVER_LOAD_DANGER_THRESHOLD then
        return "orange"
    end
    return "red"
end

local function get_server_load_band(load)
    local color = get_server_load_color(load)
    if color == "orange" then
        return "warning"
    elseif color == "red" then
        return "danger"
    end
    return "safe"
end

local function reset_popup_queue()
    if popup_routine ~= nil and StopCoroutine ~= nil then
        StopCoroutine(popup_routine)
    end

    popup_routine = nil
    popup_queue = {}
    popup_state.visible = false
    popup_state.opacity = 1.0
    popup_state.currentEvent = nil
end

local function reset_runtime_event_state()
    event_state.loadBand = get_server_load_band(state.serverLoad)
    event_state.timeLowTriggered = false
    event_state.hurryUpTriggered = false
    event_state.timePassingLoopPending = false
    event_state.timePassingLoopActive = false
    stop_loop(TIME_PASSING_LOOP_CHANNEL)
    reset_popup_queue()
end

local function set_popup_visible(visible)
    popup_state.visible = visible == true
    popup_state.opacity = popup_state.visible and popup_state.opacity or 1.0
end

local function set_popup_event_image(event_name)
    local definition = POPUP_EVENT_DEFINITIONS[event_name]
    if definition == nil then
        return false
    end

    popup_state.currentEvent = event_name
    popup_state.imagePath = definition.imagePath
    popup_state.opacity = 1.0
    return true
end

local function start_time_passing_loop_if_allowed()
    if event_state.hurryUpTriggered then
        event_state.timePassingLoopPending = false
        return
    end

    event_state.timePassingLoopPending = false
    if event_state.timePassingLoopActive then
        return
    end

    play_loop("sfx_time_passing", TIME_PASSING_LOOP_CHANNEL)
    event_state.timePassingLoopActive = true
end

local function stop_time_passing_loop()
    event_state.timePassingLoopPending = false
    if not event_state.timePassingLoopActive then
        return
    end

    stop_loop(TIME_PASSING_LOOP_CHANNEL)
    event_state.timePassingLoopActive = false
end

local function process_next_popup()
    if popup_routine ~= nil or #popup_queue == 0 or StartCoroutine == nil then
        return
    end

    popup_routine = StartCoroutine(function()
        while #popup_queue > 0 do
            local request = table.remove(popup_queue, 1)
            local event_name = request.eventName
            local definition = POPUP_EVENT_DEFINITIONS[event_name]

            if definition ~= nil then
                set_popup_event_image(event_name)
                set_popup_visible(true)
                play_sound(definition.soundKey)
                M.Refresh()

                Wait(POPUP_SHOW_DURATION)

                for _ = 1, POPUP_BLINK_COUNT do
                    popup_state.opacity = 0.0
                    M.Refresh()
                    Wait(POPUP_BLINK_INTERVAL)

                    popup_state.opacity = 1.0
                    M.Refresh()
                    Wait(POPUP_BLINK_INTERVAL)
                end

                set_popup_visible(false)
                M.Refresh()
            end

            if request.onFinished ~= nil then
                request.onFinished()
            end
        end

        popup_routine = nil
        popup_state.currentEvent = nil
    end)
end

local function queue_popup_internal(request)
    if request == nil then
        return false
    end

    local event_name = request.eventName
    if event_name == nil or POPUP_EVENT_DEFINITIONS[event_name] == nil then
        return false
    end

    popup_queue[#popup_queue + 1] = request
    process_next_popup()
    return true
end

local function handle_time_threshold_events(previous_time, current_time)
    local old_time = tonumber(previous_time) or current_time
    local new_time = tonumber(current_time) or old_time

    if new_time > TIME_LOW_THRESHOLD then
        event_state.timeLowTriggered = false
        event_state.hurryUpTriggered = false
        stop_time_passing_loop()
    elseif new_time > HURRY_UP_THRESHOLD then
        event_state.hurryUpTriggered = false
    end

    if not event_state.timeLowTriggered and old_time > TIME_LOW_THRESHOLD and new_time <= TIME_LOW_THRESHOLD then
        event_state.timeLowTriggered = true
        event_state.timePassingLoopPending = true
        queue_popup_internal({
            eventName = "TIME LOW",
            onFinished = start_time_passing_loop_if_allowed,
        })
    end

    if not event_state.hurryUpTriggered and old_time > HURRY_UP_THRESHOLD and new_time <= HURRY_UP_THRESHOLD then
        event_state.hurryUpTriggered = true
        stop_time_passing_loop()
        play_sound("sfx_10_seconds")
        queue_popup_internal({
            eventName = "HURRY UP",
        })
    end
end

local function handle_server_load_events(previous_load, current_load)
    local old_load = clamp(tonumber(previous_load) or current_load, 0, 100)
    local new_load = clamp(tonumber(current_load) or old_load, 0, 100)
    local previous_band = get_server_load_band(old_load)
    local next_band = get_server_load_band(new_load)
    local band_rank = {
        safe = 0,
        warning = 1,
        danger = 2,
    }

    if previous_band ~= next_band and (band_rank[next_band] or 0) > (band_rank[previous_band] or 0) then
        if next_band == "warning" then
            queue_popup_internal({ eventName = "WARNING" })
        elseif next_band == "danger" then
            queue_popup_internal({ eventName = "DANGER" })
        end
    end

    event_state.loadBand = next_band
end

local function on_time_changed(previous_time, current_time)
    handle_time_threshold_events(previous_time, current_time)
end

local function on_server_load_changed(previous_load, current_load)
    handle_server_load_events(previous_load, current_load)
end

local function set_display(element_id, visible)
    if widget == nil then
        return
    end

    widget:SetProperty(element_id, "display", visible and "block" or "none")
end

local function set_crosshair_property(element_id, property_name, value)
    if widget == nil then
        return
    end

    local key = element_id .. "." .. property_name
    if crosshair_applied[key] == value then
        return
    end

    widget:SetProperty(element_id, property_name, value)
    crosshair_applied[key] = value
end

local function set_crosshair_attribute(element_id, attribute_name, value)
    if widget == nil then
        return
    end

    local key = element_id .. "@" .. attribute_name
    if crosshair_applied[key] == value then
        return
    end

    widget:SetAttribute(element_id, attribute_name, value)
    crosshair_applied[key] = value
end

local function set_opacity(element_id, value)
    if widget == nil then
        return
    end

    widget:SetProperty(element_id, "opacity", string.format("%.3f", clamp(value, 0.0, 1.0)))
end

local function set_width(element_id, value)
    if widget == nil then
        return
    end

    widget:SetProperty(element_id, "width", string.format("%.2fpx", math.max(0.0, value)))
end

local function set_attribute(element_id, attribute_name, value)
    if widget == nil then
        return
    end

    widget:SetAttribute(element_id, attribute_name, tostring(value))
end

local function get_server_load_element_id(color)
    if color == "green" then
        return "hud_server_load_green"
    elseif color == "yellow" then
        return "hud_server_load_yellow"
    elseif color == "orange" then
        return "hud_server_load_orange"
    end
    return "hud_server_load_red"
end

local function reset_server_load_visual()
    local load = clamp(state.serverLoad, 0, 100)

    server_load_visual.activeColor = get_server_load_color(load)
    server_load_visual.previousColor = nil
    server_load_visual.transitionAlpha = 1.0
    server_load_visual.blinkPhase = 0.0
end

local function update_server_load_visual(dt)
    local load = clamp(state.serverLoad, 0, 100)
    local delta_time = math.max(0.0, tonumber(dt) or 0.0)
    local next_color = get_server_load_color(load)

    if next_color ~= server_load_visual.activeColor then
        server_load_visual.previousColor = server_load_visual.activeColor
        server_load_visual.activeColor = next_color
        server_load_visual.transitionAlpha = 0.0
        server_load_visual.blinkPhase = 0.0
    end

    if server_load_visual.previousColor ~= nil then
        local fade_step = delta_time <= 0.0 and 1.0 or (delta_time / SERVER_LOAD_OPACITY_FADE_DURATION)
        server_load_visual.transitionAlpha = math.min(server_load_visual.transitionAlpha + fade_step, 1.0)

        if server_load_visual.transitionAlpha >= 1.0 then
            server_load_visual.previousColor = nil
        end
    else
        server_load_visual.transitionAlpha = 1.0
    end

    if load >= SERVER_LOAD_DANGER_BLINK_THRESHOLD and server_load_visual.activeColor == "red" and server_load_visual.previousColor == nil then
        server_load_visual.blinkPhase = (server_load_visual.blinkPhase + (delta_time * SERVER_LOAD_RED_BLINK_SPEED)) % 1.0
    else
        server_load_visual.blinkPhase = 0.0
    end
end

local function assign_crosshair_state(crosshair)
    if crosshair == nil then
        return
    end

    if crosshair.mode ~= nil then
        state.gunMode = normalize_mode(crosshair.mode)
    end
    if crosshair.visible ~= nil then
        state.crosshair.visible = crosshair.visible ~= false
    end
    if crosshair.x ~= nil then
        state.crosshair.x = tonumber(crosshair.x) or state.crosshair.x
    end
    if crosshair.y ~= nil then
        state.crosshair.y = tonumber(crosshair.y) or state.crosshair.y
    end
    if crosshair.hold ~= nil then
        state.crosshair.hold = crosshair.hold == true
    end
    if crosshair.rotation ~= nil then
        state.crosshair.rotation = tonumber(crosshair.rotation) or 0.0
    end
end

local function sync_debug_inputs()
    if widget == nil or not debug_panel_enabled then
        return
    end

    widget:SetValue("debug_time_input", format_time(state.timeSeconds))
    widget:SetValue("debug_score_input", tostring(math.floor(state.score)))
    widget:SetValue("debug_load_input", tostring(round_to_int(state.serverLoad)))
    widget:SetValue("debug_mode_input", state.gunMode)
    widget:SetValue("debug_energy_input", tostring(round_to_int(state.gunEnergy)))
    widget:SetValue("debug_target_visible_input", state.target.visible and "show" or "hide")
    widget:SetValue("debug_target_name_input", state.target.name)
    widget:SetValue("debug_target_weight_input", state.target.weightText)
    widget:SetValue("debug_target_score_input", state.target.scoreText)
    widget:SetValue("debug_target_image_input", state.target.imagePath)
    widget:SetValue("debug_popup_event_input", popup_state.currentEvent or DEFAULT_DEBUG_POPUP_EVENT)
end

local function apply_server_load()
    local load = clamp(state.serverLoad, 0, 100)
    local display_load = clamp(load + SERVER_LOAD_DISPLAY_PADDING, 0, 100)
    local display_ratio = display_load / 100.0
    local fill_width = SERVER_LOAD_BAR_WIDTH * display_ratio
    local source_crop_width = math.max(1, round_to_int(SERVER_LOAD_SOURCE_IMAGE_WIDTH * display_ratio))
    local source_crop_height = round_to_int(SERVER_LOAD_SOURCE_IMAGE_HEIGHT)
    local active_opacity = 1.0

    set_width("hud_server_load_green", fill_width)
    set_width("hud_server_load_yellow", fill_width)
    set_width("hud_server_load_orange", fill_width)
    set_width("hud_server_load_red", fill_width)
    set_attribute("hud_server_load_green", "rect", string.format("0 0 %d %d", source_crop_width, source_crop_height))
    set_attribute("hud_server_load_yellow", "rect", string.format("0 0 %d %d", source_crop_width, source_crop_height))
    set_attribute("hud_server_load_orange", "rect", string.format("0 0 %d %d", source_crop_width, source_crop_height))
    set_attribute("hud_server_load_red", "rect", string.format("0 0 %d %d", source_crop_width, source_crop_height))
    set_opacity("hud_server_load_green", 0.0)
    set_opacity("hud_server_load_yellow", 0.0)
    set_opacity("hud_server_load_orange", 0.0)
    set_opacity("hud_server_load_red", 0.0)

    if load >= SERVER_LOAD_DANGER_BLINK_THRESHOLD and server_load_visual.activeColor == "red" and server_load_visual.previousColor == nil then
        local triangle = math.abs(1.0 - (server_load_visual.blinkPhase * 2.0))
        active_opacity = SERVER_LOAD_RED_BLINK_MIN_OPACITY + ((1.0 - SERVER_LOAD_RED_BLINK_MIN_OPACITY) * triangle)
    end

    widget:SetText("hud_server_load_value", format_load(load))

    if server_load_visual.previousColor ~= nil then
        set_opacity(get_server_load_element_id(server_load_visual.previousColor), 1.0 - server_load_visual.transitionAlpha)
        set_opacity(get_server_load_element_id(server_load_visual.activeColor), server_load_visual.transitionAlpha)
        return
    end

    set_opacity(get_server_load_element_id(server_load_visual.activeColor), active_opacity)
end

local function apply_popup()
    set_display("hud_popup_container", popup_state.visible)
    widget:SetAttribute("hud_popup_image", "src", popup_state.imagePath)
    set_opacity("hud_popup_container", popup_state.opacity)
end

local function apply_start_countdown()
    set_display("hud_start_countdown_overlay", start_countdown_state.active)
    widget:SetAttribute("hud_start_countdown_image", "src", start_countdown_state.imagePath)
    set_opacity("hud_start_countdown_dim", start_countdown_state.overlayOpacity)
end

local function apply_gameover_overlay()
    set_display("hud_gameover_overlay", gameover_overlay_state.active)
    if gameover_overlay_state.active then
        set_width("hud_gameover_banner_clip", GAMEOVER_BANNER_FULL_WIDTH * clamp(gameover_overlay_state.revealRatio, 0.0, 1.0))
    end
end

local function apply_time()
    widget:SetText("hud_time_text", format_time(state.timeSeconds))
end

local function apply_score()
    widget:SetText("hud_score_text", format_score(state.score))
end

local function apply_gun_status()
    local mode = normalize_mode(state.gunMode)

    set_display("hud_gun_mode_image", true)
    set_display("hud_gun_collect_icon", false)
    set_display("hud_gun_attack_icon", false)
    widget:SetAttribute("hud_gun_mode_image", "src", GUN_MODE_PANEL_IMAGES[mode] or GUN_MODE_PANEL_IMAGES.collect)

    widget:SetText("hud_gun_mode_text", mode_text(mode))
    widget:SetText("hud_gun_energy_text", format_energy(state.gunEnergy))
end

local function apply_crosshair_state()
    local mode = normalize_mode(state.gunMode)
    local images = CROSSHAIR_IMAGES[mode] or CROSSHAIR_IMAGES.collect
    local hold = state.crosshair.hold == true
    local show_hold_feedback = hold and mode ~= "attack"
    local x = tonumber(state.crosshair.x)
    local y = tonumber(state.crosshair.y)
    local rotation = show_hold_feedback and (tonumber(state.crosshair.rotation) or 0.0) or 0.0
    local rotation_transform = string.format("rotate(%.1fdeg)", rotation)

    set_display("hud_crosshair_container", state.crosshair.visible ~= false)
    set_display("hud_crosshair_collect", mode == "collect")
    set_display("hud_crosshair_attack", mode == "attack")

    if x ~= nil then
        set_crosshair_property("hud_crosshair_container", "left", string.format("%.2fpx", x))
    else
        set_crosshair_property("hud_crosshair_container", "left", "50%")
    end

    if y ~= nil then
        set_crosshair_property("hud_crosshair_container", "top", string.format("%.2fpx", y))
    else
        set_crosshair_property("hud_crosshair_container", "top", "50%")
    end

    set_crosshair_attribute(
        "hud_crosshair_collect",
        "src",
        show_hold_feedback and CROSSHAIR_IMAGES.collect.hold or CROSSHAIR_IMAGES.collect.normal
    )
    set_crosshair_attribute(
        "hud_crosshair_attack",
        "src",
        images.normal
    )

    set_crosshair_property("hud_crosshair_collect", "transform", rotation_transform)
    set_crosshair_property("hud_crosshair_attack", "transform", rotation_transform)
end

local function apply_target_info()
    set_display("hud_target_info_container", state.target.visible)
    widget:SetText("hud_target_name", state.target.name)
    widget:SetText("hud_target_weight", state.target.weightText)
    widget:SetText("hud_target_score", state.target.scoreText)
    -- src는 스타일이 아니라 요소 속성 — SetProperty로 넣으면 RmlUi 파싱 오류가 난다
    widget:SetAttribute("hud_target_pose_image", "src", state.target.imagePath)
end

local function apply_mission_info()
    set_display("hud_mission_container", state.mission.active)
    widget:SetText("hud_mission_text", state.mission.text)
    widget:SetText("hud_mission_progress_text", state.mission.progressText)
    widget:SetAttribute("hud_mission_reference_image", "src", state.mission.imagePath)
end

local function apply_debug_panel_state()
    set_display("hud_debug_panel", debug_panel_enabled)
    sync_debug_inputs()
end

local function apply_all()
    if widget == nil then
        return
    end

    apply_server_load()
    apply_time()
    apply_score()
    apply_gun_status()
    apply_crosshair_state()
    apply_target_info()
    apply_mission_info()
    apply_popup()
    apply_start_countdown()
    apply_gameover_overlay()
    apply_debug_panel_state()
end

local function get_input_value(element_id)
    if widget == nil then
        return ""
    end
    return widget:GetValue(element_id)
end

local function bind_debug_actions()
    if widget == nil or bindings_initialized then
        return
    end

    widget:bind_click("debug_time_apply", function()
        M.SetTimeSeconds(parse_time_input(get_input_value("debug_time_input")))
    end)

    widget:bind_click("debug_score_apply", function()
        M.SetScore(tonumber(get_input_value("debug_score_input")) or state.score)
    end)

    widget:bind_click("debug_load_apply", function()
        M.SetServerLoad(tonumber(get_input_value("debug_load_input")) or state.serverLoad)
    end)

    widget:bind_click("debug_mode_apply", function()
        M.SetGunMode(get_input_value("debug_mode_input"))
    end)

    widget:bind_click("debug_energy_apply", function()
        M.SetGunEnergy(tonumber(get_input_value("debug_energy_input")) or state.gunEnergy)
    end)

    widget:bind_click("debug_target_visible_apply", function()
        if parse_target_visible(get_input_value("debug_target_visible_input")) then
            M.ShowTargetInfo(state.target)
        else
            M.HideTargetInfo()
        end
    end)

    widget:bind_click("debug_target_name_apply", function()
        local target = {}
        for key, value in pairs(state.target) do
            target[key] = value
        end
        target.name = get_input_value("debug_target_name_input")
        M.ShowTargetInfo(target)
    end)

    widget:bind_click("debug_target_weight_apply", function()
        local target = {}
        for key, value in pairs(state.target) do
            target[key] = value
        end
        target.weightText = normalize_weight_text(get_input_value("debug_target_weight_input"))
        M.ShowTargetInfo(target)
    end)

    widget:bind_click("debug_target_score_apply", function()
        local target = {}
        for key, value in pairs(state.target) do
            target[key] = value
        end
        target.scoreText = normalize_target_score_text(get_input_value("debug_target_score_input"))
        M.ShowTargetInfo(target)
    end)

    widget:bind_click("debug_target_image_apply", function()
        local target = {}
        for key, value in pairs(state.target) do
            target[key] = value
        end
        local path = get_input_value("debug_target_image_input")
        if path ~= "" then
            target.imagePath = path
        end
        M.ShowTargetInfo(target)
    end)

    widget:bind_click("debug_popup_play", function()
        M.QueuePopup(get_input_value("debug_popup_event_input"))
    end)

    bindings_initialized = true
end

local function ensure_widget()
    if UI == nil or UI.CreateWidget == nil then
        return nil
    end

    if widget == nil then
        widget = UI.CreateWidget(UI_DOCUMENT_PATH)
        crosshair_applied = {}
        reset_server_load_visual()
    end

    if widget == nil then
        return nil
    end

    widget:SetWantsMouse(mouse_enabled)
    if widget.IsInViewport == nil or not widget:IsInViewport() then
        widget:AddToViewportZ(HUD_Z_ORDER)
    end

    bind_debug_actions()
    apply_all()

    return widget
end

function M.Create(options)
    options = options or {}
    debug_panel_enabled = options.showDebugPanel == true
    mouse_enabled = options.wantsMouse == true or debug_panel_enabled

    reset_server_load_visual()
    reset_runtime_event_state()
    ensure_widget()
    return widget
end

function M.Destroy()
    stop_time_passing_loop()

    if widget ~= nil then
        widget:RemoveFromParent()
    end

    widget = nil
    bindings_initialized = false
    debug_panel_enabled = false
    mouse_enabled = false
    crosshair_applied = {}
    reset_server_load_visual()
    reset_popup_queue()
    start_countdown_state.active = false
    start_countdown_state.imagePath = START_COUNTDOWN_IMAGES["3"]
    start_countdown_state.overlayOpacity = 0.3
    gameover_overlay_state.active = false
    gameover_overlay_state.revealRatio = 0.0
end

function M.Refresh()
    ensure_widget()
    apply_all()
end

function M.Update(dt)
    if widget == nil and ensure_widget() == nil then
        return
    end

    update_server_load_visual(dt)
    apply_server_load()
    apply_popup()
end

function M.UpdateFromSession(dt)
    local previous_time = state.timeSeconds
    local previous_load = state.serverLoad

    state.timeSeconds = Session.timeRemaining or state.timeSeconds
    state.score = Session.score or state.score
    state.serverLoad = Session.load or state.serverLoad

    on_time_changed(previous_time, state.timeSeconds)
    on_server_load_changed(previous_load, state.serverLoad)

    if Session.gun ~= nil then
        state.gunMode = normalize_mode(Session.gun.mode)
        state.gunEnergy = Session.gun.energy or state.gunEnergy
        assign_crosshair_state(Session.gun.crosshair)
    end

    if Session.target ~= nil then
        M.SetTargetState(Session.target)
    end

    if Session.mission ~= nil then
        M.SetMissionState(Session.mission)
    end

    if widget == nil and ensure_widget() == nil then
        return
    end

    update_server_load_visual(dt)
    apply_all()
end

function M.SetTimeSeconds(seconds)
    local previous_time = state.timeSeconds
    state.timeSeconds = math.max(0, tonumber(seconds) or state.timeSeconds)
    on_time_changed(previous_time, state.timeSeconds)
    M.Refresh()
end

function M.SetScore(score)
    state.score = math.max(0, tonumber(score) or state.score)
    M.Refresh()
end

function M.SetServerLoad(load)
    local previous_load = state.serverLoad
    state.serverLoad = clamp(tonumber(load) or state.serverLoad, 0, 100)
    on_server_load_changed(previous_load, state.serverLoad)
    update_server_load_visual(0.0)
    M.Refresh()
end

function M.SetGunMode(mode)
    state.gunMode = normalize_mode(mode)
    M.Refresh()
end

function M.SetGunEnergy(energy)
    state.gunEnergy = clamp(tonumber(energy) or state.gunEnergy, 0, 999)
    M.Refresh()
end

function M.SetCrosshairState(crosshair)
    assign_crosshair_state(crosshair)
    if widget ~= nil then
        apply_gun_status()
        apply_crosshair_state()
    end
end

function M.SetTargetState(target_info)
    state.targetState = target_info

    if target_info ~= nil and target_info.visible == true then
        M.ShowTargetInfo(target_info)
        return
    end

    M.HideTargetInfo()
end

function M.ShowTargetInfo(target_info)
    target_info = target_info or {}
    state.target.visible = true
    state.target.name = target_info.name or state.target.name
    state.target.weightText = target_info.weightText
        or (target_info.weight ~= nil and normalize_weight_text(target_info.weight))
        or state.target.weightText
    state.target.scoreText = target_info.scoreText
        or (target_info.score ~= nil and normalize_target_score_text(target_info.score))
        or (target_info.baseScore ~= nil and normalize_target_score_text(target_info.baseScore))
        or state.target.scoreText
    state.target.imagePath = target_info.imagePath or target_info.referenceImage or state.target.imagePath
    M.Refresh()
end

function M.HideTargetInfo()
    state.target.visible = false
    M.Refresh()
end

function M.SetMissionState(mission_info)
    mission_info = mission_info or {}

    local target_id = tostring(mission_info.target or "")
    local need = math.max(0, round_to_int(mission_info.need or 0))
    local got = math.max(0, round_to_int(mission_info.got or 0))
    local active = mission_info.active == true
    local fallback_image = "../../Sprite/ragdoll/ragdoll_sample.png"

    state.mission.active = active
    state.mission.target = target_id
    state.mission.need = need
    state.mission.got = got
    state.mission.text = format_mission_text(target_id, need, mission_info.text)
    state.mission.progressText = format_mission_progress_text(need, got)
    state.mission.imagePath = resolve_mission_image_path(target_id, fallback_image) or fallback_image

    M.Refresh()
end

function M.SetDebugPanelEnabled(enabled)
    debug_panel_enabled = enabled == true
    mouse_enabled = mouse_enabled or debug_panel_enabled
    if widget ~= nil then
        widget:SetWantsMouse(mouse_enabled)
    end
    M.Refresh()
end

function M.QueuePopup(event_name)
    local normalized_event = tostring(event_name or "")
    if normalized_event == "" then
        return false
    end

    local queued = queue_popup_internal({
        eventName = normalized_event,
    })

    if queued then
        M.Refresh()
    end

    return queued
end

function M.ShowGameOverOverlay(onComplete)
    gameover_overlay_state.active = true
    gameover_overlay_state.revealRatio = 0.0
    M.Refresh()

    StartCoroutine(function()
        local elapsed = 0.0
        while elapsed < 5.0 do
            local dt = WaitFrame()
            elapsed = math.min(elapsed + (dt or 0.0), 5.0)
            gameover_overlay_state.revealRatio = elapsed * GAMEOVER_REVEAL_SPEED
            apply_gameover_overlay()
        end
        if onComplete ~= nil then
            onComplete()
        end
    end)
end

function M.SetStartCountdownVisible(visible)
    start_countdown_state.active = visible == true
    if not start_countdown_state.active then
        start_countdown_state.overlayOpacity = 0.0
    end
    M.Refresh()
end

function M.SetStartCountdownStep(step_name, overlay_opacity)
    local key = string.upper(tostring(step_name or "3"))
    start_countdown_state.imagePath = START_COUNTDOWN_IMAGES[key] or START_COUNTDOWN_IMAGES["3"]
    start_countdown_state.overlayOpacity = clamp(tonumber(overlay_opacity) or start_countdown_state.overlayOpacity, 0.0, 1.0)
    start_countdown_state.active = true
    M.Refresh()
end

return M
