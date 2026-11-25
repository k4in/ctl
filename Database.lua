local _, ns = ...

local zoneNames = {}
local uiMapToArea
local areaToUi
local subToParent

local function compileMap(source)
    if type(source) == "table" then return source end
    if type(source) ~= "string" or type(loadstring) ~= "function" then return nil end
    local chunk = loadstring(source)
    if not chunk then return nil end
    local ok, result = pcall(chunk)
    if ok and type(result) == "table" then return result end
    return nil
end

local function mergeMap(base, extra)
    if type(extra) ~= "table" then return base end
    for key, value in pairs(extra) do
        if value ~= 0 then base[key] = value end
    end
    return base
end

function ns.DBReady()
    return ns.dbOpen == true
end

local dungeonAreas

local function loadDungeonAreas(private)
    dungeonAreas = {}
    local dungeons = private and private.dungeons
    if type(dungeons) ~= "table" then return end
    for areaId, entry in pairs(dungeons) do
        if type(areaId) == "number" and areaId > 0 then dungeonAreas[areaId] = true end
        if type(entry) == "table" and type(entry[2]) == "table" then
            for _, alt in ipairs(entry[2]) do
                if type(alt) == "number" and alt > 0 then dungeonAreas[alt] = true end
            end
        end
    end
end

function ns.OpenDatabase()
    if ns.dbOpen ~= nil then return ns.dbOpen end
    if type(LibQuestieDB) ~= "table" or type(QuestDB) ~= "table" or type(QuestDB.Exists) ~= "function" then
        ns.dbMessage = "QuestieDB is not loaded."
        ns.dbOpen = false
        return false
    end
    if type(LibQuestieDB.RequireContract) == "function" then
        local ok, message = LibQuestieDB.RequireContract(1)
        if not ok then
            ns.dbMessage = message or "QuestieDB contract does not match."
            ns.dbOpen = false
            return false
        end
    end

    local support = LibQuestieDB.Support and LibQuestieDB.Support.Get and LibQuestieDB.Support.Get("ZoneDB")
    local private = support and support.private
    if private then
        uiMapToArea = compileMap(private.uiMapIdToAreaId) or {}
        mergeMap(uiMapToArea, compileMap(private.uiMapIdToAreaIdOverride))
        areaToUi = compileMap(private.areaIdToUiMapId) or {}
        mergeMap(areaToUi, compileMap(private.areaIdToUiMapIdOverride))
        subToParent = compileMap(private.subZoneToParentZone) or {}
        mergeMap(subToParent, compileMap(private.subZoneToParentZoneOverride))
    else
        uiMapToArea, areaToUi, subToParent = {}, {}, {}
    end
    loadDungeonAreas(private)

    ns.dbOpen = true
    return true
end

-- 81 dungeon, 85 heroic. 62/88/89 are raids and stay unmarked.
function ns.QuestTagId(questId)
    if type(questId) ~= "number" or questId <= 0 then return nil end
    if C_QuestLog and C_QuestLog.GetQuestTagInfo then
        local ok, info = pcall(C_QuestLog.GetQuestTagInfo, questId)
        if ok and type(info) == "table" then
            local tag = ns.Plain(info.tagID)
            if type(tag) == "number" and tag > 0 then return tag end
        end
    end
    if GetQuestTagInfo then
        local ok, first, second = pcall(GetQuestTagInfo, questId)
        if ok then
            first, second = ns.Plain(first), ns.Plain(second)
            if type(first) == "number" and first > 0 then return first end
            if type(second) == "number" and second > 0 then return second end
        end
    end
    return nil
end

function ns.IsDungeonQuest(questId)
    if type(questId) ~= "number" or questId <= 0 then return false end
    local tag = ns.QuestTagId(questId)
    if tag == 62 or tag == 88 or tag == 89 then return false end
    if tag == 81 or tag == 85 then return true end
    if ns.dbOpen == nil then ns.OpenDatabase() end
    if type(dungeonAreas) ~= "table" then return false end
    local zone = ns.QuestNumber(questId, "zoneOrSort")
    return zone ~= nil and dungeonAreas[zone] == true
end

