-- GOIncRagdollPawn_Test.lua
--
-- Test script for AGOIncRagdollPawn.
-- C++ exposes component APIs; this script owns the DeadRagdoll -> Reviving -> AliveFlee -> FleeStopping -> DeadRagdoll state flow.
--
-- Hotkeys:
--   R    : toggle DeadRagdoll / Reviving / FleeStopping
--   WASD : fallback move direction while AliveFlee

local STATE_DEAD = "DeadRagdoll"
local STATE_REVIVING = "Reviving"
local STATE_ALIVE = "AliveFlee"
local STATE_FLEE_STOPPING = "FleeStopping"

local SYNC_BONE_NAME = "Pelvis"
local PLAYER_TAG = "Player"
local BEAM_BLOCK_REVIVE_TAG = "NoReviveWhileBeamed"
local RED_BEAM_KILLED_TAG = "KilledByRedBeam"
local BEAM_SHOCK_INTERVAL = 0.05
local BEAM_SHOCK_IMPULSE_STRENGTH = 0.00
local RED_BEAM_SHOCK_DURATION = 1.0
local RED_BEAM_SHOCK_INTERVAL = 0.05
local RED_BEAM_SHOCK_IMPULSE_STRENGTH = 0.08
local RED_BEAM_JITTER_LINEAR_STRENGTH = 0.015
local RED_BEAM_JITTER_TORQUE_STRENGTH = 0.55
local RED_BEAM_JITTER_ROOT_SCALE = 0.08
local RED_BEAM_JITTER_MAX_LINEAR_SPEED = 0.30

-- Player와의 수평 거리가 이 값 이상이면 바로 ragdoll이 아니라 감속 상태로 진입한다.
local FLEE_END_DISTANCE = 10.0

-- FleeStopping 설정값.
-- 거리 조건을 만족하면 이 시간 동안 이동 입력을 끊고 감속한다.
-- animation play rate도 남은 시간 비율에 맞춰 1.0 -> 0.0으로 내려간 뒤 ragdoll로 전환한다.
local FLEE_STOP_DURATION = 1.0
local FLEE_STOP_MIN_BRAKING_DECELERATION = 0.1

-- FleeStopping 중 flee animation play rate 범위.
-- SetPlayRate Lua binding이 없으면 로그만 찍고 이동/상태 전환은 그대로 동작한다.
local FLEE_ANIMATION_BASE_SPEED = 4.0
local FLEE_ANIMATION_MIN_PLAY_RATE = 0.0
local FLEE_ANIMATION_MAX_PLAY_RATE = 1.0
local FLEE_STOP_START_PLAY_RATE = 1.0
local FLEE_STOP_END_PLAY_RATE = 0.0

-- C++에 mesh:IsRagdollRecovering() 바인딩이 있으면 그 값을 우선 사용한다.
-- 바인딩이 아직 없을 때만 fallback timer로 AliveFlee에 들어간다.
local REVIVE_BLEND_DURATION = 0.8
local REVIVE_BLEND_FALLBACK_DURATION = REVIVE_BLEND_DURATION
local REVIVE_MIN_WAIT_TIME = 0.08

local pawn = nil
local capsule = nil          -- Alive collision / root capsule. 새 C++ 패치가 없으면 기존 CapsuleComponent를 사용한다.
local reviveTrigger = nil    -- Player overlap trigger. 새 C++ 패치가 없으면 capsule과 동일하게 fallback한다.
local mesh = nil
local movement = nil
local player = nil
local state = STATE_DEAD

local initialMeshRelativeLocation = nil
local initialMeshWorldOffsetFromActor = nil

local fleeStopElapsed = 0.0
local fleeStopStartSpeed = 0.0
local pendingDeadReason = nil
local reviveElapsed = 0.0
local reviveStartYaw = 0.0
local reviveTargetYaw = 0.0
local currentFleeAnimationPlayRate = 1.0
local bWarnedMissingSetPlayRate = false
local bWarnedMissingBeamShockImpulse = false
local beamShockElapsed = BEAM_SHOCK_INTERVAL
local redBeamShockRemaining = 0.0
local redBeamShockElapsed = RED_BEAM_SHOCK_INTERVAL
local bKilledByRedBeam = false

local FLEE_ROTATION_YAW_OFFSET_DEGREES = 0.0

-- SpawnManager가 RagdollId를 넣어주면 그 id를 쓰고,
-- 씬에 직접 배치된 테스트 Pawn처럼 id가 없으면 기본 Sonic id로 fallback한다.
-- 런타임 에셋/캡슐/이동 값의 정본은 C++ CharacterConfig다.
local DEFAULT_RAGDOLL_ID = "blue-speedster"
local RAGDOLL_ID = DEFAULT_RAGDOLL_ID
local bRuntimeConfigCached = false
local bCanRevive = true
local canReviveHere = true
local aliveCapsuleHalfHeight = 1.0

local GROUND_TRACE_UP = 50.0
local GROUND_TRACE_DOWN = 300.0


local function is_valid(value)
    return value ~= nil and (value.IsValid == nil or value:IsValid())
end

