-- =============================================================================
-- CutScene - 게임오버 연출 → 플레이어 등록 씬
-- 흐름:
--   [gameover 시퀀스] fade-in → gameover_0(spotlight) → gameover_1~5(falling/falled)
--   → dim overlay → 스토리 모달 3장 → fade-out
--   [player 시퀀스] cutscene_player fade-in → dim overlay → 스토리 모달 3장
--   → 이름 입력 → 출근하기 → fade-out → PlayScene
-- =============================================================================

local Session = require("GameSession")
local UserSettings = require("Data/UserSettings")
local QuestionPopup = require("UI/QuestionPopupUIController")

local BG_DOCUMENT_PATH = "Content/UI/CutScene/cutscene_background.rml"
local BG_Z_ORDER = 10
local MODAL_Z_ORDER = 180
local KEY_ENTER = 0x0D
local DEFAULT_EMPLOYEE_NAME = "김정글"

local IMG_GAMEOVER = {
    [0] = "../../Sprite/cutscene_gameover_0.png",
    [1] = "../../Sprite/cutscene_gameover_1.png",
    [2] = "../../Sprite/cutscene_gameover_2.png",
    [3] = "../../Sprite/cutscene_gameover_3.png",
    [4] = "../../Sprite/cutscene_gameover_4.png",
    [5] = "../../Sprite/cutscene_gameover_5.png",
}
local IMG_PLAYER = "../../Sprite/cutscene_player.png"

local background_widget = nil
local pending_scene_name = nil
local modal_confirmed = false
local name_confirmed = false
local input_modal_open = false
local last_input_name = DEFAULT_EMPLOYEE_NAME

-- ─── 유틸 ──────────────────────────────────────────────────────────────────

local function smoothstep01(t)
    local x = math.max(0.0, math.min(1.0, t))
    return x * x * (3.0 - 2.0 * x)
end

local function request_scene_load(scene_name)
    if pending_scene_name ~= nil then return end
    pending_scene_name = scene_name
end

local function set_element_opacity(element_id, alpha)
    if background_widget == nil then return end
    local v = math.max(0.0, math.min(1.0, alpha or 0.0))
    background_widget:SetProperty(element_id, "opacity", string.format("%.3f", v))
end

local function set_fade_overlay_opacity(alpha)
    set_element_opacity("cutscene_fade_overlay", alpha)
end

local function set_dim_overlay_opacity(alpha)
    set_element_opacity("cutscene_dim_overlay", alpha)
end

local function set_bg_image(src)
    if background_widget == nil then return end
    background_widget:SetAttribute("cutscene_player_background", "src", src)
end

-- ─── 코루틴 안에서만 호출하는 애니메이션 헬퍼 ──────────────────────────────

local function animate_fade_in(duration)
    -- 검은 화면(overlay=1) → 투명(overlay=0)
    local elapsed = 0
    while elapsed < duration do
        local dt = WaitFrame()
        elapsed = elapsed + dt
        set_fade_overlay_opacity(smoothstep01(1.0 - math.min(elapsed / duration, 1.0)))
    end
    set_fade_overlay_opacity(0.0)
end

local function animate_fade_out(duration)
    -- 투명(overlay=0) → 검은 화면(overlay=1)
    local elapsed = 0
    while elapsed < duration do
        local dt = WaitFrame()
        elapsed = elapsed + dt
        set_fade_overlay_opacity(smoothstep01(math.min(elapsed / duration, 1.0)))
    end
    set_fade_overlay_opacity(1.0)
end

local function animate_dim_in(duration)
    -- dim overlay 0 → 0.3 (30% 반투명 검정)
    local elapsed = 0
    while elapsed < duration do
        local dt = WaitFrame()
        elapsed = elapsed + dt
        set_dim_overlay_opacity(smoothstep01(math.min(elapsed / duration, 1.0)) * 0.3)
    end
    set_dim_overlay_opacity(0.3)
end

local function set_element_transform(element_id, value)
    if background_widget == nil then return end
    background_widget:SetProperty(element_id, "transform", value)
end

