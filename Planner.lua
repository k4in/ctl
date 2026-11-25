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

local EXACT_LIMIT = 8
local IMPROVE_LIMIT = 40
local FAR_ZONE = 1000000
local FAR_WORLD = 100000000
local UNREACHABLE = 1000000

local function hasPoint(stop)
    return type(stop) == "table"
        and type(stop.areaId) == "number" and stop.areaId > 0
        and type(stop.x) == "number" and type(stop.y) == "number"
end

-- Same zone uses the straight line. Another zone is only a stand-in until
-- Shortest Path reports a travel time. Coordinates do not cross zone borders.
function ns.CheapTravel(player, fromStop, toStop)
    if not hasPoint(toStop) then return FAR_WORLD end
    local from = fromStop or player
    if type(from) == "table" and type(from.x) == "number" and type(from.y) == "number"
        and type(from.areaId) == "number" and from.areaId == toStop.areaId then
        local dx, dy = toStop.x - from.x, toStop.y - from.y
        return dx * dx + dy * dy
    end
    if type(from) == "table" and type(from.areaId) == "number" and type(ns.ContinentOfArea) == "function" then
        local left = from.continent or ns.ContinentOfArea(from.areaId)
        local right = toStop.continent or ns.ContinentOfArea(toStop.areaId)
        if left and right and left == right then return FAR_ZONE end
    end
    return FAR_WORLD
end

-- Open tour. `first` stays at the start when the player pinned a step.
-- cost(fromIndex, toIndex) uses 0 for the player. ready(index, seen) is precedence.
function ns.TourOrder(count, cost, ready, first)
    if count < 1 then return {} end
    local function nearest()
        local order, seen = {}, {}
        local from, start = 0, 1
        if first then
            order[1], seen[first], from, start = first, true, first, 2
        end
        for step = start, count do
            local best, bestCost
            for to = 1, count do
                if not seen[to] and ready(to, seen) then
                    local value = cost(from, to)
                    if value ~= nil and (not best or value < bestCost or (value == bestCost and to < best)) then
                        best, bestCost = to, value
                    end
                end
            end
            if not best then
                for to = 1, count do
                    if not seen[to] then best = to break end
                end
            end
            if not best then break end
            order[step], seen[best], from = best, true, best
        end
        return order
    end

    local function legCost(from, to)
        local leg = cost(from, to)
        if leg == nil then return FAR_WORLD end
        return leg
    end

    local function total(order)
        local sum, from = 0, 0
        for _, to in ipairs(order) do
            sum = sum + legCost(from, to)
            from = to
        end
        return sum
    end

    local function legal(order)
        local seen = {}
        for _, index in ipairs(order) do
            if not ready(index, seen) then return false end
            seen[index] = true
        end
        return true
    end

    local function exact(fallback)
        local bits = {}
        for index = 1, count do bits[index] = 2 ^ (index - 1) end
        local memo, scratch = {}, {}
        local function allowed(index, remaining)
            for at = 1, count do scratch[at] = nil end
            for at = 1, count do
                if math.floor(remaining / bits[at]) % 2 == 0 then scratch[at] = true end
            end
            return ready(index, scratch)
        end
        local function solve(from, remaining)
            if remaining == 0 then return 0 end
            local states = memo[remaining]
            if not states then
                states = {}
                memo[remaining] = states
            end
            if states[from] then return states[from].seconds end
            local best, nextStop = math.huge, nil
            for to = 1, count do
                if math.floor(remaining / bits[to]) % 2 >= 1 and allowed(to, remaining) then
                    local leg = cost(from, to)
                    if leg ~= nil then
                        local seconds = leg + solve(to, remaining - bits[to])
                        if seconds < best then best, nextStop = seconds, to end
                    end
                end
            end
            states[from] = { seconds = best, nextStop = nextStop }
            return best
        end
        local remaining = 2 ^ count - 1
        local best = solve(0, remaining)
        if best == math.huge or (fallback and total(fallback) <= best) then
            return fallback
        end
        local order, from = {}, 0
        for index = 1, count do
            local row = memo[remaining] and memo[remaining][from]
            local to = row and row.nextStop
            if not to then return fallback end
            order[index], remaining, from = to, remaining - bits[to], to
        end
        return order
    end

    local function improve(order, locked)
        local left, right, saving
        for i = locked + 1, #order - 1 do
            local before, head = order[i - 1] or 0, order[i]
            local oldEnter = legCost(before, head)
            local forward, backward, broken = 0, 0, false
            for j = i + 1, #order do
                if broken then break end
                local previous, last, after = order[j - 1], order[j], order[j + 1]
                local reverse = cost(last, previous)
                if reverse == nil then
                    broken = true
                    break
                end
                forward = forward + legCost(previous, last)
                backward = backward + reverse
                local enter = cost(before, last)
                if enter ~= nil then
                    local leave = after and legCost(head, after) or 0
                    local oldLeave = after and legCost(last, after) or 0
                    local saved = (oldEnter + forward + oldLeave) - (enter + backward + leave)
                    if saved > (saving or 0) then
                        local candidate = {}
                        for at = 1, #order do candidate[at] = order[at] end
                        for at = i, j do candidate[at] = order[j - (at - i)] end
                        if legal(candidate) and total(candidate) < total(order) then
                            left, right, saving = i, j, saved
                        end
                    end
                end
            end
        end
        if not left then return nil end
        local improved = {}
        for at = 1, #order do improved[at] = order[at] end
        for at = left, right do improved[at] = order[right - (at - left)] end
        return improved
    end

    local order = nearest()
    if not first and count <= EXACT_LIMIT then order = exact(order) or order end
    if order and #order <= IMPROVE_LIMIT then
        local locked = first and 1 or 0
        local guard = 0
        while order and guard < 12 do
            guard = guard + 1
            local improved = improve(order, locked)
            if not improved then break end
            order = improved
        end
    end
    return order or {}