local function is_player_actor(actor)
    return is_valid(actor) and actor.HasTag ~= nil and actor:HasTag(PLAYER_TAG)
end

local function get_actor_debug_name(actor)
    if not is_valid(actor) then
        return "nil"
    end

    if actor.GetName ~= nil then
        local ok, name = pcall(function()
            return actor:GetName()
        end)

        if ok and name ~= nil then
            return tostring(name)
        end
    end

    return tostring(actor)
end

local function is_revive_blocked_by_beam()
    return is_valid(obj) and obj.HasTag ~= nil and obj:HasTag(BEAM_BLOCK_REVIVE_TAG)
end

local function is_revive_blocked()
    if bKilledByRedBeam then
        return true
    end

    if is_valid(obj) and obj.HasTag ~= nil then
        if obj:HasTag(RED_BEAM_KILLED_TAG) then
            return true
        end

        if obj:HasTag(BEAM_BLOCK_REVIVE_TAG) then
            return true
        end
    end

    return false
end

local function get_revive_block_reason()
    if not bCanRevive then
        return "canRevive=false for " .. tostring(RAGDOLL_ID)
    end

    if bKilledByRedBeam then
        return "killed by red beam"
    end

    if is_valid(obj) and obj.HasTag ~= nil then
        if obj:HasTag(RED_BEAM_KILLED_TAG) then
            return "KilledByRedBeam tag"
        end

        if obj:HasTag(BEAM_BLOCK_REVIVE_TAG) then
            return "temporarily blocked by beam"
        end
    end

    return nil
end

local function reset_beam_shock_timer()
    beamShockElapsed = BEAM_SHOCK_INTERVAL
end

local function apply_random_ragdoll_impulse(strength, context)
    if mesh == nil then
        return
    end

    if mesh.AddRandomImpulseToAllRagdollBodies ~= nil then
        mesh:AddRandomImpulseToAllRagdollBodies(strength)
        return
    end

    if not bWarnedMissingBeamShockImpulse then
        print("[GOIncRagdollPawn_Test] Missing AddRandomImpulseToAllRagdollBodies binding. " .. tostring(context) .. " impulse disabled.")
        bWarnedMissingBeamShockImpulse = true
    end

    if mesh.WakeAllRagdollBodies ~= nil then
        mesh:WakeAllRagdollBodies()
    end
end

local function apply_beam_shock_impulse()
    apply_random_ragdoll_impulse(BEAM_SHOCK_IMPULSE_STRENGTH, "Beam shock")
end

local function apply_red_beam_shock_impulse()
    apply_random_ragdoll_impulse(RED_BEAM_SHOCK_IMPULSE_STRENGTH, "Red beam shock")
end

local function set_red_beam_jitter_anchor_enabled(enabled)
    if mesh == nil then
        return
    end

    if enabled then
        if mesh.BeginRagdollJitterAnchor ~= nil then
            mesh:BeginRagdollJitterAnchor()
        end
    else
        if mesh.EndRagdollJitterAnchor ~= nil then
            mesh:EndRagdollJitterAnchor()
        end
    end
end

local function apply_red_beam_jitter_impulse()
    if mesh == nil then
        return
    end

    if mesh.AddJitterImpulseToAllRagdollBodies ~= nil then
        mesh:AddJitterImpulseToAllRagdollBodies(
            RED_BEAM_JITTER_LINEAR_STRENGTH,
            RED_BEAM_JITTER_TORQUE_STRENGTH,
            RED_BEAM_JITTER_ROOT_SCALE,
            RED_BEAM_JITTER_MAX_LINEAR_SPEED
        )
        return
    end

    apply_random_ragdoll_impulse(0.01, "Red beam jitter fallback")
end

local function tick_beam_shock(dt)
    if not is_revive_blocked_by_beam() then
        reset_beam_shock_timer()
        return
    end

    if type(dt) ~= "number" then
        dt = 0.0
    end

    beamShockElapsed = beamShockElapsed + dt
    if beamShockElapsed < BEAM_SHOCK_INTERVAL then
        return
    end

    beamShockElapsed = 0.0
    apply_beam_shock_impulse()
end

local function start_red_beam_shock()
    redBeamShockRemaining = RED_BEAM_SHOCK_DURATION
    redBeamShockElapsed = RED_BEAM_SHOCK_INTERVAL

    set_red_beam_jitter_anchor_enabled(true)
end

local function tick_red_beam_shock(dt)
    if redBeamShockRemaining <= 0.0 then
        set_red_beam_jitter_anchor_enabled(false)
        return false
    end

    if type(dt) ~= "number" then
        dt = 0.0
    end

    redBeamShockRemaining = math.max(0.0, redBeamShockRemaining - dt)
    redBeamShockElapsed = redBeamShockElapsed + dt
    if redBeamShockElapsed < RED_BEAM_SHOCK_INTERVAL then
        return true
    end

    redBeamShockElapsed = 0.0
    apply_red_beam_jitter_impulse()

    if redBeamShockRemaining <= 0.0 then
        set_red_beam_jitter_anchor_enabled(false)
        return false
    end

    return true
end

