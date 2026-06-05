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

        attackPower = 1,
    },

    ["pink-round"] = {
        -- 표시/식별
        displayName = "분홍 동글이",
        referenceImage = "Content/UI/Ragdoll/pink_round.png",

        -- 에셋
        mesh = "Content/Data/Kirby/kirby_Animated2_SkeletalMesh.uasset",
        physicsAsset = "Content/Data/Kirby/kirby_Animated2_PhysicsAsset.uasset",
        fleeAnimation = "Content/Data/Kirby/kirby_Animated2_Kirb_Skeleton_Run_Animation.uasset",

        -- 컴포넌트 배치
        -- Kirby는 작고 둥근 편이라 Sonic보다 약간 작게 시작
        meshRelativeLocation = { x = 0.0, y = 0.0, z = -0.5 },
        meshRelativeScale = { x = 1.0, y = 1.0, z = 1.0 },

        aliveCapsule = {
            radius = 0.9,
            halfHeight = 0.9,
        },

        reviveTriggerCapsule = {
            radius = 3.5,
            halfHeight = 3.5,
        },

        mass = 0.8,
        friction = 0.5,
        restitution = 0.25,
        baseScore = 120,
        spawnWeight = 8,

        canRevive = true,
        reviveDelayMin = 0.0,
        reviveDelayMax = 0.0,
        reviveBlendDuration = 0.6,

        flee = {
            speed = 3.2,
            acceleration = 12.0,
            brakingDeceleration = 8.0,

            endDistance = 8.0,
            stopDuration = 0.8,
            stopMinBrakingDeceleration = 0.1,

            animationBaseSpeed = 3.2,
            animationMinPlayRate = 0.0,
            animationMaxPlayRate = 1.0,
            stopStartPlayRate = 1.0,
            stopEndPlayRate = 0.0,

            rotationYawOffset = 0.0,
        },

        attackPower = 1,
    },

    ["brown-gorilla"] = {
        -- 표시/식별
        displayName = "갈색 고릴라",
        referenceImage = "Content/UI/Ragdoll/brown_gorilla.png",

        -- 에셋
        mesh = "Content/Data/DonkeyKong/DonkeyKong_SkeletalMesh.uasset",
        physicsAsset = "Content/Data/DonkeyKong/DonkeyKong_PhysicsAsset.uasset",
        fleeAnimation = "Content/Data/DonkeyKong/Dancing_Running_Man_Animation.uasset",

        -- 컴포넌트 배치
        -- 큰 캐릭터 후보. 실제 크기 보고 meshRelativeScale / capsule 값 조정 필요.
        meshRelativeLocation = { x = 0.0, y = 0.0, z = -1.2 },
        meshRelativeScale = { x = 1.0, y = 1.0, z = 1.0 },

        aliveCapsule = {
            radius = 1.5,
            halfHeight = 1.8,
        },

        reviveTriggerCapsule = {
            radius = 6.0,
            halfHeight = 6.0,
        },

        mass = 2.0,
        friction = 0.8,
        restitution = 0.05,
        baseScore = 180,
        spawnWeight = 3,

        canRevive = true,
        reviveDelayMin = 0.0,
        reviveDelayMax = 0.0,
        reviveBlendDuration = 1.0,

        flee = {
            speed = 2.8,
            acceleration = 10.0,
            brakingDeceleration = 8.0,

            endDistance = 7.0,
            stopDuration = 1.2,
            stopMinBrakingDeceleration = 0.1,

            animationBaseSpeed = 2.8,
            animationMinPlayRate = 0.0,
            animationMaxPlayRate = 1.0,
            stopStartPlayRate = 1.0,
            stopEndPlayRate = 0.0,

            rotationYawOffset = 0.0,
        },

        attackPower = 1,
    },

    ["red-plumber"] = {
        -- 표시/식별
        displayName = "빨간 배관공",
        referenceImage = "Content/UI/Ragdoll/red_plumber.png",

        -- 에셋
        -- 주의: Mario 쪽은 run animation uasset이 없으면 임시로 idle/walk animation 경로로 바꿔야 함.
        mesh = "Content/Data/Mario/Mario_SkeletalMesh.uasset",
        physicsAsset = "Content/Data/Mario/Mario_PhysicsAsset.uasset",
        fleeAnimation = "Content/Data/Mario/Mario_Run_Animation.uasset",

        -- 컴포넌트 배치
        meshRelativeLocation = { x = 0.0, y = 0.0, z = -1.0 },
        meshRelativeScale = { x = 1.0, y = 1.0, z = 1.0 },

        aliveCapsule = {
            radius = 1.0,
            halfHeight = 1.2,
        },

        reviveTriggerCapsule = {
            radius = 4.5,
            halfHeight = 4.5,
        },

        mass = 1.1,
        friction = 0.6,
        restitution = 0.15,
        baseScore = 130,
        spawnWeight = 5,

        canRevive = true,
        reviveDelayMin = 0.0,
        reviveDelayMax = 0.0,
        reviveBlendDuration = 0.8,

        flee = {
            speed = 3.6,
            acceleration = 14.0,
            brakingDeceleration = 9.0,

            endDistance = 9.0,
            stopDuration = 1.0,
            stopMinBrakingDeceleration = 0.1,

            animationBaseSpeed = 3.6,
            animationMinPlayRate = 0.0,
            animationMaxPlayRate = 1.0,
            stopStartPlayRate = 1.0,
            stopEndPlayRate = 0.0,

            rotationYawOffset = 0.0,
        },

        attackPower = 1,
    },
}

return RagdollData