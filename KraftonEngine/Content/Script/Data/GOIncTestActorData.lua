-- ==========================================================================
-- GOIncTestActorData — GOIncTestActor(1인칭 플레이어) 튜닝 상수 (require 모듈, 읽기 전용)
-- [역할] 이동/점프 물리, 시점, 크로스헤어, 빔/히트 연출, 그랩/던지기, 무기 ViewModel 튜닝값.
-- [사용법] local C = require("Data/GOIncTestActorData")
-- [특이사항] GOIncTestActor.lua 전용. top-level local 200개 리밋을 피하려고 상수만 분리.
--            이 파일 저장 시 모듈 캐시는 비워지지만 액터가 이미 든 참조는 다음 씬 로드부터
--            반영된다. 즉시 반영하려면 GOIncTestActor.lua를 재저장(touch)해 액터를 리로드.
-- ==========================================================================

-- 파생 상수의 기준값. 테이블 생성자 안에서는 자기 필드 참조가 불가해 local로 선행 정의한다
local MAX_TRACE_DISTANCE = 15.0 -- 화면 중앙 조준 Raycast 최대 거리
local BEAM_VISIBLE_TIME = 0.08 -- 발사 Beam을 화면에 유지하는 시간

return {
    KEY_W = 0x57,       -- 전진 입력 키: W
    KEY_A = 0x41,       -- 좌측 이동 입력 키: A
    KEY_S = 0x53,       -- 후진 입력 키: S
    KEY_D = 0x44,       -- 우측 이동 입력 키: D
    KEY_SPACE = 0x20,   -- 점프 입력 키: Space
    KEY_SHIFT = 0x10,   -- 달리기 입력 키: Shift
    KEY_LBUTTON = 0x01, -- 발사 입력 키: 마우스 왼쪽 버튼
    KEY_Q = 0x51,       -- 무기 교체 입력 키: Q

    -- 게임패드 (XInput VK 코드 — Input.GetKey* 그대로 사용 가능. 이동/시점은 스틱 축 별도)
    PAD_KEY_A  = 0xC3, -- A 버튼: 점프 (메뉴에선 엔진이 왼클릭으로 합성)
    PAD_KEY_Y  = 0xC6, -- Y 버튼: 무기 교체
    PAD_KEY_RT = 0xCA, -- 오른쪽 트리거(임계값 디지털): 그랩/발사
    PAD_KEY_LB = 0xC8, -- 왼쪽 숄더: 그랩 거리 가까이
    PAD_KEY_LT = 0xC9, -- 왼쪽 트리거(임계값 디지털): 그랩 거리 멀리
    PAD_KEY_L3 = 0xD1, -- 왼쪽 스틱 클릭(L3): 대쉬 — 누르고 있는 동안 이동 속도 배수
    PAD_LOOK_YAW_DEG_PER_SEC   = 180.0, -- 우스틱 풀기울임 시 좌우 회전 속도(도/초)
    PAD_LOOK_PITCH_DEG_PER_SEC = 120.0, -- 우스틱 풀기울임 시 상하 회전 속도(도/초). 위로 밀면 위를 본다
    PAD_DISTANCE_NOTCHES_PER_SEC = 6.0, -- LB/LT를 누르고 있는 동안 초당 휠 노치 환산량

    CROSSHAIR_HOLD_ROTATION_INTERVAL = 0.08,
    CROSSHAIR_HOLD_ROTATION_STEP = 18.0,
    COLLECT_FIRE_SFX_INTERVAL = 0.10,
    COLLECT_FIRE_SFX_VOLUME_SCALE = 0.5,
    FOOTSTEP_SFX_INTERVAL = 0.35,
    FOOTSTEP_SFX_VOLUME_SCALE = 1.0,
    TARGET_INFO_FALLBACK_IMAGE_PATH = "../../Sprite/Ragdoll_Image/ragdoll_sample.png",

    MOVE_SPEED = 6.0,                   -- WASD 수평 이동 속도
    SPRINT_SPEED_MULTIPLIER = 2.0,      -- Shift를 누른 채 이동할 때 수평 속도 배율
    DASH_SPEED_MULTIPLIER = 1.7,        -- L3(왼쪽 스틱 클릭) 누르고 있을 때 이동 속도 배수 (대쉬)
    JUMP_VELOCITY = 6.5,                -- Space 입력 시 Lua가 보관하는 Z 속도에 넣는 점프 속도
    GRAVITY_ACCELERATION = 9.8,         -- PhysX 시뮬레이션 대신 엔진 쪽 이동에서 직접 적용할 중력 가속도
    PLAYER_CAPSULE_HALF_HEIGHT = 1.0,   -- GOIncRoot 캡슐의 실제 월드 반높이. Scene의 HalfHeight 2.0 * ScaleZ 0.5
    PLAYER_CAPSULE_RADIUS = 0.5,        -- GOIncRoot 캡슐의 실제 월드 반지름. Scene의 Radius 1.0 * ScaleXY 0.5
    GROUND_PROBE_DISTANCE = 0.18,       -- 캡슐 바닥 아래로 더 확인할 여유 거리. 너무 크면 낮은 단차에 과하게 붙는다
    GROUND_WALKABLE_NORMAL_Z = 0.55,    -- 이 값보다 위를 향한 표면만 바닥으로 취급해 벽/측면 hit를 배제
    CAPSULE_SWEEP_SKIN = 0.04,          -- CapsuleSweep 결과에서 벽에 딱 붙지 않게 남기는 최소 여유
    CAPSULE_SWEEP_MIN_MOVE = 0.0001,    -- 너무 작은 이동량은 sweep을 생략해 떨림을 줄인다
    GROUNDED_Z_VELOCITY_EPSILON = 0.05, -- Raycast가 없을 때 접지 판정에 쓰는 Z 속도 허용값

    LOOK_SENSITIVITY = 0.2,  -- 마우스 이동량을 Yaw/Pitch 각도로 바꾸는 감도
    MIN_PITCH = -75.0,        -- 1인칭 카메라가 위를 볼 수 있는 최소 Pitch. 이 엔진은 음수 Pitch가 위쪽
    MAX_PITCH = 75.0,         -- 1인칭 카메라가 아래를 볼 수 있는 최대 Pitch
    CAMERA_HEIGHT = 1.2,      -- Root 기준 카메라 피벗 높이
    MAX_TRACE_DISTANCE = MAX_TRACE_DISTANCE,
    FRONT_HIT_DISTANCE_EPSILON = 0.05, -- Extra range so a physics hit on the same front surface still wins
    BEAM_VISIBLE_TIME = BEAM_VISIBLE_TIME,
    SLOT2_BEAM_MISS_VISIBLE_TIME = BEAM_VISIBLE_TIME, -- Slot2가 아무것도 맞추지 못했을 때는 기존처럼 짧게 표시
    SLOT2_BEAM_HIT_VISIBLE_TIME = BEAM_VISIBLE_TIME, -- Slot2는 hit/miss 모두 플래시처럼 짧게 표시
    SLOT1_GATHER_FX_PATH = "Content/Particle/FX_MuzzleGlowSphereCyan.uasset", -- Weapon1 홀드 중 Beam Src/총구에 붙여두는 시안 메시 글로우
    SLOT1_GATHER_FX_SOURCE_OFFSET = 0.00, -- Beam Src에서 Dst 방향으로 살짝 띄워 무기 끝에 딱 달라붙지 않게 한다
    SLOT1_TARGET_GATHER_FX_PATH = "Content/Particle/FX_GatherLoopRed.uasset", -- Weapon1 홀드 중 Beam Dst/조준점에 붙여두는 빨간 GatherLoop. Src FX처럼 새 잔상을 뿌리지 않고 위치만 따라간다
    SLOT2_MUZZLE_FX_PATH = "Content/Particle/FX_MuzzleGlowSphere.uasset", -- Weapon2 발사 순간 총구에 한 번 터지는 빨간 메시 글로우
    SLOT2_MUZZLE_FX_VISIBLE_TIME = 0.10, -- Weapon2 발사 글로우가 총구를 따라가는 시간. 기존 FX가 있으면 Reset하고 없으면 Weapon1처럼 생성한다
    SLOT2_BEAM_MATERIAL_PATH = "Content/Material/Auto/BeamPink.mat", -- Weapon2 LMB 빔 색. SectionColor = 5, 0.1, 2.5 핑크 계열
    SLOT2_HIT_SPARK_FX_PATH = "Content/Particle/FX_SparkLoopRed.uasset", -- Slot2 빔이 실제 표면을 맞춘 위치에 터뜨리는 스파크
    SLOT2_HIT_SPARK_SURFACE_OFFSET = 0.0, -- 빔 Dst와 완전히 같은 위치에 생성한다. 경로 중간처럼 보이면 이 값을 0으로 유지한다
    SLOT2_KNOCKBACK_IMPULSE_PER_MASS = 4.00, -- Slot2 피격 순간에만 주는 넉백. 질량을 곱해 크기 차이와 무관하게 반응이 보이게 한다
    SLOT2_KNOCKBACK_UP_BIAS = 2.50, -- 빔 방향에 위쪽을 섞어 뒤로 밀리면서 살짝 뜨는 느낌을 만든다
    SLOT2_RAGDOLL_KNOCKBACK_IMPULSE_PER_MASS = 8.00, -- Skeletal ragdoll은 중심 body와 전체 body에 분산해서 확실한 반응을 만든다
    SLOT2_RAGDOLL_KNOCKBACK_CENTER_BODY_SCALE = 0.85, -- 본 이름 대신 컴포넌트 동기화용 중심 body에 적용할 배율
    SLOT2_RECOIL_PITCH_DEGREES = -0.62, -- 발사 순간 카메라가 위로 짧게 튀는 값. 이 엔진은 음수 Pitch가 위쪽
    SLOT2_RECOIL_YAW_RANDOM_DEGREES = 0.22, -- 발사마다 좌우로 아주 작게 달라지는 카메라 킥
    SLOT2_RECOIL_RECOVER_TIME = 0.06, -- 카메라 킥이 원위치로 돌아오는 시간
    SLOT2_CAMERA_SHAKE_DURATION = 0.065, -- CameraPivot 위치 shake 지속 시간
    SLOT2_CAMERA_SHAKE_INTENSITY = 0.075, -- CameraPivot 위치 shake 기본 크기. 앞뒤 감각은 유지하고 좌우/상하 체감을 보강
    SLOT2_CAMERA_SHAKE_FORWARD_SCALE = 0.50, -- 앞뒤 shake 배율
    SLOT2_CAMERA_SHAKE_RIGHT_SCALE = 1.05, -- 좌우 shake 배율
    SLOT2_CAMERA_SHAKE_UP_SCALE = 0.55, -- 상하 shake 배율
    SLOT2_CAMERA_SHAKE_ROTATION_DEGREES = 0.24, -- 위치 shake에 더해 CameraPivot에 아주 짧게 주는 회전 흔들림
    SLOT2_FOV_PUNCH_DEGREES = 1.50, -- 발사 순간 FOV가 잠깐 넓어지는 정도
    SLOT2_FOV_PUNCH_DURATION = 0.08, -- FOV punch가 돌아오는 시간
    HIT_RIM_DURATION = 0.50,
    HIT_RIM_FLASH_INTENSITY = 3.5,
    HIT_RIM_SUSTAIN_INTENSITY = 1.6,
    HIT_RIM_POWER = 2.8,
    SLOT2_HIT_RIM_FLASH_INTENSITY = 1.35,
    SLOT2_HIT_RIM_SUSTAIN_INTENSITY = 0.55,
    SLOT2_HIT_IMPACT_INTENSITY = 0.85,
    HIT_RIM_STYLE_NOISE = 0.0,
    HIT_RIM_STYLE_SCAN_LINES = 1.0,
    SLOT1_HIT_RIM_COLOR_R = 0.05,
    SLOT1_HIT_RIM_COLOR_G = 0.85,
    SLOT1_HIT_RIM_COLOR_B = 1.00,
    SLOT1_HIT_RIM_COLOR_A = 1.00,
    -- RedBeam particle color ratio is about (5.0, 0.1, 2.5), normalized here for rim tint.
    SLOT2_HIT_RIM_COLOR_R = 1.00,
    SLOT2_HIT_RIM_COLOR_G = 0.18,
    SLOT2_HIT_RIM_COLOR_B = 0.76,
    SLOT2_HIT_RIM_COLOR_A = 1.00,
    HIT_SCAN_LINE_DENSITY = 18.0,
    HIT_SCAN_SCROLL_SPEED = 2.00,
    HIT_IMPACT_RADIUS = 0.16,
    HIT_IMPACT_CORE_RADIUS = 0.055,
    HIT_IMPACT_INTENSITY = 2.6,
    SLOT1_GRAB_FORCE_SCALE = 25.00, -- Weapon1 그랩 최종 힘 배율. 질량 값은 그대로 두고 끌어오는 힘만 더 키우고 싶을 때 조정한다
    GRAB_SPRING_ACCELERATION = 42.0, -- 목표 위치로 끌어당기는 가속도 계수. 질량 보정 전 단계에서 사용한다
    GRAB_DAMPING_ACCELERATION = 10.0, -- 현재 속도에 대한 감쇠 가속도 계수. 높을수록 덜 출렁인다
    GRAB_MAX_ERROR = 30.0,
    GRAB_MAX_ACCELERATION = 140.0,
    GRAB_TORQUE_SCALE = 0.25,
    GRAB_ANGULAR_DAMPING = 10.0,
    GRAB_MAX_TORQUE = 100000.0,
    STATIC_GRAB_FORCE_SCALE = 0.10, -- StaticMesh는 단일 바디라 Slot1 힘을 크게 낮춰 과한 가속을 막는다
    STATIC_GRAB_MAX_ACCELERATION = 30.0, -- StaticMesh center grab 전용 가속도 상한. Ragdoll보다 훨씬 보수적으로 둔다
    STATIC_GRAB_MAX_TORQUE = 0.0, -- StaticMesh는 표면 offset torque를 끄고 중심점만 당긴다
    GRAB_REFERENCE_MASS = 18.0, -- 이 질량은 grip scale 1.0으로 취급한다
    GRAB_MASS_POWER = 0.50, -- 질량 차이가 grip 난이도로 반영되는 곡선. 클수록 무거운 랙돌이 더 둔해진다
    GRAB_MIN_MASS_SCALE = 0.35,
    GRAB_MAX_MASS_SCALE = 1.35,
    GRAB_MIN_AIM_DISTANCE = 0.35,
    GRAB_MIN_ACTOR_DISTANCE = 5,
    GRAB_MAX_AIM_DISTANCE = MAX_TRACE_DISTANCE,
    GRAB_MOUSE_WHEEL_DISTANCE_STEP = 1.25,
    GRAB_MIN_DISTANCE_GUARD_ACCELERATION = 8.0, -- 최소 거리 안쪽으로 들어온 grab point를 부드럽게 밖으로 되돌리는 보정
    GRAB_MIN_DISTANCE_GUARD_DAMPING = 2.0, -- 안쪽으로 파고드는 속도에만 붙는 추가 보정
    GRAB_MIN_DISTANCE_GUARD_MAX_ACCELERATION = 14.0, -- guard가 랙돌을 과하게 밀어내지 않도록 별도 상한을 둔다
    THROW_IMPULSE_SCALE = 0.35,
    THROW_MAX_IMPULSE_PER_MASS = 120.0,
    THROW_MIN_SPEED = 0.5,

    WEAPON_FORWARD_OFFSET = 0.85, -- 카메라 로컬 Forward 기준 총 화면 위치
    WEAPON_RIGHT_OFFSET = 0.40,   -- 카메라 로컬 Right 기준 총 화면 위치
    WEAPON_UP_OFFSET = -0.20,     -- 카메라 로컬 Up 기준 총 화면 위치. 음수면 화면 아래
    WEAPON_PITCH_SCALE = 0.01,    -- 카메라 Pitch가 총 시각 PitchPivot에 전달되는 비율
    WEAPON_MAX_VISUAL_PITCH = 2.0, -- 총 시각 PitchPivot이 추가로 회전할 수 있는 최대 각도
    WEAPON_PITCH_NORMALIZE = 80.0, -- Pitch 보정 곡선을 만들 때 정규화 기준으로 쓰는 카메라 Pitch
    WEAPON_PITCH_DRIVER_MIN = -35.0, -- 카메라 범위가 더 넓어져도 총 ViewModel은 이 Pitch까지만 따라간다
    WEAPON_PITCH_DRIVER_MAX = 35.0, -- 아래 보기에서도 총 손잡이가 과하게 드러나지 않도록 총 보정 범위를 분리한다
    WEAPON_PITCH_PULLBACK = 0.05,  -- 극단 Pitch에서 총을 카메라 쪽으로 살짝 당기는 Forward 보정량
    WEAPON_PITCH_INWARD_OFFSET = 0.00, -- 극단 Pitch에서 총을 화면 안쪽으로 넣는 Right 보정량
    WEAPON_PITCH_UP_OFFSET = 0.04, -- 위/아래를 볼 때 총 화면 위치를 카메라 Up 방향으로 보정하는 양
    WEAPON_EXTRA_LOOK_UP_Z_OFFSET = 0.08, -- 카메라가 총 회전 한계보다 더 위를 볼 때 총을 화면 위쪽으로 조금 더 보정한다
    WEAPON_EXTRA_LOOK_DOWN_Z_OFFSET = -0.08, -- 카메라가 총 회전 한계보다 더 아래를 볼 때 총을 화면 아래쪽으로 더 강하게 보정한다
    WEAPON_WALK_BOB_MIN_SPEED = 0.2, -- 이 속도보다 느리면 걷기 무기 흔들림을 끈다
    WEAPON_WALK_BOB_BLEND_SPEED = 2.0, -- 걷기 시작/정지 시 무기 흔들림이 붙고 빠지는 속도
    WEAPON_WALK_BOB_FREQUENCY = 3.0, -- 걷기 무기 흔들림 위상 속도(rad/sec)
    WEAPON_WALK_BOB_FORWARD = 0.012, -- 걷기 중 총이 카메라 Forward 축으로 앞뒤 움직이는 폭
    WEAPON_WALK_BOB_RIGHT = 0.022,   -- 걷기 중 총이 카메라 Right 축으로 좌우 움직이는 폭
    WEAPON_WALK_BOB_UP = 0.030,      -- 걷기 중 총이 카메라 Up 축으로 상하 움직이는 폭
    WEAPON_WALK_BOB_ROLL = 0.55,     -- 걷기 중 총 VisualPivot에 더하는 Roll 흔들림(deg)
    WEAPON_WALK_BOB_PITCH = 0.35,    -- 걷기 중 총 VisualPivot에 더하는 Pitch 흔들림(deg)
    WEAPON_WALK_BOB_YAW = 0.30,      -- 걷기 중 총 VisualPivot에 더하는 Yaw 흔들림(deg)
    WEAPON_SPRINT_BLEND_SPEED = 7.0,      -- 달리기 시작/해제 시 총 내림 연출이 섞이는 속도
    WEAPON_SPRINT_BOB_FREQUENCY_SCALE = 1.45, -- 달릴 때 걷기 Bob 템포 배율
    WEAPON_SPRINT_BOB_AMPLITUDE_SCALE = 0.55, -- 달릴 때 Bob 폭을 얕게 줄이는 배율
    WEAPON_SPRINT_LOWER_FORWARD = -0.025, -- 달릴 때 총을 카메라 쪽으로 살짝 당긴다
    WEAPON_SPRINT_LOWER_RIGHT = 0.0,      -- 달릴 때 총 좌우 기준 위치 보정
    WEAPON_SPRINT_LOWER_UP = -0.085,      -- 달릴 때 총을 화면 아래로 내리는 양
    WEAPON_SPRINT_LOWER_ROLL = 0.0,       -- 달릴 때 총 기본 Roll 보정
    WEAPON_SPRINT_LOWER_PITCH = 1.1,      -- 달릴 때 총을 살짝 아래로 숙이는 Pitch 보정
    WEAPON_SPRINT_LOWER_YAW = 0.0,        -- 달릴 때 총 기본 Yaw 보정
    WEAPON_SWAP_DURATION = 0.28,
    WEAPON_SWAP_ROTATION_DEGREES = 180.0,
    WEAPON_SWAP_DIRECTION = -1.0,

    GUN_ROTATION_ROLL = -18.087906,  -- GunMesh 기본 Roll. 씬에 GunMesh가 없을 때 fallback
    GUN_ROTATION_PITCH = -2.707027,  -- GunMesh 기본 Pitch. 씬에 GunMesh가 없을 때 fallback
    GUN_ROTATION_YAW = -3.752036,    -- GunMesh 기본 Yaw. 씬에 GunMesh가 없을 때 fallback
    MUZZLE_FORWARD_OFFSET = 0.95,    -- MuzzlePoint 기본 Forward 위치. 씬에 MuzzlePoint가 없을 때 fallback
    MUZZLE_RIGHT_OFFSET = 0.0,       -- MuzzlePoint 기본 Right 위치. 씬에 MuzzlePoint가 없을 때 fallback
    MUZZLE_UP_OFFSET = 0.05,         -- MuzzlePoint 기본 Up 위치. 씬에 MuzzlePoint가 없을 때 fallback
    MUZZLE_FORWARD_EXTRA_OFFSET = 1.50, -- 씬 MuzzlePoint 기준에서 Forward 방향으로 더하는 런타임 보정. Beam Src는 최종 MuzzlePoint 위치를 그대로 쓴다
    BEAM_RENDER_SHEETS = 1, -- GOInc 빔은 한 줄 레이저로 보여야 하므로 Beam sheet를 1장으로 고정
    BEAM_SOURCE_TANGENT_STRENGTH_SCALE = 0.12, -- Src에서 총구 Forward를 따라가는 곡선 길이 비율
    BEAM_TARGET_TANGENT_STRENGTH_SCALE = 0.08, -- Dst 도착부가 과하게 휘지 않게 낮게 둔 곡선 길이 비율

    UpdateWeaponWalkBob = function(self, delta_time, velocity, state, make_vec, clamp_value, is_sprinting)
        local dt = math.max(delta_time or 0.0, 0.0)
        local vx = velocity and velocity.X or 0.0
        local vy = velocity and velocity.Y or 0.0
        local horizontal_speed = math.sqrt(vx * vx + vy * vy)
        local target_weight = 0.0
        local sprint_target_weight = 0.0

        state.walk_weight = state.walk_weight or 0.0
        state.walk_phase = state.walk_phase or 0.0
        state.sprint_weight = state.sprint_weight or 0.0

        if horizontal_speed > self.WEAPON_WALK_BOB_MIN_SPEED then
            target_weight = clamp_value(horizontal_speed / self.MOVE_SPEED, 0.0, 1.0)
        end
        if is_sprinting and target_weight > 0.0 then
            sprint_target_weight = 1.0
        end

        local blend_alpha = clamp_value(dt * self.WEAPON_WALK_BOB_BLEND_SPEED, 0.0, 1.0)
        state.walk_weight = state.walk_weight + (target_weight - state.walk_weight) * blend_alpha

        local sprint_blend_alpha = clamp_value(dt * self.WEAPON_SPRINT_BLEND_SPEED, 0.0, 1.0)
        state.sprint_weight = state.sprint_weight
            + (sprint_target_weight - state.sprint_weight) * sprint_blend_alpha

        if state.walk_weight > 0.001 then
            local sprint_tempo_scale = 1.0
                + (self.WEAPON_SPRINT_BOB_FREQUENCY_SCALE - 1.0) * state.sprint_weight
            local stride_scale = (0.75 + target_weight * 0.25) * sprint_tempo_scale
            state.walk_phase = state.walk_phase + dt * self.WEAPON_WALK_BOB_FREQUENCY * stride_scale
        else
            state.walk_phase = 0.0
            state.walk_weight = 0.0
        end

        local side = math.sin(state.walk_phase)
        local step = math.sin(state.walk_phase * 2.0)
        local sprint_amplitude_scale = 1.0
            + (self.WEAPON_SPRINT_BOB_AMPLITUDE_SCALE - 1.0) * state.sprint_weight
        local weight = state.walk_weight * sprint_amplitude_scale

        return make_vec(
            step * self.WEAPON_WALK_BOB_FORWARD * weight
                + self.WEAPON_SPRINT_LOWER_FORWARD * state.sprint_weight,
            side * self.WEAPON_WALK_BOB_RIGHT * weight
                + self.WEAPON_SPRINT_LOWER_RIGHT * state.sprint_weight,
            -math.abs(step) * self.WEAPON_WALK_BOB_UP * weight
                + self.WEAPON_SPRINT_LOWER_UP * state.sprint_weight
        ), make_vec(
            -side * self.WEAPON_WALK_BOB_ROLL * weight
                + self.WEAPON_SPRINT_LOWER_ROLL * state.sprint_weight,
            step * self.WEAPON_WALK_BOB_PITCH * weight
                + self.WEAPON_SPRINT_LOWER_PITCH * state.sprint_weight,
            side * self.WEAPON_WALK_BOB_YAW * weight
                + self.WEAPON_SPRINT_LOWER_YAW * state.sprint_weight
        )
    end,

    ComputeGrabMassGripScale = function(self, body_mass, catalog_mass)
        local mass = catalog_mass
        if type(mass) ~= "number" or mass <= 0.001 then
            mass = body_mass
        end
        if type(mass) ~= "number" or mass <= 0.001 then
            return 1.0
        end

        local reference_mass = math.max(self.GRAB_REFERENCE_MASS or 18.0, 0.001)
        local power = self.GRAB_MASS_POWER or 0.5
        local scale = (reference_mass / math.max(mass, 0.001)) ^ power

        if scale < self.GRAB_MIN_MASS_SCALE then
            return self.GRAB_MIN_MASS_SCALE
        end
        if scale > self.GRAB_MAX_MASS_SCALE then
            return self.GRAB_MAX_MASS_SCALE
        end
        return scale
    end,
}