local function cache_components()
    pawn = obj:AsGOIncRagdollPawn()
    if pawn == nil then
        print("[GOIncRagdollPawn_Test] Owner is not AGOIncRagdollPawn: " .. tostring(obj:GetName()))
        return false
    end

    if pawn.GetAliveCapsuleComponent ~= nil then
        capsule = pawn:GetAliveCapsuleComponent()
    elseif pawn.GetAliveCollisionCapsuleComponent ~= nil then
        capsule = pawn:GetAliveCollisionCapsuleComponent()
    else
        capsule = pawn:GetCapsuleComponent()
    end

    if pawn.GetReviveTriggerCapsuleComponent ~= nil then
        reviveTrigger = pawn:GetReviveTriggerCapsuleComponent()
    else
        reviveTrigger = capsule
    end

    if pawn.GetRagdollMeshComponent ~= nil then
        mesh = pawn:GetRagdollMeshComponent()
    else
        mesh = pawn:GetMesh()
    end

    if pawn.GetGOIncMovementComponent ~= nil then
        movement = pawn:GetGOIncMovementComponent()
    else
        movement = pawn:GetRagdollMovementComponent()
    end

    if capsule == nil then
        print("[GOIncRagdollPawn_Test] Missing Alive CapsuleComponent")
    end
    if reviveTrigger == nil then
        print("[GOIncRagdollPawn_Test] Missing ReviveTriggerCapsuleComponent")
    end
    if mesh == nil then
        print("[GOIncRagdollPawn_Test] Missing SkeletalMeshComponent")
    end
    if movement == nil then
        print("[GOIncRagdollPawn_Test] Missing GOIncRagdollMovementComponent")
    end

    -- initial mesh offsets are captured after C++ CharacterConfig has been applied.
    return capsule ~= nil and reviveTrigger ~= nil and mesh ~= nil and movement ~= nil
end


local function number_or(value, fallback)
    if type(value) == "number" then
        return value
    end
    return fallback
end

local function resolve_ragdoll_id()
    if pawn ~= nil and pawn.GetRagdollId ~= nil then
        local id = pawn:GetRagdollId()
        if type(id) == "string" and id ~= "" then
            return id
        end
    end

    return DEFAULT_RAGDOLL_ID
end

local function get_pawn_number(getterName, fallback)
    if pawn ~= nil and pawn[getterName] ~= nil then
        local ok, value = pcall(function()
            return pawn[getterName](pawn)
        end)

        if ok then
            return number_or(value, fallback)
        end

        print("[GOIncRagdollPawn_Test] " .. getterName .. " failed. Using fallback value.")
    end

    return fallback
end

local function get_pawn_bool(getterName, fallback)
    if pawn ~= nil and pawn[getterName] ~= nil then
        local ok, value = pcall(function()
            return pawn[getterName](pawn)
        end)

        if ok and type(value) == "boolean" then
            return value
        end

        if not ok then
            print("[GOIncRagdollPawn_Test] " .. getterName .. " failed. Using fallback value.")
        end
    end

    return fallback
end

local function cache_runtime_config_from_pawn()
    if bRuntimeConfigCached then
        return
    end

    RAGDOLL_ID = resolve_ragdoll_id()

    -- Runtime behavior values used by this Lua state machine.
    -- Do not read Data.RagdollData here. That file is now a UI / spawn / score catalog.
    -- The runtime owner is the C++ GOIncRagdollPawn CharacterConfig.
    bCanRevive = get_pawn_bool("CanRevive", bCanRevive)
    aliveCapsuleHalfHeight = get_pawn_number("GetAliveCapsuleHalfHeight", aliveCapsuleHalfHeight)

    FLEE_END_DISTANCE = get_pawn_number("GetFleeEndDistance", FLEE_END_DISTANCE)
    FLEE_STOP_DURATION = get_pawn_number("GetFleeStopDuration", FLEE_STOP_DURATION)
    FLEE_STOP_MIN_BRAKING_DECELERATION = get_pawn_number("GetFleeStopMinBrakingDeceleration", FLEE_STOP_MIN_BRAKING_DECELERATION)

    FLEE_ANIMATION_BASE_SPEED = get_pawn_number("GetFleeAnimationBaseSpeed", FLEE_ANIMATION_BASE_SPEED)
    FLEE_ANIMATION_MIN_PLAY_RATE = get_pawn_number("GetFleeAnimationMinPlayRate", FLEE_ANIMATION_MIN_PLAY_RATE)
    FLEE_ANIMATION_MAX_PLAY_RATE = get_pawn_number("GetFleeAnimationMaxPlayRate", FLEE_ANIMATION_MAX_PLAY_RATE)
    FLEE_STOP_START_PLAY_RATE = get_pawn_number("GetFleeStopStartPlayRate", FLEE_STOP_START_PLAY_RATE)
    FLEE_STOP_END_PLAY_RATE = get_pawn_number("GetFleeStopEndPlayRate", FLEE_STOP_END_PLAY_RATE)
    FLEE_ROTATION_YAW_OFFSET_DEGREES = get_pawn_number("GetFleeRotationYawOffsetDegrees", FLEE_ROTATION_YAW_OFFSET_DEGREES)

    REVIVE_BLEND_DURATION = get_pawn_number("GetReviveBlendDuration", REVIVE_BLEND_DURATION)
    REVIVE_BLEND_FALLBACK_DURATION = REVIVE_BLEND_DURATION

    print(
        "[GOIncRagdollPawn_Test] Runtime config cached from C++ Pawn: " ..
        tostring(RAGDOLL_ID) ..
        " / canRevive=" .. tostring(bCanRevive) ..
        " / fleeEndDistance=" .. tostring(FLEE_END_DISTANCE)
    )

    bRuntimeConfigCached = true
