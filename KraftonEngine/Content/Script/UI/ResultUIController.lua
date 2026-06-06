-- 게임 결과 데이터가 저장된 세션 모듈
local Session = require("GameSession")

-- Result 화면에서 사용할 RML 문서 경로
local UI_DOCUMENT_PATH = "Content/UI/Result/result_screen.rml"
-- 다른 UI 위에 Result 화면을 띄우기 위한 Z 순서
local RESULT_Z_ORDER = 250

-- =========================================================
-- Layout Config
-- 화면 배치와 크기 조정은 최대한 여기에서 관리한다.
-- RCSS는 기본 스타일만 담당하고, 실제 위치/크기 값은 Lua에서 주입한다.
-- =========================================================
local LAYOUT = {
    -- 기준 해상도와 해상도별 자동 스케일 제한
    -- 1920x1080을 기준으로 잡고, 더 작은 화면에서는 minScale까지 줄어든다.
    viewport = {
        baseWidth = 1920,
        baseHeight = 1080,
        minScale = 0.72,
        maxScale = 1.0,
    },

    -- 클립보드 배치
    -- visualScale은 클립보드 이미지에만 적용된다.
    -- 내부 글자, 랭크, 도장 크기에는 영향을 주지 않는다.
    clipboard = {
        -- result_clipboard.png의 기준 가로 크기
        width = 1180,
        -- result_clipboard.png의 기준 세로 크기
        height = 804,
        -- 클립보드 이미지만 확대/축소하는 값
        visualScale = 1.9,
        -- 클립보드 이미지만 좌우로 미세 조정할 때 사용
        imageOffsetX = 50,
        -- 클립보드 이미지 확대 기준점 X. 0.5면 중앙 기준
        originX = 0.5,
        -- 클립보드 이미지 확대 기준점 Y. 클립 상단 쪽을 기준으로 확대
        originY = 0.18,
        -- 슬라이딩 시작 Y 위치. 화면 아래쪽에서 시작하게 큰 값으로 둔다.
        startY = 1180,
        -- 슬라이딩 종료 Y 위치. 값이 작아질수록 위로 올라간다.
        endY = -300,
    },

    -- 클립보드 내부 내용 전체 오프셋
    -- 글자/랭크/총합계/도장 위치를 한꺼번에 밀고 싶을 때 사용한다.
    content = {
        offsetX = 0,
        offsetY = 0,
    },

    -- 사원 정보 value들의 시작 위치와 줄 간격
    employeeText = {
        left = 600,
        top = 550,
        lineGap = 30,
        width = 230,
        height = 26,
        fontSize = 20,
        lineHeight = 26,
        scale = 1.4,
    },

    -- 회수 실적 value들의 시작 위치와 줄 간격
    metricText = {
        left = 480,
        top = 850,
        lineGap = 36,
        width = 190,
        height = 28,
        fontSize = 20,
        lineHeight = 28,
        scale = 1.4,
    },

    -- 총 합계 숫자 위치
    totalText = {
        left = 700,
        top = 880,
        width = 250,
        height = 88,
        fontSize = 76,
        lineHeight = 88,
        scale = 1.2,
    },

    -- 랭크 글자 위치
    gradeLetter = {
        left = 880,
        top = 520,
        width = 150,
        height = 150,
        fontSize = 116,
        lineHeight = 150,
        scale = 1.2,
    },

    -- 찍으러 내려오는 도장 본체
    -- width만 바꾸면 originalWidth/originalHeight 기준으로 height가 자동 계산된다.
    stampDevice = {
        left = 700,
        top = 580,
        rotation = -13,

        originalWidth = 1400,
        originalHeight = 1123,
        width = 450,
        hiddenY = 170,
        readyY = 248,
        impactY = 392,
        recoverY = 302,
    },

    -- 종이에 남는 결과 도장
    -- width만 바꾸면 originalWidth/originalHeight 기준으로 height가 자동 계산된다.
    gradeStamp = {
        left = 700,
        top = 1000,
        originalWidth = 1279,
        originalHeight = 699,
        width = 450,
        rotation = -13,
    },

    -- Result 연출 타이밍
    animation = {
        printDuration = 1.10,
        slideDuration = 0.72,
        stampAppearDuration = 0.18,
        stampDropDuration = 0.14,
        stampSettleDuration = 0.26,
        hintFadeDuration = 0.35,
        shakeDuration = 0.28,
        shakeOffsetX = 12.0,
        shakeRotation = 1.2,
    },
}

-- 프린터 출력음
local PRINTER_SFX = "sfx_printer_print"
-- 클립보드가 올라오는 슬라이딩 효과음
local SLIDE_SFX = "sfx_clipboard_sliding"
-- 도장 찍는 순간 효과음
local STAMP_IMPACT_SFX = "sfx_stamp_impact"

-- 점수에 따른 랭크 기준
local RANK_A_SCORE_THRESHOLD = 1400
local RANK_B_SCORE_THRESHOLD = 900
local RANK_C_SCORE_THRESHOLD = 450

-- 실제 게임 결과가 없을 때 화면 확인용으로 사용하는 기본값
local FALLBACK_TOTAL_SCORE = 10720
local FALLBACK_COUNT = 18
local FALLBACK_BASE_SCORE = 8400
local FALLBACK_URGENT_SCORE = 2320

-- 외부에서 require해서 사용할 Result UI 모듈
local M = {}

