#pragma once

#include "GameFramework/AActor.h"

#include "Source/Game/Actors/GOIncBasket.generated.h"

// ======================================================
// AGOIncBasket — 들고 다니는 "큰 바구니" 액터 (plastic-laundry-basket 메시)
// Root(SceneComponent) 아래 BasketMesh(StaticMesh) 단일 동적 바디 구조.
// 레이저 그랩(PhysicsGrabRaycast는 UStaticMeshComponent 바디를 허용)으로 집어서
// 통째로 운반한다 — SimulatePhysics=true 라야 그랩 스프링 힘(AddForce)이 먹는다.
// 메시에 별도 충돌이 없으면 UStaticMesh::EnsureDefaultBodySetup이 바운드 박스를
// 충돌로 만들어주므로, 래그돌은 바구니 위/안에 얹혀 같이 끌려온다.
// "Basket" 태그가 핵심 — 포탈 순간이동(GOIncTestActor.teleport_player_with_grab)이
// 이 태그를 보고 바구니 부피 안의 래그돌들도 같은 delta로 함께 옮긴다.
// 메시 스케일은 에디터/씬에서 키워 맞춘다(기본값은 크게 잡아둠).
// ======================================================
UCLASS()
class AGOIncBasket : public AActor
{
public:
	GENERATED_BODY()
	AGOIncBasket() = default;
	~AGOIncBasket() override = default;

	// 에디터 Place Actor / 코드 스폰 직후 호출 — 씬 로드 시에는 직렬화가 복원
	void InitDefaultComponents();
};
