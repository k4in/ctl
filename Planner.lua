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
-- Above this, a full distance matrix no longer fits the search budget.
local NEIGHBOR_CUTOFF = 32
local FAR_ZONE = 1000000
local FAR_WORLD = 100000000
local UNREACHABLE = 1000000

local function hasPoint(stop)
    return type(stop) == "table"
        and type(stop.areaId) == "number" and stop.areaId > 0
        and type(stop.x) == "number" and type(stop.y) == "number"
end

-- Flat work on top of travel. Kills, pickups, and talking scale with the
-- remaining count. A mob drop uses the average Questie drop rate, so the
-- expected kills are the remaining items divided by that rate, at the kill
-- time. 8 items at 50% is 16 kills. No rate keeps the flat loot time.
-- Accept and turn-in are short fixed actions.
local WORK_SECONDS = {
    slay = 45,
    loot = 60,
    object = 30,
    chest = 30,
    node_herb = 30,
    node_ore = 30,
    node_fish = 30,
    talk = 10,
    interact = 10,
}

local function remainingUnits(stop)
    local need = stop.numRequired
    if type(need) ~= "number" or need < 1 then return 1 end
    local got = type(stop.numFulfilled) == "number" and stop.numFulfilled or 0
    local left = need - got
    if left < 0 then return 0 end
    return left
end

function ns.WorkSeconds(stop)
    if type(stop) ~= "table" or stop.skipped then return 0 end
    if stop.kind == "accept" or stop.kind == "turnin" then return 15 end
    if stop.kind ~= "objective" then return 0 end
    local units = remainingUnits(stop)
    if stop.icon == "loot" and type(ns.AverageDropRate) == "function" then
        local rate = ns.AverageDropRate(stop.itemId)
        if type(rate) == "number" and rate > 0 then
            return WORK_SECONDS.slay * units * (100 / rate)
        end
    end
    local each = WORK_SECONDS[stop.icon]
    if not each then return 0 end
    return each * units
end

function ns.FormatDuration(seconds)
    if type(seconds) ~= "number" or seconds ~= seconds or seconds <= 0 then return "0m" end
    local minutes = math.ceil(seconds / 60)
    local days = math.floor(minutes / 1440)
    minutes = minutes - days * 1440
    local hours = math.floor(minutes / 60)
    minutes = minutes - hours * 60
    if days > 0 then return string.format("%dd %dh %dm", days, hours, minutes) end
    if hours > 0 then return string.format("%dh %dm", hours, minutes) end
    return string.format("%dm", minutes)
end

function ns.TotalSeconds(steps)
    local total = 0
    if type(steps) ~= "table" then return 0 end
    for _, stop in ipairs(steps) do
        if not stop.skipped then
            total = total + ns.WorkSeconds(stop)
            local leg = stop.travelSeconds
            if type(leg) == "number" and leg >= 0 and leg < UNREACHABLE then
                total = total + leg
            end
        end
    end
    return total
end

function ns.StampTravel(steps, player, cost)
    if type(steps) ~= "table" or type(cost) ~= "function" then return end
    local previous
    for _, stop in ipairs(steps) do
        stop.travelSeconds = nil
        if not stop.skipped and hasPoint(stop) then
            local seconds = cost(previous, stop)
            if type(seconds) == "number" and seconds >= 0 and seconds < UNREACHABLE then
                stop.travelSeconds = seconds
            end
            previous = stop
        end
    end
end

local function countWord(count, one, many)
    if count == 1 then return "1 " .. one end
    return tostring(count) .. " " .. many
end

