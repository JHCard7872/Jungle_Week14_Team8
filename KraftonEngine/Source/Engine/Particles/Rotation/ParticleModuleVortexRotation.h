#pragma once
#include "Particles/ParticleModule.h"

#include "Source/Engine/Particles/Rotation/ParticleModuleVortexRotation.generated.h"

// ======================================================
// 소용돌이 회전 (Update 매 틱) — 입자 위치/속도를 에미터 중심의
// 선택한 축 기준으로 회전시킨다. UE 캐스케이드 Orbit의 실용 대체:
// 렌더 오프셋 체이닝 없이 시뮬레이션 위치를 직접 돌려서 와류를 만든다.
// 축은 엔진 로테이터 컨벤션(X:Roll, Y:Pitch, Z:Yaw)을 따르고,
// 에미터(컴포넌트) 회전을 통과시키므로 액터를 돌려 세우면 와류도 따라 선다.
// 단위는 턴/초. 입자별 속도는 스폰 시 페이로드에 추첨해 고정한다.
// 음수 방사 속도(흡입)와 조합하면 "회전하며 빨려드는" 소용돌이가 된다.
// ======================================================

struct FVortexRotationPayload
{
	float RadiansPerSecond = 0.0f;
	float Pad = 0.0f;
};

UCLASS()
class UParticleModuleVortexRotation : public UParticleModule
{
public:
	GENERATED_BODY()
	UParticleModuleVortexRotation();

	UPROPERTY(EditAnywhere, Category = "Vortex")
	float TurnsPerSecondMin = 0.5f;
	UPROPERTY(EditAnywhere, Category = "Vortex")
	float TurnsPerSecondMax = 1.0f;

	// 회전축 — 0: Roll(X·정면을 보는 세로 포탈), 1: Pitch(Y), 2: Yaw(Z·바닥 소용돌이, 기본)
	UPROPERTY(EditAnywhere, Category = "Vortex")
	int32 RotationAxis = 2;

	virtual uint32 RequiredBytes(UParticleModuleTypeDataBase* TypeData) override;
	virtual void Spawn(const FSpawnContext& Context) override;
	virtual void Update(const FUpdateContext& Context) override;

	virtual void Serialize(FArchive& Ar) override;
};
