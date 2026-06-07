#pragma once
#include "Core/Types/CoreTypes.h"
#include "ParticleModuleEventBase.h"

#include "Source/Engine/Particles/Event/ParticleModuleEventReceiverSpawn.generated.h"

// ======================================================
// 파티클 이벤트 수신기 — 같은 컴포넌트의 EventGenerator가 쏜 이벤트를 받아
// "이벤트가 난 위치에서" 이 에미터의 입자를 버스트 스폰한다.
// 예: 위스프 에미터(자연사 이벤트) + 이 모듈을 단 플래시 에미터
//     → 위스프가 사라지는 지점마다 반짝.
// 스폰된 입자에는 이 에미터의 Spawn 모듈 체인(수명/크기/색)이 그대로 적용된다.
// ======================================================
UCLASS()
class UParticleModuleEventReceiverSpawn : public UParticleModuleEventBase
{
public:
	GENERATED_BODY()
	UParticleModuleEventReceiverSpawn();

	UPROPERTY(EditAnywhere, Category = "Event")
	bool bAcceptSpawnEvents = false;
	UPROPERTY(EditAnywhere, Category = "Event")
	bool bAcceptDeathEvents = true;

	// 생성기 EventName과 일치해야 수신 (빈 문자열 = 전체 수신)
	UPROPERTY(EditAnywhere, Category = "Event")
	FString EventNameFilter;

	// 이벤트 1건당 스폰 수 (Min~Max 추첨)
	UPROPERTY(EditAnywhere, Category = "Event")
	int32 SpawnCountMin = 1;
	UPROPERTY(EditAnywhere, Category = "Event")
	int32 SpawnCountMax = 1;

	// 이벤트 주인의 속도를 물려받는 비율 (0 = 제자리 스폰)
	UPROPERTY(EditAnywhere, Category = "Event")
	float InheritVelocityScale = 0.0f;

	virtual void Update(const FUpdateContext& Context) override;

	virtual void Serialize(FArchive& Ar) override;
};
