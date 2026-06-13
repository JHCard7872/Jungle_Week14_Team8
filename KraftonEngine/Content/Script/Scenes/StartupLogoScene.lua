local UI_DOCUMENT_PATH = "Content/UI/StartupLogo/startup_logo.rml"
local STARTUP_LOGO_Z_ORDER = 250
local LOGO_FADE_IN_DURATION = 0.30
local LOGO_HOLD_DURATION = 0.45
local LOGO_FADE_OUT_DURATION = 1.05
local STARTUP_TO_TITLE_FADE_OUT_DURATION = 0.05
local TITLE_FADE_IN_DURATION = 0.5

-- 원하는 흐름:
--   (로고가 조금 빠르게 등장 -> 서서히 사라지며 하얀 화면) * 로고 개수
-- 배경은 항상 흰색이고, 로고는 opacity만 제어한다.
local LOGO_IDS = {
    "startup_0",
    "startup_1",
    "startup_2",
}

local widget = nil
local sequence_elapsed = 0.0
local pending_scene_name = nil
local fade_out_elapsed = 0.0
local fade_out_active = false

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

local function set_element_opacity(element_id, alpha)
    if widget == nil then
        return
    end

    local clamped = math.max(0.0, math.min(1.0, alpha or 0.0))
    widget:SetProperty(element_id, "opacity", string.format("%.3f", clamped))
end

local function set_fade_overlay_opacity(alpha)
    set_element_opacity("startup_fade_overlay", alpha)
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
        -- 매 프레임 display none/block을 반복하면 일부 환경에서 텍스처가 다시 뜨며 깜박일 수 있다.
        -- 슬롯은 항상 켜두고, 흰 배경 위에서 로고 opacity만 바꾼다.
        set_display(slot_id, true)
        set_element_opacity(element_id, 0.0)
    end
end

local function begin_fade_out_to_title()
    if fade_out_active then
        return
    end

    fade_out_active = true
    fade_out_elapsed = 0.0
    set_fade_overlay_opacity(0.0)
    reset_logo_slots()
end

local function update_logo_sequence(dt)
    local logo_duration = LOGO_FADE_IN_DURATION + LOGO_HOLD_DURATION + LOGO_FADE_OUT_DURATION
    local total_duration = logo_duration * #LOGO_IDS

    sequence_elapsed = math.min(sequence_elapsed + (dt or 0.0), total_duration)
    reset_logo_slots()

    if sequence_elapsed >= total_duration then
        begin_fade_out_to_title()
        return
    end

    local logo_index = math.floor(sequence_elapsed / logo_duration) + 1
    local phase_elapsed = sequence_elapsed - ((logo_index - 1) * logo_duration)
    local alpha = 0.0

    if phase_elapsed < LOGO_FADE_IN_DURATION then
        alpha = smoothstep01(phase_elapsed / LOGO_FADE_IN_DURATION)
    elseif phase_elapsed < LOGO_FADE_IN_DURATION + LOGO_HOLD_DURATION then
        alpha = 1.0
    else
        alpha = 1.0 - smoothstep01((phase_elapsed - LOGO_FADE_IN_DURATION - LOGO_HOLD_DURATION) / LOGO_FADE_OUT_DURATION)
    end

    local logo_id = LOGO_IDS[logo_index]
    set_element_opacity(logo_id, alpha)
end

function BeginPlay()
    StopAllCoroutines()
    AudioManager.StopAllLoops()
    Engine.SetCursorVisible(false)

    -- 로고 위젯이 viewport에 맞춰 레이아웃되기 전 프레임에는 흰 배경 div가 화면을
    -- 못 덮어 SceneColor clear(기본 회색)가 드러난다. clear를 흰색으로 두어 그 회색
    -- 깜박임을 없앤다. EndPlay에서 기본값으로 복구.
    if Engine.SetClearColor ~= nil then
        Engine.SetClearColor(1.0, 1.0, 1.0, 1.0)
    end

    sequence_elapsed = 0.0
    pending_scene_name = nil
    fade_out_elapsed = 0.0
    fade_out_active = false

    if ensure_widget() ~= nil then
        reset_logo_slots()
        set_fade_overlay_opacity(0.0)
    else
        request_scene_load("Title")
    end

    -- ESC 비활성화: Play의 Pause 외에는 ESC 무반응. (로고는 자동으로 Title로 진행)
    Engine.SetOnEscape(function() end)
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

    if fade_out_active then
        fade_out_elapsed = math.min(fade_out_elapsed + (dt or 0.0), STARTUP_TO_TITLE_FADE_OUT_DURATION)
        local t = STARTUP_TO_TITLE_FADE_OUT_DURATION <= 0.0 and 1.0 or (fade_out_elapsed / STARTUP_TO_TITLE_FADE_OUT_DURATION)
        set_fade_overlay_opacity(smoothstep01(t))
        if t >= 1.0 then
            local Session = require("GameSession")
            Session.sceneTransition = Session.sceneTransition or {}
            Session.sceneTransition.titleFadeInDuration = TITLE_FADE_IN_DURATION
            request_scene_load("Title")
        end
        return
    end

    update_logo_sequence(dt)
end

function EndPlay()
    StopAllCoroutines()
    AudioManager.StopAllLoops()

    -- clear color를 엔진 기본 회색으로 복구 (다른 씬 영향 방지).
    if Engine.SetClearColor ~= nil then
        Engine.SetClearColor(0.25, 0.25, 0.25, 1.0)
    end

    if widget ~= nil then
        widget:RemoveFromParent()
    end

    widget = nil
    sequence_elapsed = 0.0
    pending_scene_name = nil
    fade_out_elapsed = 0.0
    fade_out_active = false
end
