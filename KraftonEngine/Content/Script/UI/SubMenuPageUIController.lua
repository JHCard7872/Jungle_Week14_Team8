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
-- 미선택 기본값: 테두리를 또렷하게 둬서 버튼임을 알아보게 한다(모달 전환 버튼과 동일).
local TAB_DEFAULT_BG      = "#00000099"
local TAB_DEFAULT_BORDER  = "#ffffffcc"

-- 현재 화면에 표시 중인 옵션 설정값
local settings = UserSettings.GetSettings()

-- 크레딧 ID 카드 플립/확대 연출 상태
local FLIP_DURATION = 0.42      -- 한 바퀴(앞→뒤) 도는 데 걸리는 시간
local FLIP_REST_DURATION = 0.7  -- 한 바퀴 돈 뒤 다음 바퀴까지 쉬는 시간(무한 회전 시)
local CREDITS_DEFAULT_HINT = "Hint: 플레이 중 반짝이는 무언가를 찾아보세요!"
local CREDITS_ALL_HINT = "축하합니다! 모든 사원증을 찾았습니다."
local credits_collected = {}   -- 현재 컬렉션 { [key]=true } (apply_credits_collection에서 갱신)
-- [key] = { phase("idle"|"spinning"|"settling"), elapsed, showingDev, swapped, hovering, resting, rest_elapsed, settle_scale }
local flip_states = {}

-- hover 히트 테스트용 카드 레이아웃 상수 (sub_menu_page.rcss와 1:1로 맞춰야 함).
-- 엔진은 mouseout 이벤트를 Lua로 주지 않으므로, hover 해제는 매 프레임 마우스
-- 좌표(Input.GetMouseX/Y)를 카드 사각형과 직접 비교해 판정한다.
local CARD_ASPECT = 661 / 438        -- 모든 크레딧 카드 PNG = 438x661 (height/width)
local CARD_LEFT_FRAC = { 0.17, 0.35, 0.53, 0.71 }  -- .credits_id_card_N left %
local CARD_WIDTH_FRAC = 0.13         -- .credits_id_card width % (page_body 기준)
local PAGE_BODY_LEFT_FRAC = 0.05     -- #page_body left %
local PAGE_BODY_TOP_FRAC = 0.21      -- #page_body top %
local PAGE_BODY_WIDTH_FRAC = 0.90    -- #page_body width %
local CARD_TOP_OFFSET = -20 + 150    -- .credits_card top(-20px) + .credits_id_card top(150px)

-- 모달 전환 버튼 색상 (기본 테두리를 또렷하게 둬서 버튼임을 알아보게 한다)
local MODAL_BTN_BG_DEFAULT     = "#00000099"
local MODAL_BTN_BORDER_DEFAULT = "#ffffffcc"
local MODAL_BTN_BG_DISABLED    = "#0000004d"  -- 검은색 30% 오퍼시티(비활성)
local MODAL_BTN_TEXT_DISABLED  = "#ffffff66"

-- 모달이 열릴 때 가리는(=블러 처리 대용으로 감추는) 크레딧 전경 요소들.
-- 엔진 RmlUi 렌더러가 실제 blur 필터를 지원하지 않아, 선명한 전경을 숨기고
-- 뒤에 이미 깔린 블러 처리된 메인 메뉴 배경 + 딤으로 "배경 블러" 느낌을 낸다.
local CREDITS_FOREGROUND_IDS = { "page_body", "page_title_frame", "page_back_button", "page_confirm_button" }

