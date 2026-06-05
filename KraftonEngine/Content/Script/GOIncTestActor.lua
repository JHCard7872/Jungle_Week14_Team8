local KEY_W = 0x57       -- 전진 입력 키: W
local KEY_A = 0x41       -- 좌측 이동 입력 키: A
local KEY_S = 0x53       -- 후진 입력 키: S
local KEY_D = 0x44       -- 우측 이동 입력 키: D
local KEY_SPACE = 0x20   -- 점프 입력 키: Space
local KEY_LBUTTON = 0x01 -- 발사 입력 키: 마우스 왼쪽 버튼

local MOVE_SPEED = 6.0                   -- WASD 수평 이동 속도
local JUMP_VELOCITY = 6.5                -- Space 입력 시 PhysX 선형 속도 Z에 넣는 점프 속도
local GROUNDED_Z_VELOCITY_EPSILON = 0.05 -- Raycast가 없을 때 접지 판정에 쓰는 Z 속도 허용값
local GROUND_CHECK_DISTANCE = 1.75       -- 캐릭터 아래 방향 접지 확인 Raycast 거리

local LOOK_SENSITIVITY = 0.12  -- 마우스 이동량을 Yaw/Pitch 각도로 바꾸는 감도
local MIN_PITCH = -30.0        -- 1인칭 카메라가 위를 볼 수 있는 최소 Pitch. 이 엔진은 음수 Pitch가 위쪽
local MAX_PITCH = 15.0         -- 1인칭 카메라가 아래를 볼 수 있는 최대 Pitch
local CAMERA_HEIGHT = 1.2      -- Root 기준 카메라 피벗 높이
local MAX_TRACE_DISTANCE = 100.0 -- 화면 중앙 조준 Raycast 최대 거리
local BEAM_VISIBLE_TIME = 0.08 -- 발사 Beam을 화면에 유지하는 시간

local WEAPON_FORWARD_OFFSET = 0.85 -- 카메라 로컬 Forward 기준 총 화면 위치
local WEAPON_RIGHT_OFFSET = 0.40   -- 카메라 로컬 Right 기준 총 화면 위치
local WEAPON_UP_OFFSET = -0.20     -- 카메라 로컬 Up 기준 총 화면 위치. 음수면 화면 아래
local WEAPON_PITCH_SCALE = 0.01    -- 카메라 Pitch가 총 시각 PitchPivot에 전달되는 비율
local WEAPON_MAX_VISUAL_PITCH = 1.0 -- 총 시각 PitchPivot이 추가로 회전할 수 있는 최대 각도
local WEAPON_PITCH_NORMALIZE = 80.0 -- Pitch 보정 곡선을 만들 때 정규화 기준으로 쓰는 카메라 Pitch
local WEAPON_PITCH_PULLBACK = 0.05  -- 극단 Pitch에서 총을 카메라 쪽으로 살짝 당기는 Forward 보정량
local WEAPON_PITCH_INWARD_OFFSET = 0.00 -- 극단 Pitch에서 총을 화면 안쪽으로 넣는 Right 보정량
local WEAPON_PITCH_UP_OFFSET = 0.04 -- 위/아래를 볼 때 총 화면 위치를 카메라 Up 방향으로 보정하는 양

local GUN_ROTATION_ROLL = -18.087906  -- GunMesh 기본 Roll. 씬에 GunMesh가 없을 때 fallback
local GUN_ROTATION_PITCH = -2.707027  -- GunMesh 기본 Pitch. 씬에 GunMesh가 없을 때 fallback
local GUN_ROTATION_YAW = -3.752036    -- GunMesh 기본 Yaw. 씬에 GunMesh가 없을 때 fallback
local MUZZLE_FORWARD_OFFSET = 0.95    -- MuzzlePoint 기본 Forward 위치. 씬에 MuzzlePoint가 없을 때 fallback
local MUZZLE_RIGHT_OFFSET = 0.0       -- MuzzlePoint 기본 Right 위치. 씬에 MuzzlePoint가 없을 때 fallback
local MUZZLE_UP_OFFSET = 0.05         -- MuzzlePoint 기본 Up 위치. 씬에 MuzzlePoint가 없을 때 fallback

