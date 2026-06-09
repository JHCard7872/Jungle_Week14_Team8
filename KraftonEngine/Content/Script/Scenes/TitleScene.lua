local Session = require("GameSession")
local UserSettings = require("Data/UserSettings")

local TITLE_UI_PATH = "Content/UI/TitleScreen/title_screen.rml"
local TITLE_UI_Z_ORDER = 100
local PRESS_BLINK_SPEED_IDLE = 3.2
local PRESS_BLINK_SPEED_FAST = 12.0
local START_SFX_KEY = "sfx_game_start"
local START_SFX_DURATION = 2.0
local TITLE_FADE_DURATION = 1.0
local MAIN_MENU_FADE_IN_DURATION = 0.5
local SFX_SCARY_KEY = "sfx_scary"
local SFX_LOGO_IMPACT_KEY = "sfx_logo_impact"
local TITLE_BGM_KEY = "bgm_title_0"
local BGM_START_DELAY = 1.0          -- seconds after the logo lands before the BGM starts
local PRESS_REVEAL_AFTER_BGM = 1.55   -- seconds after the BGM starts before the prompt shows

-- Cinematic settings
local LETTERBOX_RATIO       = 0.12   -- bar height as fraction of viewport height
local CINEMATIC_ZOOM_DUR    = 3.0    -- zoom+pan duration (seconds)
local LETTERBOX_FADEOUT_DUR = 0.8    -- letterbox bars fade out duration
local WAIT_LOGO_DUR         = 0.4    -- pause before logo appears
local LOGO_IMPACT_DELAY     = 0.2    -- play the impact SFX this long after the logo lands
local SHAKE_DURATION        = 0.55   -- screen shake duration on logo impact
local SHAKE_INTENSITY       = 14.0   -- shake amplitude in pixels
local SHAKE_FREQUENCY       = 12.0   -- shake oscillation frequency in Hz

-- Logo particles (fluorescent-red sparkles that erupt + drift around the logo)
local PARTICLE_COUNT        = 40
local PARTICLE_SPREAD_X     = 260.0  -- horizontal spawn spread around logo center (± px)
local PARTICLE_SPREAD_Y     = 70.0   -- vertical spawn spread (± px)
local PARTICLE_RISE_MIN     = 14.0   -- upward drift speed (px/s)
local PARTICLE_RISE_MAX     = 46.0
local PARTICLE_DRIFT_X      = 22.0   -- horizontal drift speed (± px/s)
local PARTICLE_LIFE_MIN     = 1.6    -- lifetime before respawn (s)
local PARTICLE_LIFE_MAX     = 3.2
local PARTICLE_SCALE_MIN    = 0.5    -- size multiplier (base glow is 36px)
local PARTICLE_SCALE_MAX    = 1.5
local PARTICLE_WOBBLE_AMP   = 10.0   -- horizontal sine wobble amplitude (px)
local PARTICLE_WOBBLE_FREQ  = 1.8    -- wobble frequency (Hz)
local PARTICLE_MAX_ALPHA    = 0.9    -- peak opacity
-- Impact burst: first generation erupts radially from the logo, then damps into
-- the ambient float. Respawned particles use the ambient params above.
local PARTICLE_BURST_SPEED_MIN = 320.0  -- initial radial speed (px/s)
local PARTICLE_BURST_SPEED_MAX = 620.0
local PARTICLE_BURST_DAMPING   = 2.6    -- velocity decay rate (per second)
local PARTICLE_BURST_SPREAD    = 40.0   -- tight initial spread at logo center (± px)

-- State
local title_widget = nil
local press_blink_elapsed = 0.0
local waiting_for_input = false
local pending_scene_name = nil
local transition_phase = "idle"
local transition_elapsed = 0.0
local transition_duration = 0.0

local cinematic_vw = 0
local cinematic_vh = 0
local shake_elapsed = 0.0  -- counts up; active when < SHAKE_DURATION
local shake_osc_time = 0.0 -- separate timer for oscillation phase
local impact_sfx_pending = false  -- 쿵! plays a beat after the logo lands
local impact_sfx_elapsed = 0.0

local particles_active = false
local particles = {}       -- pool of {ox, oy, vx, vy, life, maxlife, scale, wobble}

local bgm_pending = false      -- true after logo lands, until the delayed BGM starts
local bgm_delay_elapsed = 0.0
local press_pending = false    -- true after the BGM starts, until the prompt is revealed
local press_delay_elapsed = 0.0
local press_visible = false    -- "PRESS ANY BUTTON" shown a beat after the BGM

