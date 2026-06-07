local UI_DOCUMENT_PATH = "Content/UI/StartupLogo/startup_logo.rml"
local STARTUP_LOGO_Z_ORDER = 250
local REVEAL_IN_DURATION = 0.8
local HOLD_DURATION = 0.25
local REVEAL_OUT_DURATION = 0.8
local LOGO_FULL_WIDTH = 720.0

-- opacity로 로고 자체를 반투명하게 만들면 흰 배경과 섞이면서
-- 중간 프레임의 채도가 죽어 보인다. 그래서 로고 색은 항상 100%로 두고,
-- 흰 배경 위에서 슬롯의 폭만 열고 닫는 방식으로 등장/퇴장시킨다.
local LOGO_IDS = {
    "logo_jungle",
    "logo_jungle_gametechlab",
    "logo_eng_ver2",
}

local widget = nil
local sequence_elapsed = 0.0
local pending_scene_name = nil

local function smoothstep01(t)
    local x = math.max(0.0, math.min(1.0, t))
    return x * x * (3.0 - 2.0 * x)
end

local function request_scene_load(scene_name)
    if pending_scene_name ~= nil then
        return
    end

    pending_scene_name = scene_name
end

local function set_display(element_id, visible)
    if widget == nil then
        return
    end

    widget:SetProperty(element_id, "display", visible and "block" or "none")
end

local function set_logo_slot_width(element_id, width)
    if widget == nil then
        return
    end

    local clamped = math.max(0.0, math.min(LOGO_FULL_WIDTH, width or 0.0))
    widget:SetProperty(element_id, "width", string.format("%.2fpx", clamped))
    widget:SetProperty(element_id, "margin-left", string.format("%.2fpx", -clamped * 0.5))
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

local function reset_logo_slots()
    for _, element_id in ipairs(LOGO_IDS) do
        local slot_id = element_id .. "_slot"
        set_display(slot_id, false)
        set_logo_slot_width(slot_id, 0.0)
        -- 로고 색상 보존용: 이미지 alpha는 건드리지 않는다.
        if widget ~= nil then
            widget:SetProperty(element_id, "opacity", "1")
        end
    end
end

local function update_logo_sequence(dt)
    local logo_duration = REVEAL_IN_DURATION + HOLD_DURATION + REVEAL_OUT_DURATION
    local total_duration = logo_duration * #LOGO_IDS

    sequence_elapsed = math.min(sequence_elapsed + (dt or 0.0), total_duration)
    reset_logo_slots()

    if sequence_elapsed >= total_duration then
        request_scene_load("Title")
        return
    end

    local logo_index = math.floor(sequence_elapsed / logo_duration) + 1
    local phase_elapsed = sequence_elapsed - ((logo_index - 1) * logo_duration)
    local width_ratio = 0.0

    if phase_elapsed < REVEAL_IN_DURATION then
        width_ratio = smoothstep01(phase_elapsed / REVEAL_IN_DURATION)
    elseif phase_elapsed < REVEAL_IN_DURATION + HOLD_DURATION then
        width_ratio = 1.0
    else
        width_ratio = 1.0 - smoothstep01((phase_elapsed - REVEAL_IN_DURATION - HOLD_DURATION) / REVEAL_OUT_DURATION)
    end

    local logo_id = LOGO_IDS[logo_index]
    local slot_id = logo_id .. "_slot"
    set_display(slot_id, true)
    set_logo_slot_width(slot_id, LOGO_FULL_WIDTH * width_ratio)
end

function BeginPlay()
    StopAllCoroutines()
    AudioManager.StopAllLoops()
    Engine.SetCursorVisible(false)

    sequence_elapsed = 0.0
    pending_scene_name = nil

    if ensure_widget() ~= nil then
        reset_logo_slots()
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
