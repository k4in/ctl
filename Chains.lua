local _, ns = ...

local function absId(value)
    if type(value) ~= "number" or value == 0 then return nil end
    if value < 0 then return -value end
    return value
end

local function isBreadcrumb(previous, current)
    return ns.QuestNumber(previous, "breadcrumbForQuestId") == current
end

local function idList(questId, field)
    local ids = {}
    for _, raw in ipairs(ns.QuestList(questId, field)) do
        local id = absId(raw)
        if id and ns.QuestExists(id) then ids[#ids + 1] = id end
    end
    return ids
end

-- One parent, so a linear label stays possible. Several prerequisites mark a branch.
local function previousOf(questId)
    local parent = absId(ns.QuestNumber(questId, "parentQuest"))
    if parent and parent ~= questId and ns.QuestExists(parent) and not isBreadcrumb(parent, questId) then
        return parent, false
    end

    local singles = {}
    for _, id in ipairs(idList(questId, "preQuestSingle")) do
        if not isBreadcrumb(id, questId) then singles[#singles + 1] = id end
    end
    if #singles == 0 then return nil, false end
    if #singles == 1 then return singles[1], false end

    table.sort(singles)
    for _, id in ipairs(singles) do
        if ns.IsQuestDone(id) then return id, true end
    end
    return singles[1], true
end

local function nextOf(questId)
    local nextId = absId(ns.QuestNumber(questId, "nextQuestInChain"))
    local children = idList(questId, "childQuests")
    if nextId and ns.QuestExists(nextId) then
        return nextId, #children > 1
    end
    if #children == 1 then return children[1], false end
    if #children > 1 then return nil, true end
    return nil, false
end

function ns.ChainInfo(questId)
    if not ns.QuestExists(questId) then return nil end

    local seen = { [questId] = true }
    local back, branched = {}, false
    local cursor = questId
    for _ = 1, 40 do
        local previous, branch = previousOf(cursor)
        if branch then branched = true end
        if not previous or seen[previous] then break end
        seen[previous] = true
        table.insert(back, 1, previous)
        cursor = previous
    end

    local forward = {}
    cursor = questId
    for _ = 1, 40 do
        local nextId, branch = nextOf(cursor)
        if branch then branched = true end
        if not nextId or seen[nextId] then break end
        seen[nextId] = true
        forward[#forward + 1] = nextId
        cursor = nextId
    end

    local total = #back + 1 + #forward
    if total < 2 then return nil end
    return {
        index = #back + 1,
        total = total,
        branched = branched,
        nextId = forward[1],
    }
end

function ns.ChainLabel(chain)
    if not chain then return nil end
    local label = string.format("Chain %d/%d", chain.index, chain.total)
    if chain.branched then label = label .. " · Branch" end
    return label
end

function ns.FollowupBriefs(questId)
    local briefs = {}
    if type(questId) ~= "number" or not ns.QuestExists(questId) then return briefs end
    local seen = { [questId] = true }

    local function push(id)
        if #briefs >= 6 then return false end
        if type(id) ~= "number" or seen[id] or not ns.QuestExists(id) then return false end
        seen[id] = true
        local zone = "No zone"
        if ns.ObjectiveZoneLabel then
            local label = ns.ObjectiveZoneLabel(id)
            if type(label) == "string" and label ~= "" then zone = label end
        end
        briefs[#briefs + 1] = {
            id = id,
            name = ns.QuestName(id) or ("Quest " .. id),
            zone = zone,
        }
        return true
    end

    local cursor = questId
    for _ = 1, 6 do
        if #briefs >= 6 then break end
        local nextId, branched = nextOf(cursor)
        if nextId then
            if not push(nextId) then break end
            cursor = nextId
        elseif branched then
            for _, child in ipairs(idList(cursor, "childQuests")) do
                push(child)
            end
            break
        else
            break
        end
    end
    return briefs
end

function ns.FollowupId(chain, inLog)
    local nextId = chain and chain.nextId
    if not nextId or (inLog and inLog[nextId]) then return nil end
    if ns.IsQuestDone(nextId) or not ns.PlayerCanTake(nextId) then return nil end

    for _, other in ipairs(ns.QuestList(nextId, "exclusiveTo")) do
        local id = absId(other)
        if id and ((inLog and inLog[id]) or ns.IsQuestDone(id)) then return nil end
    end
    return nextId
end
