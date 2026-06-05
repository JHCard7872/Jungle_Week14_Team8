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

local pawn = nil
local capsule = nil
local mesh = nil
local movement = nil
local state = STATE_DEAD

local function is_valid(value)
    return value ~= nil and (value.IsValid == nil or value:IsValid())
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
        obj.Location = location
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

local function get_flee_direction()
    local player = World.FindFirstActorByTag("Player")
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

function EnterDeadRagdoll()
    state = STATE_DEAD

    if movement ~= nil then
        movement:StopMovementImmediately()
        movement:SetMovementEnabled(false)
    end

    if capsule ~= nil then
        capsule:SetSimulatePhysics(false)
        capsule:SetCollisionEnabled("NoCollision")
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
    end

    if capsule ~= nil then
        capsule:SetSimulatePhysics(false)
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

    if state == STATE_ALIVE and movement ~= nil then
        movement:AddInputVector(get_flee_direction())
    end
end

function OnHit(other, hitComp, otherComp, normalImpulse, hitResult)
    if state == STATE_ALIVE then
        EnterDeadRagdoll()
    end
end
