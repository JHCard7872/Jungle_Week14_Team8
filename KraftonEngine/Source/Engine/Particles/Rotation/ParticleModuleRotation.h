#pragma once
#include "Particles/ParticleModule.h"

#include "Source/Engine/Particles/Rotation/ParticleModuleRotation.generated.h"

// ======================================================
// 스프라이트 초기 회전각 (Spawn 1회).
// 단위는 턴(1.0 = 360도) — FBaseParticle.Rotation(라디안)으로 변환해 넣는다.
// 회전 적분(Rotation += RotationRate*dt)과 렌더(inst.rotation)는
// 엔진에 이미 있으므로 이 모듈은 값만 채운다.
// ======================================================
UCLASS()
class UParticleModuleRotation : public UParticleModule
{
public:
	GENERATED_BODY()
	UParticleModuleRotation();

	UPROPERTY(EditAnywhere, Category = "Rotation")
	float RotationMin = 0.0f;
	UPROPERTY(EditAnywhere, Category = "Rotation")
	float RotationMax = 1.0f;

	virtual void Spawn(const FSpawnContext& Context) override;

	virtual void Serialize(FArchive& Ar) override;
};
