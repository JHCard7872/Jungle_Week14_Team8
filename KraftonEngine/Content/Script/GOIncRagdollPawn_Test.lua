-- GOIncRagdollPawn_Test.lua
--
-- Test script for AGOIncRagdollPawn.
-- C++ exposes component APIs; this script owns the DeadRagdoll <-> AliveFlee state flow.
--
-- Hotkeys:
--   R    : toggle DeadRagdoll / AliveFlee
--   WASD : move while AliveFlee

local STATE_DEAD = "DeadRagdoll"
local STATE_ALIVE = "AliveFlee"
local SYNC_BONE_NAME = "Pelvis"
local PLAYER_TAG = "Player"

local pawn = nil
local capsule = nil
local mesh = nil
local movement = nil
local state = STATE_DEAD

local initialMeshRelativeLocation = nil
local initialMeshWorldOffsetFromActor = nil

local RAD_TO_DEG = 57.29577951308232
local FLEE_ROTATION_YAW_OFFSET_DEGREES = 0.0


local function is_valid(value)
    return value ~= nil and (value.IsValid == nil or value:IsValid())
end

local function is_player_actor(actor)
    return is_valid(actor) and actor.HasTag ~= nil and actor:HasTag(PLAYER_TAG)
end

local function cache_components()
    pawn = obj:AsGOIncRagdollPawn()
    if pawn == nil then
        print("[GOIncRagdollPawn_Test] Owner is not AGOIncRagdollPawn: " .. tostring(obj:GetName()))
        return false
    end

    capsule = pawn:GetCapsuleComponent()
    mesh = pawn:GetMesh()
    movement = pawn:GetRagdollMovementComponent()

    if capsule == nil then
        print("[GOIncRagdollPawn_Test] Missing CapsuleComponent")
    end
    if mesh == nil then
        print("[GOIncRagdollPawn_Test] Missing SkeletalMeshComponent")
    end
    if movement == nil then
        print("[GOIncRagdollPawn_Test] Missing GOIncRagdollMovementComponent")
    end

    if capsule ~= nil and mesh ~= nil then
        initialMeshRelativeLocation = mesh.RelativeLocation
        initialMeshWorldOffsetFromActor = mesh.Location - obj.Location
    end

    return capsule ~= nil and mesh ~= nil and movement ~= nil
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

local function align_actor_to_ragdoll()
    local location = get_ragdoll_actor_sync_location()
    if location ~= nil then
        if initialMeshWorldOffsetFromActor ~= nil then
            obj.Location = location - initialMeshWorldOffsetFromActor
        else
            obj.Location = location
        end
    end
end

local function sync_actor_capsule_to_ragdoll()
    if state ~= STATE_DEAD then
        return
    end

    if capsule == nil or mesh == nil then
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

    obj.Location = actorTargetLocation

    -- Moving the actor/root capsule also moves child components through the hierarchy.
    -- Put the skeletal mesh component back onto the existing ragdoll sync position so
    -- this trigger-follow update does not drag the simulated ragdoll bodies around.
    mesh.Location = meshSyncLocation
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

local function get_flee_direction()
    local player = World.FindFirstActorByTag(PLAYER_TAG)
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

    local forward = obj.Forward
    forward.Z = 0.0
    if forward:Length() > 0.001 then
        return forward:Normalized()
    end

    return Vector.Forward()
end

local function atan2_safe(y, x)
    if math.atan2 ~= nil then
        return math.atan2(y, x)
    end

    if x > 0.0 then
        return math.atan(y / x)
    end

    if x < 0.0 and y >= 0.0 then
        return math.atan(y / x) + math.pi
    end

    if x < 0.0 and y < 0.0 then
        return math.atan(y / x) - math.pi
    end

    if x == 0.0 and y > 0.0 then
        return math.pi * 0.5
    end

    if x == 0.0 and y < 0.0 then
        return -math.pi * 0.5
    end

    return 0.0
end

