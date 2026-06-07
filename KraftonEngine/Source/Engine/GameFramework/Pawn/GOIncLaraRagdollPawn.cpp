#include "GameFramework/Pawn/GOIncLaraRagdollPawn.h"

FGOIncRagdollCharacterConfig AGOIncLaraRagdollPawn::MakeCharacterConfig() const
{
	FGOIncRagdollCharacterConfig Config;

	Config.RagdollId = "adventurer";
	Config.DisplayName = "모험가";

	Config.SkeletalMeshPath = "Content/Data/lara_new/Injured Run_SkeletalMesh.uasset";
	Config.PhysicsAssetPath = "Content/Data/lara_new/Injured Run_PhysicsAsset.uasset";
	Config.FleeAnimationPath = "Content/Data/lara_new/Injured Run_mixamo_com.uasset";
	Config.LuaScriptFile = "GOIncRagdollPawn_Test.lua";

	Config.MeshRelativeLocation = FVector(0.0f, 0.0f, -0.9f);
	Config.MeshRelativeScale = FVector(1.0f, 1.0f, 1.0f);

	Config.AliveCapsuleRadius = 0.3f;
	Config.AliveCapsuleHalfHeight = 0.9f;
	Config.ReviveTriggerCapsuleRadius = 4.5f;
	Config.ReviveTriggerCapsuleHalfHeight = 4.5f;

	Config.bCanRevive = true;
	Config.ReviveBlendDuration = 0.8f;

	Config.FleeSpeed = 3.7f;
	Config.FleeAcceleration = 13.5f;
	Config.FleeBrakingDeceleration = 8.5f;
	Config.FleeEndDistance = 8.5f;
	Config.FleeStopDuration = 0.9f;
	Config.FleeStopMinBrakingDeceleration = 0.1f;
	Config.FleeRotationYawOffsetDegrees = 0.0f;

	Config.FleeAnimationBaseSpeed = 3.7f;
	Config.FleeAnimationMinPlayRate = 0.0f;
	Config.FleeAnimationMaxPlayRate = 1.0f;
	Config.FleeStopStartPlayRate = 1.0f;
	Config.FleeStopEndPlayRate = 0.0f;

	return Config;
}
