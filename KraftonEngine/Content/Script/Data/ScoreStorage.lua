-- =============================================================================
-- ScoreStorage — Result 점수 JSON 저장 유틸
-- [저장 파일] scoreboard.json
-- [형식] JSON 배열에 { nickname, totalScore, collectedCount, savedAt } 객체를 추가한다.
-- =============================================================================

local M = {}

local SAVE_PATH = "Content/Data/scoreboard.json"
local LEGACY_SAVE_PATHS = {
    "scoreboard.json",
    "Content/scoreboard.json",
}

local function escape_json_string(value)
    local text = tostring(value or "")
    text = string.gsub(text, "\\", "\\\\")
    text = string.gsub(text, '"', '\\"')
    text = string.gsub(text, "\n", "\\n")
    text = string.gsub(text, "\r", "\\r")
    text = string.gsub(text, "\t", "\\t")
    return text
end

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

local function read_current_content()
    local primary_content = read_all(SAVE_PATH)
    if primary_content ~= "" and not string.match(primary_content, "^%s*$") then
        return SAVE_PATH, primary_content
    end

    for _, legacy_path in ipairs(LEGACY_SAVE_PATHS) do
        local legacy_content = read_all(legacy_path)
        if legacy_content ~= "" and not string.match(legacy_content, "^%s*$") then
            if not write_all(SAVE_PATH, legacy_content) then
                return legacy_path, legacy_content
            end
            return SAVE_PATH, legacy_content
        end
    end

    return SAVE_PATH, primary_content
end

local function build_record_json(record)
    return string.format(
        '{"nickname":"%s","totalScore":%d,"collectedCount":%d,"savedAt":%d}',
        escape_json_string(record.nickname),
        math.max(0, math.floor(tonumber(record.totalScore) or 0)),
        math.max(0, math.floor(tonumber(record.collectedCount) or 0)),
        math.floor(tonumber(record.savedAt) or 0)
    )
end

local function parse_records(content)
    local records = {}
    for object_text in string.gmatch(content or "", "{%s*.-%s*}") do
        local nickname = string.match(object_text, '"nickname"%s*:%s*"([^"]*)"') or "SAMPLE"
        local total_score = tonumber(string.match(object_text, '"totalScore"%s*:%s*(%-?%d+)')) or 0
        local collected_count = tonumber(string.match(object_text, '"collectedCount"%s*:%s*(%-?%d+)')) or 0
        local saved_at = tonumber(string.match(object_text, '"savedAt"%s*:%s*(%-?%d+)')) or 0

        table.insert(records, {
            nickname = nickname,
            totalScore = total_score,
            collectedCount = collected_count,
            savedAt = saved_at,
        })
    end

    table.sort(records, function(a, b)
        if (a.totalScore or 0) == (b.totalScore or 0) then
            return (a.savedAt or 0) > (b.savedAt or 0)
        end
        return (a.totalScore or 0) > (b.totalScore or 0)
    end)

    return records
end

function M.ReadAll()
    local _, content = read_current_content()
    return parse_records(content)
end

function M.ReadTop(max_count)
    local all = M.ReadAll()
    local top = {}
    local count = math.min(tonumber(max_count) or 5, #all)
    for i = 1, count do
        top[i] = all[i]
    end
    return top
end

function M.Append(record)
    record = record or {}
    local _, content = read_current_content()
    local record_json = build_record_json(record)

    if content == "" or string.match(content, "^%s*$") then
        return write_all(SAVE_PATH, "[\n  " .. record_json .. "\n]\n")
    end

    local prefix = string.match(content, "^(.*)%]%s*$")
    if prefix == nil then
        -- 기존 파일이 깨져 있으면 백업 없이 새 배열로 덮어쓴다.
        return write_all(SAVE_PATH, "[\n  " .. record_json .. "\n]\n")
    end

    local has_existing_record = string.find(prefix, "{%s*\"") ~= nil
    local separator = has_existing_record and ",\n  " or "\n  "
    return write_all(SAVE_PATH, prefix .. separator .. record_json .. "\n]\n")
end

return M
