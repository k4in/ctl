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

-- Plan coordinates are questie-style 0-100. Shortest Path wants 0-1.
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

-- A moving quest giver has no static spawn. Questie then pins the first waypoint.
local function bestWaypoint(db, ids, player, preferArea)
    if type(ids) ~= "table" or type(db) ~= "table" or type(db.waypoints) ~= "function" then return nil end
    local best
    for _, id in ipairs(ids) do
        if type(id) == "number" and id > 0 then
            local ok, routes = pcall(db.waypoints, id)
            if ok and type(routes) == "table" then
                for areaId, paths in pairs(routes) do
                    if type(areaId) == "number" and type(paths) == "table" then
                        local path = paths[1]
                        local row = path
                        if type(path) == "table" and type(path[1]) == "table" then row = path[1] end
                        if type(row) == "table" then
                            local point = considerPoint(nil, areaId, row[1], row[2], player, preferArea)
                            if point and (not best or point.score < best.score) then
                                point.name = entityName(db, id)
                                best = point
                            end
                        end
                    end
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

local function idList(field, itemId)
    if type(ItemDB) ~= "table" or type(ItemDB[field]) ~= "function" then return nil end
    local ok, drops = pcall(ItemDB[field], itemId)
    if not ok or type(drops) ~= "table" or drops[1] == nil then return nil end
    return drops
end

-- Questie's resolved percent for one mob, the same number its tooltip shows.
-- Nil when Questie is not loaded or has no rate for that pair.
function ns.QuestieDropRate(itemId, npcId)
    if type(itemId) ~= "number" or itemId <= 0 then return nil end
    if type(npcId) ~= "number" or npcId <= 0 then return nil end
    local loader = QuestieLoader
    if type(loader) ~= "table" or type(loader.ImportModule) ~= "function" then return nil end
    local ok, db = pcall(loader.ImportModule, loader, "QuestieDB")
    if not ok or type(db) ~= "table" or type(db.GetItemDroprate) ~= "function" then return nil end
    local found, data = pcall(db.GetItemDroprate, itemId, npcId)
    if not found or type(data) ~= "table" then return nil end
    local rate = data[1]
    if type(rate) ~= "number" or rate <= 0 then return nil end
    return rate
end

-- Mean percent across every mob Questie lists for the item. Mobs with no
-- rate are left out. Nil when none of them have one.
function ns.AverageDropRate(itemId)
    local drops = idList("npcDrops", itemId)
    if not drops then return nil end
    local sum, count = 0, 0
    for _, npcId in ipairs(drops) do
        if type(npcId) == "number" and npcId > 0 then
            local rate = ns.QuestieDropRate(itemId, npcId)
            if type(rate) == "number" and rate > 0 then
                sum = sum + rate
                count = count + 1
            end
        end
    end
    if count == 0 then return nil end
    return sum / count
end

local function inArea(point, areaId)
    return type(point) == "table" and type(areaId) == "number" and areaId > 0 and point.areaId == areaId
end

-- The collect step stays the item. This is only where to go: mobs when the
-- item drops, object spawns when it is picked up. A source in the quest zone
-- wins over a nearer source of the other kind, so a passing mob does not
-- replace the chest the quest is about.
local function itemPoint(itemId, player, preferArea)
    if type(itemId) ~= "number" or itemId == 0 then return nil end
    local npcPoint = bestOfIds(NpcDB, idList("npcDrops", itemId), player, preferArea, 12)
    local objectPoint = bestOfIds(ObjectDB, idList("objectDrops", itemId), player, preferArea, 8)
    if objectPoint and not npcPoint then return objectPoint end
    if npcPoint and not objectPoint then return npcPoint end
    if not objectPoint or not npcPoint then return nil end
    local objectHome, npcHome = inArea(objectPoint, preferArea), inArea(npcPoint, preferArea)
    if objectHome ~= npcHome then return objectHome and objectPoint or npcPoint end
    if objectPoint.score == npcPoint.score then return objectPoint end
    return objectPoint.score < npcPoint.score and objectPoint or npcPoint
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

