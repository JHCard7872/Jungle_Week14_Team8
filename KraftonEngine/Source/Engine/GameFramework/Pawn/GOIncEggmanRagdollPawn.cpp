#include "GameFramework/Pawn/GOIncEggmanRagdollPawn.h"

FGOIncRagdollCharacterConfig AGOIncEggmanRagdollPawn::MakeCharacterConfig() const
{
	FGOIncRagdollCharacterConfig Config;

	Config.RagdollId = "egg-scientist";
	Config.DisplayName = "에그 과학자";

	Config.SkeletalMeshPath = "Content/Data/Eggman/eggman_SkeletalMesh.uasset";
	Config.PhysicsAssetPath = "Content/Data/Eggman/eggman_PhysicsAsset.uasset";
	Config.FleeAnimationPath = "Content/Data/Eggman/Injured Run_mixamo_com.uasset";
	Config.LuaScriptFile = "GOIncRagdollPawn_Test.lua";

	Config.MeshRelativeLocation = FVector(0.0f, 0.0f, -1.0f);
	Config.MeshRelativeScale = FVector(1.0f, 1.0f, 1.0f);

	Config.AliveCapsuleRadius = 0.4f;
	Config.AliveCapsuleHalfHeight = 1.0f;
	Config.ReviveTriggerCapsuleRadius = 5.0f;
	Config.ReviveTriggerCapsuleHalfHeight = 5.0f;

	Config.bCanRevive = true;
	Config.ReviveBlendDuration = 0.5f;

	Config.FleeSpeed = 3.0f;
	Config.FleeAcceleration = 11.0f;
	Config.FleeBrakingDeceleration = 8.0f;
	Config.FleeEndDistance = 8.0f;
	Config.FleeStopDuration = 1.0f;
	Config.FleeStopMinBrakingDeceleration = 0.1f;
	Config.FleeRotationYawOffsetDegrees = 0.0f;

	Config.FleeAnimationBaseSpeed = 3.0f;
	Config.FleeAnimationMinPlayRate = 0.0f;
	Config.FleeAnimationMaxPlayRate = 1.0f;
	Config.FleeStopStartPlayRate = 1.0f;
	Config.FleeStopEndPlayRate = 0.0f;

	return Config;
}
