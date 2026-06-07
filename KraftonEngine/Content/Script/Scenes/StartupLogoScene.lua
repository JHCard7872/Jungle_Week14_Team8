local UI_DOCUMENT_PATH = "Content/UI/StartupLogo/startup_logo.rml"
local STARTUP_LOGO_Z_ORDER = 250
local FADE_IN_DURATION = 0.5
local FADE_OUT_DURATION = 0.5

local LOGO_IDS = {
    "logo_jungle",
    "logo_jungle_gametechlab",
    "logo_eng_ver2",
}

local widget = nil
local sequence_elapsed = 0.0
local pending_scene_name = nil

local function request_scene_load(scene_name)
    if pending_scene_name ~= nil then
        return
    end

    pending_scene_name = scene_name
end

local function set_logo_opacity(element_id, alpha)
    if widget == nil then
        return
    end

    local clamped = math.max(0.0, math.min(1.0, alpha))
    widget:SetProperty(element_id, "opacity", string.format("%.3f", clamped))
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
        widget:AddToViewportZ(STARTUP_LOGO_Z_ORDER)
    end

    widget:SetWantsMouse(false)
    return widget
end

local function reset_logo_opacity()
    for _, element_id in ipairs(LOGO_IDS) do
        set_logo_opacity(element_id, 0.0)
    end
end

local function update_logo_sequence(dt)
    local logo_duration = FADE_IN_DURATION + FADE_OUT_DURATION
    local total_duration = logo_duration * #LOGO_IDS

    sequence_elapsed = math.min(sequence_elapsed + dt, total_duration)
    reset_logo_opacity()

    if sequence_elapsed >= total_duration then
        request_scene_load("Title")
        return
    end

    local logo_index = math.floor(sequence_elapsed / logo_duration) + 1
    local phase_elapsed = sequence_elapsed - ((logo_index - 1) * logo_duration)
    local alpha = 0.0

    if phase_elapsed < FADE_IN_DURATION then
        alpha = phase_elapsed / FADE_IN_DURATION
    else
        alpha = 1.0 - ((phase_elapsed - FADE_IN_DURATION) / FADE_OUT_DURATION)
    end

    set_logo_opacity(LOGO_IDS[logo_index], alpha)
end

function BeginPlay()
    StopAllCoroutines()
    AudioManager.StopAllLoops()
    Engine.SetCursorVisible(false)

    sequence_elapsed = 0.0
    pending_scene_name = nil

    if ensure_widget() ~= nil then
        reset_logo_opacity()
    else
        request_scene_load("Title")
    end

    Engine.SetOnEscape(function()
        request_scene_load("Title")
    end)
end

function Tick(dt)
    if pending_scene_name ~= nil then
        local scene_name = pending_scene_name
        pending_scene_name = nil
        Engine.LoadScene(scene_name)
        return
    end

    if widget == nil then
        return
    end

    update_logo_sequence(dt)
end

function EndPlay()
    StopAllCoroutines()
    AudioManager.StopAllLoops()

    if widget ~= nil then
        widget:RemoveFromParent()
    end

    widget = nil
    sequence_elapsed = 0.0
    pending_scene_name = nil
end