end

-- Shortest travel order that still turns a quest in after its objectives and
-- accepts a follow-up before that follow-up's own steps. Steps without a point
-- stay attached to their quest and do not pull the tour.
function ns.OrderStops(stops, _, player, cost, pinKey)
    player = player or {}
    cost = cost or function(fromStop, toStop)
        return ns.CheapTravel(player, fromStop, toStop)
    end
    local pool, tail = {}, {}
    local skipped = ns.CharDB and ns.CharDB().skipped or nil
    for _, stop in ipairs(stops or {}) do
        local key = ns.StepKey(stop)
        if type(skipped) == "table" and skipped[key] then
            stop.skipped = true
            tail[#tail + 1] = stop
        else
            stop.skipped = nil
            pool[#pool + 1] = stop
        end
    end

    local objectives, turnin, accept = {}, {}, {}
    for _, stop in ipairs(pool) do
        local questId = stop.questId
        if stop.kind == "objective" then
            local list = objectives[questId]
            if not list then
                list = {}
                objectives[questId] = list
            end
            list[#list + 1] = stop
        elseif stop.kind == "accept" then
            accept[questId] = stop
        elseif stop.kind == "turnin" then
            turnin[questId] = stop
        end
    end

    local geo, geoOf = {}, {}
    for _, stop in ipairs(pool) do
        if hasPoint(stop) then
            geo[#geo + 1] = stop
            geoOf[stop] = #geo
        end
    end

    local blockers = {}
    for index = 1, #geo do blockers[index] = {} end
    local function block(index, stop)
        local other = stop and geoOf[stop]
        if other and other ~= index then blockers[index][#blockers[index] + 1] = other end
    end
    for index, stop in ipairs(geo) do
        if stop.kind == "turnin" then
            for _, obj in ipairs(objectives[stop.questId] or {}) do block(index, obj) end
        end
        if stop.afterAccept then block(index, accept[stop.afterAccept]) end
        if stop.afterTurnin then
            local prev = turnin[stop.afterTurnin]
            if prev and geoOf[prev] then
                block(index, prev)
            else
                for _, obj in ipairs(objectives[stop.afterTurnin] or {}) do block(index, obj) end
            end
        end
    end

    local function ready(index, seen)
        for _, other in ipairs(blockers[index]) do
            if not seen[other] then return false end
        end
        return true
    end

    local first
    if type(pinKey) == "string" then
        for index, stop in ipairs(geo) do
            if ns.StepKey(stop) == pinKey then first = index break end
        end
    end

    local function indexCost(from, to)
        return cost(from > 0 and geo[from] or nil, geo[to])
    end

    local indexes = ns.TourOrder(#geo, indexCost, ready, first)
    local geoOrder = {}
    for _, index in ipairs(indexes) do geoOrder[#geoOrder + 1] = geo[index] end

    local placed, emitting, result = {}, {}, {}
    local function emit(stop)
        if not stop or placed[stop] or emitting[stop] then return end
        emitting[stop] = true
        if stop.afterTurnin then emit(turnin[stop.afterTurnin]) end
        if stop.afterAccept then emit(accept[stop.afterAccept]) end
        if stop.kind == "turnin" then
            for _, obj in ipairs(objectives[stop.questId] or {}) do emit(obj) end
        end
        emitting[stop] = nil
        if placed[stop] then return end
        placed[stop] = true
        result[#result + 1] = stop
    end
    for _, stop in ipairs(geoOrder) do emit(stop) end
    for _, stop in ipairs(pool) do emit(stop) end
    if type(pinKey) == "string" then
        for index, stop in ipairs(result) do
            if ns.StepKey(stop) == pinKey and index ~= 1 then
                table.remove(result, index)
                table.insert(result, 1, stop)
                break
            end
        end
    end
    for _, stop in ipairs(tail) do result[#result + 1] = stop end
    return result
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

    local ordered = ns.ApplySkips(ns.OrderStops(stops, objCount, player))
    return {
        quests = ns.WithPendingQuests(view, rows, ordered),
        steps = ordered,
        warning = warning,
    }
end

local function travelPoint(spot)
    if type(spot) ~= "table" or type(ns.UiMap) ~= "function" or type(ns.MapFraction) ~= "function" then
        return nil
    end
    local map = ns.UiMap(spot.areaId)
    local x, y = ns.MapFraction(spot.x), ns.MapFraction(spot.y)
    if type(map) ~= "number" or not x or not y then return nil end
    return map, x, y
end

local function estimateApi()
    local api = type(ShortestPathForever) == "table" and ShortestPathForever.API or nil
    if type(api) ~= "table" or type(api.Estimate) ~= "function" then return nil end
    return api
end

function ns.CancelTour()
    if not ns.tourPending then return end
    ns.tourEpoch = (ns.tourEpoch or 0) + 1
    ns.tourPending = false
end

function ns.ApplyTour(plan, ordered, epoch)
    if epoch ~= ns.tourEpoch or ns.lastPlan ~= plan or type(ordered) ~= "table" then return end
    local live = {}
    for _, stop in ipairs(plan.steps or {}) do live[stop] = true end
    local nextSteps, seen = {}, {}
    for _, stop in ipairs(ordered) do
        if live[stop] and not seen[stop] then
            nextSteps[#nextSteps + 1] = stop
            seen[stop] = true
        end
    end
    for _, stop in ipairs(plan.steps or {}) do
        if not seen[stop] then nextSteps[#nextSteps + 1] = stop end
    end
    plan.steps = ns.ApplySkips(nextSteps)
    local start = 1
    while plan.steps[start] and plan.steps[start].skipped do start = start + 1 end
    if not plan.steps[start] then start = 1 end
    if #plan.steps > 0 and start > #plan.steps then start = #plan.steps end
    ns.windowStart = start
    ns.tourPending = false
    if ns.Render then ns.Render(plan, ns.lastErr) end
    local db = ns.CharDB and ns.CharDB() or nil
    if db and db.navigating == true and ns.PushRoute then
        ns.PushRoute(plan, start, { plan = true })
    end
end

-- One uncached Shortest Path estimate per frame. The cheap order stays up until this finishes.
function ns.ScheduleTour(plan, player, pinKey)
    ns.tourEpoch = (ns.tourEpoch or 0) + 1
    local epoch = ns.tourEpoch
    ns.tourPending = false
    local api = estimateApi()
    local steps = plan and plan.steps
    if not api or type(C_Timer) ~= "table" or type(C_Timer.After) ~= "function" then return end
    if type(steps) ~= "table" then return end
    local mappable = 0
    for _, stop in ipairs(steps) do
        if travelPoint(stop) then mappable = mappable + 1 end
    end
    if mappable < 2 then return end

    local ids = {}
    for index, stop in ipairs(steps) do ids[stop] = index end
    local cache = {}
    local function yieldingCost(fromStop, toStop)
        local key = (fromStop and ids[fromStop] or 0) .. ":" .. (ids[toStop] or 0)
        local cached = cache[key]
        if cached == nil then
            cached = coroutine.yield("need", fromStop, toStop)
            cache[key] = cached
        end
        return cached
    end

    local function ask(fromStop, toStop)
        local fromMap, fromX, fromY = travelPoint(fromStop or player)
        local toMap, toX, toY = travelPoint(toStop)
        if not fromMap or not toMap then return UNREACHABLE, "unreachable" end
        local ok, seconds, reason = pcall(api.Estimate, fromMap, fromX, fromY, toMap, toX, toY)
        if not ok then return UNREACHABLE, "unreachable" end
        if type(seconds) == "number" then return seconds end
        return nil, reason or "loading"
    end

    local worker = coroutine.create(function()
        return ns.OrderStops(steps, nil, player, yieldingCost, pinKey)
    end)

    local function step(value)
        if epoch ~= ns.tourEpoch then return end
        local ok, tag, fromStop, toStop = coroutine.resume(worker, value)
        if epoch ~= ns.tourEpoch then return end
        if not ok then
            ns.tourPending = false
            if ns.Render then ns.Render(plan, ns.lastErr) end
            return
        end
        if coroutine.status(worker) == "dead" then
            ns.tourPending = false
            if type(tag) == "table" then
                ns.ApplyTour(plan, tag, epoch)
            elseif ns.Render then
                ns.Render(plan, ns.lastErr)
            end
            return
        end
        if tag ~= "need" then
            C_Timer.After(0, function() step(nil) end)
            return
        end
        local function deliver()
            if epoch ~= ns.tourEpoch then return end
            local seconds, reason = ask(fromStop, toStop)
            if seconds == nil and reason ~= "unreachable" then
                C_Timer.After(0.25, deliver)
                return
            end
            C_Timer.After(0, function() step(seconds or UNREACHABLE) end)
        end
        deliver()
    end

    ns.tourPending = true
    C_Timer.After(0, function() step(nil) end)
end
