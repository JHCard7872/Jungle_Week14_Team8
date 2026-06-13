-- ==========================================================================
-- PortalBehavior — 순간이동 포탈 (ASummonPortalActor의 LuaScriptComponent에 부착)
-- [역할] 트리거에 플레이어가 닿으면 "같은 색 짝 포탈"로 순간이동시킨다. 들고 있는
--        오브젝트가 있으면 통째로 함께 이동(연출/이동은 PortalTeleport가 담당).
--        더 이상 래그돌을 수거하지 않는다 — 수거(점수/미션)는 수거함(TrashBox)이 전담.
-- [사용법] ASummonPortalActor를 씬에 직접 배치(에디터, Color Index로 색 지정). 로드 시 C++가
--          컴포넌트를 구성하고 "PortalColor{N}" 태그 부여 + 빛기둥을 색칠한다.
-- ==========================================================================

local PortalTeleport = require("Manager/PortalTeleport")

local myColor = -1   -- BeginPlay에서 자신의 색 태그로 캐시

-- 같은 색 짝 포탈 찾기 — 같은 태그를 가진 액터 중 내가 아닌 것(위치로 구분).
local function find_pair(idx, selfLoc)
    if World == nil or World.FindActorsByTag == nil then return nil end
    local list = World.FindActorsByTag("PortalColor" .. idx) or {}
    for _, a in ipairs(list) do
        if a ~= nil and (a.IsValid == nil or a:IsValid()) then
            local l = a.Location
            if l ~= nil and (math.abs(l.X - selfLoc.X) > 0.01
                          or math.abs(l.Y - selfLoc.Y) > 0.01
                          or math.abs(l.Z - selfLoc.Z) > 0.01) then
                return a
            end
        end
    end
    return nil
end

function BeginPlay()
    -- 트리거 박스 설정 검증 — GenerateOverlapEvents가 꺼져 있으면 OnOverlap이
    -- 바인딩되지 않아 순간이동이 조용히 죽는다 (씬 설정 실수를 조기에 드러냄)
    local hasTrigger = false
    for _, comp in pairs(obj:GetPrimitiveComponents()) do
        if comp:GetGenerateOverlapEvents() then
            hasTrigger = true
            break
        end
    end
    if not hasTrigger then
        print("[Portal] 경고: GenerateOverlapEvents=true인 컴포넌트가 없음 — 순간이동 트리거가 동작하지 않음")
    end

    -- 자신의 색 인덱스 캐시 (C++가 PortalColor{N} 태그를 부여)
    for i = 0, 2 do
        if obj:HasTag("PortalColor" .. i) then
            myColor = i
            break
        end
    end
    if myColor < 0 then
        print("[Portal] 경고: PortalColor 태그가 없음 — 색상 미지정 포탈은 순간이동하지 않음")
    end
end

-- 플레이어가 트리거에 닿으면 같은 색 짝 포탈로 이동. 래그돌 등 다른 액터는 무시.
function OnOverlap(other_actor, overlapped_component, other_comp)
    if not other_actor or not other_actor:IsValid() then return end
    if not other_actor:HasTag("Player") then return end
    if myColor < 0 then return end
    if PortalTeleport.IsBusy() then return end   -- 이동/연출/쿨다운 중이면 무시(되튕김 방지)

    local pair = find_pair(myColor, obj.Location)
    if pair == nil then
        print("[Portal] 경고: 색 " .. myColor .. " 짝 포탈을 찾지 못함")
        return
    end

    PortalTeleport.Trigger(obj.Location, pair.Location, myColor)
end