-- 현재 생성된 UI 위젯 인스턴스
local widget = nil
-- Result 연출이 끝났는지 여부
local sequence_finished = false
-- 현재 연출 단계: idle / printing / sliding / stamp_appear / stamp_drop / stamp_reveal / done
local current_phase = "idle"
-- 현재 phase에 들어온 뒤 누적 시간
local phase_elapsed = 0.0
-- 화면에 표시할 결과 데이터 묶음
local current_payload = nil
-- 디버그 패널 버튼 이벤트를 중복 등록하지 않기 위한 플래그
local bindings_initialized = false
-- 디버그 패널 표시 여부
local debug_panel_enabled = false
-- 외부에서 원래 요청한 마우스 입력 사용 여부
local base_mouse_enabled = false
-- 실제 위젯에 적용할 마우스 입력 사용 여부
local mouse_enabled = false

-- 테이블을 재귀적으로 복사한다. ResetLayoutConfig에서 기본값 복구용으로 사용.
local function deep_copy(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for key, nested_value in pairs(value) do
        copy[key] = deep_copy(nested_value)
    end

    return copy
end

-- 런타임에서 LAYOUT을 조정한 뒤 원래 값으로 되돌리기 위한 백업
local DEFAULT_LAYOUT = deep_copy(LAYOUT)

-- =========================================================
-- Runtime State
-- 애니메이션 중 계속 변하는 값들.
-- LAYOUT은 기준값, state는 현재 프레임의 실제 상태라고 보면 된다.
-- =========================================================
local state = {
    clipboardY = LAYOUT.clipboard.startY,
    clipboardOffsetX = 0.0,
    clipboardRotation = 0.0,
    stampDeviceY = LAYOUT.stampDevice.hiddenY,
    stampDeviceOpacity = 0.0,
    gradeLetterOpacity = 1.0,
    gradeStampOpacity = 0.0,
    hintOpacity = 0.0,
}

-- 랭크별 도장 이미지와 결과 사운드 매핑
local RESULT_PRESETS = {
    A = {
        stampImage = "../../Sprite/result_stamp_bonus_approved.png",
        stampOriginalWidth = 1279,
        stampOriginalHeight = 699,
        resultSfx = "sfx_result_high",
    },
    B = {
        stampImage = "../../Sprite/result_stamp_still_employed.png",
        stampOriginalWidth = 1236,
        stampOriginalHeight = 667,
        resultSfx = "sfx_result_medium",
    },
    C = {
        stampImage = "../../Sprite/result_stamp_still_employed.png",
        stampOriginalWidth = 1236,
        stampOriginalHeight = 667,
        resultSfx = "sfx_result_medium",
    },
    F = {
        stampImage = "../../Sprite/result_stamp_you_re_fired.png",
        stampOriginalWidth = 1258,
        stampOriginalHeight = 653,
        resultSfx = "sfx_result_low",
    },
}

-- value를 min_value와 max_value 사이로 제한한다.
local function clamp(value, min_value, max_value)
    if value < min_value then
        return min_value
    end

    if value > max_value then
        return max_value
    end

    return value
end

-- a에서 b까지 t 비율만큼 선형 보간한다.
local function lerp(a, b, t)
    return a + (b - a) * t
end

-- 빠르게 시작해서 부드럽게 멈추는 easing. 클립보드 슬라이딩에 사용.
local function ease_out_cubic(t)
    local inv = 1.0 - t
    return 1.0 - inv * inv * inv
end

-- 천천히 시작해서 빠르게 떨어지는 easing. 도장 내려찍기에 사용.
local function ease_in_cubic(t)
    return t * t * t
end

-- 목표 지점 근처에서 살짝 튕기는 easing. 도장 등장 연출에 사용.
local function ease_out_back(t)
    local c1 = 1.70158
    local c3 = c1 + 1.0
    local x = t - 1.0
    return 1.0 + c3 * x * x * x + c1 * x * x
end

-- 원본 비율을 유지하면서 width에 맞는 height를 계산한다.
local function aspect_height(width, original_width, original_height)
    if original_width == 0 then
        return original_height
    end

    return width * original_height / original_width
end

-- 도장 본체의 현재 width 기준 height 계산
local function get_stamp_device_height()
    return aspect_height(
        LAYOUT.stampDevice.width,
        LAYOUT.stampDevice.originalWidth,
        LAYOUT.stampDevice.originalHeight
    )
end

-- 찍힌 도장의 현재 width 기준 height 계산
local function get_grade_stamp_height()
    local original_width = LAYOUT.gradeStamp.originalWidth
    local original_height = LAYOUT.gradeStamp.originalHeight

    if current_payload ~= nil then
        original_width = current_payload.stampOriginalWidth or original_width
        original_height = current_payload.stampOriginalHeight or original_height
    end

    return aspect_height(
        LAYOUT.gradeStamp.width,
        original_width,
        original_height
    )
end

-- RML 요소의 텍스트를 변경하는 안전 래퍼
local function set_text(element_id, value)
    if widget == nil then
        return
    end

    widget:SetText(element_id, tostring(value))
end

-- RML 요소의 CSS 속성을 변경하는 안전 래퍼
local function set_property(element_id, property_name, value)
    if widget == nil then
        return
    end

    widget:SetProperty(element_id, property_name, tostring(value))
end

-- 숫자 값을 px 문자열로 변환해서 속성에 넣는다.
local function set_px(element_id, property_name, value)
    set_property(element_id, property_name, string.format("%.1fpx", value))
end

-- opacity 전용 래퍼
local function set_opacity(element_id, value)
    set_property(element_id, "opacity", string.format("%.3f", value))
end

-- display 속성으로 요소 표시/숨김을 제어한다.
local function set_display(element_id, visible)
    set_property(element_id, "display", visible and "block" or "none")
end

-- 디버그 패널 input 값 설정
local function set_input_value(element_id, value)
    if widget == nil or widget.SetValue == nil then
        return
    end

    widget:SetValue(element_id, tostring(value))
end

-- 디버그 패널 input 값 읽기
local function get_input_value(element_id)
    if widget == nil or widget.GetValue == nil then
        return ""
    end

    return widget:GetValue(element_id)
end

-- input 값을 숫자로 읽고, 실패하면 fallback을 반환한다.
local function read_number_input(element_id, fallback)
    local value = tonumber(get_input_value(element_id))
    if value == nil then
        return fallback
    end
    return value
end

local function scaled(value, scale)
    return value * scale
end

-- 숫자 점수를 10,720처럼 콤마가 들어간 문자열로 변환한다.
local function format_score(value)
    local formatted = tostring(math.max(0, math.floor(tonumber(value) or 0)))

    while true do
        local changed = 0
        formatted, changed = string.gsub(formatted, "^(%-?%d+)(%d%d%d)", "%1,%2")

        if changed == 0 then
            break
        end
    end

    return formatted
end

-- 총점에 따라 A/B/C/F 랭크를 결정한다.
local function compute_rank(score)
    if score >= RANK_A_SCORE_THRESHOLD then
        return "A"
    end

    if score >= RANK_B_SCORE_THRESHOLD then
        return "B"
    end

    if score >= RANK_C_SCORE_THRESHOLD then
        return "C"
    end

    return "F"
end

-- GameSession에서 결과 데이터를 읽어서 UI에 표시하기 좋은 형태로 가공한다.
local function build_result_payload()
    local employee = Session.employee or {}
    local result = Session.result or {}

    local raw_score = math.max(0, math.floor(tonumber(Session.score) or 0))
    local raw_count = math.max(0, math.floor(tonumber(result.collectedCount) or 0))
    local has_live_result = raw_score > 0 or raw_count > 0

    local total_score = has_live_result and raw_score or FALLBACK_TOTAL_SCORE
    local count_value = raw_count > 0 and raw_count or FALLBACK_COUNT

    local base_score = tonumber(result.baseScore)
    local urgent_score = tonumber(result.urgentScore)

    if base_score == nil or urgent_score == nil then
        base_score = has_live_result and math.floor(total_score * 0.78) or FALLBACK_BASE_SCORE
        urgent_score = has_live_result and math.max(0, total_score - base_score) or FALLBACK_URGENT_SCORE
    else
        base_score = math.max(0, math.floor(base_score))
        urgent_score = math.max(0, math.floor(urgent_score))
    end

    local rank = compute_rank(total_score)
    local preset = RESULT_PRESETS[rank] or RESULT_PRESETS.F

    return {
        rank = rank,
        employeeNumber = employee.number or "GO-2417",
        employeeName = employee.name or "Employee",
        employeeDepartment = employee.department or "Operations",
        employeeRank = employee.rank or "Contract",
        countText = tostring(count_value),
        baseScoreText = format_score(base_score),
        urgentScoreText = format_score(urgent_score),
        totalScoreText = format_score(total_score),
        resultSfx = preset.resultSfx,
        stampImage = preset.stampImage,
        stampOriginalWidth = preset.stampOriginalWidth,
        stampOriginalHeight = preset.stampOriginalHeight,
    }
end

-- current_payload의 값을 실제 RML 텍스트/이미지에 반영한다.
local function apply_payload()
    if widget == nil or current_payload == nil then
        return
    end

    set_text("result_employee_no_value", current_payload.employeeNumber)
    set_text("result_employee_name_value", current_payload.employeeName)
    set_text("result_employee_dept_value", current_payload.employeeDepartment)
    set_text("result_employee_rank_value", current_payload.employeeRank)

    set_text("result_metric_count_value", current_payload.countText)
    set_text("result_metric_base_value", current_payload.baseScoreText)
    set_text("result_metric_urgent_value", current_payload.urgentScoreText)

    set_text("result_total_value", current_payload.totalScoreText)
    set_text("result_grade_letter", current_payload.rank)
    set_property("result_grade_stamp_image", "src", current_payload.stampImage)
end

-- 클립보드 stage와 클립보드 이미지의 위치/크기/스케일을 적용한다.
local function apply_clipboard_layout()
    if widget == nil then
        return
    end

    local viewport = Engine.GetViewportSize()
    local viewport_width = tonumber(viewport.Width) or LAYOUT.viewport.baseWidth
    local viewport_height = tonumber(viewport.Height) or LAYOUT.viewport.baseHeight

    local viewport_scale = math.min(
        viewport_width / LAYOUT.viewport.baseWidth,
        viewport_height / LAYOUT.viewport.baseHeight
    )

    -- stage_scale: UI 전체를 해상도에 맞추기 위한 배율
    -- 내부 글자와 도장도 이 배율은 같이 받는다.
    local stage_scale = clamp(
        viewport_scale,
        LAYOUT.viewport.minScale,
        LAYOUT.viewport.maxScale
    )

    -- image_scale: 클립보드 이미지에만 적용되는 배율
    -- 글자/도장은 커지지 않는다.
    local image_scale = LAYOUT.clipboard.visualScale
    local origin_x = LAYOUT.clipboard.width * LAYOUT.clipboard.originX
    local origin_y = LAYOUT.clipboard.height * LAYOUT.clipboard.originY
    local visual_width = LAYOUT.clipboard.width * image_scale * stage_scale

    -- 확대된 클립보드 이미지가 화면 중앙에 오도록 stage 위치를 보정한다.
    local stage_left =
        (viewport_width - visual_width) * 0.5
        + (origin_x * stage_scale * (image_scale - 1.0))
        + (state.clipboardOffsetX * stage_scale)

    local stage_top =
        (state.clipboardY * stage_scale)
        + (origin_y * stage_scale * (image_scale - 1.0))

    set_px("result_clipboard_stage", "width", LAYOUT.clipboard.width)
    set_px("result_clipboard_stage", "height", LAYOUT.clipboard.height)
    set_px("result_clipboard_stage", "left", stage_left)
    set_px("result_clipboard_stage", "top", stage_top)

    -- stage에는 해상도 대응 scale과 흔들림 회전만 적용한다.
    -- visualScale을 여기에 걸면 글자/도장까지 같이 커지므로 주의.
    set_property(
        "result_clipboard_stage",
        "transform",
        string.format("scale(%.3f) rotate(%.3fdeg)", stage_scale, state.clipboardRotation)
    )

    -- 클립보드 이미지에만 visualScale을 적용한다.
    set_property(
        "result_clipboard_image",
        "transform",
        string.format("scale(%.3f)", image_scale)
    )
    set_px("result_clipboard_image", "left", LAYOUT.clipboard.imageOffsetX)
end

-- 사원 정보, 실적, 총합계, 랭크 글자의 위치를 LAYOUT 값 기준으로 적용한다.
local function apply_text_layout()
    local employee_scale = LAYOUT.employeeText.scale
    local metric_scale = LAYOUT.metricText.scale
    local total_scale = LAYOUT.totalText.scale
    local grade_scale = LAYOUT.gradeLetter.scale

    set_px("result_overlay", "left", LAYOUT.content.offsetX)
    set_px("result_overlay", "top", LAYOUT.content.offsetY)

    set_px("result_employee_no_value", "left", LAYOUT.employeeText.left)
    set_px("result_employee_no_value", "top", LAYOUT.employeeText.top)
    set_px("result_employee_no_value", "width", scaled(LAYOUT.employeeText.width, employee_scale))
    set_px("result_employee_no_value", "height", scaled(LAYOUT.employeeText.height, employee_scale))
    set_px("result_employee_no_value", "font-size", scaled(LAYOUT.employeeText.fontSize, employee_scale))
    set_px("result_employee_no_value", "line-height", scaled(LAYOUT.employeeText.lineHeight, employee_scale))
    set_px("result_employee_name_value", "left", LAYOUT.employeeText.left)
    set_px("result_employee_name_value", "top", LAYOUT.employeeText.top + scaled(LAYOUT.employeeText.lineGap, employee_scale))
    set_px("result_employee_name_value", "width", scaled(LAYOUT.employeeText.width, employee_scale))
    set_px("result_employee_name_value", "height", scaled(LAYOUT.employeeText.height, employee_scale))
    set_px("result_employee_name_value", "font-size", scaled(LAYOUT.employeeText.fontSize, employee_scale))
    set_px("result_employee_name_value", "line-height", scaled(LAYOUT.employeeText.lineHeight, employee_scale))
    set_px("result_employee_dept_value", "left", LAYOUT.employeeText.left)
    set_px("result_employee_dept_value", "top", LAYOUT.employeeText.top + scaled(LAYOUT.employeeText.lineGap * 2, employee_scale))
    set_px("result_employee_dept_value", "width", scaled(LAYOUT.employeeText.width, employee_scale))
    set_px("result_employee_dept_value", "height", scaled(LAYOUT.employeeText.height, employee_scale))
    set_px("result_employee_dept_value", "font-size", scaled(LAYOUT.employeeText.fontSize, employee_scale))
    set_px("result_employee_dept_value", "line-height", scaled(LAYOUT.employeeText.lineHeight, employee_scale))
    set_px("result_employee_rank_value", "left", LAYOUT.employeeText.left)
    set_px("result_employee_rank_value", "top", LAYOUT.employeeText.top + scaled(LAYOUT.employeeText.lineGap * 3, employee_scale))
    set_px("result_employee_rank_value", "width", scaled(LAYOUT.employeeText.width, employee_scale))
    set_px("result_employee_rank_value", "height", scaled(LAYOUT.employeeText.height, employee_scale))
    set_px("result_employee_rank_value", "font-size", scaled(LAYOUT.employeeText.fontSize, employee_scale))
    set_px("result_employee_rank_value", "line-height", scaled(LAYOUT.employeeText.lineHeight, employee_scale))

    set_px("result_metric_count_value", "left", LAYOUT.metricText.left)
    set_px("result_metric_count_value", "top", LAYOUT.metricText.top)
    set_px("result_metric_count_value", "width", scaled(LAYOUT.metricText.width, metric_scale))
    set_px("result_metric_count_value", "height", scaled(LAYOUT.metricText.height, metric_scale))
    set_px("result_metric_count_value", "font-size", scaled(LAYOUT.metricText.fontSize, metric_scale))
    set_px("result_metric_count_value", "line-height", scaled(LAYOUT.metricText.lineHeight, metric_scale))
    set_px("result_metric_base_value", "left", LAYOUT.metricText.left)
    set_px("result_metric_base_value", "top", LAYOUT.metricText.top + scaled(LAYOUT.metricText.lineGap, metric_scale))
    set_px("result_metric_base_value", "width", scaled(LAYOUT.metricText.width, metric_scale))
    set_px("result_metric_base_value", "height", scaled(LAYOUT.metricText.height, metric_scale))
    set_px("result_metric_base_value", "font-size", scaled(LAYOUT.metricText.fontSize, metric_scale))
    set_px("result_metric_base_value", "line-height", scaled(LAYOUT.metricText.lineHeight, metric_scale))
    set_px("result_metric_urgent_value", "left", LAYOUT.metricText.left)
    set_px("result_metric_urgent_value", "top", LAYOUT.metricText.top + scaled(LAYOUT.metricText.lineGap * 2, metric_scale))
    set_px("result_metric_urgent_value", "width", scaled(LAYOUT.metricText.width, metric_scale))
    set_px("result_metric_urgent_value", "height", scaled(LAYOUT.metricText.height, metric_scale))
    set_px("result_metric_urgent_value", "font-size", scaled(LAYOUT.metricText.fontSize, metric_scale))
    set_px("result_metric_urgent_value", "line-height", scaled(LAYOUT.metricText.lineHeight, metric_scale))

    set_px("result_total_value", "left", LAYOUT.totalText.left)
    set_px("result_total_value", "top", LAYOUT.totalText.top)
    set_px("result_total_value", "width", scaled(LAYOUT.totalText.width, total_scale))
    set_px("result_total_value", "height", scaled(LAYOUT.totalText.height, total_scale))
    set_px("result_total_value", "font-size", scaled(LAYOUT.totalText.fontSize, total_scale))
    set_px("result_total_value", "line-height", scaled(LAYOUT.totalText.lineHeight, total_scale))

    set_px("result_grade_letter", "left", LAYOUT.gradeLetter.left)
    set_px("result_grade_letter", "top", LAYOUT.gradeLetter.top)
    set_px("result_grade_letter", "width", scaled(LAYOUT.gradeLetter.width, grade_scale))
    set_px("result_grade_letter", "height", scaled(LAYOUT.gradeLetter.height, grade_scale))
    set_px("result_grade_letter", "font-size", scaled(LAYOUT.gradeLetter.fontSize, grade_scale))
    set_px("result_grade_letter", "line-height", scaled(LAYOUT.gradeLetter.lineHeight, grade_scale))
end

-- 도장 본체와 찍힌 도장의 위치/크기/회전을 적용한다.
local function apply_stamp_layout()
    local stamp_device_height = get_stamp_device_height()
    local grade_stamp_height = get_grade_stamp_height()

    set_px("result_stamp_device", "left", LAYOUT.stampDevice.left)
    set_px("result_stamp_device", "top", LAYOUT.stampDevice.top + state.stampDeviceY)
    set_px("result_stamp_device", "width", LAYOUT.stampDevice.width)
    set_px("result_stamp_device", "height", stamp_device_height)
    set_property(
        "result_stamp_device",
        "transform",
        string.format("rotate(%.1fdeg)", LAYOUT.stampDevice.rotation)
    )
    set_opacity("result_stamp_device", state.stampDeviceOpacity)

    set_px("result_grade_stamp_wrap", "left", LAYOUT.gradeStamp.left)
    set_px("result_grade_stamp_wrap", "top", LAYOUT.gradeStamp.top)
    set_px("result_grade_stamp_wrap", "width", LAYOUT.gradeStamp.width)
    set_px("result_grade_stamp_wrap", "height", grade_stamp_height)
    set_opacity("result_grade_stamp_wrap", state.gradeStampOpacity)

    set_property(
        "result_grade_stamp_wrap",
        "transform",
        string.format("rotate(%.1fdeg)", LAYOUT.gradeStamp.rotation)
    )

    set_px("result_grade_stamp_image", "width", LAYOUT.gradeStamp.width)
    set_px("result_grade_stamp_image", "height", grade_stamp_height)
end

-- 현재 state와 LAYOUT을 바탕으로 모든 시각 상태를 한 번에 반영한다.
local function apply_visual_state()
    if widget == nil then
        return
    end

    apply_clipboard_layout()
    apply_text_layout()
    apply_stamp_layout()
    set_opacity("result_grade_letter", state.gradeLetterOpacity)
    set_opacity("result_input_hint", state.hintOpacity)
end

-- 현재 LAYOUT 값을 디버그 패널 input들에 동기화한다.
local function sync_debug_inputs()
    if widget == nil or not debug_panel_enabled then
        return
    end

    set_input_value("debug_clipboard_scale_input", string.format("%.3f", LAYOUT.clipboard.visualScale))
    set_input_value("debug_clipboard_end_y_input", string.format("%.1f", LAYOUT.clipboard.endY))
    set_input_value("debug_content_x_input", string.format("%.1f", LAYOUT.content.offsetX))
    set_input_value("debug_content_y_input", string.format("%.1f", LAYOUT.content.offsetY))
    set_input_value("debug_stamp_device_x_input", string.format("%.1f", LAYOUT.stampDevice.left))
    set_input_value("debug_stamp_device_y_input", string.format("%.1f", LAYOUT.stampDevice.top))
    set_input_value("debug_stamp_device_rotation_input", string.format("%.1f", LAYOUT.stampDevice.rotation))
    set_input_value("debug_stamp_x_input", string.format("%.1f", LAYOUT.gradeStamp.left))
    set_input_value("debug_stamp_y_input", string.format("%.1f", LAYOUT.gradeStamp.top))
    set_input_value("debug_stamp_width_input", string.format("%.1f", LAYOUT.gradeStamp.width))
    set_input_value("debug_stamp_rotation_input", string.format("%.1f", LAYOUT.gradeStamp.rotation))
    set_input_value("debug_employee_scale_input", string.format("%.3f", LAYOUT.employeeText.scale))
    set_input_value("debug_metric_scale_input", string.format("%.3f", LAYOUT.metricText.scale))
    set_input_value("debug_total_scale_input", string.format("%.3f", LAYOUT.totalText.scale))
    set_input_value("debug_grade_scale_input", string.format("%.3f", LAYOUT.gradeLetter.scale))
end

-- 디버그 패널 표시 상태와 input 값을 갱신한다.
local function apply_debug_panel_state()
    set_display("result_debug_panel", debug_panel_enabled)
    sync_debug_inputs()
end

-- Result 연출을 처음 상태로 되돌린다.
local function reset_sequence_state()
    sequence_finished = false
    current_phase = "printing"
    phase_elapsed = 0.0
    state.clipboardY = LAYOUT.clipboard.startY
    state.clipboardOffsetX = 0.0
    state.clipboardRotation = 0.0
    state.stampDeviceY = LAYOUT.stampDevice.hiddenY
    state.stampDeviceOpacity = 0.0
    state.gradeLetterOpacity = 1.0
    state.gradeStampOpacity = 0.0
    state.hintOpacity = 0.0
end

-- 연출 phase를 변경하고, phase 진입 시 필요한 사운드/상태를 처리한다.
local function enter_phase(phase_name)
    current_phase = phase_name
    phase_elapsed = 0.0

    if phase_name == "sliding" then
        AudioManager.Play(SLIDE_SFX, 0.95)
    elseif phase_name == "stamp_reveal" then
        AudioManager.Play(STAMP_IMPACT_SFX, 1.0)
    elseif phase_name == "done" then
        if current_payload ~= nil then
            AudioManager.Play(current_payload.resultSfx, 1.0)
        end
        sequence_finished = true
    end
end

-- 현재 조정된 주요 LAYOUT 값을 콘솔에 복사하기 좋은 문자열로 만든다.
local function build_layout_dump()
    return table.concat({
        "clipboard = {",
        string.format("    visualScale = %.3f,", LAYOUT.clipboard.visualScale),
        string.format("    endY = %.1f,", LAYOUT.clipboard.endY),
        "},",
        "content = {",
        string.format("    offsetX = %.1f,", LAYOUT.content.offsetX),
        string.format("    offsetY = %.1f,", LAYOUT.content.offsetY),
        "},",
        "employeeText = {",
        string.format("    scale = %.3f,", LAYOUT.employeeText.scale),
        "},",
        "metricText = {",
        string.format("    scale = %.3f,", LAYOUT.metricText.scale),
        "},",
        "totalText = {",
        string.format("    left = %.1f,", LAYOUT.totalText.left),
        string.format("    top = %.1f,", LAYOUT.totalText.top),
        string.format("    scale = %.3f,", LAYOUT.totalText.scale),
        "},",
        "gradeLetter = {",
        string.format("    left = %.1f,", LAYOUT.gradeLetter.left),
        string.format("    top = %.1f,", LAYOUT.gradeLetter.top),
        string.format("    scale = %.3f,", LAYOUT.gradeLetter.scale),
        "},",
        "stampDevice = {",
        string.format("    left = %.1f,", LAYOUT.stampDevice.left),
        string.format("    top = %.1f,", LAYOUT.stampDevice.top),
        string.format("    rotation = %.1f,", LAYOUT.stampDevice.rotation),
        "},",
        "gradeStamp = {",
        string.format("    left = %.1f,", LAYOUT.gradeStamp.left),
        string.format("    top = %.1f,", LAYOUT.gradeStamp.top),
        string.format("    width = %.1f,", LAYOUT.gradeStamp.width),
        string.format("    rotation = %.1f,", LAYOUT.gradeStamp.rotation),
        "},",
    }, "\n")
end

-- 디버그 패널 버튼 클릭 이벤트를 등록한다.
local function bind_debug_actions()
    if widget == nil or bindings_initialized or widget.bind_click == nil then
        return
    end

    widget:bind_click("debug_clipboard_scale_apply", function()
        LAYOUT.clipboard.visualScale = clamp(
            read_number_input("debug_clipboard_scale_input", LAYOUT.clipboard.visualScale),
            0.2,
            4.0
        )
        apply_visual_state()
        sync_debug_inputs()
    end)

    widget:bind_click("debug_clipboard_end_y_apply", function()
        LAYOUT.clipboard.endY = read_number_input("debug_clipboard_end_y_input", LAYOUT.clipboard.endY)
        if current_phase ~= "printing" and current_phase ~= "sliding" then
            state.clipboardY = LAYOUT.clipboard.endY
        end
        apply_visual_state()
        sync_debug_inputs()
    end)

    widget:bind_click("debug_content_x_apply", function()
        LAYOUT.content.offsetX = read_number_input("debug_content_x_input", LAYOUT.content.offsetX)
        apply_visual_state()
        sync_debug_inputs()
    end)

    widget:bind_click("debug_content_y_apply", function()
        LAYOUT.content.offsetY = read_number_input("debug_content_y_input", LAYOUT.content.offsetY)
        apply_visual_state()
        sync_debug_inputs()
    end)

    widget:bind_click("debug_stamp_device_x_apply", function()
        LAYOUT.stampDevice.left = read_number_input("debug_stamp_device_x_input", LAYOUT.stampDevice.left)
        apply_visual_state()
        sync_debug_inputs()
    end)

    widget:bind_click("debug_stamp_device_y_apply", function()
        LAYOUT.stampDevice.top = read_number_input("debug_stamp_device_y_input", LAYOUT.stampDevice.top)
        apply_visual_state()
        sync_debug_inputs()
    end)

    widget:bind_click("debug_stamp_device_rotation_apply", function()
        LAYOUT.stampDevice.rotation = read_number_input(
            "debug_stamp_device_rotation_input",
            LAYOUT.stampDevice.rotation
        )
        apply_visual_state()
        sync_debug_inputs()
    end)

    widget:bind_click("debug_stamp_x_apply", function()
        LAYOUT.gradeStamp.left = read_number_input("debug_stamp_x_input", LAYOUT.gradeStamp.left)
        apply_visual_state()
        sync_debug_inputs()
    end)

    widget:bind_click("debug_stamp_y_apply", function()
        LAYOUT.gradeStamp.top = read_number_input("debug_stamp_y_input", LAYOUT.gradeStamp.top)
        apply_visual_state()
        sync_debug_inputs()
    end)

    widget:bind_click("debug_stamp_width_apply", function()
        LAYOUT.gradeStamp.width = clamp(
            read_number_input("debug_stamp_width_input", LAYOUT.gradeStamp.width),
            20,
            2000
        )
        apply_visual_state()
        sync_debug_inputs()
    end)

    widget:bind_click("debug_stamp_rotation_apply", function()
        LAYOUT.gradeStamp.rotation = read_number_input(
            "debug_stamp_rotation_input",
            LAYOUT.gradeStamp.rotation
        )
        apply_visual_state()
        sync_debug_inputs()
    end)

    widget:bind_click("debug_employee_scale_apply", function()
        LAYOUT.employeeText.scale = clamp(
            read_number_input("debug_employee_scale_input", LAYOUT.employeeText.scale),
            0.2,
            4.0
        )
        apply_visual_state()
        sync_debug_inputs()
    end)

    widget:bind_click("debug_metric_scale_apply", function()
        LAYOUT.metricText.scale = clamp(
            read_number_input("debug_metric_scale_input", LAYOUT.metricText.scale),
            0.2,
            4.0
        )
        apply_visual_state()
        sync_debug_inputs()
    end)

    widget:bind_click("debug_total_scale_apply", function()
        LAYOUT.totalText.scale = clamp(
            read_number_input("debug_total_scale_input", LAYOUT.totalText.scale),
            0.2,
            4.0
        )
        apply_visual_state()
        sync_debug_inputs()
    end)

    widget:bind_click("debug_grade_scale_apply", function()
        LAYOUT.gradeLetter.scale = clamp(
            read_number_input("debug_grade_scale_input", LAYOUT.gradeLetter.scale),
            0.2,
            4.0
        )
        apply_visual_state()
        sync_debug_inputs()
    end)

    widget:bind_click("debug_result_replay", function()
        M.RestartSequence()
    end)

    widget:bind_click("debug_result_reset_layout", function()
        M.ResetLayoutConfig()
    end)

    widget:bind_click("debug_result_dump_layout", function()
        M.DumpLayoutConfig()
    end)

    bindings_initialized = true
end

-- UI 위젯을 생성하고 viewport에 올린다. 이미 있으면 재사용한다.
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
        widget:AddToViewportZ(RESULT_Z_ORDER)
    end

    bind_debug_actions()

    return widget
end

-- Result UI 생성 진입점
function M.Create(options)
    options = options or {}
    debug_panel_enabled = options.showDebugPanel == true
    base_mouse_enabled = options.wantsMouse == true
    mouse_enabled = base_mouse_enabled or debug_panel_enabled

    if ensure_widget() == nil then
        return nil
    end

    current_payload = build_result_payload()
    reset_sequence_state()
    apply_payload()
    apply_visual_state()
    apply_debug_panel_state()
    enter_phase("printing")

    return widget
end

-- 현재 payload/layout/debug 상태를 다시 화면에 반영한다.
function M.Refresh()
    if ensure_widget() == nil then
        return nil
    end

    apply_payload()
    apply_visual_state()
    apply_debug_panel_state()
    return widget
end

-- 결과 연출을 처음부터 다시 재생한다.
function M.RestartSequence()
    current_payload = build_result_payload()
    reset_sequence_state()
    apply_payload()
    apply_visual_state()
    apply_debug_panel_state()
    enter_phase("printing")
end

-- LAYOUT 값을 처음 로드했을 때의 기본값으로 되돌린다.
function M.ResetLayoutConfig()
    for key, value in pairs(DEFAULT_LAYOUT) do
        LAYOUT[key] = deep_copy(value)
    end

    reset_sequence_state()
    apply_visual_state()
    apply_debug_panel_state()
end

-- 현재 주요 LAYOUT 값을 콘솔에 출력한다.
function M.DumpLayoutConfig()
    print("[ResultUI] Current layout values")
    print(build_layout_dump())
end

-- 디버그 패널을 켜거나 끈다.
function M.SetDebugPanelEnabled(enabled)
    debug_panel_enabled = enabled == true
    mouse_enabled = base_mouse_enabled or debug_panel_enabled

    if widget ~= nil then
        widget:SetWantsMouse(mouse_enabled)
    end

    apply_debug_panel_state()
end

-- 매 프레임 호출해서 현재 phase에 맞는 애니메이션을 진행한다.
function M.Update(dt)
    if widget == nil then
        return
    end

    local delta = math.max(0.0, tonumber(dt) or 0.0)
    phase_elapsed = phase_elapsed + delta

    if current_phase == "printing" then
        state.clipboardY = LAYOUT.clipboard.startY
        state.clipboardOffsetX = 0.0
        state.clipboardRotation = 0.0

        if phase_elapsed >= LAYOUT.animation.printDuration then
            enter_phase("sliding")
        end
    elseif current_phase == "sliding" then
        local t = clamp(phase_elapsed / LAYOUT.animation.slideDuration, 0.0, 1.0)

        state.clipboardY = lerp(
            LAYOUT.clipboard.startY,
            LAYOUT.clipboard.endY,
            ease_out_cubic(t)
        )

        state.clipboardOffsetX = 0.0
        state.clipboardRotation = 0.0

        if t >= 1.0 then
            enter_phase("stamp_appear")
        end
    elseif current_phase == "stamp_appear" then
        local t = clamp(phase_elapsed / LAYOUT.animation.stampAppearDuration, 0.0, 1.0)

        state.clipboardY = LAYOUT.clipboard.endY
        state.clipboardOffsetX = 0.0
        state.clipboardRotation = 0.0
        state.stampDeviceOpacity = t
        state.stampDeviceY = lerp(
            LAYOUT.stampDevice.hiddenY,
            LAYOUT.stampDevice.readyY,
            ease_out_back(t)
        )

        if t >= 1.0 then
            enter_phase("stamp_drop")
        end
    elseif current_phase == "stamp_drop" then
        local t = clamp(phase_elapsed / LAYOUT.animation.stampDropDuration, 0.0, 1.0)

        state.clipboardY = LAYOUT.clipboard.endY
        state.clipboardOffsetX = 0.0
        state.clipboardRotation = 0.0
        state.stampDeviceOpacity = 1.0
        state.stampDeviceY = lerp(
            LAYOUT.stampDevice.readyY,
            LAYOUT.stampDevice.impactY,
            ease_in_cubic(t)
        )

        if t >= 1.0 then
            enter_phase("stamp_reveal")
        end
    elseif current_phase == "stamp_reveal" then
        local t = clamp(phase_elapsed / LAYOUT.animation.stampSettleDuration, 0.0, 1.0)
        local shake_t = clamp(phase_elapsed / LAYOUT.animation.shakeDuration, 0.0, 1.0)

        local shake_damp = 1.0 - shake_t
        local shake_wave = math.sin(shake_t * math.pi * 5.0)

        state.clipboardY = LAYOUT.clipboard.endY
        state.clipboardOffsetX = shake_wave * LAYOUT.animation.shakeOffsetX * shake_damp
        state.clipboardRotation = shake_wave * LAYOUT.animation.shakeRotation * shake_damp
        state.stampDeviceOpacity = 1.0 - t
        state.stampDeviceY = lerp(
            LAYOUT.stampDevice.impactY,
            LAYOUT.stampDevice.recoverY,
            ease_out_cubic(t)
        )
        state.gradeLetterOpacity = 1.0
        state.gradeStampOpacity = t

        if t >= 1.0 then
            enter_phase("done")
        end
    elseif current_phase == "done" then
        local t = clamp(phase_elapsed / LAYOUT.animation.hintFadeDuration, 0.0, 1.0)
        local blink = 0.5 + 0.5 * math.sin(
            math.max(0.0, phase_elapsed - LAYOUT.animation.hintFadeDuration) * math.pi * 2.6
        )

        state.clipboardY = LAYOUT.clipboard.endY
        state.clipboardOffsetX = 0.0
        state.clipboardRotation = 0.0
        state.stampDeviceOpacity = 0.0
        state.stampDeviceY = LAYOUT.stampDevice.recoverY
        state.gradeLetterOpacity = 1.0
        state.gradeStampOpacity = 1.0

        if t < 1.0 then
            state.hintOpacity = t
        else
            state.hintOpacity = 0.3 + blink * 0.7
        end
    end

    apply_visual_state()
end

-- Result 연출 완료 여부 반환
function M.IsSequenceFinished()
    return sequence_finished
end

-- Result UI 제거 및 내부 상태 초기화
function M.Destroy()
    if widget ~= nil then
        widget:RemoveFromParent()
    end

    widget = nil
    current_payload = nil
    current_phase = "idle"
    phase_elapsed = 0.0
    sequence_finished = false
    bindings_initialized = false
    debug_panel_enabled = false
    base_mouse_enabled = false
    mouse_enabled = false
end

return M