-- 카드 확대 모달 상태
local expanded_person = nil          -- 현재 확대 중인 사람(없으면 nil)
local expanded_showing_dev = false   -- 모달에서 사원증(dev) 면을 보는 중인지
-- 모달에서 마지막으로 고른 면을 닫은 뒤 그리드 카드에도 유지하기 위한 per-key 오버라이드.
-- [key] = true(사원증/dev) | false(교육생증/jungle). 없으면 습득 여부 기본값을 따른다.
local card_face_override = {}
local modal_opening = false          -- 등장(확대) 애니메이션 진행 중
local modal_open_elapsed = 0.0
local MODAL_OPEN_DURATION = 0.22
-- 확대 도착 지점: 화면 중앙(가로 50%, 세로 44%)에 높이 62%로. (#credits_modal_card와 일치)
local MODAL_CARD_HEIGHT_FRAC = 0.62
local MODAL_CARD_CENTER_X_FRAC = 0.50
local MODAL_CARD_CENTER_Y_FRAC = 0.44
-- 확대 애니메이션의 시작(클릭한 카드 위치/크기) / 도착(중앙 확대) 사각형 {left, top, w, h} (px)
local modal_src_rect = nil
local modal_dst_rect = nil

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

-- 그리드에 놓인 카드 한 장의 화면 사각형(px) {left, top, w, h}. RCSS 레이아웃 상수로 계산.
local function compute_card_grid_rect(index, vw, vh)
    local body_w = PAGE_BODY_WIDTH_FRAC * vw
    local left = PAGE_BODY_LEFT_FRAC * vw + CARD_LEFT_FRAC[index] * body_w
    local top = PAGE_BODY_TOP_FRAC * vh + CARD_TOP_OFFSET
    local w = CARD_WIDTH_FRAC * body_w
    return left, top, w, w * CARD_ASPECT
end

-- 확대 도착 사각형(px): 화면 중앙에 높이 62%(폭은 비율대로).
local function compute_modal_target_rect(vw, vh)
    local h = MODAL_CARD_HEIGHT_FRAC * vh
    local w = h / CARD_ASPECT
    local left = MODAL_CARD_CENTER_X_FRAC * vw - w * 0.5
    local top = MODAL_CARD_CENTER_Y_FRAC * vh - h * 0.5
    return left, top, w, h
end

-- 모달 카드를 주어진 px 사각형에 배치한다(확대 애니메이션용 — translate 대신 left/top/size 직접).
local function set_modal_card_rect(left, top, w, h)
    widget:SetProperty("credits_modal_card", "transform", "scale(1.0)")
    widget:SetProperty("credits_modal_card", "left", string.format("%.1fpx", left))
    widget:SetProperty("credits_modal_card", "top", string.format("%.1fpx", top))
    widget:SetProperty("credits_modal_card", "width", string.format("%.1fpx", w))
    widget:SetProperty("credits_modal_card", "height", string.format("%.1fpx", h))
end

-- 카드의 "쉬는 면": 습득자는 사원증(dev), 미습득자는 교육생증(jungle)을 기본으로 보여준다.
-- 모달에서 면을 골라 닫았으면(card_face_override) 그 선택을 우선한다.
-- 단 미습득자는 어떤 경우에도 사원증을 노출하지 않으므로 collected 검사를 함께 둔다.
local function rest_dev(person)
    local override = card_face_override[person.key]
    if override ~= nil then
        return override and credits_collected[person.key] == true
    end
    return credits_collected[person.key] == true
end

-- 모달이 가리던 크레딧 전경(카드/제목/버튼)의 표시 여부를 한 번에 토글한다.
local function set_credits_foreground_visible(is_visible)
    for _, element_id in ipairs(CREDITS_FOREGROUND_IDS) do
        set_display(element_id, is_visible)
    end
end

-- 카드 확대 모달을 닫고 그리드(4장) 상태로 되돌린다.
local function close_card_modal()
    expanded_person = nil
    modal_opening = false
    set_display("credits_card_modal", false)
    set_credits_foreground_visible(true)
end

-- 크레딧 ID 카드 컬렉션 반영: 저장 파일을 읽어 습득한 사람은 dev 이미지로, 미습득은
-- jungle 이미지로 갈아끼운다. 카드 플립 상태를 초기화하고, 4명 모두 습득 시 힌트 문구를
-- 축하 문구로 바꾼다. (크레딧 진입 때마다 호출 — 파일을 매번 다시 읽는다)
local function apply_credits_collection()
    if widget == nil or widget.SetAttribute == nil then
        return
    end

    close_card_modal()
    credits_collected = IdCardCollection.LoadCollectedSet()

    local all_collected = true
    for _, person in ipairs(IdCardCollection.GetPeople()) do
        local got = credits_collected[person.key] == true
        if not got then
            all_collected = false
        end

        flip_states[person.key] = { phase = "idle", elapsed = 0.0, showingDev = got, swapped = false, hovering = false, resting = false, rest_elapsed = 0.0, settle_scale = 1.0 }
        set_card_src(person, got)
        widget:SetProperty(person.creditsElementId, "transform", "scale(1.0, 1.0)")
    end

    set_text("credits_hint", all_collected and CREDITS_ALL_HINT or CREDITS_DEFAULT_HINT)
end

-- 현재 회전 진행도(t)에서의 scaleX. (t<0.5: 현재 면이 접힘 1→0, t>=0.5: 다음 면이 펼쳐짐 0→1)
local function flip_scale_x(t)
    if t < 0.5 then
        return 1.0 - t * 2.0
    end
    return (t - 0.5) * 2.0
end

-- 플립 애니메이션 1프레임 진행. 카드 중심을 기준으로 scaleX 1→0(가장 얇은 순간 면 전환)→1.
-- 한 바퀴를 다 돌면 FLIP_REST_DURATION 만큼 쉬었다가 다음 바퀴를 돈다(무한 회전이 너무
-- 빠르지 않게). settling이면 현재 보고 있는 면을 그대로 펼쳐 가까운 면에서 멈춘다.
-- (미습득 카드는 내부 showingDev는 토글하되 화면에는 사원증을 절대 노출하지 않는다)
local function advance_flip(person, st, delta)
    if st.phase == "idle" then
        return
    end

    -- hover 해제 후 정착: 지금 보이는 면 그대로 scaleX를 1까지 펼치고 멈춘다(면 전환 없음).
    if st.phase == "settling" then
        st.settle_scale = math.min(1.0, st.settle_scale + delta / (FLIP_DURATION * 0.5))
        if st.settle_scale >= 1.0 then
            st.phase = "idle"
            widget:SetProperty(person.creditsElementId, "transform", "scale(1.0, 1.0)")
        else
            widget:SetProperty(person.creditsElementId, "transform", string.format("scale(%.3f, 1.0)", st.settle_scale))
        end
        return
    end

    -- 바퀴 사이 쉬는 시간 (카드는 scale(1,1)로 멈춰 있음)
    if st.resting then
        st.rest_elapsed = st.rest_elapsed + delta
        if st.rest_elapsed < FLIP_REST_DURATION then
            return
        end
        st.resting = false
        st.rest_elapsed = 0.0
        st.elapsed = 0.0
        st.swapped = false
    end

    st.elapsed = st.elapsed + delta
    local t = st.elapsed / FLIP_DURATION

    if t >= 1.0 then
        -- 한 바퀴 완료 → 다음 바퀴 전 잠시 쉰다 (hover 유지 중에만 여기 도달)
        st.elapsed = 0.0
        st.swapped = false
        st.resting = true
        st.rest_elapsed = 0.0
        widget:SetProperty(person.creditsElementId, "transform", "scale(1.0, 1.0)")
        return
    end

    if t >= 0.5 and not st.swapped then   -- 가장 얇아진 순간 한 번만 면 전환
        st.showingDev = not st.showingDev
        -- 미습득 카드는 사원증(dev) 면을 노출하지 않는다 — 항상 교육생증 유지
        set_card_src(person, st.showingDev and rest_dev(person))
        st.swapped = true
    end

    widget:SetProperty(person.creditsElementId, "transform", string.format("scale(%.3f, 1.0)", flip_scale_x(t)))
end

-- hover가 풀린 순간 호출. 현재 회전 각도에서 "가까운 면"으로 멈추게 한다.
--  · 쉬는 중이면 이미 한 면(scaleX=1)에 멈춰 있으므로 그대로 정지.
--  · 회전 중이면 지금 보이는 면을 그대로 펼쳐(settling) 가까운 면에서 멈춘다.
--    (t<0.5면 전환 전 면, t>=0.5면 이미 전환된 면 — 둘 다 현재 보이는 면이 가까운 쪽)
local function begin_settle(st)
    if st.phase == "idle" or st.phase == "settling" then
        return
    end
    if st.resting then
        st.resting = false
        st.rest_elapsed = 0.0
        st.phase = "idle"
        return
    end
    st.settle_scale = flip_scale_x(st.elapsed / FLIP_DURATION)
    st.phase = "settling"
end

-- 정착(settling) 중 다시 hover하면 보이던 면을 마저 펼친 뒤 이어서 회전하도록 복원한다.
local function resume_spin_from_settle(st)
    st.phase = "spinning"
    st.swapped = true   -- 지금 보이는 면은 "전환 완료" 상태로 취급
    st.resting = false
    st.rest_elapsed = 0.0
    st.elapsed = (0.5 + st.settle_scale * 0.5) * FLIP_DURATION  -- 현재 scaleX에 해당하는 후반부 지점
end

-- 매 프레임 마우스 좌표로 4장의 카드 hover 여부를 직접 판정한다(엔진에 mouseout 이벤트가
-- 없어 이벤트로는 hover 해제를 알 수 없다). hover 진입 시 무한 회전 시작 + hover 사운드,
-- 해제 시 현재 각도에서 가까운 면으로 정착한다.
local function update_card_hover_and_flip(delta)
    local viewport = Engine.GetViewportSize()
    local vw = tonumber(viewport.Width) or 0
    local vh = tonumber(viewport.Height) or 0
    local mx = Input.GetMouseX()
    local my = Input.GetMouseY()
    local has_viewport = vw > 0 and vh > 0

    for i, person in ipairs(IdCardCollection.GetPeople()) do
        local st = flip_states[person.key]
        if st ~= nil then
            local hovering = false
            if has_viewport then
                local left, top, w, h = compute_card_grid_rect(i, vw, vh)
                hovering = mx >= left and mx <= left + w and my >= top and my <= top + h
            end

            if hovering and not st.hovering then
                st.hovering = true
                if st.phase == "idle" then
                    st.phase = "spinning"
                    st.elapsed = 0.0
                    st.swapped = false
                    st.resting = false
                    st.rest_elapsed = 0.0
                elseif st.phase == "settling" then
                    resume_spin_from_settle(st)
                end
                play_ui_hover()
            elseif not hovering and st.hovering then
                st.hovering = false
                begin_settle(st)
            end

            advance_flip(person, st, delta)
        end
    end
end

-- 모달 하단 교육생증/사원증 버튼의 선택/비활성 상태를 그린다.
-- (Lua에서 class 토글이 안 되므로 색/투명도를 SetProperty로 직접 적용 — set_controls_device와 동일 방식)
local function update_modal_switch_buttons()
    if widget == nil or expanded_person == nil then
        return
    end

    local obtained = credits_collected[expanded_person.key] == true

    -- 교육생증(jungle): 항상 활성, dev를 안 볼 때 선택 상태
    local trainee_selected = not expanded_showing_dev
    widget:SetProperty("credits_modal_btn_trainee", "color", "#ffffff")
    widget:SetProperty("credits_modal_btn_trainee", "background-color", trainee_selected and TAB_SELECTED_BG or MODAL_BTN_BG_DEFAULT)
    widget:SetProperty("credits_modal_btn_trainee", "border-color", trainee_selected and TAB_SELECTED_BORDER or MODAL_BTN_BORDER_DEFAULT)

    -- 사원증(dev): 미습득이면 검은색 30% 배경으로 비활성(테두리는 또렷하게 유지)
    if not obtained then
        widget:SetProperty("credits_modal_btn_employee", "color", MODAL_BTN_TEXT_DISABLED)
        widget:SetProperty("credits_modal_btn_employee", "background-color", MODAL_BTN_BG_DISABLED)
        widget:SetProperty("credits_modal_btn_employee", "border-color", MODAL_BTN_BORDER_DEFAULT)
    else
        local employee_selected = expanded_showing_dev
        widget:SetProperty("credits_modal_btn_employee", "color", "#ffffff")
        widget:SetProperty("credits_modal_btn_employee", "background-color", employee_selected and TAB_SELECTED_BG or MODAL_BTN_BG_DEFAULT)
        widget:SetProperty("credits_modal_btn_employee", "border-color", employee_selected and TAB_SELECTED_BORDER or MODAL_BTN_BORDER_DEFAULT)
    end
end

-- 모달 카드 면 전환. 미습득 카드는 사원증으로 전환할 수 없다.
local function set_modal_face(show_dev)
    if widget == nil or expanded_person == nil then
        return
    end
    if show_dev and credits_collected[expanded_person.key] ~= true then
        return
    end

    expanded_showing_dev = show_dev
    widget:SetAttribute("credits_modal_card", "src", show_dev and expanded_person.devImage or expanded_person.jungleImage)
    update_modal_switch_buttons()
end

-- 카드를 클릭한 위치/크기에서부터 서서히 화면 중앙으로 확대(모달).
-- index = 클릭한 카드의 1~4 위치(시작 사각형 계산용). 진입 시 그리드 카드는 쉬는 면으로 초기화.
local function open_card_modal(person, index)
    if widget == nil then
        return
    end

    -- 뒤에 깔린 그리드 카드들은 회전을 멈추고 쉬는 면으로 되돌린다.
    for _, p in ipairs(IdCardCollection.GetPeople()) do
        local st = flip_states[p.key]
        if st ~= nil then
            st.phase = "idle"
            st.elapsed = 0.0
            st.swapped = false
            st.hovering = false
            st.resting = false
            st.rest_elapsed = 0.0
            st.settle_scale = 1.0
            st.showingDev = rest_dev(p)
            set_card_src(p, st.showingDev)
            widget:SetProperty(p.creditsElementId, "transform", "scale(1.0, 1.0)")
        end
    end

    expanded_person = person
    expanded_showing_dev = rest_dev(person)   -- 기본은 클릭 직전 보이던 면
    modal_opening = true
    modal_open_elapsed = 0.0

    -- 시작(클릭한 그리드 카드)·도착(중앙 확대) 사각형을 px로 계산해 저장. 뷰포트가
    -- 0이면 도착 위치에서 바로 뜨도록 시작=도착으로 둔다.
    local viewport = Engine.GetViewportSize()
    local vw = tonumber(viewport.Width) or 0
    local vh = tonumber(viewport.Height) or 0
    if vw > 0 and vh > 0 then
        local sl, st_, sw, sh = compute_card_grid_rect(index or 1, vw, vh)
        local dl, dt, dw, dh = compute_modal_target_rect(vw, vh)
        modal_src_rect = { left = sl, top = st_, w = sw, h = sh }
        modal_dst_rect = { left = dl, top = dt, w = dw, h = dh }
    else
        modal_src_rect = nil
        modal_dst_rect = nil
    end

    -- 선명한 전경을 숨겨 뒤(블러된 메인 메뉴 배경 + 딤)만 보이게 한다.
    set_credits_foreground_visible(false)

    widget:SetAttribute("credits_modal_card", "src", expanded_showing_dev and person.devImage or person.jungleImage)
    update_modal_switch_buttons()
    set_display("credits_card_modal", true)
    widget:SetProperty("credits_modal_dim", "opacity", "0.000")
    if modal_src_rect ~= nil then
        set_modal_card_rect(modal_src_rect.left, modal_src_rect.top, modal_src_rect.w, modal_src_rect.h)
    end
end

-- 크레딧 카드 클릭 → 일반 메뉴와 같은 클릭음 + (클릭한 위치에서) 화면 중앙 확대 모달.
local function on_credits_card_click(person, index)
    return function()
        if widget == nil or expanded_person ~= nil then
            return
        end
        play_ui_click()
        open_card_modal(person, index)
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

    -- 크레딧 ID 카드 클릭 → 클릭한 위치에서 화면 중앙으로 확대되는 모달
    for i, person in ipairs(IdCardCollection.GetPeople()) do
        widget:bind_click(person.creditsElementId, on_credits_card_click(person, i))
    end

    -- 확대 모달: 닫기(X) / 뒷배경 클릭 / 교육생증·사원증 전환 버튼
    widget:bind_click("credits_modal_close", on_button_click(close_card_modal))
    widget:bind_click("credits_modal_dim", on_button_click(close_card_modal))
    widget:bind_click("credits_modal_btn_trainee", on_button_click(function()
        set_modal_face(false)
    end))
    widget:bind_click("credits_modal_btn_employee", function()
        -- 미습득(사원증 비활성)이면 클릭음도 내지 않는다.
        if expanded_person == nil or credits_collected[expanded_person.key] ~= true then
            return
        end
        play_ui_click()
        set_modal_face(true)
    end)

    bind_hover_sound("credits_modal_close")
    bind_hover_sound("credits_modal_btn_trainee")
    bind_hover_sound("credits_modal_btn_employee")

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
    close_card_modal()
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

-- 매 프레임 크레딧 연출 갱신 (MainMenuScene.update_sub_page_fade에서 호출)
--  · 모달이 열려 있으면: 등장(확대) 애니메이션만 진행하고 그리드 hover 회전은 멈춘다.
--  · 모달이 닫혀 있으면: 마우스 hover에 따라 카드가 무한 회전/복귀한다.
function M.Update(dt)
    if widget == nil or not visible or current_page_type ~= "credits" then
        return
    end

    local delta = math.max(0.0, tonumber(dt) or 0.0)

    if expanded_person ~= nil then
        if modal_opening then
            modal_open_elapsed = math.min(modal_open_elapsed + delta, MODAL_OPEN_DURATION)
            local t = modal_open_elapsed / MODAL_OPEN_DURATION
            local e = t * (2.0 - t)                   -- ease-out (처음 빠르게, 끝에서 부드럽게)
            widget:SetProperty("credits_modal_dim", "opacity", string.format("%.3f", t))

            if modal_src_rect ~= nil and modal_dst_rect ~= nil then
                -- 클릭한 카드 위치/크기 → 중앙 확대 위치/크기로 서서히 이동·확대
                local s, d = modal_src_rect, modal_dst_rect
                set_modal_card_rect(
                    s.left + (d.left - s.left) * e,
                    s.top  + (d.top  - s.top)  * e,
                    s.w    + (d.w    - s.w)    * e,
                    s.h    + (d.h    - s.h)    * e)
            end

            if t >= 1.0 then
                modal_opening = false
                if modal_dst_rect ~= nil then
                    set_modal_card_rect(modal_dst_rect.left, modal_dst_rect.top, modal_dst_rect.w, modal_dst_rect.h)
                end
            end
        end
        return
    end

    update_card_hover_and_flip(delta)
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
    expanded_person = nil
    expanded_showing_dev = false
    modal_opening = false
    modal_open_elapsed = 0.0
    modal_src_rect = nil
    modal_dst_rect = nil
end

return M