function ns.GuideFooter(plan)
    local steps = plan and plan.steps or {}
    local inLog, included = 0, 0
    for _, quest in ipairs(plan and plan.quests or {}) do
        if not quest.pending then
            inLog = inLog + 1
            if quest.included then included = included + 1 end
        end
    end
    local logWord = inLog == 1 and "quest" or "quests"
    local verb = included == 1 and "is" or "are"
    local summary = string.format(
        "%s. %d of %d %s in your log %s in the guide.",
        countWord(#steps, "total step", "total steps"),
        included, inLog, logWord, verb
    )
    local timeText = "Total estimated time to complete: …"
    if not ns.tourPending and ns.travelReady then
        timeText = "Total estimated time to complete: " .. ns.FormatDuration(ns.TotalSeconds(steps))
    end
    return summary, timeText
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

-- Steps worth measuring from `from`. Same zone first, then a couple of entrances
-- per other zone, then a few more nearby ones. The search falls back to every
-- step when none of these is allowed yet.
function ns.TourNeighbors(count, zoneOf, rank)
    if type(count) ~= "number" or count < 2 or type(zoneOf) ~= "function" or type(rank) ~= "function" then
        return nil
    end
    local neighbors = {}
    local function build(from)
        local fromZone = zoneOf(from)
        local scored = {}
        for to = 1, count do
            if to ~= from then
                local value = rank(from, to)
                scored[#scored + 1] = {
                    to = to,
                    zone = zoneOf(to),
                    rank = type(value) == "number" and value or 0,
                }
            end
        end
        table.sort(scored, function(a, b)
            if a.rank ~= b.rank then return a.rank < b.rank end
            return a.to < b.to
        end)
        local picked, list = {}, {}
        local function take(to)
            if to == from or picked[to] then return false end
            picked[to] = true
            list[#list + 1] = to
            return true
        end
        local same = 0
        for _, item in ipairs(scored) do
            if fromZone ~= nil and item.zone == fromZone and same < 24 and take(item.to) then
                same = same + 1
            end
        end
        local perZone = {}
        for _, item in ipairs(scored) do
            if item.zone ~= fromZone then
                local used = perZone[item.zone] or 0
                if used < 2 and take(item.to) then perZone[item.zone] = used + 1 end
            end
        end
        local extra = 0
        for _, item in ipairs(scored) do
            if extra >= 6 then break end
            if take(item.to) then extra = extra + 1 end
        end
        neighbors[from] = list
    end
    build(0)
    for index = 1, count do build(index) end
    return neighbors
end

-- Open tour. `first` stays at the start when the player pinned a step.
-- cost(fromIndex, toIndex) uses 0 for the player. ready(index, seen) is precedence.
-- options.thorough keeps searching past the first local improvement. A log of
-- 40-80 steps is the normal case, and a dozen reversals stop well short of a short route.
function ns.TourOrder(count, cost, ready, first, options)
    if count < 1 then return {} end
    local thorough = type(options) == "table" and options.thorough or false
    local neighbors = type(options) == "table" and options.neighbors or nil
    local group = type(options) == "table" and options.group or nil
    local member
    if type(neighbors) == "table" then
        member = {}
        for from, list in pairs(neighbors) do
            if type(list) == "table" then
                local set = {}
                for _, to in ipairs(list) do set[to] = true end
                member[from] = set
            end
        end
    end
    local function linked(from, to)
        if not member then return true end
        local set = member[from]
        if not set then return true end
        return set[to] == true
    end
    local function nearest()
        local order, seen = {}, {}
        local from, start = 0, 1
        if first then
            order[1], seen[first], from, start = first, true, first, 2
        end
        for step = start, count do
            local best, bestCost
            local function consider(to, restricted)
                if seen[to] or not ready(to, seen) then return end
                if restricted and not linked(from, to) then return end
                local value = cost(from, to)
                if value ~= nil and (not best or value < bestCost or (value == bestCost and to < best)) then
                    best, bestCost = to, value
                end
            end
            if neighbors and neighbors[from] then
                for _, to in ipairs(neighbors[from]) do consider(to, true) end
            else
                for to = 1, count do consider(to, false) end
            end
            if not best and neighbors then
                for to = 1, count do consider(to, false) end
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
    if not first and count <= EXACT_LIMIT then
        order = exact(order) or order
        -- A handful of steps is already solved. Further passes cannot beat it.
        if thorough then return order or {} end
    end
    if not thorough then
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

    -- Relocate keeps a block in its own order, so a quest chain can move
    -- without turning the chain around. Reversal only tidies a short window.
    local locked = first and 1 or 0
    local function breathe()
        if coroutine.running() then coroutine.yield("pause") end
    end
    local function copied(list)
        local out = {}
        for index = 1, #list do out[index] = list[index] end
        return out
    end
    local function usable(list)
        return type(list) == "table" and #list == count and legal(list)
    end
    local function keep(best, candidate)
        if not usable(candidate) then return best end
        if not best or total(candidate) < total(best) then return copied(candidate) end
        return best
    end

    local preds = {}
    for node = 1, count do
        local list = {}
        for other = 1, count do
            if other ~= node then
                local seen = {}
                for at = 1, count do
                    if at ~= other then seen[at] = true end
                end
                if not ready(node, seen) then list[#list + 1] = other end
            end
        end
        preds[node] = list
    end

    local function insertion()
        local built, seen, placed = {}, {}, {}
        local function place(node, at)
            table.insert(built, at, node)
            seen[node] = true
            placed[node] = at
            for index = at, #built do placed[built[index]] = index end
        end
        if first then place(first, 1) end
        local guard = 0
        while #built < count and guard <= count do
            guard = guard + 1
            local bestNode, bestAt, bestDelta
            local function try(node, restricted)
                local earliest = locked + 1
                for _, pred in ipairs(preds[node]) do
                    local at = placed[pred]
                    if at and at + 1 > earliest then earliest = at + 1 end
                end
                local found = false
                for at = earliest, #built + 1 do
                    local prev = built[at - 1] or 0
                    local nxt = built[at]
                    if not restricted or (linked(prev, node) and (not nxt or linked(node, nxt))) then
                        found = true
                        local delta = legCost(prev, node)
                        if nxt then delta = delta + legCost(node, nxt) - legCost(prev, nxt) end
                        if not bestDelta or delta < bestDelta or (delta == bestDelta and node < bestNode) then
                            bestNode, bestAt, bestDelta = node, at, delta
                        end
                    end
                end
                return found
            end
            local pending = false
            for node = 1, count do
                if not seen[node] and ready(node, seen) then
                    pending = true
                    if neighbors and not try(node, true) then try(node, false) end
                    if not neighbors then try(node, false) end
                end
            end
            if bestNode then
                place(bestNode, bestAt)
            elseif pending or guard > 0 then
                for node = 1, count do
                    if not seen[node] then
                        place(node, #built + 1)
                        break
                    end
                end
            end
        end
        if not usable(built) then return nil end
        return built
    end

    local function zoneSweep()
        if type(group) ~= "table" then return nil end
        local built, seen = {}, {}
        local from = 0
        if first then
            built[1], seen[first], from = first, true, first
        end
        local guard = 0
        while #built < count and guard < count * 2 do
            guard = guard + 1
            local pool = {}
            for node = 1, count do
                if not seen[node] and ready(node, seen) then pool[#pool + 1] = node end
            end
            if #pool == 0 then
                for node = 1, count do
                    if not seen[node] then
                        built[#built + 1] = node
                        seen[node] = true
                        from = node
                        break
                    end
                end
            else
                local function cheapest(zone, restricted)
                    local pick, pickCost
                    for _, node in ipairs(pool) do
                        if not seen[node] and (zone == nil or group[node] == zone) and ready(node, seen) then
                            if not restricted or linked(from, node) then
                                local value = legCost(from, node)
                                if not pick or value < pickCost or (value == pickCost and node < pick) then
                                    pick, pickCost = node, value
                                end
                            end
                        end
                    end
                    return pick
                end
                local door = cheapest(nil, true) or cheapest(nil, false)
                if not door then break end
                local zone = group[door]
                local function take(restricted)
                    local pick = cheapest(zone, restricted)
                    if not pick then return false end
                    built[#built + 1] = pick
                    seen[pick] = true
                    from = pick
                    return true
                end
                if not take(true) and not take(false) then
                    built[#built + 1] = door
                    seen[door] = true
                    from = door
                else
                    while take(true) or take(false) do end
                end
            end
        end
        if not usable(built) then return nil end
        return built
    end

    local function shortReverse(list)
        local span = 5
        local bestGain, bestOrder
        local base = total(list)
        for i = locked + 1, #list - 1 do
            local last = i + span - 1
            if last > #list then last = #list end
            for j = i + 1, last do
                local before, head = list[i - 1] or 0, list[i]
                local tail, after = list[j], list[j + 1]
                if (not member or linked(before, tail)) and (not after or not member or linked(head, after)) then
                    local candidate = copied(list)
                    for at = i, j do candidate[at] = list[j - (at - i)] end
                    if legal(candidate) then
                        local gain = base - total(candidate)
                        if gain > (bestGain or 0) then bestGain, bestOrder = gain, candidate end
                    end
                end
            end
        end
        return bestOrder
    end

    local function relocate(list)
        local base = total(list)
        local bestGain, bestOrder
        for length = 1, 3 do
            for i = locked + 1, #list - length + 1 do
                if i % 12 == 0 then breathe() end
                local j = i + length - 1
                local shrunk = {}
                for index = 1, i - 1 do shrunk[#shrunk + 1] = list[index] end
                for index = j + 1, #list do shrunk[#shrunk + 1] = list[index] end
                local head, tail = list[i], list[j]
                local before = list[i - 1] or 0
                local after = list[j + 1]
                for at = locked + 1, #shrunk + 1 do
                    if at ~= i then
                        local left = at == 1 and 0 or shrunk[at - 1]
                        local right = shrunk[at]
                        local bridge = not after or not member or linked(before, after)
                        local enter = not member or linked(left, head)
                        local leave = not right or not member or linked(tail, right)
                        if bridge and enter and leave then
                            local candidate = {}
                            local cursor = 0
                            for index = 1, at - 1 do
                                cursor = cursor + 1
                                candidate[cursor] = shrunk[index]
                            end
                            for index = i, j do
                                cursor = cursor + 1
                                candidate[cursor] = list[index]
                            end
                            for index = at, #shrunk do
                                cursor = cursor + 1
                                candidate[cursor] = shrunk[index]
                            end
                            if legal(candidate) then
                                local gain = base - total(candidate)
                                if gain > (bestGain or 0) then bestGain, bestOrder = gain, candidate end
                            end
                        end
                    end
                end
            end
        end
        return bestOrder
    end

    local function polish(list)
        local current = copied(list)
        local moves = 0
        while current and moves < 28 do
            breathe()
            local improved = shortReverse(current) or relocate(current)
            if not improved then break end
            current = improved
            moves = moves + 1
        end
        return current
    end

    local function kick(list, salt)
        local current = copied(list)
        local moved = 0
        local guard = 0
        while moved < 3 and guard < count * 2 do
            guard = guard + 1
            local span = count - locked
            if span < 1 then break end
            local pos = locked + 1 + (salt * 13 + guard * 5) % span
            if pos > count then pos = count end
            local shrunk = {}
            for index = 1, count do
                if index ~= pos then shrunk[#shrunk + 1] = current[index] end
            end
            local room = #shrunk - locked
            if room < 1 then room = 1 end
            local dest = locked + 1 + (salt * 3 + pos * 7) % room
            if dest > #shrunk + 1 then dest = #shrunk + 1 end
            local node = current[pos]
            local candidate = {}
            local cursor = 0
            for index = 1, dest - 1 do
                cursor = cursor + 1
                candidate[cursor] = shrunk[index]
            end
            cursor = cursor + 1
            candidate[cursor] = node
            for index = dest, #shrunk do
                cursor = cursor + 1
                candidate[cursor] = shrunk[index]
            end
            if usable(candidate) then
                current = candidate
                moved = moved + 1
            end
        end
        return current
    end

    local best = keep(nil, order)
    breathe()
    best = keep(best, polish(order))
    local seeded = insertion()
    if seeded then best = keep(best, polish(seeded)) end
    breathe()
    local swept = zoneSweep()
    if swept then best = keep(best, polish(swept)) end
    local idle = 0
    for salt = 1, 8 do
        if idle >= 4 then break end
        breathe()
        local shaken = polish(kick(best or order, salt))
        local before = best and total(best) or math.huge
        best = keep(best, shaken)
        if best and total(best) < before then idle = 0 else idle = idle + 1 end
    end
    return best or order or {}
end

-- Shortest travel order that still turns a quest in after its objectives and
-- accepts a follow-up before that follow-up's own steps. Steps without a point
-- stay attached to their quest and do not pull the tour.
function ns.OrderStops(stops, _, player, cost, pinKey, thorough)
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

    local search
    if thorough and #geo > 1 then
        local group = {}
        for index, stop in ipairs(geo) do group[index] = stop.areaId or 0 end
        local neighbors
        if #geo > NEIGHBOR_CUTOFF and ns.TourNeighbors then
            local worlds, ranked = {}, true
            local function remember(index, spot)
                if not hasPoint(spot) or type(C_Map) ~= "table" or type(C_Map.GetWorldPosFromMapPos) ~= "function" then
                    ranked = false
                    return
                end
                if type(CreateVector2D) ~= "function" or type(ns.UiMap) ~= "function" or type(ns.MapFraction) ~= "function" then
                    ranked = false
                    return
                end
                local map = ns.UiMap(spot.areaId)
                local x, y = ns.MapFraction(spot.x), ns.MapFraction(spot.y)
                if type(map) ~= "number" or not x or not y then
                    ranked = false
                    return
                end
                local ok, continent, world = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(x, y))
                if not ok or type(continent) ~= "number" or type(world) ~= "table" or type(world.GetXY) ~= "function" then
                    ranked = false
                    return
                end
                local wx, wy = world:GetXY()
                if type(wx) ~= "number" or type(wy) ~= "number" then
                    ranked = false
                    return
                end
                worlds[index] = { map = continent, x = wx, y = wy }
            end
            remember(0, player)
            for index, stop in ipairs(geo) do
                if not ranked then break end
                remember(index, stop)
            end
            local function zoneOf(index)
                if index == 0 then return player and player.areaId or 0 end
                return group[index]
            end
            local function rank(from, to)
                if ranked then
                    local left, right = worlds[from], worlds[to]
                    if left and right and left.map == right.map then
                        local dx, dy = left.x - right.x, left.y - right.y
                        return dx * dx + dy * dy
                    end
                    return 1e12 + to
                end
                local left = from == 0 and player or geo[from]
                local right = geo[to]
                if type(left) == "table" and type(right) == "table"
                    and left.areaId and left.areaId == right.areaId
                    and type(left.x) == "number" and type(right.x) == "number" then
                    local dx, dy = left.x - right.x, left.y - right.y
                    return dx * dx + dy * dy
                end
                return FAR_ZONE + (type(right) == "table" and right.areaId or 0) * 1000 + to
            end
            neighbors = ns.TourNeighbors(#geo, zoneOf, rank)
        end
        search = { thorough = true, group = group, neighbors = neighbors }
    end

    local indexes = ns.TourOrder(#geo, indexCost, ready, first, search)
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
    ns.travelReady = true
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
    ns.travelReady = true
    if ns.Render then ns.Render(plan, ns.lastErr) end
    local db = ns.CharDB and ns.CharDB() or nil
    if db and db.navigating == true and ns.PushRoute then
        ns.PushRoute(plan, start, { plan = true })
    end
end

-- A few uncached Shortest Path estimates per frame. One cold estimate is a couple of
-- milliseconds, so the search stays inside a short frame budget and still finishes
-- a 40-80 step log in roughly ten to twenty seconds.
function ns.ScheduleTour(plan, player, pinKey)
    ns.tourEpoch = (ns.tourEpoch or 0) + 1
    local epoch = ns.tourEpoch
    ns.tourPending = false
    ns.travelReady = false
    local api = estimateApi()
    local steps = plan and plan.steps
    if not api or type(C_Timer) ~= "table" or type(C_Timer.After) ~= "function" then
        ns.travelReady = true
        return
    end
    if type(steps) ~= "table" then
        ns.travelReady = true
        return
    end
    local mappable = 0
    for _, stop in ipairs(steps) do
        if travelPoint(stop) then mappable = mappable + 1 end
    end
    if mappable < 1 then
        ns.travelReady = true
        return
    end

    local ids = {}
    for index, stop in ipairs(steps) do ids[stop] = index end
    local cache = {}
    -- Past this, new pairs are treated as unreachable so a huge log still returns
    -- the best complete tour found so far instead of running on.
    local ASK_CAP = 5000
    local asked = 0
    local function yieldingCost(fromStop, toStop)
        local key = (fromStop and ids[fromStop] or 0) .. ":" .. (ids[toStop] or 0)
        local cached = cache[key]
        if cached == nil then
            if asked >= ASK_CAP then
                cache[key] = UNREACHABLE
                return UNREACHABLE
            end
            asked = asked + 1
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
        local ordered = steps
        if mappable >= 2 then
            ordered = ns.OrderStops(steps, nil, player, yieldingCost, pinKey, true)
        end
        if type(ordered) ~= "table" then ordered = steps end
        ns.StampTravel(ordered, player, yieldingCost)
        return ordered
    end)

    local function step(value)
        if epoch ~= ns.tourEpoch then return end
        local frameStart = type(debugprofilestop) == "function" and debugprofilestop() or nil
        local asks = 0
        while epoch == ns.tourEpoch do
            local ok, tag, fromStop, toStop = coroutine.resume(worker, value)
            if epoch ~= ns.tourEpoch then return end
            if not ok then
                ns.tourPending = false
                ns.travelReady = true
                if ns.Render then ns.Render(plan, ns.lastErr) end
                return
            end
            if coroutine.status(worker) == "dead" then
                ns.tourPending = false
                ns.travelReady = true
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
            local seconds, reason = ask(fromStop, toStop)
            if seconds == nil and reason ~= "unreachable" then
                local function retry()
                    if epoch ~= ns.tourEpoch then return end
                    local again, why = ask(fromStop, toStop)
                    if again == nil and why ~= "unreachable" then
                        C_Timer.After(0.25, retry)
                        return
                    end
                    step(again or UNREACHABLE)
                end
                C_Timer.After(0.25, retry)
                return
            end
            value = seconds or UNREACHABLE
            asks = asks + 1
            local spent = frameStart and (debugprofilestop() - frameStart) or (asks * 3)
            -- One cold estimate is a few milliseconds. Stop this frame before it adds up.
            if asks >= 6 or spent >= 8 then
                C_Timer.After(0, function() step(value) end)
                return
            end
        end
    end

    ns.tourPending = true
    C_Timer.After(0, function() step(nil) end)
end