end

local function capture_initial_mesh_offsets()
    if mesh == nil then
        return false
    end

    -- Cache the alive/animation mesh offset after the C++ CharacterConfig has already
    -- applied mesh relative transform. Reviving moves the Actor/Capsule to the ragdoll
    -- sync position, then restores this relative offset so the mesh returns under the
    -- Alive capsule instead of staying at the dead ragdoll component position.
    initialMeshRelativeLocation = mesh.RelativeLocation
    initialMeshWorldOffsetFromActor = mesh.Location - obj.Location
    return true
end

local function restore_initial_mesh_relative_location()
    if mesh ~= nil and initialMeshRelativeLocation ~= nil then
        mesh.RelativeLocation = initialMeshRelativeLocation
    end
end

local function cache_player()
    player = World.FindFirstActorByTag(PLAYER_TAG)

    if not is_valid(player) then
        print("[GOIncRagdollPawn_Test] Missing Player actor with tag: " .. PLAYER_TAG)
        return false
    end

    return true
end

local function get_ragdoll_actor_sync_location()
    if mesh == nil then
        return nil
    end

    -- Prefer the corrected component-sync location used by USkeletalMeshComponent.
    -- This is better than raw pelvis location when aligning the Actor/Capsule back to ragdoll.
    local syncLocation = mesh:GetRagdollComponentSyncWorldLocation()
    if syncLocation ~= nil then
        return syncLocation
    end

    -- Fallback for assets that do not have the component sync offset captured yet.
    return mesh:GetRagdollBodyWorldLocation(SYNC_BONE_NAME)
end

local function project_to_ground(actorTargetLocation, sourceZ)
    if World == nil or World.LineTraceGround == nil then
        return Vector.new(actorTargetLocation.X, actorTargetLocation.Y, obj.Location.Z), true
    end

    local start = Vector.new(
        actorTargetLocation.X,
        actorTargetLocation.Y,
        sourceZ + GROUND_TRACE_UP
    )

    local finish = Vector.new(
        actorTargetLocation.X,
        actorTargetLocation.Y,
        sourceZ - GROUND_TRACE_DOWN
    )

    local hit = World.LineTraceGround(start, finish, obj)

    if hit == nil or not hit.bHit or hit.WorldHitLocation == nil then
        return obj.Location, false
    end

    return Vector.new(
        actorTargetLocation.X,
        actorTargetLocation.Y,
        hit.WorldHitLocation.Z + aliveCapsuleHalfHeight
    ), true
end

local function align_actor_to_ragdoll()
    local meshSyncLocation = get_ragdoll_actor_sync_location()
    if meshSyncLocation == nil then
        return false
    end

    local actorTargetLocation = meshSyncLocation
    if initialMeshWorldOffsetFromActor ~= nil then
        actorTargetLocation = meshSyncLocation - initialMeshWorldOffsetFromActor
    end

    local projectedLocation, bGroundValid = project_to_ground(actorTargetLocation, meshSyncLocation.Z)
    canReviveHere = bGroundValid

    if not bGroundValid then
        return false
    end

    obj.Location = projectedLocation
    return true
end

local function sync_revive_trigger_to_ragdoll()
    if state ~= STATE_DEAD then
        return
    end

    if reviveTrigger == nil or mesh == nil then
        return
    end

    local meshSyncLocation = get_ragdoll_actor_sync_location()
    if meshSyncLocation == nil then
        return
    end

    local actorTargetLocation = meshSyncLocation
    if initialMeshWorldOffsetFromActor ~= nil then
        actorTargetLocation = meshSyncLocation - initialMeshWorldOffsetFromActor
    end

    -- Dead 상태에서는 Actor/AliveCapsule을 ragdoll 위치로 끌고 가지 않는다.
    -- Player revive 감지용 trigger만 ragdoll 근처의 안전한 바닥 위치를 따라가게 한다.
    local projectedLocation, bGroundValid = project_to_ground(actorTargetLocation, meshSyncLocation.Z)
    canReviveHere = bGroundValid

    if bGroundValid then
        reviveTrigger.Location = projectedLocation
    else
        -- Ground가 없으면 revive는 막되, trigger 자체는 ragdoll 근처에 남겨 debug 위치를 확인하기 쉽게 둔다.
        reviveTrigger.Location = meshSyncLocation
    end
end

local function sync_dead_root_to_ragdoll_safe()
    if state ~= STATE_DEAD then
        return
    end

    if pawn ~= nil and pawn.UpdateDeadRootFromRagdollSafe ~= nil then
        canReviveHere = pawn:UpdateDeadRootFromRagdollSafe()
        return
    end

    -- Older engine fallback.
    sync_revive_trigger_to_ragdoll()
