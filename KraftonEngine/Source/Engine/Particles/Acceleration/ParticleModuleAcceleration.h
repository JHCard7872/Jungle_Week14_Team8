#pragma once
#include "Particles/ParticleModule.h"

#include "Source/Engine/Particles/Acceleration/ParticleModuleAcceleration.generated.h"

// ======================================================
// 상수 가속도 (Update 매 틱) — 중력, 바람 같은 일정한 힘.
// 매 틱 리셋 루프가 Velocity = BaseVelocity로 복원하므로
// Base에 누적해야 지속된다 (VortexRotation에서 확립한 패턴).
// 기본값은 약한 중력 — 포탈 불똥이 튀고 떨어지는 연출용.
// ======================================================
UCLASS()
class UParticleModuleAcceleration : public UParticleModule
{
public:
	GENERATED_BODY()
	UParticleModuleAcceleration();

	// 월드 공간 가속도 (m/s^2). Z-up이므로 중력은 -Z
	UPROPERTY(EditAnywhere, Category = "Acceleration")
	FVector Acceleration = FVector(0.0f, 0.0f, -9.8f);

	virtual void Update(const FUpdateContext& Context) override;

	virtual void Serialize(FArchive& Ar) override;
};