-- A later quest already in the log means this one was accepted and turned in.
local function laterQuestInLog(questId, inLog)
    if type(questId) ~= "number" or type(inLog) ~= "table" or type(ns.ChainInfo) ~= "function" then
        return false
    end
    local chain = ns.ChainInfo(questId)
    if type(chain) ~= "table" or type(chain.ids) ~= "table" then return false end
    local passed = false
    for _, id in ipairs(chain.ids) do
        if id == questId then
            passed = true
        elseif passed and inLog[id] ~= nil then
            return true
        end
    end
    return false
end

-- True when this step is already done, wherever it sits in the plan.
function ns.SyncStop(stop, row, inLog)
    if type(stop) ~= "table" then return false end
    local present = type(row) == "table"
    if present and stop.followup then
        stop.followup = nil
        if stop.note == "not in the log yet" then stop.note = nil end
    end
    local questId = stop.questId
    if not present and type(questId) == "number" and ns.IsQuestDone(questId) then return true end
    if stop.kind == "accept" then
        if present then return true end
        return laterQuestInLog(questId, inLog)
    end
    if stop.kind == "turnin" then
        stop.awaitAccept = nil
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
        local got, need = line.numFulfilled, line.numRequired
        if ns.MergeProgress then got, need = ns.MergeProgress(got, need, line.text) end
        stop.progressText = line.text
        stop.numFulfilled = got
        stop.numRequired = need
        stop.objectiveDone = line.finished and true or false
        return line.finished and true or false
    end
    if type(row.objectives) ~= "table" or #row.objectives == 0 then return false end
    for _, entry in ipairs(row.objectives) do
        if not entry.finished then return false end
    end
    return true
end

-- Questie icon type numbers. Zero means the objective has no override.
local ICON_NAME = {
    [1] = "slay",
    [2] = "loot",
    [3] = "event",
    [4] = "object",
    [5] = "talk",
    [6] = "available",
    [7] = "available_gray",
    [8] = "complete",
    [9] = "glow",
    [10] = "repeatable",
    [11] = "repeatable_complete",
    [12] = "incomplete",
    [13] = "eventquest",
    [14] = "eventquest_complete",
    [15] = "pvpquest",
    [16] = "pvpquest_complete",
    [17] = "interact",
    [18] = "sod_rune",
    [19] = "mount_up",
    [20] = "node_fish",
    [21] = "node_herb",
    [22] = "node_ore",
    [23] = "chest",
    [24] = "petbattle",
}

local ICON_PATH = {
    slay = "Interface\\Addons\\Questie\\Icons\\slay.blp",
    loot = "Interface\\Addons\\Questie\\Icons\\loot.blp",
    event = "Interface\\Addons\\Questie\\Icons\\event.blp",
    object = "Interface\\Addons\\Questie\\Icons\\object.blp",
    talk = "Interface\\Addons\\Questie\\Icons\\chatbubblegossipicon.blp",
    available = "Interface\\Addons\\Questie\\Icons\\available.blp",
    available_gray = "Interface\\Addons\\Questie\\Icons\\available_gray.blp",
    complete = "Interface\\Addons\\Questie\\Icons\\complete.blp",
    incomplete = "Interface\\Addons\\Questie\\Icons\\incomplete.blp",
    interact = "Interface\\Addons\\Questie\\Icons\\interact.blp",
    mount_up = "Interface\\Addons\\Questie\\Icons\\mount_up.blp",
    glow = "Interface\\Addons\\Questie\\Icons\\glow.blp",
    repeatable = "Interface\\Addons\\Questie\\Icons\\repeatable.blp",
    repeatable_complete = "Interface\\Addons\\Questie\\Icons\\repeatable_complete.blp",
    eventquest = "Interface\\Addons\\Questie\\Icons\\eventquest.blp",
    eventquest_complete = "Interface\\Addons\\Questie\\Icons\\eventquest_complete.blp",
    pvpquest = "Interface\\Addons\\Questie\\Icons\\pvpquest.blp",
    pvpquest_complete = "Interface\\Addons\\Questie\\Icons\\pvpquest_complete.blp",
    sod_rune = "Interface\\Addons\\Questie\\Icons\\sod_rune.tga",
    node_fish = "Interface\\Addons\\Questie\\Icons\\node_fish.blp",
    node_herb = "Interface\\Addons\\Questie\\Icons\\node_herb.blp",
    node_ore = "Interface\\Addons\\Questie\\Icons\\node_ore.blp",
    chest = "Interface\\Addons\\Questie\\Icons\\chest.blp",
    petbattle = "Interface\\Addons\\Questie\\Icons\\petbattle.png",
}

