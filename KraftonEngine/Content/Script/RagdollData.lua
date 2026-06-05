local RagdollData = {
    ["blue-speedster"] = {
        -- 표시/식별
        displayName = "파란 고슴도치",
        referenceImage = "Content/UI/Ragdoll/blue_speedster.png",

        -- 에셋
        mesh = "Content/Data/Sonic/sc_dash_loop_anm_hkx_SkeletalMesh.uasset",
        physicsAsset = "Content/Data/Sonic/sc_dash_loop_anm_hkx_PhysicsAsset.uasset",
        fleeAnimation = "Content/Data/Sonic/sc_dash_loop_anm_hkx_sc_dash_loop.uasset",

        -- 컴포넌트 배치
        -- import scale을 못 바꾸므로 여기서 SkeletalMeshComponent 상대 scale 조절
        meshRelativeLocation = { x = 0.0, y = 0.0, z = -1.0 },
        meshRelativeScale = { x = 1.0, y = 1.0, z = 1.0 },

        -- Alive 상태에서 이동/충돌용 Capsule
        aliveCapsule = {
            radius = 1.0,
            halfHeight = 1.0,
        },

        -- Dead 상태에서 Player overlap revive 감지용 Capsule
        reviveTriggerCapsule = {
            radius = 5.0,
            halfHeight = 5.0,
        },

        -- 물리/수거 밸런스
        mass = 1.0,
        friction = 0.6,
        restitution = 0.1,
        baseScore = 100,
        spawnWeight = 10,

        -- 부활 여부/타이밍
        canRevive = true,
        reviveDelayMin = 0.0,
        reviveDelayMax = 0.0,
        reviveBlendDuration = 0.8,

        -- 살아난 뒤 도망 설정
        flee = {
            speed = 4.0,
            acceleration = 15.0,
            brakingDeceleration = 10.0,

            endDistance = 10.0,
            stopDuration = 1.0,
            stopMinBrakingDeceleration = 0.1,

            animationBaseSpeed = 4.0,
            animationMinPlayRate = 0.0,
            animationMaxPlayRate = 1.0,
            stopStartPlayRate = 1.0,
            stopEndPlayRate = 0.0,

            rotationYawOffset = 0.0,
        },

        -- 현재 기획상 실제 공격력 없음. 후순위/placeholder.
        attackPower = 1,
    },
}

return RagdollData