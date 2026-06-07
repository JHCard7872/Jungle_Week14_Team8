#include "GameFramework/Pawn/GOIncDonkeyKongRagdollPawn.h"

FGOIncRagdollCharacterConfig AGOIncDonkeyKongRagdollPawn::MakeCharacterConfig() const
{
	FGOIncRagdollCharacterConfig Config;

	Config.RagdollId = "brown-gorilla";
	Config.DisplayName = "갈색 고릴라";

	Config.SkeletalMeshPath = "Content/Data/DonkeyKong/Dancing Running Man_SkeletalMesh.uasset";
	Config.PhysicsAssetPath = "Content/Data/DonkeyKong/Dancing Running Man_PhysicsAsset.uasset";
	Config.FleeAnimationPath = "Content/Data/DonkeyKong/Dancing Running Man_mixamo_com.uasset";
	Config.LuaScriptFile = "GOIncRagdollPawn_Test.lua";

	Config.MeshRelativeLocation = FVector(0.0f, 0.0f, -1.2f);
	Config.MeshRelativeScale = FVector(1.0f, 1.0f, 1.0f);

	Config.AliveCapsuleRadius = 1.5f;
	Config.AliveCapsuleHalfHeight = 1.8f;
	Config.ReviveTriggerCapsuleRadius = 6.0f;
	Config.ReviveTriggerCapsuleHalfHeight = 6.0f;

	Config.bCanRevive = true;
	Config.ReviveBlendDuration = 0.5f;

	Config.FleeSpeed = 2.8f;
	Config.FleeAcceleration = 10.0f;
	Config.FleeBrakingDeceleration = 8.0f;
	Config.FleeEndDistance = 7.0f;
	Config.FleeStopDuration = 1.2f;
	Config.FleeStopMinBrakingDeceleration = 0.1f;
	Config.FleeRotationYawOffsetDegrees = 0.0f;

	Config.FleeAnimationBaseSpeed = 2.8f;
	Config.FleeAnimationMinPlayRate = 0.0f;
	Config.FleeAnimationMaxPlayRate = 1.0f;
	Config.FleeStopStartPlayRate = 1.0f;
	Config.FleeStopEndPlayRate = 0.0f;

	return Config;
}
