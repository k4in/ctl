local _, ns = ...

function ns.StepKey(stop)
    local text = type(stop.text) == "string" and stop.text or ""
    text = text:lower()
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    text = text:gsub("%s*:%s*%d+%s*/%s*%d+%s*$", "")
    text = text:gsub("%s*%(%s*%d+%s*/%s*%d+%s*%)%s*$", "")
    text = text:gsub("%s+%d+%s*/%s*%d+%s*$", "")
    text = text:gsub("^%s*%d+%s*/%s*%d+%s+", "")
    text = text:gsub("%s+", " ")
    text = text:match("^%s*(.-)%s*$") or ""
    return tostring(stop.questId or 0) .. "\031" .. tostring(stop.kind or "") .. "\031" .. text
end

function ns.PromoteStep(steps, key)
    if type(steps) ~= "table" or type(key) ~= "string" then return end
    for index, stop in ipairs(steps) do
        if ns.StepKey(stop) == key then
            stop.skipped = nil
            if index ~= 1 then
                table.remove(steps, index)
                table.insert(steps, 1, stop)
            end
            return
        end
    end
end

function ns.ApplySkips(ordered)
    local db = ns.CharDB()
    if type(db.skipped) ~= "table" then return ordered end
    local head, tail = {}, {}
    for _, stop in ipairs(ordered) do
        if db.skipped[ns.StepKey(stop)] then
            stop.skipped = true
            tail[#tail + 1] = stop
        else
            head[#head + 1] = stop
        end
    end
    for _, stop in ipairs(tail) do
        head[#head + 1] = stop
    end
    return head
end

-- The guide lists every remaining step. Routing still sends only the next few.
function ns.VisibleStepIndexes(steps)
    local list = steps or {}
    local rows = {}
    for index = 1, #list do
        rows[#rows + 1] = index
    end
    return rows
end

local function fallbackStops(row)
    local name = row.title or ("Quest " .. row.id)
    local dungeon = ns.IsDungeonQuest and ns.IsDungeonQuest(row.id) or false
    local stops = {}
    if not row.complete then
        for _, line in ipairs(row.objectives or {}) do
            if not line.finished and type(line.text) == "string" and line.text ~= "" then
                stops[#stops + 1] = {
                    questId = row.id,
                    questName = name,
                    kind = "objective",
                    text = line.text,
                    areaId = 0,
                    dungeon = dungeon or nil,
                    progressText = line.text,
                    numFulfilled = line.numFulfilled,
                    numRequired = line.numRequired,
                    objectiveDone = false,
                    icon = "event",
                }
            end
        end
    end
    local note = row.secret and "Objective data is unreadable right now" or "no Questie data"
    stops[#stops + 1] = {
        questId = row.id,
        questName = name,
        kind = "turnin",
        text = row.complete and "Ready to turn in" or "Turn in",
        areaId = 0,
        note = note,
        dungeon = dungeon or nil,
        icon = "complete",
    }
    return stops
end

local function countObjectives(stops, into)
    for _, stop in ipairs(stops) do
        if stop.kind == "objective" then
            into[stop.questId] = (into[stop.questId] or 0) + 1
        end
    end
end

-- The turn-in zone is visited before the follow-up's zone when that zone still has work.
local function primaryArea(stops)
    local counts = {}
    for _, stop in ipairs(stops) do
        if stop.kind == "objective" and stop.areaId and stop.areaId ~= 0 then
            counts[stop.areaId] = (counts[stop.areaId] or 0) + 1
        end
    end
    local best, bestCount
    for areaId, count in pairs(counts) do
        if not best or count > bestCount then best, bestCount = areaId, count end
    end
    if best then return best end
    for _, stop in ipairs(stops) do
        if stop.areaId and stop.areaId ~= 0 then return stop.areaId end
    end
    return nil
end

local function attachFollowup(turnin, followStops, nextName, nextId)
    if not turnin then return end
    local areaId = primaryArea(followStops)
    turnin.nextArea = areaId
    turnin.nextName = nextName
    if type(nextId) == "number" and nextId > 0 then
        turnin.acceptId = nextId
        turnin.acceptName = nextName
    end
    if not nextName then return end
    if areaId then
        turnin.note = "Next: " .. nextName .. " in " .. ns.ZoneName(areaId)
    else
        turnin.note = "Next: " .. nextName
    end
end

local function here(player, areaId)
    if not player or not areaId or areaId == 0 then return false end
    if player.areaId and player.areaId == areaId then return true end
    return player.zoneName and ns.ZoneName(areaId) == player.zoneName
end

local function orderStops(stops, objCount, player)
    player = player or {}
    local emittedObj, emittedTurnin, emittedAccept = {}, {}, {}

    local function ready(stop)
        if stop.afterTurnin and not emittedTurnin[stop.afterTurnin] then return false end
        if stop.afterAccept and not emittedAccept[stop.afterAccept] then return false end
        if stop.kind == "turnin" then
            return (emittedObj[stop.questId] or 0) >= (objCount[stop.questId] or 0)
        end
        return true
    end

    local function take(stop)
        stop.used = true
        if stop.kind == "objective" then
            emittedObj[stop.questId] = (emittedObj[stop.questId] or 0) + 1
        elseif stop.kind == "accept" then
            emittedAccept[stop.questId] = true
        else
            emittedTurnin[stop.questId] = true
        end
    end

    local ordered = {}

    local function takeZone(areaId)
        local cursorX, cursorY
        if here(player, areaId) then cursorX, cursorY = player.x, player.y end
        local guard = 0
        while guard < 80 do
            guard = guard + 1
            local best, bestDistance, bestIndex
            for index, stop in ipairs(stops) do
                if not stop.used and (stop.areaId or 0) == areaId and ready(stop) then
                    local distance
                    if cursorX and stop.x and stop.y then
                        local dx, dy = stop.x - cursorX, stop.y - cursorY
                        distance = dx * dx + dy * dy
                    else
                        distance = stop.x and 1e9 or 1e11
                    end
                    if not best or distance < bestDistance or (distance == bestDistance and index < bestIndex) then
                        best, bestDistance, bestIndex = stop, distance, index
                    end
                end
            end
            if not best then return end
            take(best)
            ordered[#ordered + 1] = best
            if best.x and best.y then cursorX, cursorY = best.x, best.y end
        end
    end

    local function zoneScore(areaId)
        local eligible, objectives = 0, 0
        for _, stop in ipairs(stops) do
            if not stop.used and (stop.areaId or 0) == areaId and ready(stop) then
                eligible = eligible + 1
                if stop.kind == "objective" then objectives = objectives + 1 end
            end
        end
        if eligible == 0 then return nil end
        local score = eligible * 20 + objectives * 50
        if here(player, areaId) then score = score + 10000 end
        if areaId ~= 0 and player.continent and ns.ContinentOfArea(areaId) == player.continent then
            score = score + 700
        end
        if areaId == 0 then score = score - 2500 end
        return score
    end

    local guard = 0
    while guard <= #stops + 2 do
        guard = guard + 1
        local bestArea, bestScore
        local pending = false
        for _, stop in ipairs(stops) do
            if not stop.used then
                pending = true
                local score = zoneScore(stop.areaId or 0)
                if score and (not bestScore or score > bestScore) then
                    bestArea, bestScore = stop.areaId or 0, score
                end
            end
        end
        if not pending then break end

        if not bestArea then
            for _, stop in ipairs(stops) do
                if not stop.used then
                    take(stop)
                    ordered[#ordered + 1] = stop
                    break
                end
            end
        else
            -- A ready turn-in whose follow-up plays in the zone we would enter next
            -- is done first, so both sets of objectives share one visit.
            if not here(player, bestArea) then
                for _, stop in ipairs(stops) do
                    local turninArea = stop.areaId or 0
                    if not stop.used and stop.kind == "turnin" and stop.nextArea == bestArea
                        and turninArea ~= 0 and turninArea ~= bestArea and ready(stop) then
                        bestArea = turninArea
                        break
                    end
                end
            end
            local before = #ordered
            takeZone(bestArea)
            if #ordered == before then
                for _, stop in ipairs(stops) do
                    if not stop.used then
                        take(stop)
                        ordered[#ordered + 1] = stop
                        break
                    end
                end
            end
        end
    end

    return ordered
end

function ns.QuestView(rows)
    if ns.dbOpen == nil and ns.OpenDatabase then ns.OpenDatabase() end
    local dbReady = ns.DBReady and ns.DBReady()
    local view = {}
    for _, row in ipairs(rows or {}) do
        local name = row.title
        if type(name) ~= "string" or name == "" then
            name = (dbReady and ns.QuestName(row.id)) or ("Quest " .. row.id)
        end
        local chain = dbReady and ns.ChainInfo(row.id) or nil
        local level = row.level
        if dbReady then
            local questLevel = ns.QuestNumber(row.id, "questLevel")
            if questLevel and questLevel > 0 then level = questLevel end
        end
        local zone = row.zone
        if (type(zone) ~= "string" or zone == "") and dbReady then
            local area = ns.QuestNumber(row.id, "zoneOrSort")
            if type(area) == "number" and area > 0 then zone = ns.ZoneName(area) end
        end
        view[#view + 1] = {
            id = row.id,
            name = name,
            level = level,
            zone = (type(zone) == "string" and zone ~= "") and zone or "No zone",
            included = ns.IsIncluded(row.id),
            chainEnabled = chain and ns.ChainEnabled(row.id) or false,
            chain = chain,
            complete = row.complete,
            known = dbReady and ns.QuestExists(row.id) or false,
            dungeon = ns.IsDungeonQuest and ns.IsDungeonQuest(row.id) or false,
            objectives = row.objectives,
        }
    end
    table.sort(view, function(a, b)
        if a.included ~= b.included then return a.included end
        local left, right = a.level or 0, b.level or 0
        if left ~= right then return left < right end
        return (a.name or "") < (b.name or "")
    end)
    return view
end

local function pendingEntry(questId)
    local dbReady = ns.DBReady and ns.DBReady()
    local name = (dbReady and ns.QuestName(questId)) or ("Quest " .. questId)
    local level
    if dbReady then
        local questLevel = ns.QuestNumber(questId, "questLevel")
        if questLevel and questLevel > 0 then level = questLevel end
    end
    local zone = "No zone"
    if dbReady then
        local area = ns.QuestNumber(questId, "zoneOrSort")
        if type(area) == "number" and area > 0 and ns.ZoneName then
            local label = ns.ZoneName(area)
            if type(label) == "string" and label ~= "" then zone = label end
        end
    end
    local chain = dbReady and ns.ChainInfo and ns.ChainInfo(questId) or nil
    return {
        id = questId,
        name = name,
        level = level,
        zone = zone,
        included = true,
        chainEnabled = chain and ns.ChainEnabled and ns.ChainEnabled(questId) or false,
        chain = chain,
        complete = false,
        known = dbReady and ns.QuestExists(questId) or false,
        dungeon = ns.IsDungeonQuest and ns.IsDungeonQuest(questId) or false,
        objectives = {},
        pending = true,
    }
end

-- After a turn-in, the chain is gone from the Blizzard log until the follow-up
-- is accepted. Keep that follow-up in the quest list while the guide still has it.
function ns.WithPendingQuests(view, rows, steps)
    if type(view) ~= "table" then view = {} end
    local seen, live = {}, {}
    for _, quest in ipairs(view) do
        if type(quest.id) == "number" then seen[quest.id] = true end
    end
    for _, row in ipairs(rows or {}) do
        if type(row.id) == "number" then live[row.id] = true end
    end
    local candidates = {}
    local function consider(id)
        if type(id) ~= "number" or id <= 0 or seen[id] or live[id] then return end
        if ns.IsIncluded and not ns.IsIncluded(id) then return end
        candidates[id] = true
    end
    for _, stop in ipairs(steps or {}) do
        if stop.followup then consider(stop.questId) end
        if type(stop.acceptId) == "number" and (stop.awaitAccept or stop.followup) then
            consider(stop.acceptId)
        end
    end
    local function chainIds(id)
        local chain = type(ns.ChainInfo) == "function" and ns.ChainInfo(id) or nil
        if chain and type(chain.ids) == "table" then return chain.ids end
        return { id }
    end
    local function listed(ids)
        for _, member in ipairs(ids) do
            if live[member] then return true end
        end
        return false
    end
    local covered, chosen = {}, {}
    for id in pairs(candidates) do
        if not covered[id] then
            local members = chainIds(id)
            local best, bestAt
            for index, member in ipairs(members) do
                covered[member] = true
                if candidates[member] and not listed(members) and (not bestAt or index < bestAt) then
                    best, bestAt = member, index
                end
            end
            if best then chosen[#chosen + 1] = best end
        end
    end
    table.sort(chosen)
    for _, id in ipairs(chosen) do
        view[#view + 1] = pendingEntry(id)
    end
    return view
end

function ns.BuildPlan(rows, player)
    if ns.dbOpen == nil then ns.OpenDatabase() end
    player = player or {}

    local inLog = {}
    for _, row in ipairs(rows) do inLog[row.id] = true end

    local view = ns.QuestView(rows)
    local viewById = {}
    for _, quest in ipairs(view) do viewById[quest.id] = quest end

    local stops, objCount = {}, {}
    local addedFollow = {}
    local dbReady = ns.DBReady()

    for _, row in ipairs(rows) do
        local quest = viewById[row.id]
        local name = quest and quest.name or ("Quest " .. row.id)
        local chain = quest and quest.chain or nil

        if ns.IsIncluded(row.id) then
            local questStops
            if dbReady and ns.QuestExists(row.id) then
                local ok, result = pcall(ns.CollectStops, row.id, {
                    player = player,
                    questName = name,
                    complete = row.complete,
                    lines = row.objectives,
                })
                if ok and type(result) == "table" then questStops = result end
            end
            if not questStops then questStops = fallbackStops(row) end
            countObjectives(questStops, objCount)

            local turnin
            for _, stop in ipairs(questStops) do
                stops[#stops + 1] = stop
                if stop.kind == "turnin" then turnin = stop end
            end

            local cutoff = chain and ns.ChainCutoff and ns.ChainCutoff(row.id, chain) or nil
            if cutoff and cutoff ~= row.id then
                local previousId = row.id
                local previousTurnin = turnin
                local passed = false
                for _, id in ipairs(chain.ids or {}) do
                    if not passed then
                        if id == row.id then passed = true end
                    else
                        local nextId = ns.FollowupId({ nextId = id }, inLog)
                        if not nextId or addedFollow[nextId] then break end
                        addedFollow[nextId] = true
                        local followName = ns.QuestName(nextId) or ("Quest " .. nextId)
                        local ok, followStops = pcall(ns.CollectStops, nextId, {
                            player = player,
                            questName = followName,
                            lines = {},
                            followup = true,
                            afterTurnin = previousId,
                        })
                        if not ok or type(followStops) ~= "table" then break end
                        attachFollowup(previousTurnin, followStops, followName, nextId)
                        countObjectives(followStops, objCount)
                        local followTurnin
                        for _, stop in ipairs(followStops) do
                            stop.note = stop.note or "not in the log yet"
                            stops[#stops + 1] = stop
                            if stop.kind == "turnin" then followTurnin = stop end
                        end
                        previousId = nextId
                        previousTurnin = followTurnin
                        if nextId == cutoff then break end
                    end
                end
            end
        end
    end

    -- A turned-in quest leaves the log before its follow-up is accepted. Those
    -- quests stay reserved so a rebuild in that gap does not drop them.
    local handoff = ns.CharDB().handoff
    if dbReady and type(handoff) == "table" then
        local pending = {}
        for acceptId, fromId in pairs(handoff) do
            if not addedFollow[acceptId] and ns.FollowupReserved(acceptId, fromId, inLog) then
                pending[#pending + 1] = acceptId
            end
        end
        table.sort(pending, function(a, b)
            local left = ns.ChainInfo and ns.ChainInfo(a)
            local right = ns.ChainInfo and ns.ChainInfo(b)
            local leftAt = left and left.index or a
            local rightAt = right and right.index or b
            if leftAt ~= rightAt then return leftAt < rightAt end
            return a < b
        end)
        local previousId, previousTurnin
        for _, acceptId in ipairs(pending) do
            addedFollow[acceptId] = true
            local followName = ns.QuestName(acceptId) or ("Quest " .. acceptId)
            local ok, followStops = pcall(ns.CollectStops, acceptId, {
                player = player,
                questName = followName,
                lines = {},
                followup = true,
                afterTurnin = previousId,
            })
            if ok and type(followStops) == "table" then
                if previousTurnin then
                    attachFollowup(previousTurnin, followStops, followName, acceptId)
                end
                countObjectives(followStops, objCount)
                local followTurnin
                for _, stop in ipairs(followStops) do
                    stop.note = stop.note or "not in the log yet"
                    stops[#stops + 1] = stop
                    if stop.kind == "turnin" then followTurnin = stop end
                end
                previousId = acceptId
                previousTurnin = followTurnin
            end
        end
    end

    local warning
    if not dbReady then warning = ns.dbMessage or "QuestieDB is not loaded." end
    for _, row in ipairs(rows) do
        if row.secret then
            local suffix = "Some objective data is unavailable right now."
            warning = warning and (warning .. " " .. suffix) or suffix
            break
        end
    end

    local ordered = ns.ApplySkips(orderStops(stops, objCount, player))
    return {
        quests = ns.WithPendingQuests(view, rows, ordered),
        steps = ordered,
        warning = warning,
    }
end
