-- =============================================================================
-- IdCardCollection — 개발자 ID 카드 컬렉션 (JSON 저장 + 해시 검증)
-- [개념] 플레이 중 특정 개발자의 ID 카드를 습득하면, Result 화면 진입 시
--        습득 목록을 JSON 파일에 누적(합집합) 기록한다 — 컬렉션 개념.
--        크레딧 화면 진입 시 이 파일을 읽어, 습득한 사람은 id_card_jungle_ 대신
--        id_card_dev_ 이미지를 렌더한다.
-- [저장 파일] Content/Data/idcard_collection.json  (scoreboard.json 과 같은 경로)
-- [포맷] { name, hash } 객체의 JSON 배열. 예:
--          [
--            { "name": "김연하", "hash": "d913...33d4" },
--            { "name": "강건우", "hash": "115a...42bc" }
--          ]
--        hash = (이름 + 솔트)의 해시. 읽을 때 hash == hash(name) 인지 다시 계산해
--        검증하므로, 이름만 끼워 넣거나 해시를 임의로 바꾸면 인정되지 않는다.
--        (단 솔트/레인이 소스에 있어 암호학적 보안은 아님 — 캐주얼 치트 방지용 난독화)
-- [사용]
--        게임플레이: require("Data/IdCardCollection").MarkCollected("KKW")
--        Result 진입: IdCardCollection.PersistSessionCollection()
--        크레딧 진입: IdCardCollection.LoadCollectedSet()  -> { [key]=true }
-- [누적] 저장은 항상 기존 파일을 읽어 합집합으로만 한다. 이번 판에 못 얻은 카드라도
--        이미 저장돼 있으면 그대로 유지되고, 제거/초기화는 하지 않는다.
-- [주의] 이미지 경로는 sub_menu_page.rml 기준 상대경로(../../Sprite/...)다.
-- =============================================================================

local Session = require("GameSession")

local M = {}

local SAVE_PATH = "Content/Data/idcard_collection.json"

-- 해시 솔트/모듈러스. 솔트나 레인 구성을 바꾸면 기존 저장 파일은 무효가 된다(전부 미습득 처리).
local HASH_SALT = "goinc_idcard_v1::"
local HASH_MOD = 4294967296  -- 2^32

-- 8개 레인 = 레인마다 (초기값, 곱수, 레인 솔트)가 달라 독립적인 32비트 해시를 만든다.
-- 8개 × 8 hex = 64자리(SHA-256 길이) 결과. 곱수를 작게(<60) 유지해
-- hash*mult < 2^53 안에 들어오므로 Lua 5.1/5.3 double에서 정밀도 손실이 없다.
local HASH_LANES = {
    { init = 5381,       mult = 33, salt = "0" },
    { init = 52711,      mult = 31, salt = "1" },
    { init = 648391,     mult = 37, salt = "2" },
    { init = 9737333,    mult = 41, salt = "3" },
    { init = 174440041,  mult = 43, salt = "4" },
    { init = 2971215073, mult = 47, salt = "5" },
    { init = 99194853,   mult = 53, salt = "6" },
    { init = 374761393,  mult = 59, salt = "7" },
}

-- 크레딧에 표시되는 4명.
--  key             : 게임플레이/세션에서 습득을 표시할 때 쓰는 식별자(MarkCollected 인자)
--  name            : 저장 파일에 기록되고 해시 입력값으로 쓰이는 사람 이름
--  creditsElementId: sub_menu_page.rml의 img id 와 1:1 매칭
--  jungleImage     : 기본(미습득) 이미지 / devImage: 습득 시 교체할 이미지
M.PEOPLE = {
    { key = "KYH", name = "김연하", creditsElementId = "credits_id_card_1",
      jungleImage = "../../Sprite/id_card_jungle_KYH_with_holder.png",
      devImage    = "../../Sprite/id_card_dev_KYH.png" },
    { key = "KKW", name = "강건우", creditsElementId = "credits_id_card_2",
      jungleImage = "../../Sprite/id_card_jungle_KKW_with_holder.png",
      devImage    = "../../Sprite/id_card_dev_KKW.png" },
    { key = "PJH", name = "박준혁", creditsElementId = "credits_id_card_3",
      jungleImage = "../../Sprite/id_card_jungle_PJH_with_holder.png",
      devImage    = "../../Sprite/id_card_dev_PJH.png" },
    { key = "OJH", name = "오준혁", creditsElementId = "credits_id_card_4",
      jungleImage = "../../Sprite/id_card_jungle_OJH_with_holder.png",
      devImage    = "../../Sprite/id_card_dev_OJH.png" },
}

local BY_KEY = {}
local BY_NAME = {}
for _, person in ipairs(M.PEOPLE) do
    BY_KEY[person.key] = person
    BY_NAME[person.name] = person
