#include "GameFramework/Pawn/GOIncPikachuRagdollPawn.h"

FGOIncRagdollCharacterConfig AGOIncPikachuRagdollPawn::MakeCharacterConfig() const
{
	FGOIncRagdollCharacterConfig Config;

	Config.RagdollId = "yellow-mouse";
	Config.DisplayName = "노란 전기쥐";

	Config.SkeletalMeshPath = "Content/Data/Pikachu/Pikachu_SkeletalMesh.uasset";
	Config.PhysicsAssetPath = "Content/Data/Pikachu/Pikachu_PhysicsAsset.uasset";
	Config.FleeAnimationPath = "Content/Data/Pikachu/Pikachu_GLTF_created_0_Walking.uasset";
	Config.LuaScriptFile = "GOIncRagdollPawn_Test.lua";

	Config.MeshRelativeLocation = FVector(0.0f, 0.0f, -0.6f);
	Config.MeshRelativeScale = FVector(1.0f, 1.0f, 1.0f);

	Config.AliveCapsuleRadius = 0.4f;
	Config.AliveCapsuleHalfHeight = 0.6f;
	Config.ReviveTriggerCapsuleRadius = 4.0f;
	Config.ReviveTriggerCapsuleHalfHeight = 4.0f;

	Config.bCanRevive = true;
	Config.ReviveBlendDuration = 0.7f;

	Config.FleeSpeed = 7.0f;
	Config.FleeAcceleration = 13.0f;
	Config.FleeBrakingDeceleration = 8.5f;
	Config.FleeEndDistance = 8.5f;
	Config.FleeStopDuration = 0.9f;
	Config.FleeStopMinBrakingDeceleration = 0.1f;
	Config.FleeRotationYawOffsetDegrees = 0.0f;

	Config.FleeAnimationBaseSpeed = 3.4f;
	Config.FleeAnimationMinPlayRate = 0.0f;
	Config.FleeAnimationMaxPlayRate = 1.0f;
	Config.FleeStopStartPlayRate = 1.0f;
	Config.FleeStopEndPlayRate = 0.0f;

	return Config;
}