end

local function set_alive_capsule_enabled(enabled)
    if capsule == nil then
        return
    end

    capsule:SetSimulatePhysics(false)
    capsule:SetKinematicPhysics(true)
    capsule:SetGenerateOverlapEvents(false)

    if enabled then
        -- 새 collision split 구조에서는 Alive capsule이 바닥/환경 충돌 기준이다.
        -- 구버전처럼 reviveTrigger와 capsule이 같은 경우에는 기존 동작에 가깝게 QueryOnly를 유지한다.
        if reviveTrigger ~= nil and reviveTrigger ~= capsule then
            capsule:SetCollisionEnabled("QueryAndPhysics")
        else
            capsule:SetCollisionEnabled("QueryOnly")
        end
    else
        capsule:SetCollisionEnabled("NoCollision")
    end
end

local function set_revive_trigger_enabled(enabled)
    if reviveTrigger == nil then
        return
    end

    if enabled then
        -- ReviveTrigger is only a sensor. Do not turn it off just because the
        -- current ragdoll cannot revive or the last ground projection failed;
        -- those are handled after OnOverlap so we can still observe why revive
        -- was blocked. Red-beam/permanent blocks still disable the trigger.
        enabled = state == STATE_DEAD and not is_revive_blocked()
    end

    reviveTrigger:SetSimulatePhysics(false)
    reviveTrigger:SetKinematicPhysics(true)
    reviveTrigger:SetGenerateOverlapEvents(enabled)

    if enabled then
        reviveTrigger:SetCollisionEnabled("QueryOnly")
    else
        reviveTrigger:SetCollisionEnabled("NoCollision")
    end
end

local function get_manual_move_direction()
    local dir = Vector.Zero()

    if Input.GetKey(Key.W) then
        dir = dir + obj.Forward
    end
    if Input.GetKey(Key.S) then
        dir = dir - obj.Forward
    end
    if Input.GetKey(Key.D) then
        dir = dir + obj.Right
    end
    if Input.GetKey(Key.A) then
        dir = dir - obj.Right
    end

    dir.Z = 0.0
    if dir:Length() > 0.001 then
        return dir:Normalized()
    end

    return nil
end

local function has_reached_flee_end_distance()
    if not is_valid(player) then
        return false
    end

    local diff = obj.Location - player.Location
    diff.Z = 0.0

    return diff:Length() >= FLEE_END_DISTANCE
end

local function get_movement_speed_2d()
    if movement == nil or movement.GetVelocity == nil then
        return nil
    end

    local velocity = movement:GetVelocity()
    if velocity == nil then
        return nil
    end

    local velocity2D = Vector.new(velocity.X, velocity.Y, 0.0)
    return velocity2D:Length()
end

local function clamp(value, minValue, maxValue)
    if value < minValue then
        return minValue
    end

    if value > maxValue then
        return maxValue
    end

    return value
end

local function set_flee_animation_play_rate(playRate)
    local clampedRate = clamp(playRate, FLEE_ANIMATION_MIN_PLAY_RATE, FLEE_ANIMATION_MAX_PLAY_RATE)
    currentFleeAnimationPlayRate = clampedRate

    if mesh ~= nil and mesh.SetPlayRate ~= nil then
        mesh:SetPlayRate(clampedRate)
        return
    end

    if not bWarnedMissingSetPlayRate then
        bWarnedMissingSetPlayRate = true
        print("[GOIncRagdollPawn_Test] mesh:SetPlayRate() binding missing. Flee animation speed sync is disabled.")
    end
end

local function clamp01(value)
    return clamp(value, 0.0, 1.0)
end

local function smoothstep(alpha)
    alpha = clamp01(alpha)
    return alpha * alpha * (3.0 - 2.0 * alpha)
end

local function normalize_angle_degrees(angle)
    while angle > 180.0 do
        angle = angle - 360.0
    end
    while angle < -180.0 do
        angle = angle + 360.0
    end
    return angle
end

local function lerp_yaw_degrees(fromYaw, toYaw, alpha)
    local delta = normalize_angle_degrees(toYaw - fromYaw)
    return fromYaw + delta * clamp01(alpha)
end

local function get_flee_direction()
    if is_valid(player) then
        local dir = obj.Location - player.Location
        dir.Z = 0.0
        if dir:Length() > 0.001 then
            return dir:Normalized()
        end
    end

    local manualDir = get_manual_move_direction()
    if manualDir ~= nil then
        return manualDir
    end

    local fallback = obj.Forward
    fallback.Z = 0.0
    if fallback:Length() > 0.001 then
        return fallback:Normalized()
    end

    return Vector.new(1.0, 0.0, 0.0)
end

local function get_yaw_from_direction(direction)
    if direction == nil then
        return obj.Rotation.Z
    end

    local dir = Vector.new(direction.X, direction.Y, 0.0)
    if dir:Length() <= 0.001 then
        return obj.Rotation.Z
    end

    dir = dir:Normalized()
    return Math.RadiansToDegrees(Math.Atan2(dir.Y, dir.X)) + FLEE_ROTATION_YAW_OFFSET_DEGREES