local ICON_TYPE = {}
for id, name in pairs(ICON_NAME) do ICON_TYPE[name] = id end

local function namedIcon(value)
    if type(value) ~= "number" or value <= 0 then return nil end
    return ICON_NAME[value]
end

local function listHasEntry(list)
    return type(list) == "table" and list[1] ~= nil
end

-- A collect objective that only comes from objects uses the object icon.
local function itemSourceIcon(itemId)
    if type(itemId) ~= "number" or itemId <= 0 or type(ItemDB) ~= "table" then return nil end
    local npc, object = false, false
    if type(ItemDB.npcDrops) == "function" then
        local ok, drops = pcall(ItemDB.npcDrops, itemId)
        npc = ok and listHasEntry(drops)
    end
    if type(ItemDB.objectDrops) == "function" then
        local ok, drops = pcall(ItemDB.objectDrops, itemId)
        object = ok and listHasEntry(drops)
    end
    if object and not npc then return "object" end
    return nil
end

local function itemIcon(iconField, itemId)
    return namedIcon(iconField) or itemSourceIcon(itemId) or "loot"
end

local function playerSide()
    if type(UnitFactionGroup) ~= "function" then return nil end
    local ok, faction = pcall(UnitFactionGroup, "player")
    if not ok then return nil end
    faction = ns.Plain(faction)
    if faction == "Alliance" then return "A" end
    if faction == "Horde" then return "H" end
    return nil
end

-- A creature objective with no icon is a talk step when that NPC is friendly.
local function friendlyNpc(id, side)
    if type(id) ~= "number" or id <= 0 then return nil end
    if type(NpcDB) ~= "table" or type(NpcDB.friendlyToFaction) ~= "function" then return nil end
    local ok, value = pcall(NpcDB.friendlyToFaction, id)
    if not ok or type(value) ~= "string" or value == "" then return false end
    if value == "AH" then return true end
    if side and value == side then return true end
    return false
end

local function creatureIcon(entry, iconIndex, ids)
    local named = namedIcon(entry[iconIndex])
    if named then return named end
    if type(ids) ~= "table" then return "slay" end
    local side = playerSide()
    local friendly = false
    for _, id in ipairs(ids) do
        local known = friendlyNpc(id, side)
        if known == false then return "slay" end
        if known == true then friendly = true end
    end
    if friendly then return "talk" end
    return "slay"
end

local function questStepIcon(questId, done)
    local flags = ns.QuestCall(questId, "specialFlags")
    if type(flags) == "number" and ns.Band(flags, 1) ~= 0 then
        return done and "repeatable_complete" or "repeatable"
    end
    return done and "complete" or "available"
end