-- 0 means the quest does not ask for a group.
function ns.SuggestedGroup(questId)
    if type(questId) ~= "number" or questId <= 0 then return 0 end
    local function read(fn)
        if type(fn) ~= "function" then return nil end
        local ok, value = pcall(fn, questId)
        if not ok then return nil end
        value = ns.Plain(value)
        if type(value) == "number" and value > 0 then return value end
    end
    local questLog = C_QuestLog
    return read(questLog and questLog.GetSuggestedGroupSize)
        or read(GetSuggestedGroupSize)
        or 0
end

-- Tag 1 is the elite/group marker. A suggested group counts too.
-- Dungeon quests keep the dungeon mark instead.
function ns.IsGroupQuest(questId)
    if type(questId) ~= "number" or questId <= 0 then return false end
    if ns.IsDungeonQuest(questId) then return false end
    local tag = ns.QuestTagId(questId)
    if tag == 1 then return true end
    -- Another tag, such as a raid, keeps its own mark. Only an untagged quest
    -- with a suggested group is a plain group quest.
    if tag ~= nil then return false end
    return ns.SuggestedGroup(questId) > 0
end

function ns.QuestCall(questId, field)
    if not ns.DBReady() or type(questId) ~= "number" then return nil end
    local fn = QuestDB[field]
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, questId)
    if not ok then return nil end
    return value
end

function ns.QuestNumber(questId, field)
    local value = ns.QuestCall(questId, field)
    if type(value) ~= "number" or value == 0 then return nil end
    return value
end

function ns.QuestList(questId, field)
    local value = ns.QuestCall(questId, field)
    if type(value) ~= "table" then return {} end
    return value
end

function ns.QuestExists(questId)
    if not ns.DBReady() or type(questId) ~= "number" then return false end
    local ok, value = pcall(QuestDB.Exists, questId)
    return ok and value == true
end

function ns.QuestName(questId)
    local name = ns.QuestCall(questId, "name")
    if type(name) == "string" and name ~= "" then return name end
    return nil
end

function ns.ZoneName(areaId)
    if type(areaId) ~= "number" or areaId == 0 then return "No zone" end
    local cached = zoneNames[areaId]
    if cached then return cached end
    local name
    if C_Map and C_Map.GetAreaInfo then
        local ok, result = pcall(C_Map.GetAreaInfo, areaId)
        if ok then name = ns.Plain(result) end
    end
    if type(name) ~= "string" or name == "" then name = "Area " .. areaId end
    zoneNames[areaId] = name
    return name
end

local CONTINENT = Enum and Enum.UIMapType and Enum.UIMapType.Continent or 2

local function continentOfMap(mapId)
    local guard = 0
    while type(mapId) == "number" and mapId > 0 and guard < 10 do
        local ok, info = pcall(C_Map.GetMapInfo, mapId)
        if not ok or type(info) ~= "table" then return nil end
        local mapType = ns.Plain(info.mapType)
        if mapType == CONTINENT then return mapId end
        local parent = ns.Plain(info.parentMapID)
        if type(parent) ~= "number" or parent == 0 or parent == mapId then return nil end
        mapId = parent
        guard = guard + 1
    end
    return nil
end

function ns.UiMap(areaId)
    if ns.dbOpen == nil then ns.OpenDatabase() end
    if type(areaToUi) ~= "table" or type(areaId) ~= "number" or areaId <= 0 then return nil end
    local mapId = areaToUi[areaId]
    if type(mapId) == "number" and mapId > 0 then return mapId end
    return nil
end

-- Plan coordinates are questie-style 0-100. TomTom and Shortest Path want 0-1.
function ns.MapFraction(value)
    if type(value) ~= "number" then return nil end
    local fraction = value / 100
    if fraction < 0 or fraction > 1 then return nil end
    return fraction
end

function ns.HasMapPoint(stop)
    if type(stop) ~= "table" then return false end
    return ns.UiMap(stop.areaId) ~= nil
        and ns.MapFraction(stop.x) ~= nil
        and ns.MapFraction(stop.y) ~= nil
end

function ns.ContinentOfArea(areaId)
    if not areaToUi or type(areaId) ~= "number" then return nil end
    local mapId = areaToUi[areaId]
    if type(mapId) ~= "number" or mapId == 0 then return nil end
    return continentOfMap(mapId)
end

local function areaFromMap(mapId)
    if not uiMapToArea or type(mapId) ~= "number" then return nil end
    local areaId = uiMapToArea[mapId]
    if type(areaId) == "number" and areaId > 0 then return areaId end
    return nil
end

