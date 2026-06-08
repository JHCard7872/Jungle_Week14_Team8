#include "GameFramework/Pawn/GOIncKirbyRagdollPawn.h"

FGOIncRagdollCharacterConfig AGOIncKirbyRagdollPawn::MakeCharacterConfig() const
{
	FGOIncRagdollCharacterConfig Config;

	Config.RagdollId = "pink-round";
	Config.DisplayName = "분홍 동글이";

	Config.SkeletalMeshPath = "Content/Data/Kirby/kirby_Animated2_SkeletalMesh.uasset";
	Config.PhysicsAssetPath = "Content/Data/Kirby/kirby_Animated2_PhysicsAsset.uasset";
	Config.FleeAnimationPath = "Content/Data/Kirby/kirby_Animated2_Kirb_Skeleton_Run_Animation.uasset";
	Config.LuaScriptFile = "GOIncRagdollPawn_Test.lua";

	Config.MeshRelativeLocation = FVector(0.0f, 0.0f, 0.0f);
	Config.MeshRelativeScale = FVector(0.5f, 0.5f, 0.5f);

	Config.AliveCapsuleRadius = 0.5f;
	Config.AliveCapsuleHalfHeight = 0.5f;
	Config.ReviveTriggerCapsuleRadius = 16.0f;
	Config.ReviveTriggerCapsuleHalfHeight = 16.0f;

	Config.bCanRevive = true;
	Config.ReviveBlendDuration = 0.2f;

	Config.FleeSpeed = 12.0f;
	Config.FleeAcceleration = 12.0f;
	Config.FleeBrakingDeceleration = 8.0f;
	Config.FleeEndDistance = 30.0f;
	Config.FleeStopDuration = 0.8f;
	Config.FleeStopMinBrakingDeceleration = 0.1f;
	Config.FleeRotationYawOffsetDegrees = 0.0f;

	Config.FleeAnimationBaseSpeed = 3.2f;
	Config.FleeAnimationMinPlayRate = 0.0f;
	Config.FleeAnimationMaxPlayRate = 1.8f;
	Config.FleeStopStartPlayRate = 1.8f;
	Config.FleeStopEndPlayRate = 0.0f;

	return Config;
}
