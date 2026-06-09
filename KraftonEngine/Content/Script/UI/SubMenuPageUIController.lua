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
local IdCardCollection = require("Data/IdCardCollection")
local Cursor = require("UI/CursorSpriteUtil")
-- Pause(220)보다 위에 뜨도록
local PAGE_Z_ORDER = 230
local CURSOR_SIZE = Cursor.GetDefaultSize()

local UI_CLICK_KEY = "sfx_ui_click"
local UI_HOVER_KEY = "sfx_ui_hover"

local MIN_VOLUME = 0
local MAX_VOLUME = 10
local DEFAULT_SFX_VOLUME = 8
local DEFAULT_BGM_VOLUME = 8
local ENTRIES_PER_PAGE = 5
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
local scoreboard_current_page = 1

-- 플레이 방법 탭/장치 상태
local controls_active_tab = "input"
local controls_active_device = "km"
local controls_game_current_page = 1
local CONTROLS_GAME_TOTAL_PAGES = 2

local TAB_SELECTED_BG     = "#d6f28e40"
local TAB_SELECTED_BORDER = "#d6f28eff"
local TAB_DEFAULT_BG      = "#00000060"
local TAB_DEFAULT_BORDER  = "#ffffff44"

-- 현재 화면에 표시 중인 옵션 설정값
local settings = UserSettings.GetSettings()

-- 크레딧 ID 카드 플립 연출 상태
local FLIP_DURATION = 0.42
local FLIP_SFX_KEY = "sfx_shine"
local CREDITS_DEFAULT_HINT = "Hint: 플레이 중 반짝이는 무언가를 찾아보세요!"
local CREDITS_ALL_HINT = "축하합니다! 모든 사원증을 찾았습니다."
local credits_collected = {}   -- 현재 컬렉션 { [key]=true } (apply_credits_collection에서 갱신)
local flip_states = {}         -- [key] = { phase, elapsed, showingDev, swapped }

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
    if widget == nil then return end

    local entries = scoreboard_entries or {}
    local total_entries = #entries
    local total_pages = math.max(1, math.ceil(total_entries / ENTRIES_PER_PAGE))
    scoreboard_current_page = math.max(1, math.min(scoreboard_current_page, total_pages))

    local start_idx = (scoreboard_current_page - 1) * ENTRIES_PER_PAGE + 1

    for i = 1, ENTRIES_PER_PAGE do
        local row_id = "score_row_" .. tostring(i)
        local entry = entries[start_idx + i - 1]
        set_display(row_id, entry ~= nil)

        if entry ~= nil then
            local rank = start_idx + i - 1
            set_text("score_rank_" .. tostring(i), tostring(rank))
            set_text("score_name_" .. tostring(i), tostring(entry.nickname or "김정글"))
            set_text("score_count_" .. tostring(i), tostring(entry.collectedCount or 0) .. "체")
            set_text("score_value_" .. tostring(i), tostring(entry.totalScore or 0))
            set_text("score_date_" .. tostring(i), tostring(entry.savedDateText or entry.savedDate or "-"))
        end
    end

    set_display("score_empty_text", total_entries == 0)
    set_text("scoreboard_page_label", tostring(scoreboard_current_page) .. "/" .. tostring(total_pages))
end

-- 크레딧 카드 한 장의 src를 앞면(dev)/뒷면(jungle)으로 설정한다.
-- (RmlUi img src는 스타일로 못 바꾸지만 SetAttribute("src", ...)는 가능 — HUD와 동일 방식)
local function set_card_src(person, show_dev)
    if widget == nil or widget.SetAttribute == nil then
        return
    end

    widget:SetAttribute(person.creditsElementId, "src", show_dev and person.devImage or person.jungleImage)
end

-- 크레딧 ID 카드 컬렉션 반영: 저장 파일을 읽어 습득한 사람은 dev 이미지로, 미습득은
-- jungle 이미지로 갈아끼운다. 카드 플립 상태를 초기화하고, 4명 모두 습득 시 힌트 문구를
-- 축하 문구로 바꾼다. (크레딧 진입 때마다 호출 — 파일을 매번 다시 읽는다)
local function apply_credits_collection()
    if widget == nil or widget.SetAttribute == nil then
        return
    end

    credits_collected = IdCardCollection.LoadCollectedSet()

    local all_collected = true
    for _, person in ipairs(IdCardCollection.GetPeople()) do
        local got = credits_collected[person.key] == true
        if not got then
            all_collected = false
        end

        flip_states[person.key] = { phase = "idle", elapsed = 0.0, showingDev = got, swapped = false }
        set_card_src(person, got)
        widget:SetProperty(person.creditsElementId, "transform", "scale(1.0, 1.0)")
    end

    set_text("credits_hint", all_collected and CREDITS_ALL_HINT or CREDITS_DEFAULT_HINT)
