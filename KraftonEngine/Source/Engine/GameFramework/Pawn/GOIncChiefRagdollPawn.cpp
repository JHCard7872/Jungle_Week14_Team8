#include "GameFramework/Pawn/GOIncChiefRagdollPawn.h"

FGOIncRagdollCharacterConfig AGOIncChiefRagdollPawn::MakeCharacterConfig() const
{
	FGOIncRagdollCharacterConfig Config;

	Config.RagdollId = "space-chief";
	Config.DisplayName = "스페이스 치프";

	Config.SkeletalMeshPath = "Content/Data/chief/Injured Run_SkeletalMesh.uasset";
	Config.PhysicsAssetPath = "Content/Data/chief/Injured Run_PhysicsAsset.uasset";
	Config.FleeAnimationPath = "Content/Data/chief/Injured Run_mixamo_com.uasset";
	Config.LuaScriptFile = "GOIncRagdollPawn_Test.lua";

	Config.MeshRelativeLocation = FVector(0.0f, 0.0f, -1.0f);
	Config.MeshRelativeScale = FVector(1.0f, 1.0f, 1.0f);

	Config.AliveCapsuleRadius = 0.3f;
	Config.AliveCapsuleHalfHeight = 0.9f;
	Config.ReviveTriggerCapsuleRadius = 10.0f;
	Config.ReviveTriggerCapsuleHalfHeight = 10.0f;

	Config.bCanRevive = false;
	Config.ReviveBlendDuration = 0.5f;

	Config.FleeSpeed = 3.4f;
	Config.FleeAcceleration = 12.0f;
	Config.FleeBrakingDeceleration = 8.5f;
	Config.FleeEndDistance = 20.0f;
	Config.FleeStopDuration = 1.0f;
	Config.FleeStopMinBrakingDeceleration = 0.1f;
	Config.FleeRotationYawOffsetDegrees = 0.0f;

	Config.FleeAnimationBaseSpeed = 3.4f;
	Config.FleeAnimationMinPlayRate = 0.0f;
	Config.FleeAnimationMaxPlayRate = 1.0f;
	Config.FleeStopStartPlayRate = 1.0f;
	Config.FleeStopEndPlayRate = 0.0f;

	return Config;
}