function ns.StepIcon(stop)
    if type(stop) ~= "table" then return nil end
    local name = stop.icon
    if type(name) ~= "string" or not ICON_PATH[name] then
        if stop.kind == "accept" then name = "available"
        elseif stop.kind == "turnin" then name = "complete"
        elseif stop.kind == "objective" then name = "event"
        else return nil
        end
    end
    local typeId = ICON_TYPE[name]
    if type(Questie) == "table" and type(Questie.usedIcons) == "table" and typeId then
        local path = Questie.usedIcons[typeId]
        if type(path) == "string" and path ~= "" then return path end
    end
    if type(Questie) == "table" and type(Questie.icons) == "table" then
        local path = Questie.icons[name]
        if type(path) == "string" and path ~= "" then return path end
    end
    return ICON_PATH[name]
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
        local got, need = line.numFulfilled, line.numRequired
        if ns.MergeProgress then got, need = ns.MergeProgress(got, need, line.text) end
        stop.progressText = line.text
        stop.numFulfilled = got
        stop.numRequired = need
        stop.objectiveDone = line.finished and true or false
    end

    local function pushObjective(text, point, sourceName, icon, itemId)
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
            icon = icon or "event",
            itemId = type(itemId) == "number" and itemId > 0 and itemId or nil,
            unmatched = line == nil,
        }
        applyProgress(stop, line)
        queue[#queue + 1] = stop
    end

    if ns.QuestExists(questId) and not spec.complete then
        local objectives = ns.QuestCall(questId, "objectives") or {}
        local function creatures(list, textIndex, idIndex, iconIndex)
            if type(list) ~= "table" then return end
            for _, entry in ipairs(list) do
                if type(entry) == "table" then
                    local ids = entry[idIndex]
                    if type(ids) ~= "table" then ids = { ids } end
                    local point = bestOfIds(NpcDB, ids, player, prefer, 8)
                    local text = objectiveText(entry, textIndex, point and point.name or "Enemy")
                    pushObjective(text, point, point and point.name, creatureIcon(entry, iconIndex, ids))
                end
            end
        end

        creatures(objectives[1], 2, 1, 3)
        if type(objectives[2]) == "table" then
            for _, entry in ipairs(objectives[2]) do
                if type(entry) == "table" then
                    local point = bestOfIds(ObjectDB, { entry[1] }, player, prefer, 4)
                    local text = objectiveText(entry, 2, point and point.name or "Object")
                    pushObjective(text, point, point and point.name, namedIcon(entry[3]) or "object")
                end
            end
        end
        if type(objectives[3]) == "table" then
            for _, entry in ipairs(objectives[3]) do
                if type(entry) == "table" then
                    local name = entityName(ItemDB, entry[1])
                    local point = itemPoint(entry[1], player, prefer)
                    local text = objectiveText(entry, 2, name or "Item")
                    pushObjective(text, point, name, itemIcon(entry[3], entry[1]), entry[1])
                end
            end
        end
        creatures(objectives[5], 3, 1, 4)
        if type(objectives[6]) == "table" then
            for _, entry in ipairs(objectives[6]) do
                if type(entry) == "table" then
                    local point = itemPoint(entry[3], player, prefer)
                    local icon = "interact"
                    if type(entry[3]) == "number" and entry[3] > 0 then icon = itemIcon(nil, entry[3]) end
                    pushObjective(objectiveText(entry, 2, "Spell target"), point, nil, icon)
                end
            end
        end

        local trigger = ns.QuestCall(questId, "triggerEnd")
        if type(trigger) == "table" then
            local text = type(trigger[1]) == "string" and trigger[1] ~= "" and trigger[1] or "Enter the area"
            pushObjective(text, bestPoint(trigger[2], player, prefer), nil, "event")
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
                    if text or point then
                        pushObjective(text or "Extra objective", point, nil, namedIcon(entry[2]) or "event")
                    end
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
                    icon = "event",
                }
                applyProgress(stop, line)
                addStop(stops, stop)
            end
        end
    end

    -- The step names the quest. The NPC stays on the map point, not in the title.
    local turninText = questName
    if type(turninText) ~= "string" or turninText == "" then turninText = "Turn in" end
    local point
    if ns.QuestExists(questId) then
        local finishedBy = ns.QuestCall(questId, "finishedBy") or {}
        point = bestOfIds(NpcDB, finishedBy[1], player, prefer, 8)
        local objectPoint = bestOfIds(ObjectDB, finishedBy[2], player, prefer, 6)
        if objectPoint and (not point or objectPoint.score < point.score) then point = objectPoint end
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
        afterAccept = spec.followup and questId or nil,
        icon = questStepIcon(questId, true),
    })

    -- Accepting the follow-up is its own step, at that quest's giver.
    if spec.followup then
        local giver = select(1, ns.QuestContacts(questId, player))
        if type(giver) ~= "table" or type(giver.x) ~= "number" or type(giver.y) ~= "number" then
            local started = ns.QuestCall(questId, "startedBy") or {}
            local function asIds(value)
                if type(value) == "number" and value > 0 then return { value } end
                if type(value) ~= "table" then return nil end
                return value
            end
            local walked = bestWaypoint(NpcDB, asIds(started[1]), player, prefer)
            if not walked then walked = bestWaypoint(ObjectDB, asIds(started[2]), player, prefer) end
            if walked then
                if type(giver) == "table" and type(giver.name) == "string" and not walked.name then
                    walked.name = giver.name
                end
                giver = walked
            end
        end
        local accept = {
            questId = questId,
            questName = questName,
            kind = "accept",
            text = questName,
            areaId = giver and giver.areaId or 0,
            x = giver and giver.x,
            y = giver and giver.y,
            sourceName = giver and giver.name,
            followup = true,
            afterTurnin = spec.afterTurnin,
            acceptId = questId,
            acceptName = questName,
            icon = questStepIcon(questId, false),
        }
        table.insert(stops, 1, accept)
        for index = 2, #stops do
            stops[index].afterAccept = questId
        end
    end

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
    text = text:gsub("%s*：%s*%d+%s*/%s*%d+%s*$", "")
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
    if ns.CountInText then
        local parsedGot, parsedNeed = ns.CountInText(stop.progressText)
        if type(parsedGot) == "number" and parsedGot > got then
            got = parsedGot
            if type(parsedNeed) == "number" and parsedNeed > 0 then need = parsedNeed end
        elseif (type(need) ~= "number" or need < 1) and type(parsedNeed) == "number" and parsedNeed > 0 then
            need = parsedNeed
        end
    end
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