local function animate_shake(element_id, duration, magnitude)
    -- 착지 임팩트용 화면 흔들림. 살짝 확대(scale)해 가장자리 검은 여백을 가리고,
    -- 진폭은 점점 약하게(decay) 줄이며 끝나면 transform을 none으로 복귀시킨다.
    local elapsed = 0
    while elapsed < duration do
        local dt = WaitFrame()
        elapsed = elapsed + dt
        local decay = 1.0 - math.min(elapsed / duration, 1.0)
        local amp = magnitude * decay
        local ox = math.sin(elapsed * 90.0) * amp
        local oy = math.cos(elapsed * 70.0) * amp
        local scale = 1.0 + 0.05 * decay
        set_element_transform(element_id, string.format("scale(%.3f) translate(%.1fpx, %.1fpx)", scale, ox, oy))
    end
    set_element_transform(element_id, "none")
end

-- ─── 모달 헬퍼 ─────────────────────────────────────────────────────────────

local function show_story_modal(text, btn_text)
    modal_confirmed = false
    QuestionPopup.ShowNotice({
        zOrder = MODAL_Z_ORDER,
        title = "",
        message = text,
        buttonText = btn_text or "다음으로",
        showCursor = true,
        onConfirm = function()
            modal_confirmed = true
        end,
    })
end

-- ─── 이름 입력 (검증 포함) ─────────────────────────────────────────────────

local function trim(value)
    value = tostring(value or "")
    value = value:gsub("^%s+", "")
    value = value:gsub("%s+$", "")
    return value
end

local function next_codepoint(text, index)
    local b1 = string.byte(text, index)
    if b1 == nil then return nil, index end
    if b1 < 0x80 then return b1, index + 1 end
    local b2 = string.byte(text, index + 1) or 0
    if b1 >= 0xC0 and b1 < 0xE0 then
        return (b1 - 0xC0) * 0x40 + (b2 - 0x80), index + 2
    end
    local b3 = string.byte(text, index + 2) or 0
    if b1 >= 0xE0 and b1 < 0xF0 then
        return (b1 - 0xE0) * 0x1000 + (b2 - 0x80) * 0x40 + (b3 - 0x80), index + 3
    end
    local b4 = string.byte(text, index + 3) or 0
    return (b1 - 0xF0) * 0x40000 + (b2 - 0x80) * 0x1000 + (b3 - 0x80) * 0x40 + (b4 - 0x80), index + 4
end

local function is_allowed_name_codepoint(cp)
    local is_alpha = (cp >= 0x41 and cp <= 0x5A) or (cp >= 0x61 and cp <= 0x7A)
    local is_hangul = cp >= 0xAC00 and cp <= 0xD7A3
    return is_alpha or is_hangul
end

local function validate_name(name)
    name = trim(name)
    if name == "" then return false end
    local count = 0
    local i = 1
    while i <= #name do
        local cp
        cp, i = next_codepoint(name, i)
        if cp == nil or not is_allowed_name_codepoint(cp) then return false end
        count = count + 1
        if count > 6 then return false end
    end
    return true
end

local function save_player_name(name)
    Session.playerName = name
    Session.employee = Session.employee or {}
    Session.employee.name = name
    Session.employee.number = Session.employee.number or "GO-2417"
    Session.employee.department = Session.employee.department or "Operations"
    Session.employee.rank = Session.employee.rank or "Contract"
    _G.PlayerName = name
end

local show_name_input  -- 전방 선언

local function show_invalid_name_notice(name)
    input_modal_open = false
    last_input_name = trim(name)
    if last_input_name == "" then last_input_name = DEFAULT_EMPLOYEE_NAME end
    QuestionPopup.ShowNotice({
        zOrder = MODAL_Z_ORDER,
        title = "입력 오류",
        message = "한글 / Alphabet 6글자 이내로 입력해주세요.",
        buttonText = "확인",
        showCursor = true,
        onConfirm = function()
            show_name_input(last_input_name)
        end,
    })
end