local yaw = 0.0        -- 현재 플레이어 Yaw. Actor Root 회전에 적용
local pitch = 0.0      -- 현재 카메라 Pitch. CameraPivot 회전에 적용
local viewport_center_x = 0.0 -- 조준점 기준으로 쓰는 뷰포트 중앙 X
local viewport_center_y = 0.0 -- 조준점 기준으로 쓰는 뷰포트 중앙 Y
local beam_visible_remaining = 0.0 -- Beam을 계속 보이게 유지할 남은 시간
local last_aim_point = nil         -- 마지막 발사 시 카메라 Raycast로 계산한 조준 지점

local root_body = nil            -- PhysX 이동/점프 속도를 적용할 Root PrimitiveComponent
local camera_pivot = nil         -- Pitch 회전을 담당하는 GOIncCameraPivot
local camera = nil               -- 실제 활성 카메라 컴포넌트
local view_weapon_root = nil     -- 카메라 위치/회전에 붙는 1인칭 총 ViewModel 루트
local weapon_visual_pivot = nil  -- 화면 offset과 기본 기울기를 담는 GOIncWeaponVisualPivot
local weapon_pitch_pivot = nil   -- 총의 작은 시각 Pitch 회전 중심인 GOIncWeaponPitchPivot
local gun = nil                  -- 1인칭 총 메시
local muzzle_point = nil         -- Beam 시작점으로 쓰는 총구 위치
local beam_particle = nil        -- 총구에서 조준점까지 그리는 Beam 파티클

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

local function flat_normalized(v)
    local flat = vec(v.X, v.Y, 0.0)
    if flat:Length() > 0.0001 then
        return flat:Normalized()
    end
    return Vector.Zero()
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

local function update_viewport_center()
    local size = Engine.GetViewportSize()
    if size ~= nil then
        viewport_center_x = (size.Width or 0.0) * 0.5
        viewport_center_y = (size.Height or 0.0) * 0.5
    end
end

local function bind_components()
    root_body = obj:GetRootPrimitiveComponent()
    camera_pivot = obj:GetComponentByName("GOIncCameraPivot")
    camera = obj:GetCamera()

    view_weapon_root = obj:GetComponentByName("GOIncViewWeaponRoot")
    weapon_visual_pivot = obj:GetComponentByName("GOIncWeaponVisualPivot")
    weapon_pitch_pivot = obj:GetComponentByName("GOIncWeaponPitchPivot")
    gun = obj:GetComponentByName("GOIncFirstPersonGunMesh")
    muzzle_point = obj:GetComponentByName("GOIncMuzzlePoint")
    beam_particle = obj:GetPrimitiveComponentByName("GOIncBeamParticle")
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
        base_weapon_offset_location = vec(WEAPON_FORWARD_OFFSET, WEAPON_RIGHT_OFFSET, WEAPON_UP_OFFSET)
        base_weapon_visual_rotation = Vector.Zero()
    end

    if weapon_pitch_pivot ~= nil then
        base_weapon_pitch_location = copy_vec(weapon_pitch_pivot.RelativeLocation)
        base_weapon_pitch_rotation = copy_vec(weapon_pitch_pivot.Rotation)
    else
        base_weapon_pitch_location = Vector.Zero()
        base_weapon_pitch_rotation = Vector.Zero()
    end

    if gun ~= nil then
        base_gun_location = copy_vec(gun.RelativeLocation)
        base_gun_rotation = copy_vec(gun.Rotation)
    else
        base_gun_location = Vector.Zero()
        base_gun_rotation = vec(GUN_ROTATION_ROLL, GUN_ROTATION_PITCH, GUN_ROTATION_YAW)
    end

    if muzzle_point ~= nil then
        base_muzzle_location = copy_vec(muzzle_point.RelativeLocation)
        base_muzzle_rotation = copy_vec(muzzle_point.Rotation)
    else
        base_muzzle_location = vec(MUZZLE_FORWARD_OFFSET, MUZZLE_RIGHT_OFFSET, MUZZLE_UP_OFFSET)
        base_muzzle_rotation = Vector.Zero()
    end

    if beam_particle ~= nil then
        base_beam_location = copy_vec(beam_particle.RelativeLocation)
        base_beam_rotation = copy_vec(beam_particle.Rotation)
    else
        base_beam_location = copy_vec(base_muzzle_location)
        base_beam_rotation = copy_vec(base_muzzle_rotation)
    end
