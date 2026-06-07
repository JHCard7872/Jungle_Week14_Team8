#pragma once
#include "Particles/ParticleModule.h"

#include "Source/Engine/Particles/Attractor/ParticleModuleAttractorPoint.generated.h"

// ======================================================
// 지점 흡인 (Update 매 틱) — 입자를 에미터 중심으로 가속시켜 빨아들인다.
// KillRadius 안에 들어오면 즉시 소멸 — 음수 방사 속도와 달리
// 중심을 관통하지 않아 "기가 모이는" 충전 연출에 맞는다.
// 매 틱 리셋 루프 호환을 위해 BaseVelocity에 누적한다.
// ======================================================
UCLASS()
class UParticleModuleAttractorPoint : public UParticleModule
{
public:
	GENERATED_BODY()
	UParticleModuleAttractorPoint();

	// 흡인 가속도 (m/s^2) — 클수록 빨리 모인다
	UPROPERTY(EditAnywhere, Category = "Attractor")
	float Strength = 10.0f;

	// 이 반경 안에 들어오면 입자 소멸 (0 = 소멸 없음, 관통 허용)
	UPROPERTY(EditAnywhere, Category = "Attractor")
	float KillRadius = 0.05f;

	virtual void Update(const FUpdateContext& Context) override;

	virtual void Serialize(FArchive& Ar) override;
};
