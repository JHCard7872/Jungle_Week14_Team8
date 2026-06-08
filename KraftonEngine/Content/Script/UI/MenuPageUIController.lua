-- =============================================================================
-- SubMenuPageUIController — 메인 메뉴 하위 페이지 공통 UI 컨트롤러
-- [역할] 메인 메뉴 배경 위에 30% 어두운 오버레이, 좌상단 제목,
--        우상단 Back 버튼, 중앙 하단 Confirm 버튼을 공통으로 띄운다.
-- [페이지] Options / Controls / Scoreboard / Credits
-- [주의] 화면을 열 때만 Create/AddToViewport 하고, 닫을 때 Destroy 해서
--        숨겨진 문서가 메인 메뉴 hover/click을 막지 않게 한다.
-- =============================================================================

local UI_DOCUMENT_PATH = "Content/UI/SubMenuPage/sub_menu_page.rml"
local UserSettings = require("Data/UserSettings")
-- Pause(220)보다 위에 뜨도록
local PAGE_Z_ORDER = 230

local UI_CLICK_KEY = "sfx_ui_click"
local UI_HOVER_KEY = "sfx_ui_hover"

local MIN_VOLUME = 0
local MAX_VOLUME = 10
local DEFAULT_SFX_VOLUME = 8
local DEFAULT_BGM_VOLUME = 8
local PAGE_BODY_IDS = {
    options = "page_body_options",
    controls = "page_body_controls",
    scoreboard = "page_body_scoreboard",
    credits = "page_body_credits",
}


local M = {}

local widget = nil
local bindings_initialized = false
local visible = false
local current_page_type = "options"
local on_settings_changed = nil
local scoreboard_entries = nil

-- Confirm/Back 버튼 클릭 시 호출할 콜백
local on_confirm = nil
local on_back = nil

-- 현재 화면에 표시 중인 옵션 설정값
local settings = UserSettings.GetSettings()

local function clamp(value, min_value, max_value)
    value = tonumber(value) or min_value

    if value < min_value then
        return min_value
    end

    if value > max_value then
        return max_value
    end

    return value
end

local function get_sfx_volume_scalar()
    return UserSettings.VolumeToScalar(settings.sfxVolume)
end

local function set_display(element_id, is_visible)
    if widget == nil then
        return
    end

    widget:SetProperty(element_id, "display", is_visible and "block" or "none")
end

local function set_text(element_id, value)
    if widget == nil then
        return
    end

    widget:SetText(element_id, tostring(value))
end


local function play_ui_click()
    AudioManager.Play(UI_CLICK_KEY, get_sfx_volume_scalar())
end

local function play_ui_hover()
    AudioManager.Play(UI_HOVER_KEY, get_sfx_volume_scalar())
end

local function on_button_click(callback)
    return function()
        play_ui_click()
        callback()
    end
end

local function bind_hover_sound(element_id)
    if widget == nil or widget.bind_hover == nil then
        return
    end

    widget:bind_hover(element_id, function()
        play_ui_hover()
    end)
end

-- 화면에 표시되는 볼륨 숫자를 settings 값에 맞춰 갱신한다
local function apply_settings_to_view()
    if widget == nil then
        return
    end

    set_text("sfx_volume_value", settings.sfxVolume)
    set_text("bgm_volume_value", settings.bgmVolume)
end

local function commit_option_settings()
    UserSettings.Apply(settings)

    if on_settings_changed ~= nil then
        on_settings_changed(M.GetSettings(), current_page_type)
    end
end