end

function M.GetPeople()
    return M.PEOPLE
end

function M.IsValidKey(key)
    return key ~= nil and BY_KEY[key] ~= nil
end

-- 비트 연산 없는 다항식 롤링 해시(레인 1개분, 8자리 hex).
local function lane_hash(data, init, mult)
    local hash = init % HASH_MOD
    for i = 1, #data do
        hash = (hash * mult + string.byte(data, i)) % HASH_MOD
    end
    return string.format("%08x", math.floor(hash))
end

-- 이름을 솔트보다 먼저 처리해, 작은 차이가 긴 솔트를 거치며 전체로 확산되게 한다
-- (앞자리가 비슷해지는 문제 방지). 8개 레인을 이어붙여 64자리 hex를 반환한다.
local function hash_name(name)
    local parts = {}
    for _, lane in ipairs(HASH_LANES) do
        parts[#parts + 1] = lane_hash(tostring(name) .. HASH_SALT .. lane.salt, lane.init, lane.mult)
    end
    return table.concat(parts)
end
M.HashName = hash_name

local function read_all(path)
    local file = io.open(path, "r")
    if file == nil then
        return ""
    end

    local content = file:read("*a") or ""
    file:close()
    return content
end

local function write_all(path, content)
    local file = io.open(path, "w")
    if file == nil then
        return false
    end

    file:write(content)
    file:close()
    return true
end

-- JSON 배열에서 { "name": ..., "hash": ... } 객체들을 뽑아 { name -> hash } 맵으로 만든다.
-- 파일이 없거나 깨졌으면 빈 테이블을 반환한다.
local function parse_entries(content)
    local map = {}
    for object_text in string.gmatch(content or "", "{.-}") do
        local name = string.match(object_text, '"name"%s*:%s*"([^"]*)"')
        local hash = string.match(object_text, '"hash"%s*:%s*"([0-9a-fA-F]+)"')
        if name ~= nil and hash ~= nil then
            map[name] = hash
        end
    end
    return map
end

local function load_stored_entries()
    return parse_entries(read_all(SAVE_PATH))
end

-- name -> hash 맵을 JSON 배열 문자열로 직렬화한다. 알려진 사람은 PEOPLE 순서로,
-- 그 외 보존 대상은 뒤에 붙여 출력이 안정적이도록 한다.
local function serialize_entries(map)
    local names = {}
    local emitted = {}
    for _, person in ipairs(M.PEOPLE) do
        if map[person.name] and not emitted[person.name] then
            names[#names + 1] = person.name
            emitted[person.name] = true
        end
    end
    for name in pairs(map) do
        if not emitted[name] then
            names[#names + 1] = name
            emitted[name] = true
        end
    end

    if #names == 0 then
        return "[]\n"
    end

    local lines = {}
    for i, name in ipairs(names) do
        local comma = (i < #names) and "," or ""
        lines[#lines + 1] = string.format('  { "name": "%s", "hash": "%s" }%s', name, map[name], comma)
    end
    return "[\n" .. table.concat(lines, "\n") .. "\n]\n"
end

-- 이번 판(세션)에서 습득한 카드를 표시한다. 게임플레이에서 호출한다.
-- 실제 파일 누적 저장은 Result 진입 시 PersistSessionCollection()이 담당한다.
function M.MarkCollected(key)
    if not M.IsValidKey(key) then
        return false
    end

    Session.collectedIdCards = Session.collectedIdCards or {}
    Session.collectedIdCards[key] = true
    return true
end

-- 저장된 컬렉션을 { [key]=true } 집합으로 읽어온다. (크레딧 화면용)
-- 각 항목의 hash가 hash(name)과 일치하고, name이 등록된 사람일 때만 인정한다.
function M.LoadCollectedSet()
    local stored = load_stored_entries()
    local collected = {}
    for name, hash in pairs(stored) do
        local person = BY_NAME[name]
        if person ~= nil and hash == hash_name(name) then
            collected[person.key] = true
        end
    end
    return collected
end

-- 이번 세션에서 습득한 카드를 기존 컬렉션에 합집합으로 누적 저장한다. (Result 진입용)
-- 새로 추가될 것이 없으면 파일을 건드리지 않고 false를 반환한다.
function M.PersistSessionCollection()
    local session_collected = Session.collectedIdCards or {}

    local stored = load_stored_entries()
    local added = false
    for key in pairs(session_collected) do
        local person = BY_KEY[key]
        if person ~= nil and stored[person.name] == nil then
            stored[person.name] = hash_name(person.name)
            added = true
        end
    end

    if not added then
        return false
    end

    return write_all(SAVE_PATH, serialize_entries(stored))
end

return M
