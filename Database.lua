local _, ns = ...

local zoneNames = {}
local uiMapToArea
local areaToUi

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

function ns.OpenDatabase()
    if ns.dbOpen ~= nil then return ns.dbOpen end
    if type(LibQuestieDB) ~= "table" or type(QuestDB) ~= "table" or type(QuestDB.Exists) ~= "function" then
        ns.dbMessage = "QuestieDB ist nicht geladen."
        ns.dbOpen = false
        return false
    end
    if type(LibQuestieDB.RequireContract) == "function" then
        local ok, message = LibQuestieDB.RequireContract(1)
        if not ok then
            ns.dbMessage = message or "QuestieDB-Vertrag passt nicht."
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
    else
        uiMapToArea, areaToUi = {}, {}
    end

    ns.dbOpen = true
    return true
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
    if type(areaId) ~= "number" or areaId == 0 then return "Ohne Gebiet" end
    local cached = zoneNames[areaId]
    if cached then return cached end
    local name
    if C_Map and C_Map.GetAreaInfo then
        local ok, result = pcall(C_Map.GetAreaInfo, areaId)
        if ok then name = ns.Plain(result) end
    end
    if type(name) ~= "string" or name == "" then name = "Gebiet " .. areaId end
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
    return text:lower()
end

local function preferZone(questId)
    local zone = ns.QuestNumber(questId, "zoneOrSort")
    if zone and zone > 0 then return zone end
    return nil
end

local function addStop(stops, stop)
    stop.areaId = stop.areaId or 0
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

    local function claimed(text)
        local key = norm(text)
        if key == "" then return false end
        for _, line in ipairs(lines) do
            if not line.used and norm(line.text) == key then
                line.used = true
                if line.finished then return true end
                return false
            end
        end
        return false
    end

    local function pushObjective(text, point, sourceName)
        if spec.complete then return end
        if claimed(text) then return end
        local key = norm(text)
        if key ~= "" and seen[key] then return end
        if key ~= "" then seen[key] = true end
        addStop(stops, {
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
        })
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
                    pushObjective(objectiveText(entry, textIndex, point and point.name or "Gegner"), point, point and point.name)
                end
            end
        end

        creatures(objectives[1], 2, 1)
        if type(objectives[2]) == "table" then
            for _, entry in ipairs(objectives[2]) do
                if type(entry) == "table" then
                    local point = bestOfIds(ObjectDB, { entry[1] }, player, prefer, 4)
                    pushObjective(objectiveText(entry, 2, point and point.name or "Objekt"), point, point and point.name)
                end
            end
        end
        if type(objectives[3]) == "table" then
            for _, entry in ipairs(objectives[3]) do
                if type(entry) == "table" then
                    local point = itemPoint(entry[1], player, prefer)
                    local text = objectiveText(entry, 2, point and point.name or "Gegenstand")
                    pushObjective(text, point, point and point.name)
                end
            end
        end
        creatures(objectives[5], 3, 1)
        if type(objectives[6]) == "table" then
            for _, entry in ipairs(objectives[6]) do
                if type(entry) == "table" then
                    local point = itemPoint(entry[3], player, prefer)
                    pushObjective(objectiveText(entry, 2, "Zauberziel"), point, point and point.name)
                end
            end
        end

        local trigger = ns.QuestCall(questId, "triggerEnd")
        if type(trigger) == "table" then
            local text = type(trigger[1]) == "string" and trigger[1] ~= "" and trigger[1] or "Gebiet betreten"
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
                    if text or point then pushObjective(text or "Weiteres Ziel", point) end
                end
            end
        end
    end

    if not spec.followup and not spec.complete then
        for _, line in ipairs(lines) do
            if not line.used and not line.finished and type(line.text) == "string" and line.text ~= "" then
                line.used = true
                pushObjective(line.text, nil)
            end
        end
    end

    local turninText = "Abgeben"
    local point
    if ns.QuestExists(questId) then
        local finishedBy = ns.QuestCall(questId, "finishedBy") or {}
        point = bestOfIds(NpcDB, finishedBy[1], player, prefer, 8)
        local objectPoint = bestOfIds(ObjectDB, finishedBy[2], player, prefer, 6)
        if objectPoint and (not point or objectPoint.score < point.score) then point = objectPoint end
        if point and point.name then turninText = "Bei " .. point.name .. " abgeben" end
    end
    if spec.complete then
        turninText = point and point.name and ("Fertig, bei " .. point.name .. " abgeben") or "Fertig, abgeben"
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
