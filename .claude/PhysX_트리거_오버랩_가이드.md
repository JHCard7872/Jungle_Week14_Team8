# PhysX 트리거 오버랩 가이드 — "왜 Player 오버랩만 안 왔나"와 Query-Query 패스

> 2026-06-07 작성. fix/collision-bug 브랜치의 "ReviveTrigger가 Player를 감지 못 하는 버그" 수정과 함께 작성된 문서.
> 관련 코드: `Source/Engine/Physics/PhysXPhysicsScene.cpp` (ShouldBodyShapeBeTrigger / KraftonFilterShader / onTrigger / UpdateQueryTriggerOverlaps)

---

## 1. 아주 쉽게: 무슨 일이 있었나

유령 둘은 서로를 만질 수 없다.

- 우리 엔진에서 **QueryOnly** 물체는 "물리적 실체 없이 감지만 하는 유령"이다. 플레이어 캡슐도 유령이고, 래그돌의 ReviveTrigger도 유령이다.
- PhysX는 유령(트리거)이 **실체 있는 물체**(시뮬레이션 바디)와 겹치면 알려준다. 래그돌 본은 실체라서 트리거에 잘 걸렸다.
- 그런데 PhysX는 **유령끼리 겹치는 건 아예 알려주지 않는다** (에러도 경고도 없이, 그냥 침묵).
- 그래서 "래그돌끼리(본=실체)의 오버랩은 오는데, Player(유령)와의 오버랩만 안 오는" 증상이 됐다.

수정: 엔진이 물리 스텝마다 유령들끼리 직접 "지금 누구랑 겹쳤어?"라고 물어보는 패스(`UpdateQueryTriggerOverlaps`)를 추가했다.

## 2. 아주 자세하게: 오버랩 이벤트 파이프라인 전체

### 2-1. CollisionEnabled → PhysX 셰입 플래그

바디가 PhysX에 등록될 때 (`PhysXPhysicsScene.cpp` 셰입 생성부):

| CollisionEnabled | eSCENE_QUERY (레이캐스트 대상) | eSIMULATION (물리 충돌) | eTRIGGER (오버랩 통지) |
|---|---|---|---|
| NoCollision | ✗ (등록 자체가 해제됨) | ✗ | — |
| **QueryOnly** | ✓ | ✗ | **✓ 무조건** |
| QueryAndPhysics + Block 응답 있음 | ✓ | ✓ | ✗ |
| QueryAndPhysics + Block 응답 없음 | ✓ | ✗ | ✓ |

핵심은 `ShouldBodyShapeBeTrigger()`: **QueryOnly는 응답 설정과 무관하게 전부 트리거가 된다.**
이건 그 자체로 영리한 우회다 — QueryOnly 셰입은 시뮬레이션에 안 들어가서 PhysX가 아무 이벤트도 안 주는데, 트리거로라도 등록하면 "시뮬레이션 바디가 들어왔다 나갔다"는 통지를 받을 수 있기 때문.

### 2-2. 이벤트가 만들어지는 두 경로

```
PhysX simulate()
 ├─ onContact  : simulation ↔ simulation 쌍. 응답이 둘 다 Block이면 Hit 이벤트,
 │               한쪽이라도 Overlap이면 Overlap 큐로 라우팅 (응답 매트릭스 검사 있음)
 └─ onTrigger  : trigger ↔ simulation 쌍. 양방향으로 Overlap 큐에 적재
                 (+ 이번 수정으로 응답 매트릭스 Ignore 가드 추가)
                 ↓
       PendingTriggers/PendingHits 큐 → 물리 틱 끝(DispatchPhysicsEvents)에서
       NotifyComponentBeginOverlap/Hit → Lua OnOverlap/OnHit
```

큐를 거치는 이유: PhysX 콜백은 fetchResults 도중에 불려서, 그 안에서 액터를 파괴하면 크래시한다. 그래서 적재만 하고 시뮬레이션 바깥에서 일괄 디스패치한다.

### 2-3. PhysX의 숨은 제약 두 개 (이번 버그의 본체)

**제약 A — 트리거끼리는 통지가 없다.**
PhysX 3.4부터 trigger ↔ trigger 쌍의 onTrigger 통지가 제거됐다. 둘 다 QueryOnly(=트리거)인 플레이어 캡슐과 ReviveTrigger는 이 제약에 정확히 걸렸다.

