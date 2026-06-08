-- ==========================================================================
-- GameConfig — 게임 전체 설정 상수 (require 모듈, 읽기 전용)
-- [역할] 판 단위 튜닝값. 런타임에 아무도 이 값을 쓰지(write) 않는다.
-- [사용법] local Config = require("Data/GameConfig")
-- [특이사항] 밸런싱 = 이 파일만 수정. 저장하면 파일 워처 핫리로드로 반영된다
--            (이미 require해둔 모듈은 다음 판부터). 값은 전부 임시 밸런스.
-- ==========================================================================

return {
    timeLimit      = 90,   -- 한 판 제한시간(초)                       -- 임시 밸런스
    maxServerLoad  = 100,  -- 게임오버가 되는 서버 부하 한계치           -- 임시 밸런스
    loadPerRagdoll = 0.5,  -- 방치 래그돌 1마리가 1초당 올리는 부하(%)   -- 임시 밸런스
    loadRecoverPerPortalCollect = 25.0, -- 포탈 미션 수거 1회당 낮추는 서버 부하(%) -- 임시 밸런스

    spawn = {              -- GOIncRagdollSpawnManager가 사용
        interval       = 10.0,   -- 스폰 간격(초)                         -- 임시 밸런스
        maxCount       = 15,    -- 최대 동시 스폰 수 (0 이하 = 무제한)     -- 임시 밸런스
        immediateFirst = true,  -- BeginPlay 직후 1마리 즉시 스폰 여부
        areaMinX = -10.0,       -- 스폰 영역(XY 박스) — 맵 확정 시 조정
        areaMaxX =  10.0,
        areaMinY = -10.0,
        areaMaxY =  10.0,
        z        =  1.0,        -- 스폰 높이

        -- 레벨에 배치한 Empty Actor / AActor의 Actor Tag.
        -- SpawnManager는 BeginPlay 때 이 태그를 가진 Actor를 1회 수집하고,
        -- 해당 Actor 하위 BoxComponent들을 스폰 구역으로 캐싱한다.
        spawnAreaTag = "GOIncSpawnArea",

        -- 스폰 위치가 기존 래그돌과 너무 가까우면 다시 뽑는다.
        -- 0 이하로 두면 거리 체크를 사실상 끌 수 있다.
        minDistanceBetweenSpawns = 0.15,
        maxLocationRetry = 10,

        defaultRagdollId = "blue-speedster",  -- 추첨 실패 시 폴백 타입
    },
}
