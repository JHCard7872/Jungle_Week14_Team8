#pragma once
#include "Particles/ParticleModule.h"

#include "Source/Engine/Particles/RotationRate/ParticleModuleRotationRate.generated.h"

// ======================================================
// 스프라이트 회전 속도 (Spawn 1회 — BaseRotationRate에 기록).
// 단위는 턴/초(1.0 = 초당 한 바퀴). 매 틱 리셋 루프가
// RotationRate = BaseRotationRate로 복원하므로 Base에 더해둬야 지속된다.
// ======================================================
UCLASS()
class UParticleModuleRotationRate : public UParticleModule
{
public:
	GENERATED_BODY()
	UParticleModuleRotationRate();

	UPROPERTY(EditAnywhere, Category = "Rotation")
	float RotationRateMin = 0.1f;
	UPROPERTY(EditAnywhere, Category = "Rotation")
	float RotationRateMax = 0.5f;

	virtual void Spawn(const FSpawnContext& Context) override;

	virtual void Serialize(FArchive& Ar) override;
};
