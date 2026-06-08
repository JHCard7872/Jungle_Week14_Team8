#include "GameFramework/Pawn/GOIncLinkRagdollPawn.h"

FGOIncRagdollCharacterConfig AGOIncLinkRagdollPawn::MakeCharacterConfig() const
{
	FGOIncRagdollCharacterConfig Config;

	Config.RagdollId = "green-swordsman";
	Config.DisplayName = "초록 검사";

	Config.SkeletalMeshPath = "Content/Data/Link/Link_Injured_Run_SkeletalMesh.uasset";
	Config.PhysicsAssetPath = "Content/Data/Link/Link_Injured_Run_PhysicsAsset.uasset";
	Config.FleeAnimationPath = "Content/Data/Link/Link_Injured_Run_mixamo_com.uasset";
	Config.LuaScriptFile = "GOIncRagdollPawn_Test.lua";

	Config.MeshRelativeLocation = FVector(0.0f, 0.0f, -0.9f);
	Config.MeshRelativeScale = FVector(1.0f, 1.0f, 1.0f);

	Config.AliveCapsuleRadius = 0.25f;
	Config.AliveCapsuleHalfHeight = 0.9f;
	Config.ReviveTriggerCapsuleRadius = 20.0f;
	Config.ReviveTriggerCapsuleHalfHeight = 20.0f;

	Config.bCanRevive = true;
	Config.ReviveBlendDuration = 0.5f;

	Config.FleeSpeed = 7.0f;
	Config.FleeAcceleration = 14.0f;
	Config.FleeBrakingDeceleration = 9.0f;
	Config.FleeEndDistance = 30.0f;
	Config.FleeStopDuration = 0.9f;
	Config.FleeStopMinBrakingDeceleration = 0.1f;
	Config.FleeRotationYawOffsetDegrees = 0.0f;

	Config.FleeAnimationBaseSpeed = 3.8f;
	Config.FleeAnimationMinPlayRate = 0.0f;
	Config.FleeAnimationMaxPlayRate = 1.3f;
	Config.FleeStopStartPlayRate = 1.3f;
	Config.FleeStopEndPlayRate = 0.0f;

	return Config;
}