end

local function face_direction(direction)
    obj.Rotation = Vector.new(0.0, 0.0, get_yaw_from_direction(direction))
end

function EnterDeadRagdoll()
    state = STATE_DEAD
    reset_beam_shock_timer()
    pendingDeadReason = nil
    fleeStopElapsed = 0.0
    fleeStopStartSpeed = 0.0
    reviveElapsed = 0.0
    reviveStartYaw = obj.Rotation.Z
    reviveTargetYaw = obj.Rotation.Z

    if pawn ~= nil and pawn.EnterDeadRagdollState ~= nil then
        pawn:EnterDeadRagdollState()
        return
    end

    if movement ~= nil then
        movement:StopMovementImmediately()
        movement:SetMovementEnabled(false)

        if movement.SetFloorRaycastEnabled ~= nil then
            movement:SetFloorRaycastEnabled(false)
        end
        if movement.SetGravityEnabled ~= nil then
            movement:SetGravityEnabled(false)
        end
    end

    -- Dead 상태에서 Alive용 capsule은 바닥/환경과 충돌하면 안 된다.
    -- Player revive 감지는 reviveTrigger가 QueryOnly로 담당한다.
    set_alive_capsule_enabled(false)
    set_revive_trigger_enabled(true)

    if mesh ~= nil then
        mesh:SetCollisionEnabled("QueryAndPhysics")
        mesh:SetRagdollGravityEnabled(true)

        -- StopFleeAnimation()보다 먼저 ragdoll을 켠다.
        -- 그래야 Alive/Flee 중 마지막 animation pose 기준으로 ragdoll body가 시작될 가능성이 높다.
        mesh:SetRagdollEnabled(true)
        mesh:SetAllBodiesSimulatePhysics(true)
        mesh:SetAllBodiesPhysicsBlendWeight(1.0)
        mesh:WakeAllRagdollBodies()
    end

    if pawn ~= nil then
        pawn:StopFleeAnimation()
    end
end

-- RequestEnterDeadRagdoll("Laser") 같은 식으로 이후 이벤트도 이 경로를 타게 만들면 된다.
local function RequestEnterDeadRagdoll(reason)
    if state == STATE_DEAD then
        return
    end

    print("[GOIncRagdollPawn_Test] RequestEnterDeadRagdoll reason: " .. tostring(reason))
    EnterDeadRagdoll(reason)
end

function RequestDeadRagdoll(reason)
    RequestEnterDeadRagdoll(reason or "ExternalRequest")
end

function OnRedBeamHit(reason)
    -- Slot2 red beam should permanently kill only pawns that are currently alive/reviving.
    -- DeadRagdoll pawns are ignored here so already-dead, non-revivable actors are not newly polluted.
    if state == STATE_DEAD then
        return
    end

    if state ~= STATE_REVIVING and state ~= STATE_ALIVE and state ~= STATE_FLEE_STOPPING then
        return
    end

    bKilledByRedBeam = true
    if is_valid(obj) and obj.AddTag ~= nil then
        obj:AddTag(RED_BEAM_KILLED_TAG)
    end

    print("[GOIncRagdollPawn_Test] Red beam killed ragdoll permanently. reason: " .. tostring(reason))
    RequestEnterDeadRagdoll(reason or "Slot2RedBeam")
    set_revive_trigger_enabled(false)

    start_red_beam_shock()
    apply_red_beam_jitter_impulse()
end

