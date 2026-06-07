#include "Game/Actors/GOIncTrashBox.h"

#include "Component/Primitive/DecalComponent.h"
#include "Component/Primitive/StaticMeshComponent.h"
#include "Component/SceneComponent.h"
#include "Component/Script/LuaScriptComponent.h"
#include "Component/Shape/BoxComponent.h"
#include "Core/Types/CollisionTypes.h"
#include "Materials/MaterialManager.h"
#include "Mesh/MeshManager.h"
#include "Runtime/Engine.h"

namespace
{
	const FString TrashBoxStaticMeshPath = "Content/Data/Box/TrashBox_StaticMesh.uasset";
	const FString TrashBoxMaterialPath = "Content/Material/Auto/Material.013.mat";
	const FString CollectorLuaScriptFile = "CollectorBehavior.lua";
	const FString LogoDecalMaterialPath = "Content/Material/Decal/Decal_game_over_inc_icon.mat";
}

// 기본값들은 Default.Scene의 AGOIncTrashBox_0 튜닝값을 구운 것 (씬 scale은 extent에 반영)
void AGOIncTrashBox::InitDefaultComponents()
{
	AddTag(FName("TrashBox"));

	// 1) Root — 메시/트리거/데칼/벽을 형제로 묶는 기준점.
	USceneComponent* Root = AddComponent<USceneComponent>();
	Root->SetFName(FName("TrashBoxRoot"));
	SetRootComponent(Root);

	// 2) TrashBoxMesh — 시각 표현만 담당, 충돌은 4면 벽이 전담.
	//    z+4.4로 올려 바닥을 액터 원점에 맞춘다 (메시 원본 바운드: X ±7, Y ±13.6, Z -4.4 ~ 9.2)
	UStaticMeshComponent* Mesh = AddComponent<UStaticMeshComponent>();
	Mesh->SetFName(FName("TrashBoxMesh"));
	Mesh->AttachToComponent(Root);
	Mesh->SetRelativeLocation(FVector(0.0f, 0.0f, 4.402424f));
	Mesh->SetCollisionEnabled(ECollisionEnabled::NoCollision);
	if (GEngine)
	{
		ID3D11Device* Device = GEngine->GetRenderer().GetFD3DDevice().GetDevice();
		if (UStaticMesh* Loaded = FMeshManager::LoadStaticMesh(TrashBoxStaticMeshPath, Device))
		{
			Mesh->SetStaticMesh(Loaded);
		}
	}
	if (UMaterial* BoxMat = FMaterialManager::Get().GetOrCreateMaterial(TrashBoxMaterialPath))
	{
		Mesh->SetMaterial(0, BoxMat);
	}

	// 3) CollectTrigger — 박스 내부 수거 판정. 메시 내부 공간이 X로 길어서
	//    yaw -89.26으로 눕혀 맞춘 상태 (extent 장축이 액터 X방향을 향한다)
	UBoxComponent* Trigger = AddComponent<UBoxComponent>();
	Trigger->SetFName(FName("CollectTrigger"));
	Trigger->AttachToComponent(Root);
	Trigger->SetRelativeLocation(FVector(0.0f, -0.289363f, 5.373981f));
	Trigger->SetRelativeRotation(FRotator(0.0f, -89.264374f, 0.0f));
	Trigger->SetBoxExtent(FVector(5.724f, 10.994f, 4.272f));
	Trigger->SetSimulatePhysics(false);
	Trigger->SetKinematicPhysics(true);
	Trigger->SetGenerateOverlapEvents(true);
	Trigger->SetCollisionEnabled(ECollisionEnabled::QueryOnly);
	Trigger->SetCollisionObjectType(ECollisionChannel::Trigger);
	Trigger->SetCollisionResponseToAllChannels(ECollisionResponse::Overlap);

	// 4) LogoDecal — 측면에 로고 투영. Decal.hlsl이 데칼 로컬 +X 방향으로 투영하고
	//    로컬 Y가 이미지 가로, Z가 세로다.
	UDecalComponent* Decal = AddComponent<UDecalComponent>();
	Decal->SetFName(FName("LogoDecal"));
	Decal->AttachToComponent(Root);
	Decal->SetRelativeLocation(FVector(-1.492686f, 6.124441f, 6.828254f));
	Decal->SetRelativeRotation(FRotator(4.49f, -90.0f, 0.0f));
	Decal->SetRelativeScale(FVector(4.0f, 8.0f, 8.0f));
	if (UMaterial* DecalMat = FMaterialManager::Get().GetOrCreateMaterial(LogoDecalMaterialPath))
	{
		Decal->SetMaterial(DecalMat);
	}

	// 5) 4면 벽 — 래그돌이 위 입구로만 들어가게 물리로 막는다.
	//    Play.Scene 지형과 같은 정적 블로커 조합(QueryAndPhysics·WorldStatic·Block).
	//    메시 내부 공간(X -11.5~11.7, Y -6.3~5.3)에 맞춰 전부 yaw 90 회전 배치 —
	//    이름은 최초 배치 기준이라 실제 막는 면과 다르다 (PX/NX=Y방향 벽, PY/NY=X방향 벽).
	struct FWallDef { const char* Name; FVector Location; FVector Extent; };
	const FWallDef Walls[] = {
		{ "WallPX", FVector( -0.177349f,  5.320573f, 6.8f), FVector(0.5f, 13.6f, 6.8f) },
		{ "WallNX", FVector(  0.021723f, -6.299274f, 6.8f), FVector(0.5f, 13.6f, 6.8f) },
		{ "WallPY", FVector( 11.656894f,  1.0f,      6.8f), FVector(7.0f,  0.5f, 6.8f) },
		{ "WallNY", FVector(-11.5f,      -0.084033f, 6.8f), FVector(7.0f,  0.5f, 6.8f) },
	};
	for (const FWallDef& Def : Walls)
	{
		UBoxComponent* Wall = AddComponent<UBoxComponent>();
		Wall->SetFName(FName(Def.Name));
		Wall->AttachToComponent(Root);
		Wall->SetRelativeLocation(Def.Location);
		Wall->SetRelativeRotation(FRotator(0.0f, 90.0f, 0.0f));
		Wall->SetBoxExtent(Def.Extent);
		Wall->SetCollisionEnabled(ECollisionEnabled::QueryAndPhysics);
		Wall->SetCollisionObjectType(ECollisionChannel::WorldStatic);
		Wall->SetCollisionResponseToAllChannels(ECollisionResponse::Block);
	}

	// 6) LuaScript — 수거(점수/미션/소멸) 처리 전부 Lua에서.
	ULuaScriptComponent* Script = AddComponent<ULuaScriptComponent>();
	Script->SetScriptFile(CollectorLuaScriptFile);
}
