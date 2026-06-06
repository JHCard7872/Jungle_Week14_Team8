#pragma once

#include "GameFramework/AActor.h"

#include "Source/Game/Actors/GOIncTruck.generated.h"

// ======================================================
// AGOIncTruck — 수거 트럭 액터 (TruckTest.Scene의 Truck 구성을 클래스화)
// Root(SceneComponent) 아래 TruckMesh + CollectTrigger(BoxComponent) 형제 구조.
// 주행/수거 로직은 C++이 아니라 TruckBehavior.lua가 담당한다.
// 트리거는 QueryOnly·Kinematic·GenerateOverlapEvents=true 조합 — 하나라도
// 빠지면 OnOverlap이 안 와서 수거가 조용히 죽는다.
// ======================================================
UCLASS()
class AGOIncTruck : public AActor
{
public:
	GENERATED_BODY()
	AGOIncTruck() = default;
	~AGOIncTruck() override = default;

	// TruckTest.Scene에 저장된 Truck 액터와 동일한 기본 구성을 만든다.
	// (에디터 Place Actor / 코드 스폰 직후 호출 — 씬 로드 시에는 직렬화가 복원)
	void InitDefaultComponents();
};