end

-- 습득(true)한 카드를 클릭할 때마다 뒤집기를 (재)시작하고 SfxShine을 재생한다.
-- 진행 중에 다시 눌러도 처음부터 다시 뒤집으므로, 빠르게 연타하거나 되돌릴 때도
-- 매번 소리가 난다. (이전엔 phase=="idle"이 아니면 무시해 복귀 플립 소리가 씹혔다)
local function on_credits_card_click(person)
    return function()
        if widget == nil or credits_collected[person.key] ~= true then
            return
        end

        local st = flip_states[person.key]
        if st == nil then
            return
        end

        st.phase = "flipping"
        st.elapsed = 0.0
        st.swapped = false
        AudioManager.Play(FLIP_SFX_KEY, get_sfx_volume_scalar())
    end
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


local function set_controls_device(device)
    if widget == nil then return end
    controls_active_device = device
    local km = device == "km"
    widget:SetProperty("controls_device_km", "background-color", km and TAB_SELECTED_BG or TAB_DEFAULT_BG)
    widget:SetProperty("controls_device_km", "border-color",     km and TAB_SELECTED_BORDER or TAB_DEFAULT_BORDER)
    widget:SetProperty("controls_device_gp", "background-color", (not km) and TAB_SELECTED_BG or TAB_DEFAULT_BG)
    widget:SetProperty("controls_device_gp", "border-color",     (not km) and TAB_SELECTED_BORDER or TAB_DEFAULT_BORDER)
    set_display("controls_image_km", km)
    set_display("controls_image_gp", not km)
end

local function set_controls_game_page(page)
    if widget == nil then return end
    controls_game_current_page = math.max(1, math.min(page, CONTROLS_GAME_TOTAL_PAGES))
    for i = 1, CONTROLS_GAME_TOTAL_PAGES do
        set_display("controls_game_page_" .. tostring(i), i == controls_game_current_page)
    end
    set_text("controls_game_page_label", tostring(controls_game_current_page) .. "/" .. tostring(CONTROLS_GAME_TOTAL_PAGES))
    set_display("controls_game_prev_button", controls_game_current_page > 1)
    set_display("controls_game_next_button", controls_game_current_page < CONTROLS_GAME_TOTAL_PAGES)
end