local function face_direction(direction)
    if direction == nil then
        return
    end

    local x = direction.X
    local y = direction.Y

    local len = math.sqrt(x * x + y * y)
    if len <= 0.001 then
        return
    end

    x = x / len
    y = y / len

    local yaw = atan2_safe(y, x) * RAD_TO_DEG + FLEE_ROTATION_YAW_OFFSET_DEGREES

    local rot = obj.Rotation
    rot.X = 0.0
    rot.Y = 0.0
    rot.Z = yaw

    obj.Rotation = rot
end

function EnterDeadRagdoll()
    state = STATE_DEAD

    if pawn ~= nil then
        pawn:StopFleeAnimation()
    end

    if movement ~= nil then
        movement:StopMovementImmediately()
        movement:SetMovementEnabled(false)
    end

    if capsule ~= nil then
        -- Dead state uses the pawn capsule as a revive trigger.
        -- The ragdoll mesh remains physical, but revive detection is based on
        -- Player entering this capsule area, not on hitting individual bones.
        -- Keep the capsule kinematic so PhysX can generate trigger pairs
        -- against non-simulating player/controller shapes.
        capsule:SetSimulatePhysics(false)
        capsule:SetKinematicPhysics(true)
        capsule:SetGenerateOverlapEvents(true)
        capsule:SetCollisionEnabled("QueryOnly")
    end

    if mesh ~= nil then
        mesh:SetCollisionEnabled("QueryAndPhysics")
        mesh:SetRagdollGravityEnabled(true)
        mesh:SetRagdollEnabled(true)
        mesh:SetAllBodiesSimulatePhysics(true)
        mesh:SetAllBodiesPhysicsBlendWeight(1.0)
        mesh:WakeAllRagdollBodies()
    end
end

function EnterAliveFlee()
    state = STATE_ALIVE

    -- Align the Actor/Capsule to the ragdoll result before turning physics off.
    align_actor_to_ragdoll()

    if mesh ~= nil then
        mesh:SetAllBodiesPhysicsBlendWeight(0.0)
        mesh:SetAllBodiesSimulatePhysics(false)
        mesh:SetRagdollGravityEnabled(false)
        mesh:SetRagdollEnabled(false)
        mesh:SetCollisionEnabled("NoCollision")

        if initialMeshRelativeLocation ~= nil then
            mesh.RelativeLocation = initialMeshRelativeLocation
        end
    end

    if pawn ~= nil then
        pawn:PlayFleeAnimation()
    end

    if capsule ~= nil then
        capsule:SetSimulatePhysics(false)
        capsule:SetKinematicPhysics(true)
        capsule:SetGenerateOverlapEvents(false)
        capsule:SetCollisionEnabled("QueryOnly")
    end

    if movement ~= nil then
        movement:StopMovementImmediately()
        movement:SetMovementEnabled(true)
    end
end

function GetGOIncRagdollState()
    return state
end

function BeginPlay()
    if not cache_components() then
        return
    end

    EnterDeadRagdoll()
    print("[GOIncRagdollPawn_Test] BeginPlay -> DeadRagdoll. Press R to toggle AliveFlee/DeadRagdoll.")
end

function Tick(dt)
    if pawn == nil then
        if not cache_components() then
            return
        end
    end

    if Input.GetKeyDown(Key.R) then
        if state == STATE_DEAD then
            EnterAliveFlee()
        else
            EnterDeadRagdoll()
        end
        return
    end

    if state == STATE_DEAD then
        sync_actor_capsule_to_ragdoll()
        return
    end

    if state == STATE_ALIVE and movement ~= nil then
        local fleeDir = get_flee_direction()
        face_direction(fleeDir)
        movement:AddInputVector(fleeDir)
    end
end

function OnOverlap(other, overlappedComp, otherComp)
    if state ~= STATE_DEAD then
        return
    end

    if not is_player_actor(other) then
        return
    end

    print("[GOIncRagdollPawn_Test] Player overlapped revive capsule -> AliveFlee")
    EnterAliveFlee()
end