-- ─── Helpers ──────────────────────────────────────────────────────────────────

local function smoothstep01(t)
    local x = math.max(0.0, math.min(1.0, t))
    return x * x * (3.0 - 2.0 * x)
end

local function request_scene_load(scene_name)
    if pending_scene_name ~= nil then return end
    pending_scene_name = scene_name
end

local function is_any_button_pressed()
    for vk = 1, 255 do
        if Input.GetKeyDown(vk) then return true end
    end
    return false
end

local function set_element_opacity(element_id, alpha)
    if title_widget == nil then return end
    local clamped = math.max(0.0, math.min(1.0, alpha))
    title_widget:SetProperty(element_id, "opacity", string.format("%.3f", clamped))
end

local function set_fade_overlay_opacity(alpha)
    set_element_opacity("title_fade_overlay", alpha)
end

local function stop_title_bgm()
    if AudioManager == nil then return end
    if AudioManager.StopBGM ~= nil then
        AudioManager.StopBGM()
        return
    end
    if AudioManager.Stop ~= nil then AudioManager.Stop("bgm_title_0") end
    if AudioManager.StopManaged ~= nil then AudioManager.StopManaged("bgm_title_0") end
end

local function ensure_title_widget()
    if UI == nil or UI.CreateWidget == nil then return nil end
    if title_widget == nil then
        title_widget = UI.CreateWidget(TITLE_UI_PATH)
    end
    if title_widget == nil then return nil end
    if title_widget.IsInViewport == nil or not title_widget:IsInViewport() then
        title_widget:AddToViewportZ(TITLE_UI_Z_ORDER)
    end
    title_widget:SetWantsMouse(true)
    return title_widget
end

local function consume_title_transition_fade_in_duration()
    local scene_transition = Session.sceneTransition
    if scene_transition == nil then return 0.0 end
    local duration = tonumber(scene_transition.titleFadeInDuration) or 0.0
    scene_transition.titleFadeInDuration = 0.0
    return math.max(0.0, duration)
end

local function update_press_prompt(dt, blink_speed)
    press_blink_elapsed = press_blink_elapsed + dt
    local blink = 0.5 + 0.5 * math.sin(press_blink_elapsed * math.pi * blink_speed)
    set_element_opacity("press_any_button", 0.25 + blink * 0.75)
end

-- ─── Cinematic ────────────────────────────────────────────────────────────────

-- Refreshes cached viewport size. Engine.GetViewportSize() returns 0×0 during
-- BeginPlay before the viewport is ready, so the cinematic self-heals on Tick.
local function ensure_viewport_size()
    if cinematic_vw > 0 and cinematic_vh > 0 then return end
    local vp = Engine.GetViewportSize()
    cinematic_vw = math.max(cinematic_vw, (vp and tonumber(vp.Width))  or 0)
    cinematic_vh = math.max(cinematic_vh, (vp and tonumber(vp.Height)) or 0)
end

-- Animates title_background: zoom 3x→1x + pan top-center → bottom-center
local function set_bg_zoom_pan(t_linear)
    if title_widget == nil then return end
    ensure_viewport_size()
    if cinematic_vw <= 0 or cinematic_vh <= 0 then return end
    local t = smoothstep01(t_linear)
    local z = 3.0 - 2.0 * t               -- scale factor: 3 → 1
    local img_w = cinematic_vw * z
    local img_h = cinematic_vh * z
    local img_left = (cinematic_vw - img_w) / 2  -- keep horizontally centered
    local img_top = t * (cinematic_vh - img_h)    -- pan from top (0) to bottom
    title_widget:SetProperty("title_background", "width",  string.format("%.0fpx", img_w))
    title_widget:SetProperty("title_background", "height", string.format("%.0fpx", img_h))
    title_widget:SetProperty("title_background", "left",   string.format("%.0fpx", img_left))
    title_widget:SetProperty("title_background", "top",    string.format("%.0fpx", img_top))
end

-- Sets letterbox bar heights (amount: 0=hidden, 1=full).
-- Uses % of #title_root (which is 100% of the viewport) instead of computed
-- pixels, so the bars show even before the viewport size is known at BeginPlay.
local function set_letterbox_height(amount)
    if title_widget == nil then return end
    local pct = LETTERBOX_RATIO * math.max(0, math.min(1, amount)) * 100.0
    title_widget:SetProperty("letterbox_top",    "height", string.format("%.3f%%", pct))
    title_widget:SetProperty("letterbox_bottom", "height", string.format("%.3f%%", pct))
