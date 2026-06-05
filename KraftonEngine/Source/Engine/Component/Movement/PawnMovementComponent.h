#pragma once

#include "MovementComponent.h"

// APawn 계열에서 사용할 최소 이동 컴포넌트 베이스.
// 이번 단계에서는 ARespawnRagdollPawn 의 UpdatedComponent 연결용 껍데기만 제공하고,
// 실제 AddInputVector/Velocity/Sweep 이동 로직은 후속 패치에서 확장한다.
#include "Source/Engine/Component/Movement/PawnMovementComponent.generated.h"

UCLASS()
class UPawnMovementComponent : public UMovementComponent
{
public:
	GENERATED_BODY()
	UPawnMovementComponent() = default;
	~UPawnMovementComponent() override = default;
};
