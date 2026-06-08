#include "GameFramework/Pawn/GOIncMarioRagdollPawn.h"

FGOIncRagdollCharacterConfig AGOIncMarioRagdollPawn::MakeCharacterConfig() const
{
	FGOIncRagdollCharacterConfig Config;

	Config.RagdollId = "red-plumber";
	Config.DisplayName = "빨간 배관공";

	Config.SkeletalMeshPath = "Content/Data/Mario/Mario_SkeletalMesh.uasset";
	Config.PhysicsAssetPath = "Content/Data/Mario/Mario_PhysicsAsset.uasset";
	Config.FleeAnimationPath = "Content/Data/Mario/Mario_mixamo_com.uasset";
	Config.LuaScriptFile = "GOIncRagdollPawn_Test.lua";

	Config.MeshRelativeLocation = FVector(0.0f, 0.0f, -0.8f);
	Config.MeshRelativeScale = FVector(1.0f, 1.0f, 1.0f);

	Config.AliveCapsuleRadius = 0.4f;
	Config.AliveCapsuleHalfHeight = 0.8f;
	Config.ReviveTriggerCapsuleRadius = 10.0f;
	Config.ReviveTriggerCapsuleHalfHeight = 10.0f;

	Config.bCanRevive = true;
	Config.ReviveBlendDuration = 0.5f;

	Config.FleeSpeed = 3.6f;
	Config.FleeAcceleration = 13.0f;
	Config.FleeBrakingDeceleration = 8.5f;
	Config.FleeEndDistance = 20.0f;
	Config.FleeStopDuration = 0.9f;
	Config.FleeStopMinBrakingDeceleration = 0.1f;
	Config.FleeRotationYawOffsetDegrees = 0.0f;

	Config.FleeAnimationBaseSpeed = 3.6f;
	Config.FleeAnimationMinPlayRate = 0.0f;
	Config.FleeAnimationMaxPlayRate = 1.0f;
	Config.FleeStopStartPlayRate = 1.0f;
	Config.FleeStopEndPlayRate = 0.0f;

	return Config;
}
