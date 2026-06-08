#include "Game/Actors/GOIncIdCard.h"

#include "Component/Movement/BobbingMovementComponent.h"
#include "Component/Primitive/BillboardComponent.h"
#include "Component/Primitive/ParticleSystemComponent.h"
#include "Component/SceneComponent.h"
#include "Component/Shape/BoxComponent.h"
#include "Core/Logging/Log.h"
#include "Core/Types/CollisionTypes.h"
#include "Materials/MaterialManager.h"
#include "Particles/ParticleSystem.h"
#include "Particles/ParticleSystemManager.h"

namespace
{
	const FString IdCardMaterialPath = "Content/Material/IDCard/id_card_dev_KKW.mat";
	const FString PortalTemplatePath = "Content/Particle/FX_StrangePortal.uasset";

	// Default.Scene의 AActor_0 진자 튜닝값을 구운 것
	constexpr float BobAmplitude = 1.0f;
	constexpr float BobFrequency = 0.5f;
	constexpr float BobPhase = 0.0f;
}

// 기본값들은 Default.Scene의 AActor_0 구성을 구운 것
void AGOIncIdCard::InitDefaultComponents()
{
	AddTag(FName("IdCard"));

	// 1) Root — 빌보드/파티클/그랩박스를 형제로 묶는 기준점. Bobbing이 이 Root를 위아래로 움직인다.
	USceneComponent* Root = AddComponent<USceneComponent>();
	Root->SetFName(FName("IdCardRoot"));
	SetRootComponent(Root);

	// 2) Billboard — 신분증 이미지. 항상 카메라를 바라본다 (회전은 카메라가 결정).
	UBillboardComponent* Billboard = AddComponent<UBillboardComponent>();
	Billboard->SetFName(FName("IdCardBillboard"));
	Billboard->AttachToComponent(Root);
	if (UMaterial* CardMat = FMaterialManager::Get().GetOrCreateMaterial(IdCardMaterialPath))
	{
		Billboard->SetMaterial(CardMat);
	}
	Billboard->SetRelativeScale(FVector(1.f, 1.f, 1.5f));

	// 3) PortalFX — 발밑 소환진 파티클 (Summon Portal과 동일 템플릿).
	UParticleSystemComponent* Particle = AddComponent<UParticleSystemComponent>();
	Particle->SetFName(FName("PortalFX"));
	Particle->AttachToComponent(Root);
	if (UParticleSystem* Template = FParticleSystemManager::Get().Load(PortalTemplatePath))
	{
		Particle->SetTemplate(Template);
	}
	else
	{
		UE_LOG("[GOIncIdCard] 파티클 로드 실패. Path=%s", PortalTemplatePath.c_str());
	}

	// 4) GrabBox — Gun 조준 레이캐스트(PrimitiveRaycast)에 걸리는 콜라이더.
	//    QueryOnly·Kinematic — 진자 운동과 충돌하지 않게 물리 시뮬은 끈다.
	//    extent/채널/응답은 배치 후 에디터에서 튜닝한다.
	UBoxComponent* GrabBox = AddComponent<UBoxComponent>();
	GrabBox->SetFName(FName("GrabBox"));
	GrabBox->AttachToComponent(Root);
	GrabBox->SetBoxExtent(FVector(0.5f, 0.5f, 0.5f));
	GrabBox->SetSimulatePhysics(false);
	GrabBox->SetKinematicPhysics(true);
	GrabBox->SetCollisionEnabled(ECollisionEnabled::QueryOnly);
	GrabBox->SetCollisionObjectType(ECollisionChannel::WorldDynamic);
	GrabBox->SetCollisionResponseToAllChannels(ECollisionResponse::Block);

	// 5) Bobbing — Root를 Z축으로 위아래 sin 왕복 (UpdatedComponent는 BeginPlay에서 Root 자동 등록).
	UBobbingMovementComponent* Bobbing = AddComponent<UBobbingMovementComponent>();
	Bobbing->SetFName(FName("Bobbing"));
	Bobbing->SetAmplitude(BobAmplitude);
	Bobbing->SetFrequency(BobFrequency);
	Bobbing->SetPhase(BobPhase);
}