end

local function update_camera_view()
    obj.Rotation = vec(0.0, 0.0, yaw)

    if camera_pivot ~= nil then
        camera_pivot.RelativeLocation = vec(0.0, 0.0, CAMERA_HEIGHT)
        camera_pivot.Rotation = vec(0.0, pitch, 0.0)
    end

    if camera ~= nil then
        camera.RelativeLocation = Vector.Zero()
        camera.Rotation = Vector.Zero()
    end
end

local function update_view_weapon()
    if base_weapon_offset_location == nil then
        cache_view_weapon_base_transforms()
    end

    local pitch_alpha = clamp(pitch / WEAPON_PITCH_NORMALIZE, -1.0, 1.0)
    local pitch_abs = math.abs(pitch_alpha)
    local pitch_curve = pitch_abs * pitch_abs
    local pitch_signed_curve = pitch_curve
    if pitch_alpha < 0.0 then
        pitch_signed_curve = -pitch_curve
    end
    local look_up_curve = -pitch_signed_curve

    local visual_pitch = clamp(pitch * WEAPON_PITCH_SCALE, -WEAPON_MAX_VISUAL_PITCH, WEAPON_MAX_VISUAL_PITCH)
    local weapon_offset = vec(
        base_weapon_offset_location.X - pitch_curve * WEAPON_PITCH_PULLBACK,
        base_weapon_offset_location.Y - pitch_curve * WEAPON_PITCH_INWARD_OFFSET,
        base_weapon_offset_location.Z + look_up_curve * WEAPON_PITCH_UP_OFFSET
    )

    if view_weapon_root ~= nil then
        if camera ~= nil then
            view_weapon_root.Location = camera.Location
        else
            view_weapon_root.RelativeLocation = vec(0.0, 0.0, CAMERA_HEIGHT)
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

    if weapon_pitch_pivot ~= nil then
        weapon_pitch_pivot.RelativeLocation = copy_vec(base_weapon_pitch_location)
        weapon_pitch_pivot.Rotation = vec(
            base_weapon_pitch_rotation.X,
            base_weapon_pitch_rotation.Y + visual_pitch,
            base_weapon_pitch_rotation.Z
        )
    end

    if gun ~= nil then
        gun.RelativeLocation = sub_vec(base_gun_location, base_weapon_pitch_location)
        gun.Rotation = copy_vec(base_gun_rotation)
    end

    if muzzle_point ~= nil then
        muzzle_point.RelativeLocation = sub_vec(base_muzzle_location, base_weapon_pitch_location)
        muzzle_point.Rotation = copy_vec(base_muzzle_rotation)
    end

    if beam_particle ~= nil then
        beam_particle.RelativeLocation = sub_vec(base_beam_location, base_weapon_pitch_location)
        beam_particle.Rotation = copy_vec(base_beam_rotation)
    end
end

local function get_camera_aim_point()
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
    local fallback_end = start + direction * MAX_TRACE_DISTANCE

    if World ~= nil and World.PhysicsRaycast ~= nil then
        local hit = World.PhysicsRaycast(start, direction, MAX_TRACE_DISTANCE, obj)
        if hit ~= nil then
            if hit.bHit and hit.Location ~= nil then
                return hit.Location
            end
            if hit.End ~= nil then
                return hit.End
            end
        end
    end

    return fallback_end
end

local function set_beam_visible(is_visible)
    if beam_particle == nil then
        return
    end

    beam_particle:SetVisibility(is_visible)
    beam_particle:SetActive(is_visible)