function EnterReviving()
    if state ~= STATE_DEAD then
        return
    end

    local reviveBlockReason = get_revive_block_reason()
    if reviveBlockReason ~= nil then
        print("[GOIncRagdollPawn_Test] Revive blocked: " .. tostring(reviveBlockReason))
        return
    end

    state = STATE_REVIVING
    reset_beam_shock_timer()
    pendingDeadReason = nil
    fleeStopElapsed = 0.0
    fleeStopStartSpeed = 0.0
    reviveElapsed = 0.0

    print("[GOIncRagdollPawn_Test] EnterReviving")

    -- Ragdoll 결과 위치로 Actor/Root를 Reviving 진입 순간에만 맞춘 뒤 recovery를 시작한다.
    -- Dead tick에서는 Actor/AliveCapsule 위치를 더 이상 계속 동기화하지 않는다.
    local bPrepared = false
    if pawn ~= nil and pawn.PrepareReviveFromRagdoll ~= nil then
        bPrepared = pawn:PrepareReviveFromRagdoll()
    else
        bPrepared = align_actor_to_ragdoll()
    end

    if not bPrepared then
        print("[GOIncRagdollPawn_Test] EnterReviving failed: no valid ground.")
        state = STATE_DEAD
        canReviveHere = false
        set_revive_trigger_enabled(true)
        return
    end

    -- Recovery 중 Actor yaw도 도망 방향으로 서서히 보간한다.
    -- Recovery가 끝난 뒤 첫 Alive tick에서 face_direction()이 yaw를 확 돌리는 문제를 줄인다.
    reviveStartYaw = obj.Rotation.Z
    reviveTargetYaw = get_yaw_from_direction(get_flee_direction())

    if pawn ~= nil and pawn.EnterRevivingState ~= nil then
        if mesh ~= nil and mesh.SetRagdollRecoveryDuration ~= nil then
            mesh:SetRagdollRecoveryDuration(REVIVE_BLEND_DURATION)
        end
        pawn:EnterRevivingState()
        set_flee_animation_play_rate(1.0)
        restore_initial_mesh_relative_location()
        return
    end

    if movement ~= nil then
        movement:StopMovementImmediately()
        movement:SetMovementEnabled(false)

        if movement.SetFloorRaycastEnabled ~= nil then
            movement:SetFloorRaycastEnabled(false)
        end
        if movement.SetGravityEnabled ~= nil then
            movement:SetGravityEnabled(false)
        end
    end

    -- Reviving 중에는 Player overlap도, Alive collision도 잠깐 꺼둔다.
    set_revive_trigger_enabled(false)
    set_alive_capsule_enabled(false)

    -- 목표 animation pose가 있어야 recovery가 ragdoll pose -> animation pose로 보간된다.
    if pawn ~= nil then
        pawn:PlayFleeAnimation()
    end
    set_flee_animation_play_rate(1.0)

    if mesh ~= nil then
        -- 중요:
        -- SetRagdollEnabled(false) 전에 아래 두 함수를 호출하면 recovery 시작 pose가 망가질 수 있다.
        --   mesh:SetAllBodiesPhysicsBlendWeight(0.0)
        --   mesh:SetAllBodiesSimulatePhysics(false)
        -- SetRagdollEnabled(false) 내부의 StartRagdollRecovery()가 현재 ragdoll pose를 잡게 둔다.

        if mesh.SetRagdollRecoveryDuration ~= nil then
            mesh:SetRagdollRecoveryDuration(REVIVE_BLEND_DURATION)
        end

        mesh:SetRagdollGravityEnabled(false)
        mesh:SetRagdollEnabled(false)
        mesh:SetCollisionEnabled("NoCollision")

        restore_initial_mesh_relative_location()
    end
end

function EnterAliveFlee()
    state = STATE_ALIVE
    pendingDeadReason = nil
    fleeStopElapsed = 0.0
    fleeStopStartSpeed = 0.0
    reviveElapsed = 0.0

    if pawn ~= nil and pawn.EnterAliveFleeState ~= nil then
        pawn:EnterAliveFleeState()
    else
        if mesh ~= nil then
            mesh:SetCollisionEnabled("NoCollision")
            mesh:SetRagdollGravityEnabled(false)
            mesh:SetAllBodiesPhysicsBlendWeight(0.0)
            mesh:SetAllBodiesSimulatePhysics(false)
            mesh:SetRagdollEnabled(false)
        end

        set_revive_trigger_enabled(false)
        set_alive_capsule_enabled(true)

        if movement ~= nil then
            movement:StopMovementImmediately()
            movement:SetMovementEnabled(true)

            if movement.SetFloorRaycastEnabled ~= nil then
                movement:SetFloorRaycastEnabled(true)
            end
            if movement.SetGravityEnabled ~= nil then
                movement:SetGravityEnabled(true)
            end
        end

        if pawn ~= nil then
            pawn:PlayFleeAnimation()
        end
    end

    restore_initial_mesh_relative_location()
    set_flee_animation_play_rate(1.0)

    -- Reviving yaw blend의 마지막 값을 확정해 첫 AliveFlee Tick에서 회전이 튀지 않게 한다.
    obj.Rotation = Vector.new(0.0, 0.0, reviveTargetYaw)

    print("[GOIncRagdollPawn_Test] Revive finished -> AliveFlee")
end

local function TickReviving(dt)
    reviveElapsed = reviveElapsed + (dt or 0.0)

    local reviveAlpha = clamp01(reviveElapsed / REVIVE_BLEND_DURATION)
    local yawAlpha = smoothstep(reviveAlpha)
    local yaw = lerp_yaw_degrees(reviveStartYaw, reviveTargetYaw, yawAlpha)
    obj.Rotation = Vector.new(0.0, 0.0, yaw)

    if mesh ~= nil and mesh.IsRagdollRecovering ~= nil then
        -- C++의 SkeletalPhysicsMode/Recovering 상태를 직접 확인한다.
        if mesh:IsRagdollRecovering() then
            return
        end

        -- 같은 프레임에 false가 들어오는 케이스 방지용 최소 대기.
        if reviveElapsed < REVIVE_MIN_WAIT_TIME then
            return
        end

        EnterAliveFlee()
        return
    end

    -- 아직 C++ binding이 없을 때만 fallback timer 사용.
    if reviveElapsed >= REVIVE_BLEND_FALLBACK_DURATION then
        print("[GOIncRagdollPawn_Test] IsRagdollRecovering binding missing. Using fallback revive timer.")
        EnterAliveFlee()
        return
    end
end