local function confirm_name(name)
    name = trim(name)
    last_input_name = name
    if not validate_name(name) then
        show_invalid_name_notice(name)
        return
    end
    save_player_name(name)
    name_confirmed = true
    input_modal_open = false
    QuestionPopup.Destroy()
end

show_name_input = function(default_name)
    input_modal_open = true
    name_confirmed = false
    QuestionPopup.ShowInput({
        zOrder = MODAL_Z_ORDER,
        title = "",
        message = "나의 이름은...",
        ruleText = "",
        defaultValue = default_name or DEFAULT_EMPLOYEE_NAME,
        confirmText = "결정",
        showCursor = true,
        onConfirm = confirm_name,
    })
end

-- ─── 위젯 ──────────────────────────────────────────────────────────────────

local function ensure_background_widget()
    if UI == nil or UI.CreateWidget == nil then return nil end
    if background_widget == nil then
        background_widget = UI.CreateWidget(BG_DOCUMENT_PATH)
    end
    if background_widget == nil then return nil end
    if background_widget.IsInViewport == nil or not background_widget:IsInViewport() then
        background_widget:AddToViewportZ(BG_Z_ORDER)
    end
    background_widget:SetWantsMouse(false)
    return background_widget
end

-- ─── 메인 컷씬 코루틴 ──────────────────────────────────────────────────────

local function run_cutscene()
    local sfx_vol = UserSettings.GetSfxVolumeScalar()

    -- 초기 상태: gameover_0 이미지, 검은 화면
    set_bg_image(IMG_GAMEOVER[0])
    set_dim_overlay_opacity(0.0)
    set_fade_overlay_opacity(1.0)

    -- 1. 1초 fade-in (검은 화면 → gameover_0 노출)
    animate_fade_in(1.0)

    -- 2. 어두운 무대(gameover_0)를 잠시 유지하며 긴장 빌드업
    Wait(2.3)

    -- 3. 스포트라이트(불 켜지는 소리)와 동시에 gameover_1 렌더 + 낙하 시작
    --    낙하 구간이 길어진 만큼 falling 사운드도 pitch를 낮춰 느리게 재생한다.
    --    Play()엔 pitch 인자가 없어 PlayLoop(강제 루프)로 재생하고 착지 시 StopLoop로 끊는다.
    AudioManager.Play("sfx_spotlight", sfx_vol)
    set_bg_image(IMG_GAMEOVER[1])
    Wait(0.4)  -- 떨어지는 소리를 스포트라이트보다 조금 늦게
    AudioManager.PlayLoop("sfx_falling", "cutscene_falling", sfx_vol, 0.65)
    Wait(0.8)  -- 1→2 총 유지 1.2초 (0.4 + 0.8)
    for i = 2, 3 do
        set_bg_image(IMG_GAMEOVER[i])
        Wait(0.8)  -- 2→3, 3→4 낙하 속도
    end
    -- 4. gameover_4 렌더(착지) 시 falling 정지 + SfxFalled 재생 + 화면 흔들림
    set_bg_image(IMG_GAMEOVER[4])
    AudioManager.StopLoop("cutscene_falling")
    AudioManager.Play("sfx_falled", sfx_vol)
    animate_shake("cutscene_player_background", 0.35, 12)  -- 착지 임팩트
    Wait(1.5)  -- 4→5 총 유지 1.5초 (흔들림 0.35 + 1.15), 5 렌더 타이밍

    -- 5. gameover_5 렌더 시 SfxBbbing 재생, 2.0초 유지 (모달 등장을 더 늦춤)
    set_bg_image(IMG_GAMEOVER[5])
    AudioManager.Play("sfx_bbing", sfx_vol)
    Wait(2.0)

    -- 5. dim overlay 0 → 30% fade-in
    animate_dim_in(0.4)

    -- 스토리 모달 1: 세계관 소개
    for _, text in ipairs({
        "캐릭터들은 게임에서 쓰러지면 어디로 갈까?",
        "천국? 지옥? 세이브 포인트?",
        "아니다. 대부분은 그냥… 처리 대기 상태가 된다.",
        "사망, 버그, 튕김, 방치로 발생한 래그돌들.",
        "그걸 처리하는 회사가 바로, 게임오버 주식회사다.",
    }) do
        show_story_modal(text, "다음으로")
        WaitUntil(function() return modal_confirmed end)
    end
    QuestionPopup.Destroy()

    -- 6. fade-out to black
    animate_fade_out(0.5)

    -- 7. cutscene_player 이미지로 교체, dim 초기화
    set_bg_image(IMG_PLAYER)
    set_dim_overlay_opacity(0.0)

    -- 8. fade-in
    animate_fade_in(1.0)

    -- 플레이어 이미지를 잠시 보여준 뒤 모달 (텀을 늘림)
    Wait(1.5)

    -- dim overlay 다시 적용
    animate_dim_in(0.4)

    -- 스토리 모달 2: 주인공 소개 — 첫 대사("내가 처음 출근") 직후 자기소개로 이름을 입력받고,
    -- 이어서 나머지 대사. 마지막 "첫날부터 큰일이야" 대사는 출근 버튼 모달로 분리.
    show_story_modal("그리고 오늘, 내가 처음 출근하게 된 회사가 여기다.", "다음으로")
    WaitUntil(function() return modal_confirmed end)
    QuestionPopup.Destroy()

    -- 9. 이름 입력 (자기소개)
    show_name_input(DEFAULT_EMPLOYEE_NAME)
    WaitUntil(function() return name_confirmed end)

    for _, text in ipairs({
        "부서는 래그돌 회수 센터.",
        "힘들다는 소문은 좀 들었다.",
        "야근이 많고, 서버가 자주 터지고, 가끔 직원도 튕긴다던데…",
    }) do
        show_story_modal(text, "다음으로")
        WaitUntil(function() return modal_confirmed end)
    end
    QuestionPopup.Destroy()

    -- 10. "뭐, 첫날부터 큰일이야 있겠어?" + "첫 출근 업무 개시" 버튼 (주인공 소개 마지막 대사)
    modal_confirmed = false
    QuestionPopup.ShowNotice({
        zOrder = MODAL_Z_ORDER,
        title = "",
        message = "뭐, 첫날부터 큰일이야 있겠어?",
        buttonText = "첫 업무 개시",
        showCursor = true,
        onConfirm = function()
            modal_confirmed = true
        end,
    })
    WaitUntil(function() return modal_confirmed end)
    QuestionPopup.Destroy()

    -- 11. fade-out to black → Play 씬으로
    animate_fade_out(0.5)
    request_scene_load("Play")
