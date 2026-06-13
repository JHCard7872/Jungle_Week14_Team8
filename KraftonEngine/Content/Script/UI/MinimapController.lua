-- ======================================================
-- MinimapController — 월드 좌표를 미니맵 위 마커 위치로 변환해 표시한다.
-- [역할] 플레이어/포탈/수거함/래그돌의 월드 위치를 매 프레임 미니맵 컨테이너 px로 바꿔
--        미리 깔아둔 마커 <img>들을 show/move 한다. RmlUi는 런타임 요소 생성이 안 되므로
--        play_hud.rml에 마커를 미리 깔아두고 여기서 위치/표시만 제어하는 "풀" 방식이다.
-- [호출] HUDController.Update / UpdateFromSession 가 widget을 넘겨 M.Update(widget, dt) 호출.
-- [좌표 변환]
--   - 원점(world 0,0,0) = play_hud_minimap의 빨간점/gizmo 위치 = 정규화 (U0, V0).
--   - 방향(gizmo 기준): world +X → 미니맵 오른쪽(+u), world +Y → 미니맵 아래(+v, 화면 y는 아래로 증가).
--   - world→이미지px는 사실상 균일 스케일(이미지 종횡비 ≈ 월드 종횡비라 정규화가 종횡비를 자동 반영).
--   - ★스케일 튜닝은 MINIMAP_PX_PER_WORLD 하나만 만지면 된다(엔티티 띄워보고 조정).
-- [재보정(추후 수정 절차)]
--   1) 플레이어 월드좌표와 world_to_minimap 결과 px를 임시로 출력해(print/로그) 비교한다.
--   2) 플레이어를 맵의 아는 지점(원점·모서리)에 세우고 마커가 거기 찍히는지 본다.
--   3) 원점이 어긋나면 U0,V0 를, 멀어짐/모임이 어긋나면 MINIMAP_PX_PER_WORLD 를 조정(멀면↓·모이면↑).
--   4) 미니맵 크기/모양을 바꾸면 ★3곳을 같은 값·같은 비율(1190:1322≈0.90)로 동기화:
--      이 파일 MAP_W/MAP_H = play_hud.rcss #hud_minimap_container = #hud_minimap_image.
--   5) rcss는 핫리로드가 안 될 수 있으니 에디터를 완전히 재시작해 확인한다.
-- ======================================================

local M = {}

-- ── 좌표 변환 상수 ──
local U0, V0 = 0.236, 0.811         -- world(0,0,0)의 play_hud_minimap 정규화 좌표(빨간점)
local MINIMAP_PX_PER_WORLD = 5.5    -- ★튜닝: world 1유닛당 미니맵 원본 이미지 px. 마커가 너무 벌어지면 ↓, 너무 모이면 ↑ (보정샷 기준값)
local IMG_W, IMG_H = 1190, 1322     -- play_hud_minimap.png 원본 해상도
local MAP_W, MAP_H = 225, 250       -- #hud_minimap_container 크기(px). ★종횡비를 이미지(1190:1322≈0.90)에 맞춰야 왜곡·넘침이 없다. rcss 값과 일치 필수
local RAGDOLL_POOL = 15             -- 미리 깔아둔 래그돌 마커 개수. play_hud.rml 마커 수와 반드시 일치
local TRASHBOX_POOL = 6            -- 미리 깔아둔 수거함 마커 개수. play_hud.rml 마커 수와 반드시 일치

-- 플레이어 마커(삼각형) 회전 보정.
--   - 마커 이미지(minimap_marker_player.png)는 기본적으로 위(-y)를 가리킨다.
--   - 미니맵은 world +X→오른쪽 / world +Y→아래, 플레이어 yaw(도)는 atan2(dir.Y,dir.X) 기준(yaw 0 = world +X).
--   - 따라서 CSS 회전각 = yaw + 90 이면 삼각형이 플레이어가 바라보는 방향을 가리킨다.
--   - 마커 이미지의 기본 방향이 바뀌면 이 오프셋만 조정한다(위:90, 오른쪽:0, 아래:-90 또는 270).
local PLAYER_MARKER_YAW_OFFSET = 90.0

