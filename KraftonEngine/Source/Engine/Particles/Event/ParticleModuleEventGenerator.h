#pragma once
#include "Core/Types/CoreTypes.h"
#include "ParticleModuleEventBase.h"

#include "Source/Engine/Particles/Event/ParticleModuleEventGenerator.generated.h"

// ======================================================
// 파티클 이벤트 발화기 — 이 에미터의 입자가 스폰/자연사할 때
// 컴포넌트의 ParticleEvents 파이프에 이벤트를 쌓는다.
// 발화 자체는 FParticleEmitterInstance(스폰 루프/자연사 스윕)가 하고,
// 이 모듈은 "무엇을 어떤 이름으로 쏠지" 설정만 담는다.
// 같은 컴포넌트의 다른 에미터가 EventReceiverSpawn으로 수신한다.
// ======================================================
UCLASS()
class UParticleModuleEventGenerator : public UParticleModuleEventBase
{
public:
	GENERATED_BODY()

	// 충돌 이벤트는 아직 발화 지점이 없다 — 직렬화 순서 유지를 위해 필드만 보존
	bool bGenerateCollisionEvents = false;
	UPROPERTY(EditAnywhere, Category = "Event")
	bool bGenerateDeathEvents = false;
	UPROPERTY(EditAnywhere, Category = "Event")
	bool bGenerateSpawnEvents = false;

	// 수신측 필터 키 — 수신 모듈의 EventNameFilter와 일치해야 잡힌다 (빈 필터 = 전체 수신)
	UPROPERTY(EditAnywhere, Category = "Event")
	FString EventName;

	virtual void Serialize(FArchive& Ar) override;
};