local function EnterFleeStopping(reason)
    if state ~= STATE_ALIVE then
        return
    end

    state = STATE_FLEE_STOPPING
    pendingDeadReason = reason
    fleeStopElapsed = 0.0
    fleeStopStartSpeed = get_movement_speed_2d()
    if fleeStopStartSpeed == nil or fleeStopStartSpeed <= 0.001 then
        fleeStopStartSpeed = FLEE_ANIMATION_BASE_SPEED
    end
    set_flee_animation_play_rate(FLEE_STOP_START_PLAY_RATE)

    print("[GOIncRagdollPawn_Test] EnterFleeStopping reason: " .. tostring(reason))

    if movement ~= nil then
        -- 여기서 StopMovementImmediately()를 부르면 급정지한다.
        -- 현재 속도를 FLEE_STOP_DURATION 동안 줄이는 데 필요한 braking 값을 계산한다.
        if movement.SetBrakingDeceleration ~= nil then
            local brakingDeceleration = fleeStopStartSpeed / FLEE_STOP_DURATION
            if brakingDeceleration < FLEE_STOP_MIN_BRAKING_DECELERATION then
                brakingDeceleration = FLEE_STOP_MIN_BRAKING_DECELERATION
            end
            movement:SetBrakingDeceleration(brakingDeceleration)
        end

        movement:SetMovementEnabled(true)
    end
end

local function TickFleeStopping(dt)
    fleeStopElapsed = fleeStopElapsed + (dt or 0.0)

    local stopAlpha = clamp01(fleeStopElapsed / FLEE_STOP_DURATION)
    local remainingRatio = 1.0 - stopAlpha
    local playRate = FLEE_STOP_END_PLAY_RATE +
        (FLEE_STOP_START_PLAY_RATE - FLEE_STOP_END_PLAY_RATE) * remainingRatio
    set_flee_animation_play_rate(playRate)

    -- 감속 중에는 이동 입력을 넣지 않는다. 방향만 현재 속도 방향으로 유지한다.
    if movement ~= nil and movement.GetVelocity ~= nil then
        local velocity = movement:GetVelocity()
        if velocity ~= nil then
            local faceDir = Vector.new(velocity.X, velocity.Y, 0.0)
            if faceDir:Length() > 0.001 then
                face_direction(faceDir)
            end
        end
    end

    if stopAlpha >= 1.0 then
        set_flee_animation_play_rate(FLEE_STOP_END_PLAY_RATE)

        if movement ~= nil then
            movement:StopMovementImmediately()
        end

        RequestEnterDeadRagdoll(pendingDeadReason or "FleeStoppingFinished")
        return
    end
end

function GetGOIncRagdollState()
    return state
end

function BeginPlay()
    if not cache_components() then
        return
    end

    cache_runtime_config_from_pawn()
    capture_initial_mesh_offsets()
    cache_player()

    EnterDeadRagdoll()
    print("[GOIncRagdollPawn_Test] BeginPlay -> DeadRagdoll. Press R to toggle Reviving/FleeStopping/DeadRagdoll.")
end

function Tick(dt)
    if pawn == nil then
        if not cache_components() then
            return
        end

        cache_runtime_config_from_pawn()
        capture_initial_mesh_offsets()
    end

    if Input.GetKeyDown(Key.R) then
        if state == STATE_DEAD then
            EnterReviving()
        elseif state == STATE_ALIVE then
            EnterFleeStopping("DebugToggle")
        else
            RequestEnterDeadRagdoll("DebugToggle")
        end
        return
    end

    if state == STATE_DEAD then
        tick_beam_shock(dt)
        local bRedBeamShocking = tick_red_beam_shock(dt)

        if not bRedBeamShocking then
            sync_dead_root_to_ragdoll_safe()
        end

        set_revive_trigger_enabled(true)
        return
    end

    if state == STATE_REVIVING then
        TickReviving(dt)
        return
    end

    if state == STATE_ALIVE and movement ~= nil then
        if has_reached_flee_end_distance() then
            EnterFleeStopping("FleeDistance")
            return
        end

        local fleeDir = get_flee_direction()
        face_direction(fleeDir)
        movement:AddInputVector(fleeDir)
        return
    end

    if state == STATE_FLEE_STOPPING and movement ~= nil then
        TickFleeStopping(dt)
        return
    end
end

function OnOverlap(other, overlappedComp, otherComp)
    print(
        "[GOIncRagdollPawn_Test] OnOverlap entered. state=" .. tostring(state) ..
        " / other=" .. get_actor_debug_name(other) ..
        " / canRevive=" .. tostring(bCanRevive) ..
        " / canReviveHere=" .. tostring(canReviveHere)
    )

    if state ~= STATE_DEAD then
        print("[GOIncRagdollPawn_Test] OnOverlap ignored: state is " .. tostring(state))
        return
    end

    if not is_player_actor(other) then
        print("[GOIncRagdollPawn_Test] OnOverlap ignored: other is not Player")
        return
    end

    local reviveBlockReason = get_revive_block_reason()
    if reviveBlockReason ~= nil then
        print("[GOIncRagdollPawn_Test] Revive blocked: " .. tostring(reviveBlockReason))
        return
    end

    -- overlappedComp와 reviveTrigger는 같은 C++ 객체여도 Lua userdata 비교가 실패할 수 있으므로 직접 비교하지 않는다.
    print("[GOIncRagdollPawn_Test] Player overlapped revive capsule -> Reviving")
    player = other
    EnterReviving()
end
