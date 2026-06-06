#include "GameFramework/Pawn/GOIncSonicRagdollPawn.h"

FGOIncRagdollCharacterConfig AGOIncSonicRagdollPawn::MakeCharacterConfig() const
{
	FGOIncRagdollCharacterConfig Config;

	Config.RagdollId = "blue-speedster";
	Config.DisplayName = "파란 고슴도치";

	Config.SkeletalMeshPath = "Content/Data/Sonic/sc_dash_loop_anm_hkx_SkeletalMesh.uasset";
	Config.PhysicsAssetPath = "Content/Data/Sonic/sc_dash_loop_anm_hkx_PhysicsAsset.uasset";
	Config.FleeAnimationPath = "Content/Data/Sonic/sc_dash_loop_anm_hkx_sc_dash_loop.uasset";
	Config.LuaScriptFile = "GOIncRagdollPawn_Test.lua";

	Config.MeshRelativeLocation = FVector(0.0f, 0.0f, -0.6f);
	Config.MeshRelativeScale = FVector(1.0f, 1.0f, 1.0f);

	Config.AliveCapsuleRadius = 0.35f;
	Config.AliveCapsuleHalfHeight = 0.6f;
	Config.ReviveTriggerCapsuleRadius = 5.0f;
	Config.ReviveTriggerCapsuleHalfHeight = 5.0f;

	Config.bCanRevive = true;
	Config.ReviveBlendDuration = 0.8f;

	Config.FleeSpeed = 4.0f;
	Config.FleeAcceleration = 15.0f;
	Config.FleeBrakingDeceleration = 10.0f;
	Config.FleeEndDistance = 10.0f;
	Config.FleeStopDuration = 1.0f;
	Config.FleeStopMinBrakingDeceleration = 0.1f;
	Config.FleeRotationYawOffsetDegrees = 0.0f;

	Config.FleeAnimationBaseSpeed = 4.0f;
	Config.FleeAnimationMinPlayRate = 0.0f;
	Config.FleeAnimationMaxPlayRate = 1.0f;
	Config.FleeStopStartPlayRate = 1.0f;
	Config.FleeStopEndPlayRate = 0.0f;

	return Config;
}
