#pragma once

#include "GameFramework/AActor.h"

#include "Source/Game/Actors/GOIncTrashBox.generated.h"

// ======================================================
// AGOIncTrashBox — 래그돌 수거함 액터 (TrashBox 메시)
// Root(SceneComponent) 아래 TrashBoxMesh + CollectTrigger
// + LogoDecal + 4면 벽(Block) 형제 구조.
// 수거(점수만, 미션 카운트 없음)는 TrashBoxBehavior.lua가 담당한다.
// 트리거는 QueryOnly·Kinematic·GenerateOverlapEvents=true 조합 — 하나라도
// 빠지면 OnOverlap이 안 와서 수거가 조용히 죽는다.
// ======================================================
UCLASS()
class AGOIncTrashBox : public AActor
{
public:
	GENERATED_BODY()
	AGOIncTrashBox() = default;
	~AGOIncTrashBox() override = default;

	// 에디터 Place Actor / 코드 스폰 직후 호출 — 씬 로드 시에는 직렬화가 복원
	void InitDefaultComponents();
};
