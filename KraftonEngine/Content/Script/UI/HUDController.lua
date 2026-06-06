local Session = require("GameSession")

local UI_DOCUMENT_PATH = "Content/UI/PlayHUD/play_hud.rml"
local HUD_Z_ORDER = 200

local M = {}

local widget = nil
local bindings_initialized = false
local debug_panel_enabled = false
local mouse_enabled = false

local state = {
    timeSeconds = 135,
    score = 12850,
    serverLoad = 67,
    gunMode = "collect",
    gunEnergy = 100,
    target = {
        visible = true,
        name = "Red Plumber",
        weightText = "12.5kg",
        scoreText = "+300",
        imagePath = "../../Sprite/id_card_sample.png",
    },
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

local function set_display(element_id, visible)
    if widget == nil then
        return
    end

    widget:SetProperty(element_id, "display", visible and "block" or "none")
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
end

local function apply_server_load()
    local load = clamp(state.serverLoad, 0, 100)
    local angle = -90.0 + (load * 1.8)
    local color = "#79ff86"

    if load >= 90 then
        color = "#ff6b6b"
    elseif load >= 70 then
        color = "#ffb347"
    elseif load >= 40 then
        color = "#ffe66d"
    end

    widget:SetText("hud_server_load_value", format_load(load))
    widget:SetProperty("hud_server_load_value", "color", color)
    widget:SetProperty("hud_server_load_arrow", "transform", string.format("rotate(%.1fdeg)", angle))
end

local function apply_time()
    widget:SetText("hud_time_text", format_time(state.timeSeconds))
end

local function apply_score()
    widget:SetText("hud_score_text", format_score(state.score))
end

local function apply_gun_status()
    local mode = normalize_mode(state.gunMode)

    set_display("hud_crosshair_collect", mode == "collect")
    set_display("hud_crosshair_attack", mode == "attack")
    set_display("hud_gun_collect_icon", mode == "collect")
    set_display("hud_gun_attack_icon", mode == "attack")

    widget:SetText("hud_gun_mode_text", mode_text(mode))
    widget:SetText("hud_gun_energy_text", format_energy(state.gunEnergy))
end

local function apply_target_info()
    set_display("hud_target_info_container", state.target.visible)
    widget:SetText("hud_target_name", state.target.name)
    widget:SetText("hud_target_weight", state.target.weightText)
    widget:SetText("hud_target_score", state.target.scoreText)
    widget:SetProperty("hud_target_pose_image", "src", state.target.imagePath)
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
    apply_target_info()
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

    ensure_widget()
    return widget
end

function M.Destroy()
    if widget ~= nil then
        widget:RemoveFromParent()
    end

    widget = nil
    bindings_initialized = false
    debug_panel_enabled = false
    mouse_enabled = false
end

function M.Refresh()
    ensure_widget()
    apply_all()
end

function M.UpdateFromSession()
    state.timeSeconds = Session.timeRemaining or state.timeSeconds
    state.score = Session.score or state.score
    state.serverLoad = Session.load or state.serverLoad

    if Session.gun ~= nil then
        state.gunMode = normalize_mode(Session.gun.mode)
        state.gunEnergy = Session.gun.energy or state.gunEnergy
    end

    M.Refresh()
end

function M.SetTimeSeconds(seconds)
    state.timeSeconds = math.max(0, tonumber(seconds) or state.timeSeconds)
    M.Refresh()
end

function M.SetScore(score)
    state.score = math.max(0, tonumber(score) or state.score)
    M.Refresh()
end

function M.SetServerLoad(load)
    state.serverLoad = clamp(tonumber(load) or state.serverLoad, 0, 100)
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

function M.SetDebugPanelEnabled(enabled)
    debug_panel_enabled = enabled == true
    mouse_enabled = mouse_enabled or debug_panel_enabled
    if widget ~= nil then
        widget:SetWantsMouse(mouse_enabled)
    end
    M.Refresh()
end

return M
