local C = require("Data/GOIncTestActorData") -- 이동/시점/빔/그랩/무기 튜닝 상수. 값 수정은 해당 파일에서

local yaw = 0.0        -- 현재 플레이어 Yaw. Actor Root 회전에 적용
local pitch = 0.0      -- 현재 카메라 Pitch. CameraPivot 회전에 적용
local viewport_center_x = 0.0 -- 조준점 기준으로 쓰는 뷰포트 중앙 X
local viewport_center_y = 0.0 -- 조준점 기준으로 쓰는 뷰포트 중앙 Y
local crosshair_widget = nil
local crosshair_is_hold = nil
local crosshair_screen_x = nil
local crosshair_screen_y = nil
local beam_visible_remaining = 0.0 -- Beam을 계속 보이게 유지할 남은 시간
local last_aim_point = nil         -- 마지막 발사 시 카메라 Raycast로 계산한 조준 지점
local aim_trace_cache = {          -- PostCameraTick 한 프레임 안에서 fire/crosshair가 공유하는 조준 Raycast 결과
    serial = 0,
    resolved_serial = -1,
    max_distance = 0.0,
    hit = nil,
    fallback_end = nil,
    start = nil,
    direction = nil
}

local root_body = nil            -- 바닥 레이/쿼리 기준이 되는 GOIncRoot 캡슐 PrimitiveComponent
local player_velocity = nil      -- PhysX 대신 Lua가 직접 보관하는 GOIncActor 이동 속도
local camera_pivot = nil         -- Pitch 회전을 담당하는 GOIncCameraPivot
local camera = nil               -- 실제 활성 카메라 컴포넌트
local view_weapon_root = nil     -- 카메라 위치/회전에 붙는 1인칭 총 ViewModel 루트
local weapon_visual_pivot = nil  -- 화면 offset과 기본 기울기를 담는 GOIncWeaponVisualPivot
local weapon_pitch_pivot = nil   -- 총의 작은 시각 Pitch 회전 중심인 GOIncWeaponPitchPivot
local gun = nil                  -- 1인칭 총 메시
local muzzle_point = nil         -- Beam 시작점으로 쓰는 총구 위치
local beam_actor = nil
local beam_particle = nil        -- 총구에서 조준점까지 그리는 Beam 파티클
local weapon_components = {}
local weapon_base = {}
local weapon_swap_state = {
    active_index = 1,
    pending_index = 1,
    elapsed = 0.0,
    start_angle = 0.0,
    target_angle = 0.0,
    current_angle = 0.0,
    is_active = false
}

local base_view_weapon_root_rotation = nil -- 씬에서 읽은 ViewWeaponRoot 기본 회전
local base_weapon_offset_location = nil    -- 씬에서 읽은 VisualPivot 위치. 화면 고정 offset 기준값
local base_weapon_visual_rotation = nil    -- 씬에서 읽은 VisualPivot 기본 기울기
local base_weapon_pitch_location = nil     -- 씬에서 읽은 PitchPivot 위치. 총 회전 중심 기준값
local base_weapon_pitch_rotation = nil     -- 씬에서 읽은 PitchPivot 기본 회전
local base_gun_location = nil              -- 씬에서 읽은 GunMesh 기본 위치
local base_gun_rotation = nil              -- 씬에서 읽은 GunMesh 기본 회전
local base_muzzle_location = nil           -- 씬에서 읽은 MuzzlePoint 기본 위치
local base_muzzle_rotation = nil           -- 씬에서 읽은 MuzzlePoint 기본 회전
local base_beam_location = nil             -- 씬에서 읽은 BeamParticle 기본 위치
local base_beam_rotation = nil             -- 씬에서 읽은 BeamParticle 기본 회전
local grabbed_body = nil
local grabbed_owner_actor = nil            -- 바디 소유 액터 — 매 Tick 생사 확인용 (UAF 방지)
local grabbed_hit_component = nil
local grabbed_local_hit_point = nil
local grabbed_aim_distance = nil
local grabbed_target_world = nil
local grabbed_last_target_world = nil
local grabbed_target_velocity = nil
local beamed_ragdoll_actor = nil

local RAGDOLL_TAG = "Ragdoll"
local BEAM_BLOCK_REVIVE_TAG = "NoReviveWhileBeamed"
local RED_BEAM_HIT_FUNCTION = "OnRedBeamHit"
local RED_BEAM_HIT_REASON = "Slot2RedBeam"
local RED_BEAM_RIM_DURATION = 1.0

local function vec(x, y, z)
    local v = Vector.Zero()
    v.X = x
    v.Y = y
    v.Z = z
    return v
end

local function copy_vec(v)
    if v == nil then
        return Vector.Zero()
    end

    return vec(v.X, v.Y, v.Z)
end