function ns.PlayerLocation()
    local location = {}
    if GetZoneText then
        local name = ns.Plain(GetZoneText())
        if type(name) == "string" and name ~= "" then location.zoneName = name end
    end
    if not C_Map or not C_Map.GetBestMapForUnit then return location end

    local ok, mapId = pcall(C_Map.GetBestMapForUnit, "player")
    mapId = ok and ns.Plain(mapId) or nil
    if type(mapId) ~= "number" then return location end

    local posOk, pos = pcall(C_Map.GetPlayerMapPosition, mapId, "player")
    if posOk and pos and pos.GetXY then
        local x, y = pos:GetXY()
        x, y = ns.Plain(x), ns.Plain(y)
        if type(x) == "number" and type(y) == "number" then
            location.x, location.y = x * 100, y * 100
        end
    end

    local areaId = areaFromMap(mapId)
    local walked = false
    local guard = 0
    local cursor = mapId
    while not areaId and guard < 8 do
        local infoOk, info = pcall(C_Map.GetMapInfo, cursor)
        if not infoOk or type(info) ~= "table" then break end
        local parent = ns.Plain(info.parentMapID)
        if type(parent) ~= "number" or parent == 0 then break end
        cursor = parent
        areaId = areaFromMap(cursor)
        walked = true
        guard = guard + 1
    end

    location.areaId = areaId
    if walked then
        location.x, location.y = nil, nil
    end
    if areaId then location.continent = ns.ContinentOfArea(areaId) end
    return location
end

function ns.PlayerCanTake(questId)
    if not ns.QuestExists(questId) then return false end

    local classMask = ns.QuestCall(questId, "requiredClasses")
    if type(classMask) == "number" and classMask ~= 0 and LibQuestieDB.Enum and LibQuestieDB.Enum.classKeys then
        local _, classFile = UnitClass("player")
        local classBit = classFile and LibQuestieDB.Enum.classKeys[classFile]
        if classBit and ns.Band(classMask, classBit) == 0 then return false end
    end

    local raceMask = ns.QuestCall(questId, "requiredRaces")
    if type(raceMask) == "number" and raceMask ~= 0 and LibQuestieDB.Enum and LibQuestieDB.Enum.raceMaskById then
        local _, _, raceId = UnitRace("player")
        raceId = ns.Plain(raceId)
        local raceBit = type(raceId) == "number" and LibQuestieDB.Enum.raceMaskById[raceId]
        if raceBit and ns.Band(raceMask, raceBit) == 0 then return false end
    end

    return true
end

local function entityName(db, id)
    if type(id) ~= "number" or not db or type(db.name) ~= "function" then return nil end
    local ok, name = pcall(db.name, id)
    if ok and type(name) == "string" and name ~= "" then return name end
    return nil
end

local function entitySpawns(db, id)
    if type(id) ~= "number" or not db or type(db.spawns) ~= "function" then return nil end
    local ok, spawns = pcall(db.spawns, id)
    if ok and type(spawns) == "table" then return spawns end
    return nil
end

local function considerPoint(best, areaId, x, y, player, preferArea)
    if type(x) ~= "number" or type(y) ~= "number" or x < 0 or y < 0 then return best end
    local score = 300000
    if player and areaId == player.areaId then
        if player.x and player.y then
            local dx, dy = x - player.x, y - player.y
            score = dx * dx + dy * dy
        else
            score = 0
        end
    elseif preferArea and areaId == preferArea then
        score = 100000
    end
    if not best or score < best.score then
        return { areaId = areaId, x = x, y = y, score = score }
    end
    return best
end

local function bestPoint(spawns, player, preferArea)
    if type(spawns) ~= "table" then return nil end
    local best
    for areaId, list in pairs(spawns) do
        if type(areaId) == "number" and type(list) == "table" then
            for _, coord in ipairs(list) do
                if type(coord) == "table" then
                    best = considerPoint(best, areaId, coord[1], coord[2], player, preferArea)
                end
            end
        end
    end
    return best
end

local function bestOfIds(db, ids, player, preferArea, limit)
    local best
    if type(ids) ~= "table" then return nil end
    local seen = 0
    for _, id in ipairs(ids) do
        if type(id) == "number" and id > 0 then
            seen = seen + 1
            if limit and seen > limit then break end
            local point = bestPoint(entitySpawns(db, id), player, preferArea)
            if point and (not best or point.score < best.score) then
                point.name = entityName(db, id)
                best = point
            end
        end
    end
    return best
