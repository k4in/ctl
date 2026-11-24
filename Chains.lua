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
    local ids = {}
    for _, id in ipairs(back) do ids[#ids + 1] = id end
    ids[#ids + 1] = questId
    for _, id in ipairs(forward) do ids[#ids + 1] = id end
    return {
        index = #back + 1,
        total = total,
        branched = branched,
        nextId = forward[1],
        ids = ids,
    }
end

local function positionOf(ids, questId)
    for index, id in ipairs(ids) do
        if id == questId then return index end
    end
end

-- The included follow-ups are always a prefix of the chain, from the log quest
-- through chainThrough. Nil means every follow-up when the chain is on.
function ns.ChainCutoff(questId, chain)
    if type(chain) ~= "table" or type(chain.ids) ~= "table" then return questId end
    local ids = chain.ids
    local index = chain.index or positionOf(ids, questId) or 1
    if index < 1 or index > #ids then index = 1 end
    local db = ns.CharDB()
    local through = db.chainThrough and db.chainThrough[questId]
    if type(through) == "number" then
        local at = positionOf(ids, through)
        if at and at >= index then return ids[at] end
    end
    local chainOff = db.chainOff and db.chainOff[questId] == true
    if db.chain[questId] == false or (chainOff and db.chain[questId] ~= true) then
        return ids[index]
    end
    return ids[#ids]
end

function ns.ChainView(questId)
    local chain = ns.ChainInfo(questId)
    if not chain then return nil end
    local cutoff = ns.ChainCutoff(questId, chain)
    local cutoffPos = positionOf(chain.ids, cutoff) or chain.index
    local members = {}
    for index, id in ipairs(chain.ids) do
        local level = ns.QuestNumber(id, "questLevel")
        members[#members + 1] = {
            id = id,
            index = index,
            total = chain.total,
            name = ns.QuestName(id) or ("Quest " .. id),
            level = (type(level) == "number" and level > 0) and level or nil,
            dungeon = ns.IsDungeonQuest(id) and true or false,
            role = index < chain.index and "past" or (index == chain.index and "current" or "followup"),
            included = index >= chain.index and index <= cutoffPos,
        }
    end
    return {
        index = chain.index,
        total = chain.total,
        branched = chain.branched,
        cutoff = cutoff,
        label = ns.ChainLabel(chain),
        members = members,
    }
end

-- Click a later follow-up to include the chain through it.
-- Click an included follow-up to drop that quest and every quest after it.
function ns.AdjustChain(questId, clickedId)
    local chain = ns.ChainInfo(questId)
    if not chain or type(clickedId) ~= "number" then return false end
    local clickPos = positionOf(chain.ids, clickedId)
    if not clickPos or clickPos <= chain.index then return false end
    local cutoffPos = positionOf(chain.ids, ns.ChainCutoff(questId, chain)) or chain.index
    local newPos = clickPos > cutoffPos and clickPos or (clickPos - 1)
    if newPos < chain.index then newPos = chain.index end
    local through = chain.ids[newPos]
    local db = ns.CharDB()
    if type(db.chainThrough) ~= "table" then db.chainThrough = {} end
    db.chainThrough[questId] = through
    db.chain[questId] = through ~= questId
    db.chainOff[questId] = nil
    db.decided[questId] = true
    return true
end

function ns.AllFollowupsIncluded(questId)
    local chain = ns.ChainInfo(questId)
    if not chain or type(chain.ids) ~= "table" then return false end
    local index = chain.index or positionOf(chain.ids, questId) or 1
    local last = chain.ids[#chain.ids]
    if not last or index >= #chain.ids then return false end
    return ns.ChainCutoff(questId, chain) == last
end

-- Turns every later quest on, or off when they are already all on.
-- The log quest itself stays on its own checkbox.
function ns.ToggleChainFollowups(questId)
    local chain = ns.ChainInfo(questId)
    if type(questId) ~= "number" or not chain or type(chain.ids) ~= "table" then return false end
    local index = chain.index or positionOf(chain.ids, questId) or 1
    if index >= #chain.ids then return false end
    if type(ns.SetChainFollowups) ~= "function" then return false end
    ns.SetChainFollowups(questId, not ns.AllFollowupsIncluded(questId))
    return true
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