**제약 B — kinematic끼리의 쌍은 기본적으로 생성조차 안 된다.**
PhysX 4의 `PxSceneDesc.kineKineFilteringMode` 기본값은 kinematic↔kinematic 쌍을 페어 생성 단계에서 버린다 (필터 셰이더에 도달조차 안 함). 우리 씬 생성부는 이 값을 따로 설정하지 않는다.
→ 그래서 "플레이어를 QueryAndPhysics(시뮬레이션 셰입)로 바꾸면 되지 않냐"는 우회도 **단독으로는 동작하지 않는다**: 플레이어 캡슐도 ReviveTrigger도 kinematic이라 쌍 자체가 안 만들어진다. (지금 동작하는 케이스들이 전부 "kinematic 트리거 vs **dynamic** 래그돌 본"인 이유)

### 2-4. 응답 매트릭스는 어디서 적용되나

필터 셰이더(`KraftonFilterShader`)는 트리거가 한쪽이라도 끼면 **응답을 보지 않고** 무조건 통과시킨다. 그래서 응답 검사는 콜백 쪽에서 해야 하는데, onContact에는 있었고 onTrigger에는 **누락**돼 있었다. 이 때문에 ReviveTrigger가 WorldDynamic(래그돌 본)을 Ignore로 설정했는데도 본이 스칠 때마다 OnOverlap이 올라왔다 ("other가 다른 RagdollPawn"이던 스팸의 정체). 이번 수정에서 onTrigger에도 `GetMinResponse == Ignore → skip` 가드를 추가했다.

`GetMinResponse(A,B) = min(A→B채널 응답, B→A채널 응답)`, Ignore(0) < Overlap(1) < Block(2).

## 3. 수정의 핵심: Query-Query 수동 쿼리 패스 (수도 코드)

PhysX가 안 주는 "트리거 ↔ 트리거" 쌍만 엔진이 직접 찾는다. 위치: `FPhysXPhysicsScene::UpdateQueryTriggerOverlaps()` — 물리 틱에서 `SyncPhysicsToEngineAfterSim()` 직후, `DispatchPhysicsEvents()` 직전.

```
매 물리 스텝(1/60):
  for 등록된 바디 중 (트리거 셰입 && GenerateOverlapEvents && 컴포넌트 살아있음):
      Found = []
      for 그 바디의 셰입들:
          hits = PxScene::overlap(셰입 지오메트리, 현재 포즈)   # 레이캐스트 1발급 비용
          for hit in hits:
              if hit가 트리거 셰입이 아니면 skip      # simulation 쌍은 onTrigger 담당 → 이중 통지 없음
              if 같은 액터면 skip                      # 필터 셰이더의 same-owner 규칙과 동일
              if GetMinResponse == Ignore면 skip       # 응답 매트릭스 일관 적용
              Found에 추가
      Prev = 직전 스텝에 겹쳐 있던 집합 (컴포넌트별 보관)
      Found - Prev → BeginOverlap 큐에 적재
      Prev - Found → EndOverlap 큐에 적재 (파괴된 상대는 통지 생략 — onTrigger의 eREMOVED_SHAPE 스킵과 동일 정책)
      Prev ← Found
```

- 기존 `PendingTriggers` 큐/디스패치 경로를 **그대로 공유**하므로 Lua 입장에서는 onTrigger로 온 이벤트와 구분되지 않는다.
- 상태(`QueryTriggerOverlaps` 맵)는 `UnregisterComponent`(NoCollision 전환 포함)와 `Shutdown`에서 정리된다.
- 비용: 트리거 컴포넌트 수만큼의 overlap 쿼리. 루프가 3중으로 보이지만 실행량은 (트리거 ~12개) × (셰입 1개) × (터치 0~5개) — 틱당 수십 회 반복 + 쿼리 12발 수준으로, 총의 매 프레임 레이캐스트와 같은 급이다.

## 4. 심화

### 4-1. 어떤 조합이 어떤 경로로 처리되나 (치트시트)

