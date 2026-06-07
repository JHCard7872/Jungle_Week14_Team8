#include "GameFramework/Pawn/GOIncBowserRagdollPawn.h"

FGOIncRagdollCharacterConfig AGOIncBowserRagdollPawn::MakeCharacterConfig() const
{
	FGOIncRagdollCharacterConfig Config;

	Config.RagdollId = "spiked-king";
	Config.DisplayName = "가시 대왕";

	Config.SkeletalMeshPath = "Content/Data/Bowser/Bowser_SkeletalMesh.uasset";
	Config.PhysicsAssetPath = "Content/Data/Bowser/Bowser_PhysicsAsset.uasset";
	Config.FleeAnimationPath = "Content/Data/Bowser/Injured Run_mixamo_com.uasset";
	Config.LuaScriptFile = "GOIncRagdollPawn_Test.lua";

	Config.MeshRelativeLocation = FVector(0.0f, 0.0f, -1.4f);
	Config.MeshRelativeScale = FVector(1.0f, 1.0f, 1.0f);

	Config.AliveCapsuleRadius = 1.4f;
	Config.AliveCapsuleHalfHeight = 1.8f;
	Config.ReviveTriggerCapsuleRadius = 6.0f;
	Config.ReviveTriggerCapsuleHalfHeight = 6.0f;

	Config.bCanRevive = true;
	Config.ReviveBlendDuration = 1.0f;

	Config.FleeSpeed = 2.6f;
	Config.FleeAcceleration = 10.0f;
	Config.FleeBrakingDeceleration = 8.0f;
	Config.FleeEndDistance = 7.0f;
	Config.FleeStopDuration = 1.2f;
	Config.FleeStopMinBrakingDeceleration = 0.1f;
	Config.FleeRotationYawOffsetDegrees = 0.0f;

	Config.FleeAnimationBaseSpeed = 2.6f;
	Config.FleeAnimationMinPlayRate = 0.0f;
	Config.FleeAnimationMaxPlayRate = 1.0f;
	Config.FleeStopStartPlayRate = 1.0f;
	Config.FleeStopEndPlayRate = 0.0f;

	return Config;
}