end

-- Applies shake transform to the entire UI root
local function update_shake(dt)
    if title_widget == nil then return end
    if shake_elapsed >= SHAKE_DURATION then return end
    shake_elapsed = shake_elapsed + dt
    shake_osc_time = shake_osc_time + dt
    if shake_elapsed >= SHAKE_DURATION then
        title_widget:SetProperty("title_root", "transform", "translateX(0px) translateY(0px)")
        return
    end
    local decay = 1.0 - (shake_elapsed / SHAKE_DURATION)
    local freq_rad = SHAKE_FREQUENCY * 2.0 * math.pi
    local ox = SHAKE_INTENSITY * decay * math.sin(shake_osc_time * freq_rad)
    local oy = SHAKE_INTENSITY * decay * math.sin(shake_osc_time * freq_rad + 1.5)
    title_widget:SetProperty("title_root", "transform",
        string.format("translateX(%.1fpx) translateY(%.1fpx)", ox, oy))
end

-- ─── Logo particles ─────────────────────────────────────────────────────────

local function rand_range(a, b)
    return a + (b - a) * math.random()
end

-- (Re)initializes one particle. is_burst=true: erupt radially from the logo
-- center (used for the first generation on logo impact). false: ambient float.
local function spawn_particle(p, is_burst)
    p.burst = is_burst == true
    p.maxlife = rand_range(PARTICLE_LIFE_MIN, PARTICLE_LIFE_MAX)
    p.life = p.maxlife
    p.scale = rand_range(PARTICLE_SCALE_MIN, PARTICLE_SCALE_MAX)
    p.wobble = rand_range(0.0, 2.0 * math.pi)
    if p.burst then
        p.ox = rand_range(-PARTICLE_BURST_SPREAD, PARTICLE_BURST_SPREAD)
        p.oy = rand_range(-PARTICLE_BURST_SPREAD, PARTICLE_BURST_SPREAD)
        local angle = rand_range(0.0, 2.0 * math.pi)
        local speed = rand_range(PARTICLE_BURST_SPEED_MIN, PARTICLE_BURST_SPEED_MAX)
        p.vx = math.cos(angle) * speed
        p.vy = math.sin(angle) * speed
        p.fadein = 0.06   -- pop in quickly with the impact
    else
        p.ox = rand_range(-PARTICLE_SPREAD_X, PARTICLE_SPREAD_X)
        p.oy = rand_range(-PARTICLE_SPREAD_Y, PARTICLE_SPREAD_Y)
        p.vx = rand_range(-PARTICLE_DRIFT_X, PARTICLE_DRIFT_X)
        p.vy = -rand_range(PARTICLE_RISE_MIN, PARTICLE_RISE_MAX)  -- negative = upward
        p.fadein = 0.25
    end
end

local function init_logo_particles()
    if title_widget == nil then return end
    for i = 1, PARTICLE_COUNT do
        local p = particles[i] or {}
        spawn_particle(p, true)  -- first generation = impact burst (launch together)
        particles[i] = p
    end
    particles_active = true
end

local function clear_logo_particles()
    particles_active = false
    if title_widget == nil then return end
    for i = 1, PARTICLE_COUNT do
        title_widget:SetProperty("logo_particle_" .. i, "opacity", "0.000")
    end
end

local function update_logo_particles(dt)
    if not particles_active or title_widget == nil then return end
    for i = 1, PARTICLE_COUNT do
        local p = particles[i]
        if p ~= nil then
            p.life = p.life - dt
            if p.life <= 0.0 then spawn_particle(p, false) end  -- recycle as ambient float
            if p.burst then
                -- decay the radial launch velocity, then ease into a gentle rise
                local damp = math.max(0.0, 1.0 - PARTICLE_BURST_DAMPING * dt)
                p.vx = p.vx * damp
                p.vy = p.vy * damp - PARTICLE_RISE_MIN * dt
            end
            p.ox = p.ox + p.vx * dt
            p.oy = p.oy + p.vy * dt
            p.wobble = p.wobble + dt * (PARTICLE_WOBBLE_FREQ * 2.0 * math.pi)

            -- opacity envelope: fade in over p.fadein, fade out over last 45%
            local age = 1.0 - (p.life / p.maxlife)
            local fadein = p.fadein or 0.25
            local alpha
            if age < fadein then
                alpha = age / fadein
            elseif age > 0.55 then
                alpha = (1.0 - age) / 0.45
            else
                alpha = 1.0
            end
            alpha = math.max(0.0, math.min(1.0, alpha)) * PARTICLE_MAX_ALPHA

            local wob = math.sin(p.wobble) * PARTICLE_WOBBLE_AMP
            local id = "logo_particle_" .. i
            title_widget:SetProperty(id, "transform",
                string.format("translateX(%.1fpx) translateY(%.1fpx) scale(%.2f)",
                    p.ox + wob, p.oy, p.scale))
            title_widget:SetProperty(id, "opacity", string.format("%.3f", alpha))
        end
    end