| 쌍 | 경로 | 비고 |
|---|---|---|
| 트리거 ↔ dynamic 시뮬레이션 (트럭/RT vs 래그돌 본) | onTrigger | 기존 경로. 응답 Ignore면 이제 걸러짐 |
| 시뮬레이션 ↔ 시뮬레이션, 응답 Block+Block | onContact → Hit | 물리 충돌 + OnHit |
| 시뮬레이션 ↔ 시뮬레이션, 한쪽 Overlap | onContact → Overlap 큐 | 밀어내기 없는 감지 (필터 셰이더 안전망) |
| **트리거 ↔ 트리거** (Player 캡슐 vs RT) | **UpdateQueryTriggerOverlaps** | 이번에 추가된 경로 |
| kinematic 시뮬레이션 ↔ kinematic 트리거 | ❌ 어디서도 안 옴 | 제약 B. 필요해지면 4-3 참고 |

### 4-2. 새 트리거를 만들 때 체크리스트

1. `CollisionEnabled = QueryOnly` + `bGenerateOverlapEvents = true` + kinematic — 이러면 트리거 셰입이 된다.
2. **응답을 명시적으로 설계할 것**: 전 채널 Ignore + 감지하고 싶은 채널만 Overlap (ReviveTrigger 방식). 이제 onTrigger/쿼리 패스 양쪽 다 응답을 존중하므로, Ignore로 둔 채널은 이벤트가 안 온다.
3. 상대가 트리거(QueryOnly)든 시뮬레이션 바디든 신경 쓸 필요 없다 — 경로는 엔진이 알아서 고른다 (4-1 표).
4. 양쪽 다 이벤트를 받고 싶으면 양쪽 다 `GenerateOverlapEvents = true` (한쪽만 켜면 그쪽만 OnOverlap을 받는다 — onTrigger와 동일한 의미론).

### 4-3. 기각된 대안들과 그 이유 (재논의 시 참고)

- **플레이어를 QueryAndPhysics로 (1줄)**: 제약 B 때문에 단독으로는 동작 안 함. `kineKineFilteringMode = eKEEP`을 함께 넣으면 되지만, 이는 **씬 전역으로 모든 kinematic 쌍의 페어 생성을 켜는 것**이라 모든 씬의 kinematic 조합이 필터 셰이더를 타기 시작한다. 또 "래그돌 본이 Pawn 채널을 Ignore한다"는 응답 우연에 기대므로, 응답 하나만 바뀌어도 플레이어가 본을 물리적으로 밀기 시작하는 지뢰가 남는다.
- **ReviveTrigger를 QueryAndPhysics로**: 응답에 Block이 없으면 어차피 트리거가 되고(2-1 표), Block을 넣으면 그 채널과 실제 충돌이 생긴다. 원천 불가.
- **거리 기반 우회 (Lua에서 매 틱 거리 검사)**: 동작은 하지만 이벤트 시스템의 구멍을 그대로 남기고, 트리거 모양(캡슐 크기)과 검사 로직이 이중 관리된다.

### 4-4. 현재 구현의 알려진 한계

- overlap 쿼리 터치 버퍼 64개 — 트리거 하나에 다른 트리거가 64개 이상 겹치면 초과분 누락 (현재 게임 스케일에서는 도달 불가).
- 상대가 **파괴**되면 EndOverlap을 생략한다 — onTrigger의 eREMOVED_SHAPE 스킵과 동일한 기존 엔진 정책에 맞춘 것. Begin/End 쌍을 엄격히 보장해야 하는 로직을 짠다면 이 점을 감안할 것.
- 쿼리 주기는 물리 스텝(60Hz) — 렌더 프레임이 아니라 물리 틱 기준이므로, 한 스텝 안에 트리거를 완전히 통과해버리는 초고속 이동은 놓칠 수 있다 (트리거 두께/속도 설계로 회피).

### 4-5. 검증 기록 (2026-06-07)

RagdollTest_with_GOIncActor 씬, Game 빌드 45초 자동 스모크:
- `OnOverlap entered. other=GOIncActor` → `Player overlapped revive capsule -> Reviving` **5회** (풀사이클: Dead → Reviving → AliveFlee → FleeStopping → Dead)
- 래그돌 본 스팸(`ignored: other is not Player`) **0건** (수정 전: 본이 스칠 때마다 발생)
- Lua/엔진 에러 0건, 신규 크래시 덤프 없음