-- Used only when an accept step was stored without a map point.
function ns.AcceptTarget(stop)
    if type(stop) ~= "table" or stop.kind ~= "accept" then return nil end
    if ns.HasMapPoint(stop) then return nil end
    local questId = stop.questId
    if type(questId) ~= "number" or questId <= 0 then return nil end
    local player
    if type(ns.PlayerLocation) == "function" then
        local ok, value = pcall(ns.PlayerLocation)
        if ok then player = value end
    end
    local giver = ns.QuestContacts(questId, player)
    if type(giver) ~= "table" then return nil end
    giver.questId = questId
    return giver
end

-- While that quest is still unaccepted, the current step points at its giver.
function ns.RouteStop(stop)
    if type(stop) ~= "table" then return stop end
    local giver = ns.AcceptTarget(stop)
    if type(giver) ~= "table" or not ns.HasMapPoint(giver) then return stop end
    local name = stop.acceptName
    if type(name) ~= "string" or name == "" then name = stop.questName end
    if type(name) ~= "string" or name == "" then name = stop.text end
    return {
        areaId = giver.areaId,
        x = giver.x,
        y = giver.y,
        questId = giver.questId or stop.questId,
        questName = name,
        text = name,
        kind = stop.kind,
        dungeon = stop.dungeon,
        awaitAccept = stop.awaitAccept,
        followup = stop.followup,
        acceptId = stop.acceptId,
        acceptName = stop.acceptName,
        sourceName = giver.name,
        icon = stop.icon,
    }
end