end

local function begin_title_cinematic()
    local vp = Engine.GetViewportSize()
    cinematic_vw = (vp and vp.Width)  or 0
    cinematic_vh = (vp and vp.Height) or 0

    set_fade_overlay_opacity(0.0)
    set_element_opacity("press_any_button", 0.0)
    set_element_opacity("title_logo_container", 0.0)

    set_letterbox_height(1.0)       -- letterbox bars fully open
    set_bg_zoom_pan(0.0)            -- background at 3x zoom, top-center

    shake_elapsed = SHAKE_DURATION  -- no shake yet
    shake_osc_time = 0.0

    AudioManager.Play(SFX_SCARY_KEY, UserSettings.GetSfxVolumeScalar())

    waiting_for_input = false
    press_blink_elapsed = 0.0
    transition_phase = "cinematic_zoom"
    transition_elapsed = 0.0
    transition_duration = CINEMATIC_ZOOM_DUR
end

-- ─── Scene transitions ────────────────────────────────────────────────────────

local function begin_main_menu_transition()
    if pending_scene_name ~= nil or transition_phase ~= "idle" then return end
    waiting_for_input = false
    bgm_pending = false   -- cancel the pending BGM/prompt timers if the player skips ahead
    press_pending = false
    impact_sfx_pending = false
    Session.sceneTransition = Session.sceneTransition or {}
    Session.sceneTransition.mainMenuFadeInDuration = MAIN_MENU_FADE_IN_DURATION
    stop_title_bgm()
    request_scene_load("MainMenu")
    transition_phase = "start_sfx"
    transition_elapsed = 0.0
    transition_duration = START_SFX_DURATION
    AudioManager.Play(START_SFX_KEY, UserSettings.GetSfxVolumeScalar())
end

local function complete_scene_load()
    if pending_scene_name == nil then return end
    local scene_name = pending_scene_name
    pending_scene_name = nil
    Engine.LoadScene(scene_name)
end

local function update_transition(dt)
    if transition_phase == "idle" then return false end

    transition_elapsed = math.min(transition_elapsed + dt, transition_duration)
    local t = transition_duration <= 0.0 and 1.0 or (transition_elapsed / transition_duration)

    -- ── Cinematic phases ────────────────────────────────────────────────────

    if transition_phase == "cinematic_zoom" then
        set_bg_zoom_pan(t)
        if t >= 1.0 then
            -- Restore background to fill viewport exactly (z=1)
            if cinematic_vw > 0 then
                title_widget:SetProperty("title_background", "width",  cinematic_vw .. "px")
                title_widget:SetProperty("title_background", "height", cinematic_vh .. "px")
                title_widget:SetProperty("title_background", "left",   "0px")
                title_widget:SetProperty("title_background", "top",    "0px")
            end
            transition_phase = "letterbox_fade_out"
            transition_elapsed = 0.0
            transition_duration = LETTERBOX_FADEOUT_DUR
        end
        return true
    end

    if transition_phase == "letterbox_fade_out" then
        set_letterbox_height(1.0 - t)
        if t >= 1.0 then
            set_letterbox_height(0.0)
            transition_phase = "wait_logo"
            transition_elapsed = 0.0
            transition_duration = WAIT_LOGO_DUR
        end
        return true
    end

    if transition_phase == "wait_logo" then
        if t >= 1.0 then
            -- Logo appears; the 쿵! is delayed a touch (fired in Tick)
            set_element_opacity("title_logo_container", 1.0)
            -- keep the prompt hidden until a beat after the BGM (revealed in Tick)
            set_element_opacity("press_any_button", 0.0)
            press_visible = false
            press_pending = false
            press_delay_elapsed = 0.0
            impact_sfx_pending = true
            impact_sfx_elapsed = 0.0
            shake_elapsed = 0.0
            shake_osc_time = 0.0
            CameraManager.StartWaveShake(0.8)
            init_logo_particles()
            bgm_pending = true        -- start BGM a beat later (handled in Tick)
            bgm_delay_elapsed = 0.0
            press_blink_elapsed = 0.0
            waiting_for_input = true
            transition_phase = "idle"
            transition_elapsed = 0.0
            transition_duration = 0.0
        end
        return true
    end

    -- ── Menu transition phases ───────────────────────────────────────────────

    if transition_phase == "start_sfx" then
        update_press_prompt(dt, PRESS_BLINK_SPEED_FAST)
        set_fade_overlay_opacity(0.0)
        if t >= 1.0 then
            transition_phase = "fade_out"
            transition_elapsed = 0.0
            transition_duration = TITLE_FADE_DURATION
        end
        return true
    end

    if transition_phase == "fade_out" then
        set_element_opacity("press_any_button", 1.0)
        set_fade_overlay_opacity(t)
        if t >= 1.0 then
            complete_scene_load()
        end
        return true
    end

    return false