local function apply_scoreboard_to_view()
    if widget == nil then
        return
    end

    local entries = scoreboard_entries or {}
    for i = 1, 5 do
        local row_id = "score_row_" .. tostring(i)
        local entry = entries[i]
        set_display(row_id, entry ~= nil)

        if entry ~= nil then
            set_text("score_rank_" .. tostring(i), tostring(i))
            set_text("score_name_" .. tostring(i), tostring(entry.nickname or "SAMPLE"))
            set_text("score_count_" .. tostring(i), tostring(entry.collectedCount or 0))
            set_text("score_value_" .. tostring(i), tostring(entry.totalScore or 0))
        end
    end

    set_display("score_empty_text", #entries == 0)
end

local function set_sfx_volume(value)
    settings.sfxVolume = clamp(value, MIN_VOLUME, MAX_VOLUME)
    apply_settings_to_view()
    commit_option_settings()
end

local function set_bgm_volume(value)
    settings.bgmVolume = clamp(value, MIN_VOLUME, MAX_VOLUME)
    apply_settings_to_view()
    commit_option_settings()
end


local function set_current_page(page_type, title)
    if widget == nil then
        return
    end

    current_page_type = PAGE_BODY_IDS[page_type] ~= nil and page_type or "options"
    set_text("page_title", title or "Options")

    for key, body_id in pairs(PAGE_BODY_IDS) do
        set_display(body_id, key == current_page_type)
    end

    -- Confirm은 Options에서 설정 적용용으로 쓰고, 나머지 페이지에서는 닫기 버튼으로 사용한다.
    set_text("page_confirm_label", current_page_type == "options" and "Confirm" or "Close")

    apply_settings_to_view()
    apply_scoreboard_to_view()
end

local function bind_actions()
    if widget == nil or bindings_initialized or widget.bind_click == nil then
        return
    end

    widget:bind_click("page_back_button", on_button_click(function()
        if on_back ~= nil then
            on_back(current_page_type)
        end
    end))

    widget:bind_click("page_confirm_button", on_button_click(function()
        if on_confirm ~= nil then
            on_confirm(M.GetSettings(), current_page_type)
        elseif on_back ~= nil then
            on_back(current_page_type)
        end
    end))

    widget:bind_click("sfx_volume_down", on_button_click(function()
        set_sfx_volume(settings.sfxVolume - 1)
    end))

    widget:bind_click("sfx_volume_up", on_button_click(function()
        set_sfx_volume(settings.sfxVolume + 1)
    end))

    widget:bind_click("bgm_volume_down", on_button_click(function()
        set_bgm_volume(settings.bgmVolume - 1)
    end))

    widget:bind_click("bgm_volume_up", on_button_click(function()
        set_bgm_volume(settings.bgmVolume + 1)
    end))

    bind_hover_sound("page_back_button")
    bind_hover_sound("page_confirm_button")
    bind_hover_sound("sfx_volume_down")
    bind_hover_sound("sfx_volume_up")
    bind_hover_sound("bgm_volume_down")
    bind_hover_sound("bgm_volume_up")
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

    widget:SetWantsMouse(visible)

    if widget.IsInViewport == nil or not widget:IsInViewport() then
        widget:AddToViewportZ(PAGE_Z_ORDER)
    end

    bind_actions()
    set_display("page_root", visible)
    apply_settings_to_view()

    return widget
end

-- 하위 페이지 UI 생성 진입점
-- options.pageType = "options" | "controls" | "scoreboard" | "credits"
-- options.title = 화면 좌상단 제목
-- options.initialSettings = { sfxVolume, bgmVolume } (선택)
-- options.onConfirm = function(settings, pageType) end
-- options.onBack = function(pageType) end
function M.Create(options)
    options = options or {}
    on_confirm = options.onConfirm
    on_back = options.onBack
    on_settings_changed = options.onSettingsChanged
    scoreboard_entries = options.scoreboardEntries

    local initial = options.initialSettings or UserSettings.GetSettings()
    if initial ~= nil then
        settings.sfxVolume = clamp(initial.sfxVolume or UserSettings.sfxVolume or DEFAULT_SFX_VOLUME, MIN_VOLUME, MAX_VOLUME)
        settings.bgmVolume = clamp(initial.bgmVolume or UserSettings.bgmVolume or DEFAULT_BGM_VOLUME, MIN_VOLUME, MAX_VOLUME)
        settings.inputMode = UserSettings.inputMode
    end

    if ensure_widget() == nil then
        return nil
    end

    set_current_page(options.pageType or "options", options.title or "Options")
    return widget
end

-- 하위 페이지 화면을 띄운다 (어둡게 덮기 + 공통 헤더/버튼 + 페이지 내용)
function M.Show()
    visible = true

    if ensure_widget() == nil then
        return
    end

    widget:SetWantsMouse(true)
    set_display("page_root", true)
    widget:SetProperty("page_root", "opacity", "0.000")
    -- page_root가 visible 된 후 다시 적용: display:none 상태에서 SetProperty가
    -- RmlUi에 의해 무시되거나 초기화될 수 있으므로 여기서 재적용한다.
    apply_settings_to_view()
    apply_scoreboard_to_view()
end

-- 서브 페이지 전체 opacity 설정 (페이드 인/아웃용)
function M.SetOpacity(alpha)
    if widget == nil then
        return
    end
    local clamped = math.max(0.0, math.min(1.0, alpha))
    widget:SetProperty("page_root", "opacity", string.format("%.3f", clamped))
end

-- 하위 페이지 화면을 닫는다
function M.Hide()
    visible = false

    if widget == nil then
        return
    end

    widget:SetWantsMouse(false)
    set_display("page_root", false)
end

function M.IsVisible()
    return visible
end

-- 현재 화면에 표시 중인 옵션 설정값을 반환한다 ({ sfxVolume, bgmVolume })
function M.GetSettings()
    return {
        sfxVolume = settings.sfxVolume,
        bgmVolume = settings.bgmVolume,
        inputMode = settings.inputMode,
    }
end

-- 외부 설정값을 화면에 반영한다 (예: 저장된 값 불러오기)
function M.ApplySettings(new_settings)
    if new_settings == nil then
        return
    end

    if new_settings.sfxVolume ~= nil then
        settings.sfxVolume = clamp(new_settings.sfxVolume, MIN_VOLUME, MAX_VOLUME)
    end

    if new_settings.bgmVolume ~= nil then
        settings.bgmVolume = clamp(new_settings.bgmVolume, MIN_VOLUME, MAX_VOLUME)
    end


    apply_settings_to_view()
end

-- 하위 페이지 UI 제거 및 내부 상태 초기화
function M.Destroy()
    if widget ~= nil then
        widget:RemoveFromParent()
    end

    widget = nil
    bindings_initialized = false
    visible = false
    current_page_type = "options"
    on_confirm = nil
    on_back = nil
    on_settings_changed = nil
    scoreboard_entries = nil
    settings = UserSettings.GetSettings()
end

return M