local function set_controls_tab(tab)
    if widget == nil then return end
    controls_active_tab = tab
    local game  = tab == "game"
    local input = tab == "input"
    local choice = not game and not input

    -- 컨테이너만 숨기면 일부 RmlUi 스타일/hover 상태에서 내부 버튼이 남는 경우가 있어서
    -- 선택 버튼 2개도 같이 직접 토글한다.
    set_display("controls_choice_buttons", choice)
    set_display("controls_tab_game", choice)
    set_display("controls_tab_input", choice)

    set_display("controls_body_game",  game)
    set_display("controls_body_input", input)

    if game then
        controls_game_current_page = 1
        set_controls_game_page(1)
    end

    if input then
        set_controls_device(controls_active_device)
    else
        set_display("controls_image_km", false)
        set_display("controls_image_gp", false)
    end
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

    if current_page_type == "controls" then
        controls_active_tab = "none"
        controls_active_device = "km"
        set_controls_tab("none")
    end

    -- 크레딧 진입 시마다 컬렉션 파일을 다시 읽어 ID 카드 이미지를 갱신한다.
    if current_page_type == "credits" then
        apply_credits_collection()
    end

    -- Confirm은 Options에서만 노출, controls는 body 내 닫기 버튼으로 대체
    set_display("page_confirm_button", current_page_type ~= "controls")
    set_text("page_confirm_label", current_page_type == "options" and "결정" or "닫기")

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

    widget:bind_click("controls_tab_game", on_button_click(function()
        set_controls_tab("game")
    end))

    widget:bind_click("controls_tab_input", on_button_click(function()
        set_controls_tab("input")
    end))

    widget:bind_click("controls_device_km", on_button_click(function()
        set_controls_device("km")
    end))

    widget:bind_click("controls_device_gp", on_button_click(function()
        set_controls_device("gp")
    end))

    widget:bind_click("controls_close_button_game", on_button_click(function()
        set_controls_tab("none")
    end))

    widget:bind_click("controls_game_prev_button", on_button_click(function()
        set_controls_game_page(controls_game_current_page - 1)
    end))

    widget:bind_click("controls_game_next_button", on_button_click(function()
        set_controls_game_page(controls_game_current_page + 1)
    end))

    widget:bind_click("controls_close_button_input", on_button_click(function()
        set_controls_tab("none")
    end))

    widget:bind_click("scoreboard_prev_button", on_button_click(function()
        if scoreboard_current_page > 1 then
            scoreboard_current_page = scoreboard_current_page - 1
            apply_scoreboard_to_view()
        end
    end))

    widget:bind_click("scoreboard_next_button", on_button_click(function()
        local entries = scoreboard_entries or {}
        local total_pages = math.max(1, math.ceil(#entries / ENTRIES_PER_PAGE))
        if scoreboard_current_page < total_pages then
            scoreboard_current_page = scoreboard_current_page + 1
            apply_scoreboard_to_view()
        end
    end))

    bind_hover_sound("page_back_button")
    bind_hover_sound("page_confirm_button")
    bind_hover_sound("sfx_volume_down")
    bind_hover_sound("sfx_volume_up")
    bind_hover_sound("bgm_volume_down")
    bind_hover_sound("bgm_volume_up")
    bind_hover_sound("controls_tab_game")
    bind_hover_sound("controls_tab_input")
    bind_hover_sound("controls_device_km")
    bind_hover_sound("controls_device_gp")
    bind_hover_sound("controls_close_button_game")
    bind_hover_sound("controls_close_button_input")
    bind_hover_sound("controls_game_prev_button")
    bind_hover_sound("controls_game_next_button")
    bind_hover_sound("scoreboard_prev_button")
    bind_hover_sound("scoreboard_next_button")

    -- 크레딧 ID 카드 클릭 → 습득 카드면 플립 + SfxShine
    for _, person in ipairs(IdCardCollection.GetPeople()) do
        widget:bind_click(person.creditsElementId, on_credits_card_click(person))
    end

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
    Cursor.Hide(widget, "submenu_cursor_normal", "submenu_cursor_click")
end

-- 매 프레임 커서 위치/상태 갱신 (MainMenuScene.Tick에서 호출)
function M.UpdateCursor()
    if widget == nil then
        return
    end

    Cursor.Update(widget, "submenu_cursor_normal", "submenu_cursor_click", {
        visible = visible,
        size = CURSOR_SIZE,
    })
end

-- 매 프레임 크레딧 카드 플립 연출 갱신 (MainMenuScene.update_sub_page_fade에서 호출)
-- scaleX 1→0(중간에 면 전환)→1 로 카드가 한 바퀴 뒤집히는 연출.
function M.Update(dt)
    if widget == nil or not visible or current_page_type ~= "credits" then
        return
    end

    local delta = math.max(0.0, tonumber(dt) or 0.0)
    for _, person in ipairs(IdCardCollection.GetPeople()) do
        local st = flip_states[person.key]
        if st ~= nil and st.phase == "flipping" then
            st.elapsed = st.elapsed + delta
            local t = st.elapsed / FLIP_DURATION

            if t >= 1.0 then
                st.phase = "idle"
                st.elapsed = 0.0
                widget:SetProperty(person.creditsElementId, "transform", "scale(1.0, 1.0)")
            else
                local scale_x
                if t < 0.5 then
                    scale_x = 1.0 - t * 2.0          -- 1 → 0 (앞면이 모서리로 접힘)
                else
                    if not st.swapped then           -- 가장 얇아진 순간 한 번만 면 전환
                        st.showingDev = not st.showingDev
                        set_card_src(person, st.showingDev)
                        st.swapped = true
                    end
                    scale_x = (t - 0.5) * 2.0        -- 0 → 1 (뒷면이 펼쳐짐)
                end
                widget:SetProperty(person.creditsElementId, "transform",
                    string.format("scale(%.3f, 1.0)", scale_x))
            end
        end
    end
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
        Cursor.Hide(widget, "submenu_cursor_normal", "submenu_cursor_click")
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
    scoreboard_current_page = 1
    settings = UserSettings.GetSettings()
    controls_active_tab = "input"
    controls_active_device = "km"
    controls_game_current_page = 1
    flip_states = {}
    credits_collected = {}
end

return M