end

-- ─── Scene lifecycle ──────────────────────────────────────────────────────────

function BeginPlay()
    StopAllCoroutines()
    AudioManager.StopAllLoops()
    pending_scene_name = nil
    waiting_for_input = false
    press_blink_elapsed = 0.0
    transition_phase = "idle"
    transition_elapsed = 0.0
    transition_duration = 0.0
    cinematic_vw = 0
    cinematic_vh = 0
    shake_elapsed = SHAKE_DURATION
    shake_osc_time = 0.0
    particles_active = false
    particles = {}
    bgm_pending = false
    bgm_delay_elapsed = 0.0
    press_pending = false
    press_delay_elapsed = 0.0
    press_visible = false
    impact_sfx_pending = false
    impact_sfx_elapsed = 0.0
    if math.randomseed ~= nil then math.randomseed(20260609) end

    for key, path in pairs(require("Data/AudioData")) do
        AudioManager.Load(key, path, key:find("^bgm_") ~= nil)
    end
    -- BGM is deferred until shortly after the logo lands (see Tick); the cinematic
    -- opens on SfxScary alone.

    Engine.SetCursorVisible(false)
    local widget = ensure_title_widget()
    if widget ~= nil then
        consume_title_transition_fade_in_duration()  -- discard startup fade; replaced by cinematic
        begin_title_cinematic()
    end

    -- ESC 비활성화: Play의 Pause 외에는 ESC 무반응(우발 종료/전환 방지). 종료는 MainMenu 버튼으로만.
    Engine.SetOnEscape(function() end)
end

function Tick(dt)
    if title_widget == nil then return end

    update_shake(dt)
    update_logo_particles(dt)

    if update_transition(dt) then return end

    -- Fire the 쿵! a beat after the logo lands.
    if impact_sfx_pending then
        impact_sfx_elapsed = impact_sfx_elapsed + dt
        if impact_sfx_elapsed >= LOGO_IMPACT_DELAY then
            impact_sfx_pending = false
            AudioManager.Play(SFX_LOGO_IMPACT_KEY, UserSettings.GetSfxVolumeScalar())
        end
    end

    -- Start the title BGM a beat after the logo has landed.
    if bgm_pending then
        bgm_delay_elapsed = bgm_delay_elapsed + dt
        if bgm_delay_elapsed >= BGM_START_DELAY then
            bgm_pending = false
            AudioManager.PlayBGM(TITLE_BGM_KEY, UserSettings.GetBgmVolumeScalar())
            press_pending = true        -- prompt is revealed a beat later (below)
            press_delay_elapsed = 0.0
        end
    end

    -- Reveal the prompt a beat after the BGM has started.
    if press_pending then
        press_delay_elapsed = press_delay_elapsed + dt
        if press_delay_elapsed >= PRESS_REVEAL_AFTER_BGM then
            press_pending = false
            press_visible = true
            press_blink_elapsed = 0.0
        end
    end

    if press_visible then
        update_press_prompt(dt, PRESS_BLINK_SPEED_IDLE)
    end

    if waiting_for_input and is_any_button_pressed() then
        begin_main_menu_transition()
    end
end

function EndPlay()
    StopAllCoroutines()
    AudioManager.StopAllLoops()
    clear_logo_particles()
    particles = {}
    if title_widget ~= nil then
        title_widget:RemoveFromParent()
    end
    title_widget = nil
    pending_scene_name = nil
    waiting_for_input = false
    press_blink_elapsed = 0.0
    transition_phase = "idle"
    transition_elapsed = 0.0
    transition_duration = 0.0
    cinematic_vw = 0
    cinematic_vh = 0
    shake_elapsed = SHAKE_DURATION
    shake_osc_time = 0.0
end
