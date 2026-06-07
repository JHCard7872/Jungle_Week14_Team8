#include "GameFramework/Pawn/GOIncPeachRagdollPawn.h"

FGOIncRagdollCharacterConfig AGOIncPeachRagdollPawn::MakeCharacterConfig() const
{
	FGOIncRagdollCharacterConfig Config;

	Config.RagdollId = "pink-princess";
	Config.DisplayName = "분홍 공주";

	Config.SkeletalMeshPath = "Content/Data/Peach/Peach_Injured_Run_SkeletalMesh.uasset";
	Config.PhysicsAssetPath = "Content/Data/Peach/Peach_Injured_Run_PhysicsAsset.uasset";
	Config.FleeAnimationPath = "Content/Data/Peach/Peach_Injured_Run_mixamo_com.uasset";
	Config.LuaScriptFile = "GOIncRagdollPawn_Test.lua";

	Config.MeshRelativeLocation = FVector(0.0f, 0.0f, -1.1f);
	Config.MeshRelativeScale = FVector(1.0f, 1.0f, 1.0f);

	Config.AliveCapsuleRadius = 0.8f;
	Config.AliveCapsuleHalfHeight = 1.5f;
	Config.ReviveTriggerCapsuleRadius = 4.5f;
	Config.ReviveTriggerCapsuleHalfHeight = 4.5f;

	Config.bCanRevive = true;
	Config.ReviveBlendDuration = 0.8f;

	Config.FleeSpeed = 3.6f;
	Config.FleeAcceleration = 13.0f;
	Config.FleeBrakingDeceleration = 8.5f;
	Config.FleeEndDistance = 8.5f;
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
