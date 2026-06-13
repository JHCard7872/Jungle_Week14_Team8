#include "Game/Actors/GOIncBasket.h"

#include "Component/Primitive/StaticMeshComponent.h"
#include "Component/SceneComponent.h"
#include "Core/Types/CollisionTypes.h"
#include "Materials/MaterialManager.h"
#include "Mesh/MeshManager.h"
#include "Runtime/Engine.h"

namespace
{
	// FBX 소스를 직접 로드한다 — FMeshManager::LoadStaticMesh는 .obj/.fbx 원본 경로를
	// 받으면 런타임에 import하고 .statbin으로 캐시한다(.uasset 선임포트 불필요).
	const FString BasketStaticMeshPath = "Content/Data/plastic-laundry-basket/source/PlasticWashingbasket.fbx";
	const FString BasketMaterialPath   = "Content/Material/Auto/PlasticLaundryBasket.mat";

	// 임포트 직후 바구니가 매우 작게 들어오는 편이라 기본 스케일을 크게 잡아둔다.
	// 가로(X/Y)는 넓게, 높이(Z)는 낮춰 빨래바구니 비율에 맞춘다. 최종 크기는 에디터/씬에서
	// 조정하고, 맞춰서 GOIncTestActorData.lua의 BASKET_CARRY_HALF_EXTENT(래그돌 동반 판정 부피)도 손본다.
	const FVector BasketDefaultScale(10.0f, 10.0f, 5.0f);
	const float   BasketDefaultMass = 24.0f;
}

void AGOIncBasket::InitDefaultComponents()
{
	// 포탈 순간이동(GOIncTestActor.teleport_player_with_grab)이 이 태그로 바구니를 식별해
	// 부피 안의 래그돌까지 함께 옮긴다. 태그 이름이 Lua 상수(C.BASKET_TAG)와 일치해야 한다.
	AddTag(FName("Basket"));

	// 1) Root — 메시를 매다는 기준점.
	USceneComponent* Root = AddComponent<USceneComponent>();
	Root->SetFName(FName("BasketRoot"));
	SetRootComponent(Root);

	// 2) BasketMesh — 시각 + 충돌 + 그랩 대상이 되는 단일 동적 바디.
	//    PhysicsGrabRaycast는 UStaticMeshComponent 바디만 그랩 허용 → 메시 자체가 바디여야 한다.
	//    SimulatePhysics=true 라야 그랩 스프링(AddForce)이 먹는다. 별도 충돌이 없으면
	//    UStaticMesh::EnsureDefaultBodySetup이 바운드 박스를 충돌로 만들어 준다.
	UStaticMeshComponent* Mesh = AddComponent<UStaticMeshComponent>();
	Mesh->SetFName(FName("BasketMesh"));
	Mesh->AttachToComponent(Root);
	Mesh->SetRelativeScale(BasketDefaultScale);

	if (GEngine)
	{
		ID3D11Device* Device = GEngine->GetRenderer().GetFD3DDevice().GetDevice();
		if (UStaticMesh* Loaded = FMeshManager::LoadStaticMesh(BasketStaticMeshPath, Device))
		{
			Mesh->SetStaticMesh(Loaded);
		}
	}
	if (UMaterial* BasketMat = FMaterialManager::Get().GetOrCreateMaterial(BasketMaterialPath))
	{
		Mesh->SetMaterial(0, BasketMat);
	}

	// 그랩 가능 + 물리 시뮬레이션. 동적 오브젝트로 두고 모든 채널을 Block 한다.
	Mesh->SetCollisionEnabled(ECollisionEnabled::QueryAndPhysics);
	Mesh->SetCollisionObjectType(ECollisionChannel::WorldDynamic);
	Mesh->SetCollisionResponseToAllChannels(ECollisionResponse::Block);
	Mesh->SetEnableGravity(true);
	Mesh->SetSimulatePhysics(true);
	Mesh->SetMass(BasketDefaultMass);
}