end

local function itemPoint(itemId, player, preferArea)
    if type(itemId) ~= "number" or itemId == 0 or type(ItemDB) ~= "table" then return nil end
    local best
    if type(ItemDB.npcDrops) == "function" then
        local ok, drops = pcall(ItemDB.npcDrops, itemId)
        if ok then best = bestOfIds(NpcDB, drops, player, preferArea, 12) end
    end
    if type(ItemDB.objectDrops) == "function" then
        local ok, drops = pcall(ItemDB.objectDrops, itemId)
        if ok then
            local objectPoint = bestOfIds(ObjectDB, drops, player, preferArea, 8)
            if objectPoint and (not best or objectPoint.score < best.score) then best = objectPoint end
        end
    end
    if best and not best.name then best.name = entityName(ItemDB, itemId) end
    return best
end

local function norm(text)
    if type(text) ~= "string" then return "" end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h", ""):gsub("|h", "")
    text = text:lower()
    text = text:gsub("%s*:%s*%d+%s*/%s*%d+%s*$", "")
    text = text:gsub("%s*%(%s*%d+%s*/%s*%d+%s*%)%s*$", "")
    text = text:gsub("%s+%d+%s*/%s*%d+%s*$", "")
    text = text:gsub("^%s*%d+%s*/%s*%d+%s+", "")
    text = text:gsub("%s+", " ")
    return (text:match("^%s*(.-)%s*$")) or ""
end

local function objectiveScore(lineText, key, sourceName)
    local lineKey = norm(lineText)
    if lineKey == "" then return 0 end
    if key ~= "" and lineKey == key then return 100 end
    if key ~= "" and #key >= 6 and #lineKey >= 6
        and (lineKey:find(key, 1, true) or key:find(lineKey, 1, true)) then
        return 80
    end
    local name = norm(sourceName)
    if #name >= 4 and lineKey:find(name, 1, true) then return 60 end
    return 0
end

local function bestObjective(stop, row)
    local key = norm(stop.text)
    local best, bestScore, tied
    for _, line in ipairs(row.objectives or {}) do
        local score = objectiveScore(line.text, key, stop.sourceName)
        if score > 0 and (not bestScore or score > bestScore) then
            best, bestScore, tied = line, score, false
        elseif bestScore and score == bestScore then
            tied = true
        end
    end
    if tied or not best then return nil end
    return best
end

-- Updates the live counter on a step that is still in the plan. A finished
-- leading step is how the window advances; the step list itself stays put.
function ns.SyncStop(stop, row)
    if type(stop) ~= "table" then return false end
    local present = type(row) == "table"
    if present and stop.followup then
        stop.followup = nil
        if stop.note == "not in the log yet" then stop.note = nil end
    end
    if stop.kind == "turnin" then
        if present or stop.followup then return false end
        return true
    end
    if not present then
        if stop.followup then return false end
        return true
    end
    if row.complete then return true end
    local line = bestObjective(stop, row)
    if line then
        stop.progressText = line.text
        stop.numFulfilled = line.numFulfilled
        stop.numRequired = line.numRequired
        stop.objectiveDone = line.finished and true or false
        return line.finished and true or false
    end
    if type(row.objectives) ~= "table" or #row.objectives == 0 then return false end
    for _, entry in ipairs(row.objectives) do
        if not entry.finished then return false end
    end
    return true
end

local function preferZone(questId)
    local zone = ns.QuestNumber(questId, "zoneOrSort")
    if zone and zone > 0 then return zone end
    return nil
end