end

local function update_beam_points(aim_point)
    if beam_particle == nil or muzzle_point == nil then
        return
    end

    local muzzle_location = muzzle_point.Location
    beam_particle.Location = muzzle_location

    if beam_particle.SetBeamSourcePoint ~= nil then
        beam_particle:SetBeamSourcePoint(muzzle_location, 0)
    end
    if beam_particle.SetBeamTargetPoint ~= nil then
        beam_particle:SetBeamTargetPoint(aim_point, 0)
    end
end

local function apply_first_person_view()
    local mouse_x = Input.GetMouseDeltaX()
    local mouse_y = Input.GetMouseDeltaY()

    yaw = yaw + mouse_x * LOOK_SENSITIVITY
    pitch = clamp(pitch + mouse_y * LOOK_SENSITIVITY, MIN_PITCH, MAX_PITCH)

    update_camera_view()
    update_view_weapon()
end

local function is_grounded(velocity)
    if World ~= nil and World.PhysicsRaycast ~= nil then
        local hit = World.PhysicsRaycast(obj.Location, Vector.Down(), GROUND_CHECK_DISTANCE, obj)
        return hit ~= nil and hit.bHit
    end

    return math.abs(velocity.Z) <= GROUNDED_Z_VELOCITY_EPSILON
end

local function apply_physics_movement()
    local forward = flat_normalized(obj.Forward)
    local right = flat_normalized(obj.Right)
    local move_dir = Vector.Zero()

    if Input.GetKey(KEY_W) then
        move_dir = move_dir + forward
    end
    if Input.GetKey(KEY_S) then
        move_dir = move_dir - forward
    end
    if Input.GetKey(KEY_D) then
        move_dir = move_dir + right
    end
    if Input.GetKey(KEY_A) then
        move_dir = move_dir - right
    end

    if root_body ~= nil then
        local velocity = root_body:GetLinearVelocity()
        local horizontal_velocity = Vector.Zero()

        if move_dir:Length() > 0.0001 then
            horizontal_velocity = move_dir:Normalized() * MOVE_SPEED
        end

        velocity.X = horizontal_velocity.X
        velocity.Y = horizontal_velocity.Y

        if Input.GetKeyDown(KEY_SPACE) and is_grounded(velocity) then
            velocity.Z = JUMP_VELOCITY
        end

        root_body:SetLinearVelocity(velocity)
        root_body:SetAngularVelocity(Vector.Zero())
    end
end

local function apply_fire(delta_time)
    if beam_visible_remaining > 0.0 then
        beam_visible_remaining = beam_visible_remaining - delta_time
        if last_aim_point ~= nil then
            update_beam_points(last_aim_point)
        end
        if beam_visible_remaining <= 0.0 then
            set_beam_visible(false)
        end
    end

    if not Input.GetKeyDown(KEY_LBUTTON) then
        return
    end

    last_aim_point = get_camera_aim_point()

    if beam_particle ~= nil and beam_particle.ResetParticleSystem ~= nil then
        beam_particle:ResetParticleSystem()
    end

    update_beam_points(last_aim_point)
    set_beam_visible(true)
    beam_visible_remaining = BEAM_VISIBLE_TIME
end

function BeginPlay()
    update_viewport_center()

    local current_rotation = obj.Rotation
    yaw = current_rotation.Z

    bind_components()
    cache_view_weapon_base_transforms()

    if root_body ~= nil then
        root_body:SetSimulatePhysics(true)
    end

    update_camera_view()
    update_view_weapon()
    set_beam_visible(false)

    if camera ~= nil then
        CameraManager.SetActiveCameraWithBlend(camera, 0.0)
        CameraManager.PossessCamera(camera)
    end

    print("[GOInc] viewport center: " .. viewport_center_x .. ", " .. viewport_center_y)
    print("[GOInc] camera aim and view weapon separated")
end

function Tick(delta_time)
    apply_first_person_view()
    apply_physics_movement()
    apply_fire(delta_time)
end
