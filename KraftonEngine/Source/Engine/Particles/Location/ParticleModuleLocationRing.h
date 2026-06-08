#pragma once
#include "Particles/ParticleModule.h"

#include "Source/Engine/Particles/Location/ParticleModuleLocationRing.generated.h"

// ======================================================
// 원환(링) 스폰 (Spawn 1회) — 입자를 얇은 고리 위에 균일하게 뿌린다.
// 박스 균일인 기존 Location으로는 못 만드는 "포탈 링" 모양의 핵심.
// 법선축은 로테이터 컨벤션(0:X Roll·세로 포탈, 1:Y Pitch, 2:Z Yaw·바닥)이고
// VortexRotation의 RotationAxis와 짝지어 쓴다 (같은 축 = 링을 따라 도는 회전).
// 오프셋은 에미터(컴포넌트) 회전을 통과하므로 액터를 돌려 세우면 링도 따라 선다.
// ======================================================
UCLASS()
class UParticleModuleLocationRing : public UParticleModule
{
public:
	GENERATED_BODY()
	UParticleModuleLocationRing();

	UPROPERTY(EditAnywhere, Category = "Location")
	float RadiusMin = 0.9f;
	UPROPERTY(EditAnywhere, Category = "Location")
	float RadiusMax = 1.1f;

	// 링 평면의 법선축 — 0: X(Roll·세로 포탈), 1: Y(Pitch), 2: Z(Yaw·바닥 링)
	UPROPERTY(EditAnywhere, Category = "Location")
	int32 AxisNormal = 0;

	// 법선 방향 두께 (±절반씩 지터)
	UPROPERTY(EditAnywhere, Category = "Location")
	float Thickness = 0.05f;

	// true면 랜덤 각도 대신 "회전하는 헤드"에서 스폰 — 헤드가 지나간 자리에
	// 입자가 줄지어 남아 혜성 꼬리가 된다 (SizeOverLife/알파 페이드와 조합)
	UPROPERTY(EditAnywhere, Category = "Location")
	bool bSequentialAngle = false;

	// 헤드 회전 속도 (턴/초, 월드 시계 기준 — 에미터 루프와 무관하게 연속)
	UPROPERTY(EditAnywhere, Category = "Location")
	float AngleTurnsPerSecond = 1.0f;

	virtual void Spawn(const FSpawnContext& Context) override;

	virtual void Serialize(FArchive& Ar) override;
};