local function sub_vec(a, b)
    return vec(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end

local function clamp_vector_length(v, max_length)
    local length = v:Length()
    if length > max_length and length > 0.0001 then
        return v * (max_length / length)
    end
    return v
end

local function find_beam_particle()
    local component = obj:GetPrimitiveComponentByName("GOIncBeamParticle")
    if component ~= nil then
        beam_actor = obj
        return component
    end

    if World == nil or World.FindActorByName == nil then
        beam_actor = nil
        return nil
    end

    beam_actor = World.FindActorByName("BeamActor")
    if beam_actor == nil then
        beam_actor = World.FindActorByName("GOIncBeamActor")
    end

    if beam_actor == nil then
        return nil
    end

    component = beam_actor:GetPrimitiveComponentByName("GOIncBeamParticle")
    if component ~= nil then
        return component
    end
    return beam_actor:GetRootPrimitiveComponent()
end

local function flat_normalized(v)
    local flat = vec(v.X, v.Y, 0.0)
    if flat:Length() > 0.0001 then
        return flat:Normalized()
    end
    return Vector.Zero()
end

local function blend_normalized(a, b, alpha)
    local blended = a * (1.0 - alpha) + b * alpha
    if blended:Length() > 0.0001 then
        return blended:Normalized()
    end
    return copy_vec(a)
end

local function clamp(value, min_value, max_value)
    if value < min_value then
        return min_value
    end
    if value > max_value then
        return max_value
    end
    return value
end

local function ease_in_out(t)
    local clamped = clamp(t, 0.0, 1.0)
    return clamped * clamped * (3.0 - 2.0 * clamped)
end

local function get_next_weapon_swap_angle()
    return weapon_swap_state.current_angle + C.WEAPON_SWAP_DIRECTION * C.WEAPON_SWAP_ROTATION_DEGREES
end

local function cache_component_transform(component, fallback_location, fallback_rotation)
    local location = fallback_location or Vector.Zero()
    local rotation = fallback_rotation or Vector.Zero()

    if component ~= nil then
        location = component.RelativeLocation
        rotation = component.Rotation
    end

    return copy_vec(location), copy_vec(rotation)
end

local function set_weapon_mesh_visible(component, is_visible)
    if component ~= nil and component.SetVisibility ~= nil then
        component:SetVisibility(is_visible)
    end
end

local function update_viewport_center()
    local size = Engine.GetViewportSize()
    if size ~= nil then
        viewport_center_x = (size.Width or 0.0) * 0.5
        viewport_center_y = (size.Height or 0.0) * 0.5
    end
end

local function setup_crosshair_ui()
    if crosshair_widget == nil then
        if UI == nil or UI.CreateWidget == nil then
            return
        end

        crosshair_widget = UI.CreateWidget(C.CROSSHAIR_WIDGET_PATH)
        if crosshair_widget == nil then
            return
        end
    end

    crosshair_widget:SetWantsMouse(false)
    if crosshair_widget.IsInViewport == nil or not crosshair_widget:IsInViewport() then
        crosshair_widget:AddToViewportZ(C.CROSSHAIR_Z_ORDER)
        crosshair_is_hold = nil
    end
end

local function update_crosshair_ui()
    if crosshair_widget == nil then
        return
    end

    local is_hold = Input.GetKey(C.KEY_LBUTTON)
    if crosshair_is_hold == is_hold then
        return
    end

    crosshair_is_hold = is_hold
    if is_hold then
        crosshair_widget:SetProperty("crosshair_normal", "display", "none")
        crosshair_widget:SetProperty("crosshair_hold", "display", "block")
    else
        crosshair_widget:SetProperty("crosshair_normal", "display", "block")
        crosshair_widget:SetProperty("crosshair_hold", "display", "none")
    end
end

local function set_crosshair_screen_position(screen_x, screen_y)
    if crosshair_widget == nil then
        return
    end

    local left = string.format("%.2fpx", screen_x)
    local top = string.format("%.2fpx", screen_y)
    crosshair_widget:SetProperty("crosshair_normal", "left", left)
    crosshair_widget:SetProperty("crosshair_normal", "top", top)
    crosshair_widget:SetProperty("crosshair_hold", "left", left)
    crosshair_widget:SetProperty("crosshair_hold", "top", top)
end

local function ease_out_cubic(t)
    local clamped = clamp(t, 0.0, 1.0)
    local inverse = 1.0 - clamped
    return 1.0 - inverse * inverse * inverse
end

local function project_crosshair_world_position(world_point)
    update_viewport_center()

    if world_point == nil or Engine == nil or Engine.ProjectWorldToScreen == nil then
        return viewport_center_x, viewport_center_y
    end

    local projected = Engine.ProjectWorldToScreen(world_point)
    if projected == nil or not projected.bValid then
        return viewport_center_x, viewport_center_y
    end

    local screen_x = projected.X or viewport_center_x
    local screen_y = projected.Y or viewport_center_y
    local width = projected.Width or (viewport_center_x * 2.0)
    local height = projected.Height or (viewport_center_y * 2.0)
    if width > 0.0 and height > 0.0 then
        screen_x = clamp(screen_x, C.CROSSHAIR_SCREEN_PADDING, width - C.CROSSHAIR_SCREEN_PADDING)
        screen_y = clamp(screen_y, C.CROSSHAIR_SCREEN_PADDING, height - C.CROSSHAIR_SCREEN_PADDING)
    end

    return screen_x, screen_y
end

local function move_crosshair_toward(target_x, target_y, delta_time)
    if crosshair_widget == nil then
        return
    end

    if crosshair_screen_x == nil or crosshair_screen_y == nil then
        crosshair_screen_x = target_x
        crosshair_screen_y = target_y
        set_crosshair_screen_position(crosshair_screen_x, crosshair_screen_y)
        return
    end

    local alpha = 1.0
    if delta_time ~= nil and delta_time > 0.0 then
        alpha = ease_out_cubic(delta_time * C.CROSSHAIR_EASE_SPEED)
    end

    crosshair_screen_x = crosshair_screen_x + (target_x - crosshair_screen_x) * alpha
    crosshair_screen_y = crosshair_screen_y + (target_y - crosshair_screen_y) * alpha
    set_crosshair_screen_position(crosshair_screen_x, crosshair_screen_y)
end

local function bind_components()
    root_body = obj:GetRootPrimitiveComponent()
    camera_pivot = obj:GetComponentByName("GOIncCameraPivot")
    camera = obj:GetCamera()

    view_weapon_root = obj:GetComponentByName("GOIncViewWeaponRoot")
    weapon_visual_pivot = obj:GetComponentByName("GOIncWeaponVisualPivot")
    weapon_components.swap_pivot = obj:GetComponentByName("GOIncWeaponSwapPivot")
    weapon_components.slot_a = obj:GetComponentByName("GOIncWeaponSlotA")
    weapon_components.slot_b = obj:GetComponentByName("GOIncWeaponSlotB")
    weapon_components.pitch_pivot_a = obj:GetComponentByName("GOIncWeaponPitchPivotA")
    if weapon_components.pitch_pivot_a == nil then
        weapon_components.pitch_pivot_a = obj:GetComponentByName("GOIncWeaponPitchPivot")
    end
    weapon_components.pitch_pivot_b = obj:GetComponentByName("GOIncWeaponPitchPivotB")
    weapon_components.gun_a = obj:GetPrimitiveComponentByName("GOIncFirstPersonGunA")
    if weapon_components.gun_a == nil then
        weapon_components.gun_a = obj:GetPrimitiveComponentByName("GOIncFirstPersonGunMesh")
    end
    weapon_components.gun_b = obj:GetPrimitiveComponentByName("GOIncFirstPersonGunB")
    weapon_components.muzzle_point_a = obj:GetComponentByName("GOIncMuzzlePointA")
    if weapon_components.muzzle_point_a == nil then
        weapon_components.muzzle_point_a = obj:GetComponentByName("GOIncMuzzlePoint")
    end
    weapon_components.muzzle_point_b = obj:GetComponentByName("GOIncMuzzlePointB")
    weapon_pitch_pivot = weapon_components.pitch_pivot_a
    gun = weapon_components.gun_a
    muzzle_point = weapon_components.muzzle_point_a
    weapon_components.beam_particle_a = find_beam_particle()
    weapon_components.beam_particle_b = obj:GetPrimitiveComponentByName("GOIncRedBeamParticle")
    beam_particle = weapon_components.beam_particle_a
end

local function set_active_weapon(index)
    if index == 2 and weapon_components.gun_b ~= nil then
        weapon_swap_state.active_index = 2
        weapon_pitch_pivot = weapon_components.pitch_pivot_b
        gun = weapon_components.gun_b
        muzzle_point = weapon_components.muzzle_point_b
        base_weapon_pitch_location = weapon_base.pitch_b_location
        base_weapon_pitch_rotation = weapon_base.pitch_b_rotation
        base_gun_location = weapon_base.gun_b_location
        base_gun_rotation = weapon_base.gun_b_rotation
        base_muzzle_location = weapon_base.muzzle_b_location
        base_muzzle_rotation = weapon_base.muzzle_b_rotation
        base_beam_location = weapon_base.beam_b_location or copy_vec(base_muzzle_location)
        base_beam_rotation = weapon_base.beam_b_rotation or copy_vec(base_muzzle_rotation)
        set_weapon_mesh_visible(weapon_components.gun_a, false)
        set_weapon_mesh_visible(weapon_components.gun_b, true)
        return
    end

    weapon_swap_state.active_index = 1
    weapon_pitch_pivot = weapon_components.pitch_pivot_a
    gun = weapon_components.gun_a
    muzzle_point = weapon_components.muzzle_point_a
    base_weapon_pitch_location = weapon_base.pitch_a_location
    base_weapon_pitch_rotation = weapon_base.pitch_a_rotation
    base_gun_location = weapon_base.gun_a_location
    base_gun_rotation = weapon_base.gun_a_rotation
    base_muzzle_location = weapon_base.muzzle_a_location
    base_muzzle_rotation = weapon_base.muzzle_a_rotation
    base_beam_location = weapon_base.beam_a_location or copy_vec(base_muzzle_location)
    base_beam_rotation = weapon_base.beam_a_rotation or copy_vec(base_muzzle_rotation)
    set_weapon_mesh_visible(weapon_components.gun_a, true)
    set_weapon_mesh_visible(weapon_components.gun_b, false)
end

local function select_active_beam_particle()
    if weapon_swap_state.active_index == 2 then
        beam_particle = weapon_components.beam_particle_b
        base_beam_location = weapon_base.beam_b_location or copy_vec(weapon_base.muzzle_b_location)
        base_beam_rotation = weapon_base.beam_b_rotation or copy_vec(weapon_base.muzzle_b_rotation)
        return
    end

    beam_particle = weapon_components.beam_particle_a
    base_beam_location = weapon_base.beam_a_location or copy_vec(weapon_base.muzzle_a_location)
    base_beam_rotation = weapon_base.beam_a_rotation or copy_vec(weapon_base.muzzle_a_rotation)
end

local function cache_view_weapon_base_transforms()
    if view_weapon_root ~= nil then
        base_view_weapon_root_rotation = copy_vec(view_weapon_root.Rotation)
    else
        base_view_weapon_root_rotation = Vector.Zero()
    end

    if weapon_visual_pivot ~= nil then
        base_weapon_offset_location = copy_vec(weapon_visual_pivot.RelativeLocation)
        base_weapon_visual_rotation = copy_vec(weapon_visual_pivot.Rotation)
    else
        base_weapon_offset_location = vec(C.WEAPON_FORWARD_OFFSET, C.WEAPON_RIGHT_OFFSET, C.WEAPON_UP_OFFSET)
        base_weapon_visual_rotation = Vector.Zero()
    end

    weapon_base.swap_pivot_location, weapon_base.swap_pivot_rotation =
        cache_component_transform(weapon_components.swap_pivot, Vector.Zero(), Vector.Zero())
    weapon_base.slot_a_location, weapon_base.slot_a_rotation =
        cache_component_transform(weapon_components.slot_a, Vector.Zero(), Vector.Zero())
    weapon_base.slot_b_location, weapon_base.slot_b_rotation =
        cache_component_transform(weapon_components.slot_b, Vector.Zero(), Vector.Zero())

    weapon_base.pitch_a_location, weapon_base.pitch_a_rotation =
        cache_component_transform(weapon_components.pitch_pivot_a, Vector.Zero(), Vector.Zero())
    weapon_base.pitch_b_location, weapon_base.pitch_b_rotation =
        cache_component_transform(weapon_components.pitch_pivot_b, weapon_base.pitch_a_location, weapon_base.pitch_a_rotation)

    weapon_base.gun_a_location, weapon_base.gun_a_rotation =
        cache_component_transform(weapon_components.gun_a, Vector.Zero(), vec(C.GUN_ROTATION_ROLL, C.GUN_ROTATION_PITCH, C.GUN_ROTATION_YAW))
    weapon_base.gun_b_location, weapon_base.gun_b_rotation =
        cache_component_transform(weapon_components.gun_b, weapon_base.gun_a_location, weapon_base.gun_a_rotation)

    weapon_base.muzzle_a_location, weapon_base.muzzle_a_rotation =
        cache_component_transform(weapon_components.muzzle_point_a, vec(C.MUZZLE_FORWARD_OFFSET, C.MUZZLE_RIGHT_OFFSET, C.MUZZLE_UP_OFFSET), Vector.Zero())
    weapon_base.muzzle_b_location, weapon_base.muzzle_b_rotation =
        cache_component_transform(weapon_components.muzzle_point_b, weapon_base.muzzle_a_location, weapon_base.muzzle_a_rotation)

    if weapon_components.beam_particle_a ~= nil then
        weapon_base.beam_a_location = copy_vec(weapon_components.beam_particle_a.RelativeLocation)
        weapon_base.beam_a_rotation = copy_vec(weapon_components.beam_particle_a.Rotation)
    else
        weapon_base.beam_a_location = copy_vec(weapon_base.muzzle_a_location)
        weapon_base.beam_a_rotation = copy_vec(weapon_base.muzzle_a_rotation)
    end

    if weapon_components.beam_particle_b ~= nil then
        weapon_base.beam_b_location = copy_vec(weapon_components.beam_particle_b.RelativeLocation)
        weapon_base.beam_b_rotation = copy_vec(weapon_components.beam_particle_b.Rotation)
    else
        weapon_base.beam_b_location = copy_vec(weapon_base.muzzle_b_location)
        weapon_base.beam_b_rotation = copy_vec(weapon_base.muzzle_b_rotation)
    end

    set_active_weapon(weapon_swap_state.active_index)
end

local function update_camera_view()
    obj.Rotation = vec(0.0, 0.0, yaw)

    if camera_pivot ~= nil then
        camera_pivot.RelativeLocation = vec(0.0, 0.0, C.CAMERA_HEIGHT)
        camera_pivot.Rotation = vec(0.0, pitch, 0.0)
    end

    if camera ~= nil then
        camera.RelativeLocation = Vector.Zero()
        camera.Rotation = Vector.Zero()
    end
end

local function get_weapon_offset_for_pitch()
    if base_weapon_offset_location == nil then
        cache_view_weapon_base_transforms()
    end

    local pitch_alpha = clamp(pitch / C.WEAPON_PITCH_NORMALIZE, -1.0, 1.0)
    local pitch_abs = math.abs(pitch_alpha)
    local pitch_curve = pitch_abs * pitch_abs
    local pitch_signed_curve = pitch_curve
    if pitch_alpha < 0.0 then
        pitch_signed_curve = -pitch_curve
    end
    local look_up_curve = -pitch_signed_curve

    local visual_pitch = clamp(pitch * C.WEAPON_PITCH_SCALE, -C.WEAPON_MAX_VISUAL_PITCH, C.WEAPON_MAX_VISUAL_PITCH)
    local weapon_offset = vec(
        base_weapon_offset_location.X - pitch_curve * C.WEAPON_PITCH_PULLBACK,
        base_weapon_offset_location.Y - pitch_curve * C.WEAPON_PITCH_INWARD_OFFSET,
        base_weapon_offset_location.Z + look_up_curve * C.WEAPON_PITCH_UP_OFFSET
    )

    return weapon_offset, visual_pitch
end

local function get_beam_source_pitch_influence()
    if pitch > 0.0 then
        return C.BEAM_SOURCE_DOWN_PITCH_INFLUENCE
    end

    return C.BEAM_SOURCE_PITCH_INFLUENCE
end

local function get_beam_source_offset_for_pitch()
    local weapon_offset = get_weapon_offset_for_pitch()
    if base_weapon_offset_location == nil then
        return weapon_offset
    end

    local pitch_influence = get_beam_source_pitch_influence()
    return vec(
        base_weapon_offset_location.X + (weapon_offset.X - base_weapon_offset_location.X) * pitch_influence,
        base_weapon_offset_location.Y + (weapon_offset.Y - base_weapon_offset_location.Y) * pitch_influence,
        base_weapon_offset_location.Z + (weapon_offset.Z - base_weapon_offset_location.Z) * pitch_influence
    )
end

local function get_beam_source_point()
    if base_muzzle_location == nil or base_weapon_offset_location == nil then
        cache_view_weapon_base_transforms()
    end

    if camera ~= nil then
        local weapon_offset = get_beam_source_offset_for_pitch()
        local muzzle_offset = base_muzzle_location or vec(C.MUZZLE_FORWARD_OFFSET, C.MUZZLE_RIGHT_OFFSET, C.MUZZLE_UP_OFFSET)
        local pitch_influence = get_beam_source_pitch_influence()
        local camera_forward = camera.Forward
        local camera_right = camera.Right
        local camera_up = camera.Up

        if camera_forward == nil or camera_forward:Length() <= 0.0001 then
            camera_forward = obj.Forward
        end
        if camera_right == nil or camera_right:Length() <= 0.0001 then
            camera_right = obj.Right
        end
        if camera_up == nil or camera_up:Length() <= 0.0001 then
            camera_up = Vector.Up()
        end

        local flat_forward = flat_normalized(camera_forward)
        if flat_forward:Length() <= 0.0001 then
            flat_forward = flat_normalized(obj.Forward)
        end
        if flat_forward:Length() <= 0.0001 then
            flat_forward = camera_forward:Normalized()
        end

        local forward = blend_normalized(flat_forward, camera_forward:Normalized(), pitch_influence)
        local right = flat_normalized(camera_right)
        if right:Length() <= 0.0001 then
            right = camera_right:Normalized()
        end

        local up = forward:Cross(right)
        if up:Length() > 0.0001 then
            up = up:Normalized()
        else
            up = blend_normalized(Vector.Up(), camera_up:Normalized(), pitch_influence)
        end

        return camera.Location
            + forward * (weapon_offset.X + muzzle_offset.X + C.BEAM_SOURCE_FORWARD_BIAS)
            + right * (weapon_offset.Y + muzzle_offset.Y + C.BEAM_SOURCE_RIGHT_BIAS)
            + up * (weapon_offset.Z + muzzle_offset.Z + C.BEAM_SOURCE_UP_BIAS)
    end

    if muzzle_point ~= nil then
        return muzzle_point.Location
    end

    return obj.Location + obj.Forward * (C.WEAPON_FORWARD_OFFSET + C.MUZZLE_FORWARD_OFFSET + C.BEAM_SOURCE_FORWARD_BIAS)
end

local function get_beam_source_forward()
    if muzzle_point ~= nil and muzzle_point.Forward ~= nil then
        local muzzle_forward = muzzle_point.Forward
        if muzzle_forward:Length() > 0.0001 then
            return muzzle_forward:Normalized()
        end
    end

    if camera ~= nil then
        local pitch_influence = get_beam_source_pitch_influence()
        local camera_forward = camera.Forward
        if camera_forward == nil or camera_forward:Length() <= 0.0001 then
            camera_forward = obj.Forward
        end

        local flat_forward = flat_normalized(camera_forward)
        if flat_forward:Length() <= 0.0001 then
            flat_forward = flat_normalized(obj.Forward)
        end
        if flat_forward:Length() <= 0.0001 then
            return camera_forward:Normalized()
        end

        return blend_normalized(flat_forward, camera_forward:Normalized(), pitch_influence)
    end

    if obj.Forward ~= nil and obj.Forward:Length() > 0.0001 then
        return obj.Forward:Normalized()
    end
    return Vector.Forward()
end

local function get_beam_target_direction(source_point, target_point)
    if source_point ~= nil and target_point ~= nil then
        local to_target = target_point - source_point
        if to_target:Length() > 0.0001 then
            return to_target:Normalized()
        end
    end
    return get_beam_source_forward()
end

local function update_weapon_slot_transform(pitch_pivot_component, base_pitch_location, base_pitch_rotation,
    gun_component, base_gun_location_value, base_gun_rotation_value,
    muzzle_component, base_muzzle_location_value, base_muzzle_rotation_value,
    visual_pitch)
    local pitch_location = base_pitch_location or Vector.Zero()
    local pitch_rotation = base_pitch_rotation or Vector.Zero()

    if pitch_pivot_component ~= nil then
        pitch_pivot_component.RelativeLocation = copy_vec(pitch_location)
        pitch_pivot_component.Rotation = vec(
            pitch_rotation.X,
            pitch_rotation.Y + visual_pitch,
            pitch_rotation.Z
        )
    end

    if gun_component ~= nil then
        gun_component.RelativeLocation = sub_vec(base_gun_location_value or Vector.Zero(), pitch_location)
        gun_component.Rotation = copy_vec(base_gun_rotation_value or Vector.Zero())
    end

    if muzzle_component ~= nil then
        muzzle_component.RelativeLocation = sub_vec(base_muzzle_location_value or Vector.Zero(), pitch_location)
        muzzle_component.Rotation = copy_vec(base_muzzle_rotation_value or Vector.Zero())
    end
end

local function update_view_weapon()
    local weapon_offset, visual_pitch = get_weapon_offset_for_pitch()

    if view_weapon_root ~= nil then
        if camera ~= nil then
            view_weapon_root.Location = camera.Location
        else
            view_weapon_root.RelativeLocation = vec(0.0, 0.0, C.CAMERA_HEIGHT)
        end
        view_weapon_root.Rotation = vec(
            base_view_weapon_root_rotation.X,
            base_view_weapon_root_rotation.Y + pitch,
            base_view_weapon_root_rotation.Z
        )
    end

    if weapon_visual_pivot ~= nil then
        weapon_visual_pivot.RelativeLocation = weapon_offset
        weapon_visual_pivot.Rotation = copy_vec(base_weapon_visual_rotation)
    end

    if weapon_components.swap_pivot ~= nil then
        weapon_components.swap_pivot.RelativeLocation = copy_vec(weapon_base.swap_pivot_location)
        weapon_components.swap_pivot.Rotation = vec(
            weapon_base.swap_pivot_rotation.X,
            weapon_base.swap_pivot_rotation.Y + weapon_swap_state.current_angle,
            weapon_base.swap_pivot_rotation.Z
        )
    end

    if weapon_components.slot_a ~= nil then
        weapon_components.slot_a.RelativeLocation = copy_vec(weapon_base.slot_a_location)
        weapon_components.slot_a.Rotation = copy_vec(weapon_base.slot_a_rotation)
    end

    if weapon_components.slot_b ~= nil then
        weapon_components.slot_b.RelativeLocation = copy_vec(weapon_base.slot_b_location)
        weapon_components.slot_b.Rotation = copy_vec(weapon_base.slot_b_rotation)
    end

    update_weapon_slot_transform(
        weapon_components.pitch_pivot_a, weapon_base.pitch_a_location, weapon_base.pitch_a_rotation,
        weapon_components.gun_a, weapon_base.gun_a_location, weapon_base.gun_a_rotation,
        weapon_components.muzzle_point_a, weapon_base.muzzle_a_location, weapon_base.muzzle_a_rotation,
        visual_pitch
    )
    update_weapon_slot_transform(
        weapon_components.pitch_pivot_b, weapon_base.pitch_b_location, weapon_base.pitch_b_rotation,
        weapon_components.gun_b, weapon_base.gun_b_location, weapon_base.gun_b_rotation,
        weapon_components.muzzle_point_b, weapon_base.muzzle_b_location, weapon_base.muzzle_b_rotation,
        visual_pitch
    )

    if beam_particle ~= nil then
        beam_particle.RelativeLocation = copy_vec(base_beam_location)
        beam_particle.Rotation = copy_vec(base_beam_rotation)
    end
end

local set_beam_visible
local set_beam_points
local update_beam_points

local function get_camera_aim_ray()
    if Engine ~= nil and Engine.GetViewportCenterRay ~= nil then
        local ray = Engine.GetViewportCenterRay()
        if ray ~= nil and ray.bValid and ray.Direction ~= nil then
            local direction = ray.Direction
            if direction:Length() > 0.0001 then
                local start = ray.Origin or ray.NearOrigin
                if start ~= nil then
                    return start, direction:Normalized()
                end
            end
        end
    end

    local start = obj.Location
    local direction = obj.Forward

    if camera ~= nil then
        start = camera.Location
        direction = camera.Forward
    end

    if direction:Length() <= 0.0001 then
        direction = obj.Forward
    end

    direction = direction:Normalized()
    return start, direction
end

local function center_physics_raycast(max_distance)
    local distance = max_distance or C.MAX_TRACE_DISTANCE
    if aim_trace_cache.resolved_serial == aim_trace_cache.serial
        and aim_trace_cache.max_distance == distance then
        return aim_trace_cache.hit,
            aim_trace_cache.fallback_end,
            aim_trace_cache.start,
            aim_trace_cache.direction
    end

    local start, direction = get_camera_aim_ray()
    local fallback_end = start + direction * distance
    local hit = nil

    if World ~= nil and World.PhysicsRaycast ~= nil then
        hit = World.PhysicsRaycast(start, direction, distance, obj)
    end

    aim_trace_cache.resolved_serial = aim_trace_cache.serial
    aim_trace_cache.max_distance = distance
    aim_trace_cache.hit = hit
    aim_trace_cache.fallback_end = fallback_end
    aim_trace_cache.start = start
    aim_trace_cache.direction = direction

    return hit, fallback_end, start, direction
end

local function get_hit_point_or_end(hit, fallback_end)
    if hit ~= nil then
        if hit.bHit then
            if hit.WorldHitLocation ~= nil then
                return hit.WorldHitLocation
            end
            if hit.Location ~= nil then
                return hit.Location
            end
            if hit.Hit ~= nil and hit.Hit.WorldHitLocation ~= nil then
                return hit.Hit.WorldHitLocation
            end
        end
        if hit.End ~= nil then
            return hit.End
        end
    end
    return fallback_end
end

local function get_camera_aim_point()
    local hit, fallback_end = center_physics_raycast(C.MAX_TRACE_DISTANCE)
    return get_hit_point_or_end(hit, fallback_end)
end

local function get_crosshair_target_world()
    local hit, fallback_end = center_physics_raycast(C.MAX_TRACE_DISTANCE)
    if Input.GetKey(C.KEY_LBUTTON) and hit ~= nil and hit.bHit then
        return get_hit_point_or_end(hit, fallback_end)
    end
    return fallback_end
end

local function update_crosshair_aim_position(delta_time)
    if crosshair_widget == nil then
        return
    end

    local target_world = get_crosshair_target_world()
    local target_x, target_y = project_crosshair_world_position(target_world)
    move_crosshair_toward(target_x, target_y, delta_time)
end

local function compute_grab_target(start, direction)
    if grabbed_aim_distance == nil then
        return nil
    end

    return start + direction * grabbed_aim_distance
end

local function get_mouse_wheel_notches()
    if Input.GetMouseWheelNotches ~= nil then
        return Input.GetMouseWheelNotches()
    end

    if Input.GetMouseWheelDelta ~= nil then
        return Input.GetMouseWheelDelta() / 120.0
    end

    return 0.0
end

local function update_grab_distance_from_mouse_wheel()
    if grabbed_aim_distance == nil then
        return
    end

    local wheel_notches = get_mouse_wheel_notches()
    if math.abs(wheel_notches) <= 0.0001 then
        return
    end

    grabbed_aim_distance = clamp(
        grabbed_aim_distance + wheel_notches * C.GRAB_MOUSE_WHEEL_DISTANCE_STEP,
        C.GRAB_MIN_AIM_DISTANCE,
        C.GRAB_MAX_AIM_DISTANCE
    )
    grabbed_last_target_world = nil
    grabbed_target_velocity = Vector.Zero()
end

local function is_actor_valid(actor)
    return actor ~= nil and (actor.IsValid == nil or actor:IsValid())
end

local function is_ragdoll_actor(actor)
    return is_actor_valid(actor) and actor.HasTag ~= nil and actor:HasTag(RAGDOLL_TAG)
end

local function clear_beamed_ragdoll_actor()
    if is_actor_valid(beamed_ragdoll_actor) and beamed_ragdoll_actor.RemoveTag ~= nil then
        beamed_ragdoll_actor:RemoveTag(BEAM_BLOCK_REVIVE_TAG)
    end

    beamed_ragdoll_actor = nil
end

local function set_beamed_ragdoll_actor(actor)
    if not is_ragdoll_actor(actor) then
        clear_beamed_ragdoll_actor()
        return
    end

    if beamed_ragdoll_actor == actor then
        return
    end

    clear_beamed_ragdoll_actor()
    beamed_ragdoll_actor = actor

    if actor.AddTag ~= nil then
        actor:AddTag(BEAM_BLOCK_REVIVE_TAG)
    end
end

local function clear_grab_state()
    clear_beamed_ragdoll_actor()

    grabbed_body = nil
    grabbed_owner_actor = nil
    grabbed_hit_component = nil
    grabbed_local_hit_point = nil
    grabbed_aim_distance = nil
    grabbed_target_world = nil
    grabbed_last_target_world = nil
    grabbed_target_velocity = nil
end

local function compute_grab_aim_distance(start, direction, grab_point, hit, fallback_end)
    local distance = nil
    if grab_point ~= nil then
        distance = (grab_point - start):Dot(direction)
    end
    if (distance == nil or distance <= C.GRAB_MIN_AIM_DISTANCE) and hit ~= nil then
        if hit.Distance ~= nil and hit.Distance > C.GRAB_MIN_AIM_DISTANCE then
            distance = hit.Distance
        elseif hit.Hit ~= nil and hit.Hit.Distance ~= nil and hit.Hit.Distance > C.GRAB_MIN_AIM_DISTANCE then
            distance = hit.Hit.Distance
        end
    end
    if (distance == nil or distance <= C.GRAB_MIN_AIM_DISTANCE) and fallback_end ~= nil then
        distance = (fallback_end - start):Length()
    end
    return clamp(distance or C.GRAB_MIN_AIM_DISTANCE, C.GRAB_MIN_AIM_DISTANCE, C.GRAB_MAX_AIM_DISTANCE)
end

local function get_hit_physics_body(hit)
    if hit == nil then
        return nil
    end
    if hit.PhysicsBody ~= nil then
        return hit.PhysicsBody
    end
    if hit.Hit ~= nil and hit.Hit.PhysicsBody ~= nil then
        return hit.Hit.PhysicsBody
    end
    return nil
end

local function get_hit_component(hit)
    if hit == nil then
        return nil
    end
    if hit.HitComponent ~= nil then
        return hit.HitComponent
    end
    if hit.Hit ~= nil and hit.Hit.HitComponent ~= nil then
        return hit.Hit.HitComponent
    end
    return nil
end

local function get_hit_actor(hit)
    if hit == nil then
        return nil
    end
    if hit.HitActor ~= nil then
        return hit.HitActor
    end
    if hit.Hit ~= nil and hit.Hit.HitActor ~= nil then
        return hit.Hit.HitActor
    end

    local body = get_hit_physics_body(hit)
    if body ~= nil and body.GetOwnerActor ~= nil then
        local owner = body:GetOwnerActor()
        if owner ~= nil then
            return owner
        end
    end

    local component = get_hit_component(hit)
    if component ~= nil and component.GetOwner ~= nil then
        return component:GetOwner()
    end

    return nil
end

local function notify_red_beam_hit_ragdoll(hit)
    local actor = get_hit_actor(hit)
    if not is_ragdoll_actor(actor) then
        return false
    end

    local ragdollPawn = nil
    if actor.AsGOIncRagdollPawn ~= nil then
        ragdollPawn = actor:AsGOIncRagdollPawn()
    end

    if ragdollPawn == nil then
        print("[GOIncTestActor] Red beam hit tagged Ragdoll, but actor is not AGOIncRagdollPawn: " .. tostring(actor:GetName()))
        return false
    end

    local script = nil
    if ragdollPawn.GetLuaScriptComponent ~= nil then
        script = ragdollPawn:GetLuaScriptComponent()
    end

    if script ~= nil and script.CallFunctionString ~= nil then
        if script:CallFunctionString(RED_BEAM_HIT_FUNCTION, RED_BEAM_HIT_REASON) then
            return true
        end
    end

    print("[GOIncTestActor] Red beam hit Ragdoll, but OnRedBeamHit was not handled: " .. tostring(actor:GetName()))
    return false
end

local function get_hit_location(hit)
    if hit == nil then
        return nil
    end
    if hit.WorldHitLocation ~= nil then
        return hit.WorldHitLocation
    end
    if hit.Location ~= nil then
        return hit.Location
    end
    if hit.Hit ~= nil and hit.Hit.WorldHitLocation ~= nil then
        return hit.Hit.WorldHitLocation
    end
    if hit.Hit ~= nil and hit.Hit.Location ~= nil then
        return hit.Hit.Location
    end
    return nil
end

local function trigger_hit_rim_on_component(hit_component, should_flash, hit_location)
    if hit_component == nil or hit_component.GetSimulatePhysics == nil or not hit_component:GetSimulatePhysics() then
        return
    end

    if hit_component.SetHitRimColor ~= nil then
        if weapon_swap_state.active_index == 2 then
            hit_component:SetHitRimColor(1.0, 0.08, 0.04, 1.0)
        else
            hit_component:SetHitRimColor(0.05, 0.85, 1.0, 1.0)
        end
    end

    if hit_location ~= nil then
        if should_flash and hit_component.TriggerHitRimAt ~= nil then
            hit_component:TriggerHitRimAt(hit_location, C.HIT_RIM_DURATION, C.HIT_RIM_FLASH_INTENSITY, C.HIT_RIM_POWER, C.HIT_RIM_SUSTAIN_INTENSITY, C.HIT_IMPACT_RADIUS, C.HIT_IMPACT_CORE_RADIUS, C.HIT_IMPACT_INTENSITY)
            return
        elseif hit_component.RefreshHitRimAt ~= nil then
            hit_component:RefreshHitRimAt(hit_location, C.HIT_RIM_SUSTAIN_INTENSITY, C.HIT_RIM_POWER, C.HIT_IMPACT_RADIUS, C.HIT_IMPACT_CORE_RADIUS, C.HIT_IMPACT_INTENSITY)
            return
        end
    end

    if should_flash and hit_component.TriggerHitRim ~= nil then
        hit_component:TriggerHitRim(C.HIT_RIM_DURATION, C.HIT_RIM_FLASH_INTENSITY, C.HIT_RIM_POWER, C.HIT_RIM_SUSTAIN_INTENSITY)
        if hit_location ~= nil and hit_component.SetHitImpactGlow ~= nil then
            hit_component:SetHitImpactGlow(hit_location, C.HIT_IMPACT_RADIUS, C.HIT_IMPACT_CORE_RADIUS, C.HIT_IMPACT_INTENSITY)
        end
    elseif hit_component.RefreshHitRim ~= nil then
        hit_component:RefreshHitRim(C.HIT_RIM_SUSTAIN_INTENSITY, C.HIT_RIM_POWER)
    end
end

local function trigger_hit_rim(hit, should_flash)
    if hit == nil or not hit.bHit then
        return
    end

    trigger_hit_rim_on_component(get_hit_component(hit), should_flash, get_hit_location(hit))
end

local function trigger_red_beam_rim_on_ragdoll_mesh(hit)
    if hit == nil or not hit.bHit then
        return
    end

    local actor = get_hit_actor(hit)
    if not is_ragdoll_actor(actor) then
        return
    end

    local ragdollPawn = nil
    if actor.AsGOIncRagdollPawn ~= nil then
        ragdollPawn = actor:AsGOIncRagdollPawn()
    end
    if ragdollPawn == nil or ragdollPawn.GetRagdollMeshComponent == nil then
        return
    end

    local mesh = ragdollPawn:GetRagdollMeshComponent()
    if mesh == nil then
        return
    end

    if mesh.SetHitRimColor ~= nil then
        mesh:SetHitRimColor(1.0, 0.08, 0.04, 1.0)
    end

    local hit_location = get_hit_location(hit)
    if hit_location ~= nil and mesh.TriggerHitRimAt ~= nil then
        mesh:TriggerHitRimAt(hit_location, RED_BEAM_RIM_DURATION, C.HIT_RIM_FLASH_INTENSITY, C.HIT_RIM_POWER, C.HIT_RIM_SUSTAIN_INTENSITY, C.HIT_IMPACT_RADIUS, C.HIT_IMPACT_CORE_RADIUS, C.HIT_IMPACT_INTENSITY)
        return
    end

    if mesh.TriggerHitRim ~= nil then
        mesh:TriggerHitRim(RED_BEAM_RIM_DURATION, C.HIT_RIM_FLASH_INTENSITY, C.HIT_RIM_POWER, C.HIT_RIM_SUSTAIN_INTENSITY)
    end
end

local function begin_beam_grab(hit, start, direction, fallback_end)
    if hit == nil or not hit.bHit then
        return false
    end

    local body = get_hit_physics_body(hit)
    if body == nil or body.IsValid == nil or not body:IsValid() then
        return false
    end
    if body.IsDynamic ~= nil and not body:IsDynamic() then
        return false
    end

    -- 소유 액터를 지금(살아있을 때) 캐싱 — 잡는 동안 액터가 Destroy되면
    -- body userdata가 통째로 댕글링되므로, 이후엔 액터 생사로만 판단한다
    local owner = (body.GetOwnerActor ~= nil) and body:GetOwnerActor() or nil
    if owner == nil then
        return false
    end

    local grab_point = get_hit_point_or_end(hit, fallback_end)
    local grab_distance = compute_grab_aim_distance(start, direction, grab_point, hit, fallback_end)
    local target_point = start + direction * grab_distance
    grabbed_body = body
    grabbed_owner_actor = owner
    grabbed_hit_component = get_hit_component(hit)
    grabbed_local_hit_point = body:WorldToLocalPoint(grab_point)
    grabbed_aim_distance = grab_distance
    grabbed_target_world = target_point
    grabbed_last_target_world = target_point
    grabbed_target_velocity = Vector.Zero()
    set_beamed_ragdoll_actor(owner)

    body:WakeUp()

    last_aim_point = grab_point
    if beam_particle ~= nil and beam_particle.ResetParticleSystem ~= nil then
        beam_particle:ResetParticleSystem()
    end
    update_beam_points(grab_point)
    set_beam_visible(true)
    beam_visible_remaining = 0.0
    return true
end

local function apply_grab_force(delta_time, start, direction)
    -- 액터 생사 확인이 반드시 먼저다 — 수거(Destroy)로 액터가 죽으면 본 바디
    -- 메모리가 해제돼 grabbed_body:IsValid() 호출 자체가 Use-After-Free가 된다.
    -- AActor는 GC 관리라 IsValid 확인이 안전하다 (PhysicsBody는 아님)
    if grabbed_owner_actor == nil or not grabbed_owner_actor:IsValid() then
        clear_grab_state()
        set_beam_visible(false)
        return
    end
    if grabbed_body == nil or grabbed_body.IsValid == nil or not grabbed_body:IsValid() then
        clear_grab_state()
        set_beam_visible(false)
        return
    end

    local desired = compute_grab_target(start, direction)
    if desired == nil then
        clear_grab_state()
        set_beam_visible(false)
        return
    end

    if grabbed_hit_component == nil and grabbed_body.GetOwnerComponent ~= nil then
        grabbed_hit_component = grabbed_body:GetOwnerComponent()
    end
    trigger_hit_rim_on_component(grabbed_hit_component)

    grabbed_target_world = desired

    local current_body_center = grabbed_body:GetLocation()
    local current_grab_world = grabbed_body:LocalToWorldPoint(grabbed_local_hit_point)
    local error = clamp_vector_length(desired - current_grab_world, C.GRAB_MAX_ERROR)
    local linear_velocity = grabbed_body:GetLinearVelocity()

    local grab_distance_along_ray = (current_grab_world - start):Dot(direction)
    local body_distance_along_ray = (current_body_center - start):Dot(direction)
    local body_radius_proxy = (current_grab_world - current_body_center):Length()
    local body_surface_distance_along_ray = body_distance_along_ray - body_radius_proxy
    local current_min_distance = math.min(grab_distance_along_ray, body_surface_distance_along_ray)
    local min_distance_penetration = 0.0
    local blocked_inward_speed = 0.0
    if current_min_distance < C.GRAB_MIN_AIM_DISTANCE then
        min_distance_penetration = C.GRAB_MIN_AIM_DISTANCE - current_min_distance
        local velocity_along_ray = linear_velocity:Dot(direction)
        blocked_inward_speed = math.max(-velocity_along_ray, 0.0)
        if velocity_along_ray < 0.0 then
            linear_velocity = linear_velocity - direction * velocity_along_ray
            grabbed_body:SetLinearVelocity(linear_velocity)
        end
    end

    local mass = math.max(grabbed_body:GetMass(), 0.001)
    local mass_scale = clamp(
        math.pow(C.GRAB_REFERENCE_MASS / mass, C.GRAB_MASS_POWER),
        C.GRAB_MIN_MASS_SCALE,
        C.GRAB_MAX_MASS_SCALE
    )

    local acceleration = error * (C.GRAB_SPRING_ACCELERATION * mass_scale)
        - linear_velocity * (C.GRAB_DAMPING_ACCELERATION * mass_scale)

    if min_distance_penetration > 0.0 then
        local guard_acceleration = direction * (
            min_distance_penetration * C.GRAB_MIN_DISTANCE_GUARD_ACCELERATION
            + blocked_inward_speed * C.GRAB_MIN_DISTANCE_GUARD_DAMPING
        )
        acceleration = acceleration + guard_acceleration
    end

    acceleration = clamp_vector_length(acceleration, C.GRAB_MAX_ACCELERATION * mass_scale)

    local force = acceleration * mass
    grabbed_body:AddForce(force)

    local grab_offset = current_grab_world - current_body_center
    if grab_offset:Length() > 1.0 then
        local torque = grab_offset:Cross(force) * (C.GRAB_TORQUE_SCALE * mass_scale)
            - grabbed_body:GetAngularVelocity() * (C.GRAB_ANGULAR_DAMPING * mass * mass_scale)
        torque = clamp_vector_length(torque, C.GRAB_MAX_TORQUE * mass * mass_scale)
        grabbed_body:AddTorque(torque)
    end

    if delta_time > 0.0001 and grabbed_last_target_world ~= nil then
        grabbed_target_velocity = (desired - grabbed_last_target_world) / delta_time
    else
        grabbed_target_velocity = Vector.Zero()
    end
    grabbed_last_target_world = desired

    grabbed_body:WakeUp()
    last_aim_point = current_grab_world
    update_beam_points(current_grab_world)
    set_beam_visible(true)
end

local function end_beam_grab(should_throw)
    -- 액터가 이미 죽었으면 body에 손대지 않는다 (apply_grab_force와 동일한 UAF 가드)
    local owner_alive = grabbed_owner_actor ~= nil and grabbed_owner_actor:IsValid()
    if should_throw and owner_alive and grabbed_body ~= nil and grabbed_body.IsValid ~= nil and grabbed_body:IsValid() and grabbed_target_velocity ~= nil then
        local speed = grabbed_target_velocity:Length()
        if speed > C.THROW_MIN_SPEED then
            local mass = math.max(grabbed_body:GetMass(), 0.001)
            local impulse = clamp_vector_length(
                grabbed_target_velocity * (mass * C.THROW_IMPULSE_SCALE),
                C.THROW_MAX_IMPULSE_PER_MASS * mass
            )
            grabbed_body:AddImpulse(impulse)
            grabbed_body:WakeUp()
        end
    end

    clear_grab_state()
    beam_visible_remaining = C.BEAM_VISIBLE_TIME
end

local function update_active_grab(delta_time)
    if grabbed_body == nil then
        return false
    end

    if not Input.GetKey(C.KEY_LBUTTON) then
        end_beam_grab(true)
        return true
    end

    local start, direction = get_camera_aim_ray()
    update_grab_distance_from_mouse_wheel()
    apply_grab_force(delta_time, start, direction)
    return true
end

local function update_beam_fade(delta_time)
    if beam_visible_remaining > 0.0 then
        beam_visible_remaining = beam_visible_remaining - delta_time
        if last_aim_point ~= nil then
            update_beam_points(last_aim_point)
        end
        if beam_visible_remaining <= 0.0 then
            set_beam_visible(false)
        end
    end
end

local function get_slot2_beam_visible_time(hit)
    if hit ~= nil and hit.bHit then
        return C.SLOT2_BEAM_HIT_VISIBLE_TIME
    end
    return C.SLOT2_BEAM_MISS_VISIBLE_TIME
end

set_beam_visible = function(is_visible)
    if beam_particle == nil then
        return
    end

    if beam_particle.SetVisibility ~= nil then
        beam_particle:SetVisibility(is_visible)
    end
    if beam_particle.SetActive ~= nil then
        beam_particle:SetActive(is_visible)
    end
end

set_beam_points = function(source_point, target_point)
    if beam_particle == nil or source_point == nil or target_point == nil then
        return
    end

    if beam_particle.SetBeamPointsWithTangents ~= nil then
        local source_forward = get_beam_source_forward()
        local target_direction = get_beam_target_direction(source_point, target_point)
        beam_particle:SetBeamPointsWithTangents(
            source_point,
            target_point,
            source_forward,
            target_direction,
            C.BEAM_RENDER_SHEETS,
            0,
            C.BEAM_SOURCE_TANGENT_STRENGTH_SCALE,
            C.BEAM_TARGET_TANGENT_STRENGTH_SCALE)
        return
    end

    if beam_particle.SetBeamPoints ~= nil then
        beam_particle:SetBeamPoints(source_point, target_point, 0, C.BEAM_RENDER_SHEETS)
        return
    end

    if beam_particle.SetBeamSourcePoint ~= nil then
        beam_particle:SetBeamSourcePoint(source_point, 0)
    end
    if beam_particle.SetBeamTargetPoint ~= nil then
        beam_particle:SetBeamTargetPoint(target_point, 0)
    elseif beam_particle.SetBeamEndPoint ~= nil then
        beam_particle:SetBeamEndPoint(target_point)
    end
end

update_beam_points = function(aim_point)
    local source_point = get_beam_source_point()
    if source_point == nil then
        return
    end

    set_beam_points(source_point, aim_point)
end

local function apply_slot2_fire(delta_time)
    if not Input.GetKeyDown(C.KEY_LBUTTON) then
        update_beam_fade(delta_time)
        return
    end

    local hit, fallback_end = center_physics_raycast(C.MAX_TRACE_DISTANCE)
    trigger_hit_rim(hit, true)
    trigger_red_beam_rim_on_ragdoll_mesh(hit)
    notify_red_beam_hit_ragdoll(hit)
    last_aim_point = get_hit_point_or_end(hit, fallback_end)

    if beam_particle ~= nil and beam_particle.ResetParticleSystem ~= nil then
        beam_particle:ResetParticleSystem()
    end
    update_beam_points(last_aim_point)
    set_beam_visible(true)
    beam_visible_remaining = get_slot2_beam_visible_time(hit)
end

local function can_swap_weapon()
    return weapon_components.swap_pivot ~= nil
        and weapon_components.gun_b ~= nil
        and weapon_components.muzzle_point_b ~= nil
end

local function begin_weapon_swap()
    if not can_swap_weapon() or weapon_swap_state.is_active then
        return
    end

    weapon_swap_state.pending_index = 1
    if weapon_swap_state.active_index == 1 then
        weapon_swap_state.pending_index = 2
    end

    weapon_swap_state.is_active = true
    weapon_swap_state.elapsed = 0.0
    weapon_swap_state.start_angle = weapon_swap_state.current_angle
    weapon_swap_state.target_angle = get_next_weapon_swap_angle()
    beam_visible_remaining = 0.0
    clear_grab_state()
    set_beam_visible(false)
end

local function update_weapon_swap(delta_time)
    if Input.GetKeyDown(C.KEY_Q) then
        begin_weapon_swap()
    end

    if not weapon_swap_state.is_active then
        return
    end

    weapon_swap_state.elapsed = weapon_swap_state.elapsed + math.max(delta_time or 0.0, 0.0)
    local alpha = ease_in_out(weapon_swap_state.elapsed / C.WEAPON_SWAP_DURATION)
    weapon_swap_state.current_angle = weapon_swap_state.start_angle
        + (weapon_swap_state.target_angle - weapon_swap_state.start_angle) * alpha

    if weapon_swap_state.elapsed >= C.WEAPON_SWAP_DURATION then
        weapon_swap_state.current_angle = weapon_swap_state.target_angle
        weapon_swap_state.is_active = false
        set_active_weapon(weapon_swap_state.pending_index)
    end
end

local function apply_look_input()
    local mouse_x = Input.GetMouseDeltaX()
    local mouse_y = Input.GetMouseDeltaY()

    yaw = yaw + mouse_x * C.LOOK_SENSITIVITY
    pitch = clamp(pitch + mouse_y * C.LOOK_SENSITIVITY, C.MIN_PITCH, C.MAX_PITCH)

    obj.Rotation = vec(0.0, 0.0, yaw)
end

local function ensure_player_velocity()
    if player_velocity == nil then
        player_velocity = Vector.Zero()
    end
    return player_velocity
end

local function get_hit_normal(hit)
    if hit == nil then
        return nil
    end

    if hit.WorldNormal ~= nil and hit.WorldNormal:Length() > C.CAPSULE_SWEEP_MIN_MOVE then
        return hit.WorldNormal
    end
    if hit.ImpactNormal ~= nil and hit.ImpactNormal:Length() > C.CAPSULE_SWEEP_MIN_MOVE then
        return hit.ImpactNormal
    end

    if hit.Hit ~= nil then
        if hit.Hit.WorldNormal ~= nil and hit.Hit.WorldNormal:Length() > C.CAPSULE_SWEEP_MIN_MOVE then
            return hit.Hit.WorldNormal
        end
        if hit.Hit.ImpactNormal ~= nil and hit.Hit.ImpactNormal:Length() > C.CAPSULE_SWEEP_MIN_MOVE then
            return hit.Hit.ImpactNormal
        end
    end

    return nil
end

local function get_hit_distance(hit)
    if hit == nil then
        return nil
    end
    if hit.Distance ~= nil then
        return hit.Distance
    end
    if hit.Hit ~= nil then
        return hit.Hit.Distance
    end
    return nil
end

local function get_floor_hit(extra_distance)
    if World ~= nil and World.PhysicsRaycast ~= nil then
        local probe_distance = C.PLAYER_CAPSULE_HALF_HEIGHT + C.GROUND_PROBE_DISTANCE + math.max(extra_distance or 0.0, 0.0)
        local hit = World.PhysicsRaycast(obj.Location, Vector.Down(), probe_distance, obj)
        if hit == nil or not hit.bHit then
            return nil
        end

        local normal = get_hit_normal(hit)
        if normal ~= nil and normal.Z < C.GROUND_WALKABLE_NORMAL_Z then
            return nil
        end

        return hit
    end

    return nil
end

local function get_floor_location(hit)
    if hit == nil then
        return nil
    end
    if hit.WorldHitLocation ~= nil then
        return hit.WorldHitLocation
    end
    if hit.Location ~= nil then
        return hit.Location
    end
    if hit.Hit ~= nil then
        return hit.Hit.WorldHitLocation
    end
    return nil
end

local function snap_actor_to_floor(hit)
    local floor_location = get_floor_location(hit)
    if floor_location == nil then
        return
    end

    local location = obj.Location
    location.Z = floor_location.Z + C.PLAYER_CAPSULE_HALF_HEIGHT
    obj.Location = location
end

local function is_grounded(velocity, extra_distance)
    local floor_hit = get_floor_hit(extra_distance)
    if floor_hit ~= nil then
        return true, floor_hit
    end

    if World ~= nil and World.PhysicsRaycast ~= nil then
        return false, nil
    end

    return math.abs(velocity.Z) <= C.GROUNDED_Z_VELOCITY_EPSILON
end

local function is_capsule_blocking_hit(hit)
    if hit == nil or not hit.bHit then
        return false
    end

    local start_penetrating = hit.bStartPenetrating
    if start_penetrating == nil and hit.Hit ~= nil then
        start_penetrating = hit.Hit.bStartPenetrating
    end

    local normal = get_hit_normal(hit)
    if normal == nil then
        return false
    end

    if normal.Z >= C.GROUND_WALKABLE_NORMAL_Z then
        return false
    end

    local lateral_normal = vec(normal.X, normal.Y, 0.0)
    local lateral_length = lateral_normal:Length()
    if lateral_length <= C.CAPSULE_SWEEP_MIN_MOVE then
        return false
    end

    return not start_penetrating
end

local function sweep_capsule_delta(start, delta)
    local distance = delta:Length()
    if distance <= C.CAPSULE_SWEEP_MIN_MOVE then
        return delta, nil
    end

    if World == nil or World.CapsuleSweep == nil then
        return delta, nil
    end

    local direction = delta:Normalized()
    local sweep_shrink = math.min(C.CAPSULE_SWEEP_SKIN, C.PLAYER_CAPSULE_RADIUS * 0.45)
    local sweep_radius = math.max(C.PLAYER_CAPSULE_RADIUS - sweep_shrink, 0.001)
    local sweep_half_height = math.max(C.PLAYER_CAPSULE_HALF_HEIGHT - sweep_shrink, sweep_radius + 0.001)
    local hit = World.CapsuleSweep(
        start,
        direction,
        distance,
        sweep_radius,
        sweep_half_height,
        obj)
    if not is_capsule_blocking_hit(hit) then
        return delta, nil
    end

    local hit_distance = get_hit_distance(hit)
    if hit_distance == nil then
        return Vector.Zero(), hit
    end

    local allowed_distance = math.max(hit_distance - C.CAPSULE_SWEEP_SKIN, 0.0)
    allowed_distance = math.min(allowed_distance, distance)
    return direction * allowed_distance, hit
end

local function project_delta_along_surface(delta, normal)
    if normal == nil then
        return Vector.Zero()
    end

    local wall_normal = vec(normal.X, normal.Y, 0.0)
    local normal_length = wall_normal:Length()
    if normal_length <= C.CAPSULE_SWEEP_MIN_MOVE then
        return Vector.Zero()
    end

    wall_normal = wall_normal * (1.0 / normal_length)
    local into_surface = delta:Dot(wall_normal)
    if into_surface < 0.0 then
        return delta - wall_normal * into_surface
    end

    return delta
end

local function resolve_horizontal_collision(horizontal_delta)
    if horizontal_delta:Length() <= C.CAPSULE_SWEEP_MIN_MOVE then
        return horizontal_delta
    end

    local first_delta, hit = sweep_capsule_delta(obj.Location, horizontal_delta)
    if hit == nil then
        return first_delta
    end

    local remaining_delta = horizontal_delta - first_delta
    remaining_delta.Z = 0.0

    local slide_delta = project_delta_along_surface(remaining_delta, get_hit_normal(hit))
    slide_delta.Z = 0.0
    if slide_delta:Length() <= C.CAPSULE_SWEEP_MIN_MOVE then
        return first_delta
    end

    local second_delta = sweep_capsule_delta(obj.Location + first_delta, slide_delta)
    second_delta.Z = 0.0
    return first_delta + second_delta
end

local function apply_kinematic_movement(delta_time)
    delta_time = math.max(delta_time or 0.0, 0.0)

    local forward = flat_normalized(obj.Forward)
    local right = flat_normalized(obj.Right)
    local move_dir = Vector.Zero()

    if Input.GetKey(C.KEY_W) then
        move_dir = move_dir + forward
    end
    if Input.GetKey(C.KEY_S) then
        move_dir = move_dir - forward
    end
    if Input.GetKey(C.KEY_D) then
        move_dir = move_dir + right
    end
    if Input.GetKey(C.KEY_A) then
        move_dir = move_dir - right
    end

    local velocity = ensure_player_velocity()
    local horizontal_velocity = Vector.Zero()

    if move_dir:Length() > 0.0001 then
        horizontal_velocity = move_dir:Normalized() * C.MOVE_SPEED
    end

    velocity.X = horizontal_velocity.X
    velocity.Y = horizontal_velocity.Y

    local grounded, floor_hit = is_grounded(velocity)
    if grounded and velocity.Z <= 0.0 then
        snap_actor_to_floor(floor_hit)
        velocity.Z = 0.0
    end

    local did_jump = false
    if Input.GetKeyDown(C.KEY_SPACE) and grounded then
        velocity.Z = C.JUMP_VELOCITY
        did_jump = true
    end

    if did_jump or not grounded or velocity.Z > 0.0 then
        velocity.Z = velocity.Z - C.GRAVITY_ACCELERATION * delta_time
    end

    local horizontal_delta = vec(velocity.X, velocity.Y, 0.0) * delta_time
    horizontal_delta = resolve_horizontal_collision(horizontal_delta)
    if delta_time > 0.0 then
        velocity.X = horizontal_delta.X / delta_time
        velocity.Y = horizontal_delta.Y / delta_time
    end

    obj.Location = obj.Location + horizontal_delta + vec(0.0, 0.0, velocity.Z * delta_time)

    if velocity.Z <= 0.0 then
        local fall_distance = math.max(-velocity.Z * delta_time, 0.0)
        local landed, landed_hit = is_grounded(velocity, fall_distance)
        if landed then
            snap_actor_to_floor(landed_hit)
            velocity.Z = 0.0
        end
    end
end

local function apply_fire(delta_time)
    if weapon_swap_state.is_active then
        beam_visible_remaining = 0.0
        clear_beamed_ragdoll_actor()
        set_beam_visible(false)
        return
    end

    select_active_beam_particle()

    if weapon_swap_state.active_index == 2 then
        apply_slot2_fire(delta_time)
        return
    end

    if update_active_grab(delta_time) then
        return
    end

    local is_fire_pressed = Input.GetKeyDown(C.KEY_LBUTTON)
    local is_fire_held = Input.GetKey(C.KEY_LBUTTON)
    if not is_fire_held then
        clear_beamed_ragdoll_actor()
        update_beam_fade(delta_time)
        return
    end

    local hit, fallback_end, start, direction = center_physics_raycast(C.MAX_TRACE_DISTANCE)
    trigger_hit_rim(hit, is_fire_pressed)
    set_beamed_ragdoll_actor(get_hit_actor(hit))
    if is_fire_pressed and begin_beam_grab(hit, start, direction, fallback_end) then
        return
    end

    last_aim_point = get_hit_point_or_end(hit, fallback_end)

    if is_fire_pressed and beam_particle ~= nil and beam_particle.ResetParticleSystem ~= nil then
        beam_particle:ResetParticleSystem()
    end
    update_beam_points(last_aim_point)
    set_beam_visible(true)
    beam_visible_remaining = C.BEAM_VISIBLE_TIME
end

function BeginPlay()
    update_viewport_center()
    setup_crosshair_ui()
    update_crosshair_ui()
    move_crosshair_toward(viewport_center_x, viewport_center_y, 0.0)

    local current_rotation = obj.Rotation
    yaw = current_rotation.Z

    bind_components()
    cache_view_weapon_base_transforms()
    player_velocity = Vector.Zero()

    if root_body ~= nil then
        root_body:SetSimulatePhysics(false)
        root_body:SetLinearVelocity(Vector.Zero())
        root_body:SetAngularVelocity(Vector.Zero())
        if root_body.SetKinematicPhysics ~= nil then
            root_body:SetKinematicPhysics(true)
        end
        if root_body.SetCollisionEnabled ~= nil then
            root_body:SetCollisionEnabled("QueryOnly")
        end
    end

    update_camera_view()
    update_view_weapon()
    set_beam_visible(false)

    if camera ~= nil then
        CameraManager.SetActiveCameraWithBlend(camera, 0.0)
        CameraManager.PossessCamera(camera)
    end
    update_crosshair_aim_position(0.0)

    print("[GOInc] viewport center: " .. viewport_center_x .. ", " .. viewport_center_y)
    print("[GOInc] camera aim and view weapon separated")
end

function PrePhysicsTick(delta_time)
    apply_look_input()
    apply_kinematic_movement(delta_time)
end

function Tick(delta_time)
    update_weapon_swap(delta_time)
    obj.Rotation = vec(0.0, 0.0, yaw)
    select_active_beam_particle()
    update_camera_view()
    update_view_weapon()
end

function PostCameraTick(delta_time)
    aim_trace_cache.serial = aim_trace_cache.serial + 1
    apply_fire(delta_time)
    update_crosshair_aim_position(delta_time)
    update_crosshair_ui()
end