local function addStop(stops, stop)
    stop.areaId = stop.areaId or 0
    if stop.questId and ns.IsDungeonQuest(stop.questId) then stop.dungeon = true end
    stops[#stops + 1] = stop
end

local function objectiveText(entry, index, fallback)
    local text = entry and entry[index]
    if type(text) == "string" and text ~= "" then return text end
    return fallback
end

function ns.CollectStops(questId, spec)
    local stops = {}
    local player = spec.player
    local questName = spec.questName or ns.QuestName(questId) or ("Quest " .. questId)
    local prefer = preferZone(questId)
    local lines = spec.lines or {}
    local seen = {}

    -- Log text is localized and often carries a counter. Questie text is not.
    -- A unique text or NPC-name match wins. When the two lists are the same
    -- length, the remaining lines pair in order, which is how a finished
    -- "talk to this person" objective drops out even if the wording differs.
    local function scoreLine(line, key, sourceName)
        local lineKey = norm(line.text)
        if lineKey == "" then return 0 end
        if key ~= "" and lineKey == key then return 100 end
        if key ~= "" and #key >= 6 and #lineKey >= 6
            and (lineKey:find(key, 1, true) or key:find(lineKey, 1, true)) then
            return 80
        end
        local name = norm(sourceName)
        if #name >= 4 and lineKey:find(name, 1, true) then return 60 end
        return 0
    end

    local function matchLine(text, sourceName)
        local key = norm(text)
        local best, bestScore, ties
        for _, line in ipairs(lines) do
            if not line.used then
                local score = scoreLine(line, key, sourceName)
                if score > 0 and (not bestScore or score > bestScore) then
                    best, bestScore, ties = line, score, false
                elseif bestScore and score == bestScore then
                    ties = true
                end
            end
        end
        if ties or not best then return nil end
        return best
    end

    local queue = {}

    local function applyProgress(stop, line)
        if not line then return end
        stop.progressText = line.text
        stop.numFulfilled = line.numFulfilled
        stop.numRequired = line.numRequired
        stop.objectiveDone = line.finished and true or false
    end

    local function pushObjective(text, point, sourceName)
        if spec.complete then return end
        local key = norm(text)
        if key ~= "" and seen[key] then return end
        if key ~= "" then seen[key] = true end
        local line = matchLine(text, sourceName)
        if line then
            line.used = true
            if line.finished then return end
        end
        local stop = {
            questId = questId,
            questName = questName,
            kind = "objective",
            text = text,
            areaId = point and point.areaId or 0,
            x = point and point.x,
            y = point and point.y,
            followup = spec.followup,
            afterTurnin = spec.afterTurnin,
            sourceName = sourceName,
            unmatched = line == nil,
        }
        applyProgress(stop, line)
        queue[#queue + 1] = stop
    end

    if ns.QuestExists(questId) and not spec.complete then
        local objectives = ns.QuestCall(questId, "objectives") or {}
        local function creatures(list, textIndex, idIndex)
            if type(list) ~= "table" then return end
            for _, entry in ipairs(list) do
                if type(entry) == "table" then
                    local ids = entry[idIndex]
                    if type(ids) ~= "table" then ids = { ids } end
                    local point = bestOfIds(NpcDB, ids, player, prefer, 8)
                    pushObjective(objectiveText(entry, textIndex, point and point.name or "Enemy"), point, point and point.name)
                end
            end
        end

        creatures(objectives[1], 2, 1)
        if type(objectives[2]) == "table" then
            for _, entry in ipairs(objectives[2]) do
                if type(entry) == "table" then
                    local point = bestOfIds(ObjectDB, { entry[1] }, player, prefer, 4)
                    pushObjective(objectiveText(entry, 2, point and point.name or "Object"), point, point and point.name)
                end
            end
        end
        if type(objectives[3]) == "table" then
            for _, entry in ipairs(objectives[3]) do
                if type(entry) == "table" then
                    local point = itemPoint(entry[1], player, prefer)
                    local text = objectiveText(entry, 2, point and point.name or "Item")
                    pushObjective(text, point, point and point.name)
                end
            end
        end
        creatures(objectives[5], 3, 1)
        if type(objectives[6]) == "table" then
            for _, entry in ipairs(objectives[6]) do
                if type(entry) == "table" then
                    local point = itemPoint(entry[3], player, prefer)
                    pushObjective(objectiveText(entry, 2, "Spell target"), point, point and point.name)
                end
            end
        end

        local trigger = ns.QuestCall(questId, "triggerEnd")
        if type(trigger) == "table" then
            local text = type(trigger[1]) == "string" and trigger[1] ~= "" and trigger[1] or "Enter the area"
            pushObjective(text, bestPoint(trigger[2], player, prefer))
        end

        local extra = ns.QuestCall(questId, "extraObjectives")
        if type(extra) == "table" then
            local count = 0
            for _, entry in ipairs(extra) do
                count = count + 1
                if count > 6 then break end
                if type(entry) == "table" then
                    local text = type(entry[3]) == "string" and entry[3] ~= "" and entry[3] or nil
                    local point = bestPoint(entry[1], player, prefer)
                    if text or point then pushObjective(text or "Extra objective", point) end
                end
            end
        end
    end

    local unused = {}
    for _, line in ipairs(lines) do
        if not line.used then unused[#unused + 1] = line end
    end
    local pending = {}
    for index, stop in ipairs(queue) do
        if stop.unmatched then pending[#pending + 1] = index end
    end
    if #pending > 0 and #pending == #unused then
        local drop = {}
        for index, queueIndex in ipairs(pending) do
            local line = unused[index]
            line.used = true
            if line.finished then
                drop[queueIndex] = true
            else
                applyProgress(queue[queueIndex], line)
            end
        end
        if next(drop) then
            local kept = {}
            for index, stop in ipairs(queue) do
                if not drop[index] then kept[#kept + 1] = stop end
            end
            queue = kept
        end
    end
    for _, stop in ipairs(queue) do
        stop.unmatched = nil
        addStop(stops, stop)
    end

    if not spec.followup and not spec.complete then
        for _, line in ipairs(lines) do
            if not line.used and not line.finished and type(line.text) == "string" and line.text ~= "" then
                line.used = true
                local stop = {
                    questId = questId,
                    questName = questName,
                    kind = "objective",
                    text = line.text,
                    areaId = 0,
                    followup = spec.followup,
                    afterTurnin = spec.afterTurnin,
                }
                applyProgress(stop, line)
                addStop(stops, stop)
            end
        end
    end

    local turninText = "Turn in"
    local point
    if ns.QuestExists(questId) then
        local finishedBy = ns.QuestCall(questId, "finishedBy") or {}
        point = bestOfIds(NpcDB, finishedBy[1], player, prefer, 8)
        local objectPoint = bestOfIds(ObjectDB, finishedBy[2], player, prefer, 6)
        if objectPoint and (not point or objectPoint.score < point.score) then point = objectPoint end
        if point and point.name then turninText = "Turn in to " .. point.name end
    end
    if spec.complete then
        turninText = point and point.name and ("Ready to turn in to " .. point.name) or "Ready to turn in"
    end

    addStop(stops, {
        questId = questId,
        questName = questName,
        kind = "turnin",
        text = turninText,
        areaId = point and point.areaId or 0,
        x = point and point.x,
        y = point and point.y,
        followup = spec.followup,
        afterTurnin = spec.afterTurnin,
    })

    return stops
end

local function cleanText(text)
    if type(text) ~= "string" then return nil end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h", ""):gsub("|h", "")
    text = text:gsub("%s+", " ")
    text = text:match("^%s*(.-)%s*$")
    if not text or text == "" then return nil end
    return text
end

function ns.QuestBlurb(questId)
    if type(questId) ~= "number" or questId <= 0 then return nil end
    local index
    if C_QuestLog and type(C_QuestLog.GetLogIndexForQuestID) == "function" then
        local ok, value = pcall(C_QuestLog.GetLogIndexForQuestID, questId)
        if ok then index = ns.Plain(value) end
    end
    if type(index) == "number" and index > 0 and type(GetQuestLogQuestText) == "function" then
        local ok, description = pcall(GetQuestLogQuestText, index)
        if ok then
            local text = cleanText(ns.Plain(description))
            if text then return text end
        end
    end
    if C_QuestLog and type(C_QuestLog.GetQuestDescription) == "function" then
        local ok, description = pcall(C_QuestLog.GetQuestDescription, questId)
        if ok then
            local text = cleanText(ns.Plain(description))
            if text then return text end
        end
    end
    return nil
end

function ns.QuestObjectiveLines(questId)
    local value = ns.QuestCall(questId, "objectivesText")
    local lines = {}
    if type(value) == "string" then
        if value ~= "" then lines[1] = value end
        return lines
    end
    if type(value) ~= "table" then return lines end
    for _, line in ipairs(value) do
        if type(line) == "string" and line ~= "" then lines[#lines + 1] = line end
    end
    return lines
end

function ns.ObjectiveZoneLabel(questId)
    local function fallback()
        local zone = ns.QuestNumber(questId, "zoneOrSort")
        if zone and zone > 0 then
            local name = ns.ZoneName(zone)
            if type(name) == "string" and name ~= "" then return name end
        end
        return "No zone"
    end
    if not ns.QuestExists(questId) then return fallback() end
    local ok, stops = pcall(ns.CollectStops, questId, {
        followup = true,
        lines = {},
        questName = ns.QuestName(questId),
    })
    if not ok or type(stops) ~= "table" then return fallback() end
    local names, seen = {}, {}
    for _, stop in ipairs(stops) do
        if stop.kind == "objective" and type(stop.areaId) == "number" and stop.areaId > 0 then
            local name = ns.ZoneName(stop.areaId)
            if type(name) == "string" and name ~= "" and not seen[name] then
                seen[name] = true
                names[#names + 1] = name
                if #names >= 3 then break end
            end
        end
    end
    if #names == 0 then return fallback() end
    return table.concat(names, ", ")
end

local function displayWords(text)
    if type(text) ~= "string" then return "" end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h", ""):gsub("|h", "")
    text = text:gsub("%s*:%s*%d+%s*/%s*%d+%s*$", "")
    text = text:gsub("%s*%(%s*%d+%s*/%s*%d+%s*%)%s*$", "")
    text = text:gsub("%s+%d+%s*/%s*%d+%s*$", "")
    text = text:gsub("^%s*%d+%s*/%s*%d+%s+", "")
    text = text:gsub("%s+", " ")
    return (text:match("^%s*(.-)%s*$")) or ""
end

-- A fulfilled counter of 1/1 can be set while the objective is still open.
function ns.ProgressLabel(stop)
    if type(stop) ~= "table" or stop.kind ~= "objective" then return nil end
    local words = displayWords(stop.progressText)
    if words == "" then return nil end
    local need = stop.numRequired
    local got = type(stop.numFulfilled) == "number" and stop.numFulfilled or 0
    local label
    if type(need) == "number" and need > 1 then
        label = string.format("%d/%d %s", got, need, words)
    elseif stop.objectiveDone then
        label = words
    elseif type(need) == "number" and need <= 1 then
        label = "0/1 " .. words
    else
        return nil
    end
    if label == stop.text or label == displayWords(stop.text) then return nil end
    return label
end

function ns.ZonePair(areaId)
    if type(areaId) ~= "number" or areaId <= 0 then return nil, nil end
    local name = ns.ZoneName(areaId)
    local parentId = subToParent and subToParent[areaId]
    if type(parentId) == "number" and parentId > 0 and parentId ~= areaId then
        local parent = ns.ZoneName(parentId)
        if type(parent) == "string" and parent ~= "" and parent ~= name then
            return parent, name
        end
    end
    if name == "No zone" then return nil, nil end
    return name, nil
end

function ns.ContactText(spot)
    if type(spot) ~= "table" then return nil end
    local zone, subzone = ns.ZonePair(spot.areaId)
    local coord
    if type(spot.x) == "number" and type(spot.y) == "number" then
        coord = string.format("%.0f, %.0f", spot.x, spot.y)
    end
    local where = zone
    if type(subzone) == "string" and subzone ~= "" then
        where = where and (where .. ", " .. subzone) or subzone
    end
    local who = type(spot.name) == "string" and spot.name ~= "" and spot.name or nil
    local text
    if who and where then
        text = who .. " — " .. where
    else
        text = who or where
    end
    if coord then
        text = text and (text .. " (" .. coord .. ")") or coord
    end
    if not text or text == "" then return nil end
    return text
end

local function idArray(value)
    if type(value) == "number" and value > 0 then return { value } end
    if type(value) ~= "table" then return nil end
    return value
end

local function bestContact(npcIds, objectIds, itemIds, player, prefer)
    local point = bestOfIds(NpcDB, idArray(npcIds), player, prefer, 8)
    local objectPoint = bestOfIds(ObjectDB, idArray(objectIds), player, prefer, 6)
    if objectPoint and (not point or objectPoint.score < point.score) then
        point = objectPoint
    end
    if point then return point end
    local items = idArray(itemIds)
    local name = items and entityName(ItemDB, items[1])
    if name then return { name = name, areaId = 0 } end
    return nil
end

function ns.QuestContacts(questId, player)
    if not ns.QuestExists(questId) then return nil, nil end
    local prefer = preferZone(questId)
    local started = ns.QuestCall(questId, "startedBy") or {}
    local finished = ns.QuestCall(questId, "finishedBy") or {}
    return bestContact(started[1], started[2], started[3], player, prefer),
        bestContact(finished[1], finished[2], finished[3], player, prefer)
end
