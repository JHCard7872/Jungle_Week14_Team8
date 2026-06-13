-- ==========================================================================
-- PortalTeleport — 포탈 순간이동의 "런타임 코디네이터" (모듈, require 공유)
-- [역할] 여러 포탈 인스턴스가 공유하는 단일 상태:
--        (1) 실제 이동 클로저 — GOIncTestActor(플레이어)가 RegisterTeleport로 등록.
--            플레이어 + 들고 있는 오브젝트를 delta만큼 함께 옮긴다(그랩 상태 접근).
--        (2) 쿨다운 — 도착 직후 짝 포탈 위에서 즉시 되튕기는 것 방지.
--        (3) 이동 연출 FSM — 흰색 점멸 → (완전 흰 순간 이동) → 도착지 fade in.
--            블러 + 색상 비네팅 + 사운드 동반.
-- [호출] PortalBehavior.OnOverlap → Trigger(sourceLoc, destLoc, colorIndex)
--        GOIncTestActor.Tick → Tick(dt)  (플레이어가 매 프레임 구동)
--        GOIncTestActor.BeginPlay → RegisterTeleport(fn)
-- ==========================================================================

local Portal       = require("Data/PortalData")
local UserSettings = require("Data/UserSettings")

local M = {}

local teleport_fn = nil      -- function(delta_vector) — 플레이어/그랩 오브젝트 동반 이동
local cooldown = 0.0         -- 도착 직후 재이동 방지 타이머(초)

-- 연출 FSM
local fx_state = "idle"      -- idle | flash_out | fade_in
local fx_timer = 0.0
local pending_delta = nil    -- 완전 흰색 순간에 적용할 이동 벡터
local pending_color = nil

local function color_rgb(idx)
    return Portal.colors[idx] or { r = 1.0, g = 1.0, b = 1.0 }
end

-- 플레이어 스크립트가 자신의 그랩 상태를 아는 이동 클로저를 등록한다.
function M.RegisterTeleport(fn)
    teleport_fn = fn
end

-- 이동/연출 진행 중이거나 쿨다운 중이면 true — 이때 새 트리거는 무시.
function M.IsBusy()
    return cooldown > 0.0 or fx_state ~= "idle"
end

-- 포탈 트리거가 호출. sourceLoc=내 포탈 위치, destLoc=짝 포탈 위치(둘 다 Vector).
-- 성공 시 true. delta = dest - source 로 플레이어/그랩 오브젝트의 상대 위치를 보존한다.
function M.Trigger(sourceLoc, destLoc, colorIndex)
    if M.IsBusy() then return false end
    if sourceLoc == nil or destLoc == nil then return false end

    local f = Portal.fx
    pending_delta = Vector.new(destLoc.X - sourceLoc.X, destLoc.Y - sourceLoc.Y, destLoc.Z - sourceLoc.Z)
    pending_color = colorIndex

    AudioManager.Play(Portal.sfxMoveKey, UserSettings.GetSfxVolumeScalar())

    -- 블러 + 해당 색 비네팅 시작
    CameraManager.SetBlur(f.blurStrength)
    local c = color_rgb(colorIndex)
    CameraManager.SetVignette(f.vignetteIntensity, f.vignetteRadius, f.vignetteSoftness, c.r, c.g, c.b)

    -- 흰색으로 점멸 — 화면을 흰색으로 페이드 아웃
    CameraManager.FadeOut(f.flashOutDuration, 1.0, 1.0, 1.0)

    fx_state = "flash_out"
    fx_timer = 0.0
    return true
end

function M.Tick(dt)
    if cooldown > 0.0 then
        cooldown = cooldown - dt
        if cooldown < 0.0 then cooldown = 0.0 end
    end

    if fx_state == "idle" then return end

    local f = Portal.fx
    fx_timer = fx_timer + dt

    if fx_state == "flash_out" then
        if fx_timer >= f.flashOutDuration then
            -- 화면이 완전히 흰 순간 — 실제 순간이동 실행(플레이어 + 들고 있는 오브젝트)
            if teleport_fn ~= nil and pending_delta ~= nil then
                teleport_fn(pending_delta)
            end
            -- 도착지에서 서서히 fade in (흰색 → 원래 화면)
            CameraManager.FadeIn(f.fadeInDuration, 1.0, 1.0, 1.0)
            fx_state = "fade_in"
            fx_timer = 0.0
        end

    elseif fx_state == "fade_in" then
        -- fade in 동안 블러/비네팅을 서서히 0으로
        local t = fx_timer / f.fadeInDuration
        if t > 1.0 then t = 1.0 end
        local c = color_rgb(pending_color)
        CameraManager.SetBlur(f.blurStrength * (1.0 - t))
        CameraManager.SetVignette(f.vignetteIntensity * (1.0 - t), f.vignetteRadius, f.vignetteSoftness, c.r, c.g, c.b)

        if fx_timer >= f.fadeInDuration then
            CameraManager.ClearBlur()
            CameraManager.ClearVignette()
            fx_state = "idle"
            fx_timer = 0.0
            pending_delta = nil
            pending_color = nil
            cooldown = f.cooldown
        end
    end
end

return M