-- 엔티티 식별용 태그/이름. 실제 스폰되면 이 태그로 찾는다(다르면 여기만 고치면 됨).
local TAG_PLAYER = "Player"
local TAG_RAGDOLL = "Ragdoll"
local PORTAL_TAG, PORTAL_NAME = "Portal", "SummonPortalActor"
local TRASHBOX_TAG = "TrashBox"     -- 수거함은 풀(여러 개)이라 태그로만 찾는다

local function clamp01(t)
    if t < 0.0 then return 0.0 elseif t > 1.0 then return 1.0 end
    return t
end

-- 월드(X,Y) → 컨테이너 로컬 px. Z는 버린다(탑다운).
local function world_to_minimap(wx, wy)
    local u = clamp01(U0 + (wx * MINIMAP_PX_PER_WORLD) / IMG_W)
    local v = clamp01(V0 + (wy * MINIMAP_PX_PER_WORLD) / IMG_H)
    return u * MAP_W, v * MAP_H
end

local function is_alive(actor)
    return actor ~= nil and (actor.IsValid == nil or actor:IsValid())
end

-- 마커 하나를 actor 위치에 띄우거나(보임) actor가 없으면 숨긴다.
local function place(widget, id, actor)
    if not is_alive(actor) then
        widget:SetProperty(id, "display", "none")
        return
    end

    local loc = actor.Location
    if loc == nil then
        widget:SetProperty(id, "display", "none")
        return
    end

    local px, py = world_to_minimap(loc.X, loc.Y)
    widget:SetProperty(id, "left", string.format("%.1fpx", px))
    widget:SetProperty(id, "top", string.format("%.1fpx", py))
    widget:SetProperty(id, "display", "block")
end

-- 싱글턴(포탈/수거함): 태그로 먼저 찾고 없으면 이름으로 fallback.
local function find_one(tag, name)
    if World == nil then
        return nil
    end
    if World.FindFirstActorByTag ~= nil then
        local a = World.FindFirstActorByTag(tag)
        if is_alive(a) then
            return a
        end
    end
    if World.FindActorByName ~= nil then
        return World.FindActorByName(name)
    end
    return nil
end

function M.Update(widget, dt)
    if widget == nil or World == nil then
        return
    end

    -- 플레이어 — 위치 + 바라보는 방향(삼각형 회전)
    local player = (World.FindFirstActorByTag ~= nil) and World.FindFirstActorByTag(TAG_PLAYER) or nil
    place(widget, "minimap_marker_player", player)
    if is_alive(player) and player.Rotation ~= nil then
        local yaw = player.Rotation.Z or 0.0
        widget:SetProperty(
            "minimap_marker_player",
            "transform",
            string.format("rotate(%.1fdeg)", yaw + PLAYER_MARKER_YAW_OFFSET)
        )
    end

    -- 싱글턴: 포탈
    place(widget, "minimap_marker_portal", find_one(PORTAL_TAG, PORTAL_NAME))

    -- 수거함(여러 개) — 풀 슬롯에 순서대로 매핑, 남는 슬롯은 숨김.
    local trashboxes = (World.FindActorsByTag ~= nil) and World.FindActorsByTag(TRASHBOX_TAG) or {}
    for i = 1, TRASHBOX_POOL do
        place(widget, "minimap_marker_trashbox_" .. i, trashboxes[i])
    end

    -- 래그돌(여러 개) — 풀 슬롯에 순서대로 매핑, 남는 슬롯은 숨김.
    local ragdolls = (World.FindActorsByTag ~= nil) and World.FindActorsByTag(TAG_RAGDOLL) or {}
    for i = 1, RAGDOLL_POOL do
        place(widget, "minimap_marker_ragdoll_" .. i, ragdolls[i])
    end
end

return M