end

-- ─── 씬 라이프사이클 ────────────────────────────────────────────────────────

function BeginPlay()
    StopAllCoroutines()
    AudioManager.StopAllLoops()
    pending_scene_name = nil
    modal_confirmed = false
    name_confirmed = false
    input_modal_open = false
    last_input_name = DEFAULT_EMPLOYEE_NAME

    for key, path in pairs(require("Data/AudioData")) do
        AudioManager.Load(key, path, key:find("^bgm_") ~= nil)
    end
    AudioManager.PlayBGM("bgm_cutscene", UserSettings.GetBgmVolumeScalar())

    Engine.SetCursorVisible(false)

    if ensure_background_widget() ~= nil then
        StartCoroutine(run_cutscene)
    end

    Engine.SetOnEscape(function() end)
end

function Tick(dt)
    UpdateCoroutines(dt)

    if pending_scene_name ~= nil then
        local scene_name = pending_scene_name
        pending_scene_name = nil
        Engine.LoadScene(scene_name)
        return
    end

    if input_modal_open and Input.GetKeyDown(KEY_ENTER) then
        confirm_name(QuestionPopup.GetInputText())
    end
end

function EndPlay()
    StopAllCoroutines()
    AudioManager.StopAllLoops()
    QuestionPopup.Destroy()

    if background_widget ~= nil then
        background_widget:RemoveFromParent()
    end

    Engine.SetCursorVisible(true)
    background_widget = nil
    pending_scene_name = nil
    modal_confirmed = false
    name_confirmed = false
    input_modal_open = false
    last_input_name = DEFAULT_EMPLOYEE_NAME
end
