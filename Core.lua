local addonName, ns = ...

ns.addonName = addonName
ns.TITLE = "Clear the Log"
ns.GUIDE_LIMIT = 10
ns.ROUTE_STEPS = 5

-- Mainline hands addons opaque secret values. Comparing or storing them as
-- table keys throws. Anything secret becomes nil and the caller skips it.
function ns.Plain(value)
    if issecretvalue and issecretvalue(value) then return nil end
    return value
end

function ns.Band(a, b)
    if type(a) ~= "number" or type(b) ~= "number" then return 0 end
    local result, bitValue, guard = 0, 1, 0
    while (a > 0 or b > 0) and guard < 54 do
        if a % 2 >= 1 and b % 2 >= 1 then result = result + bitValue end
        a = math.floor(a / 2)
        b = math.floor(b / 2)
        bitValue = bitValue * 2
        guard = guard + 1
    end
    return result
end

function ns.Say(message)
    print("|cffd4b44aClear the Log:|r " .. tostring(message))
end

-- How many levels below the player a quest stays green. The client knows the
-- real range; 5 is the low-level classic value when no API answers.
function ns.GreenRange()
    local function call(fn, arg)
        if type(fn) ~= "function" then return nil end
        local ok, value = pcall(fn, arg)
        if not ok then return nil end
        value = ns.Plain(value)
        if type(value) == "number" and value >= 0 then return value end
    end
    local questLog = C_QuestLog
    return call(questLog and questLog.GetTrivialRange)
        or call(UnitQuestTrivialLevelRange, "player")
        or call(GetQuestGreenRange)
        or 5
end

-- Standard quest colors from the gap to the player: red, orange, yellow, green, gray.
function ns.LevelTone(level)
    if type(level) ~= "number" or level <= 0 then return nil end
    local player
    if type(UnitLevel) == "function" then
        local ok, value = pcall(UnitLevel, "player")
        if ok then player = ns.Plain(value) end
    end
    if type(player) ~= "number" or player <= 0 then return 1, 0.82, 0 end
    local diff = level - player
    if diff >= 5 then return 1, 0.10, 0.10 end
    if diff >= 3 then return 1, 0.50, 0.25 end
    if diff >= -2 then return 1, 0.82, 0 end
    if -diff <= ns.GreenRange() then return 0.25, 0.75, 0.25 end
    return 0.50, 0.50, 0.50
end

function ns.CharDB()
    if not ns.ready then
        return {
            tracked = {}, chain = {}, decided = {},
            ignored = {}, selected = {}, chainOff = {}, chainThrough = {}, skipped = {},
            refreshAccept = true, refreshTurnin = true, refreshObjective = true,
            autoTrack = true,
            navigating = false, guideShown = false,
        }
    end
    local db = ClearTheLogCharDB
    if type(db) ~= "table" then
        db = {}
        ClearTheLogCharDB = db
    end
    if type(db.tracked) ~= "table" then db.tracked = {} end
    if type(db.chain) ~= "table" then db.chain = {} end
    if type(db.decided) ~= "table" then db.decided = {} end
    if type(db.ignored) ~= "table" then db.ignored = {} end
    if type(db.selected) ~= "table" then db.selected = {} end
    if type(db.chainOff) ~= "table" then db.chainOff = {} end
    if type(db.chainThrough) ~= "table" then db.chainThrough = {} end
    if type(db.skipped) ~= "table" then db.skipped = {} end
    if type(db.handoff) ~= "table" then db.handoff = {} end
    if db.legacyMode == nil and not db.migrated and (db.mode == "ignore" or db.mode == "select") then
        db.legacyMode = db.mode
    end
    db.migrated = true
    if db.router ~= "tomtom" and db.router ~= "spf" then db.router = nil end
    -- A saved router used to mean navigation was on. Remember that once.
    if db.navigating == nil then db.navigating = db.router ~= nil end
    if db.navigating ~= true or not db.router then db.navigating = false end
    if db.guideShown ~= true then db.guideShown = false end
    if db.refreshAccept == nil then db.refreshAccept = true end
    if db.refreshTurnin == nil then db.refreshTurnin = true end
    if db.refreshObjective == nil then db.refreshObjective = true end
    if db.autoTrack == nil then db.autoTrack = true end
    if db.autoTurnIn ~= true then db.autoTurnIn = false end
    if db.autoAcceptQuest ~= true then db.autoAcceptQuest = false end
    db.autoChain = nil
    return db
end

function ns.IsIncluded(questId)
    local value = ns.CharDB().tracked[questId]
    if value == nil then return true end
    return value == true
end

function ns.ChainEnabled(questId)
    if type(ns.ChainCutoff) == "function" and type(ns.ChainInfo) == "function" then
        local chain = ns.ChainInfo(questId)
        if chain then return ns.ChainCutoff(questId, chain) ~= questId end
    end
    local db = ns.CharDB()
    if db.chain[questId] == nil then return db.chainOff[questId] ~= true end
    return db.chain[questId] == true
end

-- enabled keeps every follow-up. Otherwise the chain stops on the log quest.
function ns.SetChainFollowups(questId, enabled)
    if type(questId) ~= "number" then return end
    local db = ns.CharDB()
    if type(db.chainThrough) ~= "table" then db.chainThrough = {} end
    db.decided[questId] = true
    db.chainOff[questId] = nil
    if enabled then
        db.chain[questId] = true
        db.chainThrough[questId] = nil
        return
    end
    db.chain[questId] = false
    local through = questId
    if type(ns.ChainInfo) == "function" then
        local chain = ns.ChainInfo(questId)
        if chain and type(chain.ids) == "table" and chain.ids[chain.index] then
            through = chain.ids[chain.index]
        end
    end
    db.chainThrough[questId] = through
end

function ns.SetIncluded(questId, included)
    local db = ns.CharDB()
    local on = included and true or false
    db.tracked[questId] = on
    db.decided[questId] = true
end

-- Drops a chain that is only waiting to be accepted, from the guide and the list.
function ns.DropQuestLine(questId)
    if not ns.ready or type(questId) ~= "number" or questId <= 0 then return end
    local db = ns.CharDB()
    local ids = {}
    local function add(id)
        if type(id) == "number" and id > 0 then ids[id] = true end
    end
    add(questId)
    if type(ns.ChainInfo) == "function" then
        local chain = ns.ChainInfo(questId)
        if chain and type(chain.ids) == "table" then
            for _, id in ipairs(chain.ids) do add(id) end
        end
    end
    if type(db.handoff) == "table" then
        for acceptId, fromId in pairs(db.handoff) do
            if ids[acceptId] or ids[fromId] then
                add(acceptId)
                db.handoff[acceptId] = nil
            end
        end
    end
    for id in pairs(ids) do
        db.tracked[id] = false
        db.decided[id] = true
        if type(db.chain) == "table" then db.chain[id] = nil end
        if type(db.chainThrough) == "table" then db.chainThrough[id] = nil end
        if type(db.chainOff) == "table" then db.chainOff[id] = nil end
    end
    if type(db.skipped) == "table" then
        for key in pairs(db.skipped) do
            local id = tonumber(tostring(key):match("^(%d+)"))
            if ids[id] then db.skipped[key] = nil end
        end
    end
    ns.routeFrom = nil
    ns.routeOrigin = nil
    if ns.RequestRefresh then ns.RequestRefresh("manual") end
end

function ns.SetAllQuests(included)
    local quests = ns.lastPlan and ns.lastPlan.quests
    if type(quests) ~= "table" then return end
    local on = included and true or false
    for _, quest in ipairs(quests) do
        local id = type(quest) == "table" and quest.id or nil
        if type(id) == "number" then ns.SetIncluded(id, on) end
    end
    if ns.RequestRefresh then ns.RequestRefresh("manual") end
end

function ns.SetChainEnabled(questId, enabled)
    local db = ns.CharDB()
    db.chain[questId] = enabled and true or false
    db.decided[questId] = true
end

-- Quests already in the log keep their choice. Only an accept this session uses the auto options.
function ns.DecideQuest(questId)
    local db = ns.CharDB()
    local fresh = ns.fresh and ns.fresh[questId]
    if fresh then
        if not db.decided[questId] then
            db.tracked[questId] = db.autoTrack and true or false
            db.chain[questId] = false
            db.decided[questId] = true
        end
        ns.fresh[questId] = nil
        return
    end
    if db.decided[questId] then return end
    if db.legacyMode == "select" then
        db.tracked[questId] = db.selected[questId] == true
    elseif db.legacyMode == "ignore" then
        db.tracked[questId] = db.ignored[questId] ~= true
    else
        db.tracked[questId] = true
    end
    db.chain[questId] = not db.chainOff[questId]
    db.decided[questId] = true
end

function ns.IsQuestDone(questId)
    if type(questId) ~= "number" or not C_QuestLog or not C_QuestLog.IsQuestFlaggedCompleted then
        return false
    end
    local ok, result = pcall(C_QuestLog.IsQuestFlaggedCompleted, questId)
    if not ok then return false end
    return ns.Plain(result) == true
end

local function readLog()
    local rows = {}
    if not C_QuestLog or not C_QuestLog.GetNumQuestLogEntries or not C_QuestLog.GetInfo then
        return rows, "Quest log API is missing."
    end

    local ok, count = pcall(C_QuestLog.GetNumQuestLogEntries)
    count = ok and ns.Plain(count) or nil
    if type(count) ~= "number" then
        return nil, "The quest log cannot be read right now."
    end

    local zoneTitle
    for index = 1, count do
        local infoOk, info = pcall(C_QuestLog.GetInfo, index)
        if infoOk and type(info) == "table" then
            local questId = ns.Plain(info.questID)
            local isHeader = ns.Plain(info.isHeader)
            local isHidden = ns.Plain(info.isHidden)
            if isHeader then
                local headerTitle = ns.Plain(info.title)
                if type(headerTitle) == "string" and headerTitle ~= "" then
                    zoneTitle = headerTitle
                end
            elseif not isHidden and type(questId) == "number" and questId > 0 then
                local title = ns.Plain(info.title)
                local level = ns.Plain(info.level)
                local complete = false
                if C_QuestLog.IsComplete then
                    local completeOk, value = pcall(C_QuestLog.IsComplete, questId)
                    if completeOk then complete = ns.Plain(value) == true end
                end

                local objectives = {}
                local secret = false
                if C_QuestLog.GetQuestObjectives then
                    local objOk, listed = pcall(C_QuestLog.GetQuestObjectives, questId)
                    if objOk and type(listed) == "table" then
                        for _, objective in ipairs(listed) do
                            if type(objective) == "table" then
                                local text = ns.Plain(objective.text)
                                local finished = ns.Plain(objective.finished)
                                if finished == nil then finished = ns.Plain(objective.completed) end
                                local got = ns.Plain(objective.numFulfilled)
                                local need = ns.Plain(objective.numRequired)
                                if text == nil and finished == nil and got == nil and need == nil then
                                    secret = true
                                else
                                    objectives[#objectives + 1] = {
                                        text = text,
                                        finished = finished and true or false,
                                        numFulfilled = type(got) == "number" and got or nil,
                                        numRequired = type(need) == "number" and need or nil,
                                    }
                                end
                            end
                        end
                    end
                end

                rows[#rows + 1] = {
                    id = questId,
                    title = title,
                    level = type(level) == "number" and level or nil,
                    complete = complete,
                    objectives = objectives,
                    secret = secret,
                    zone = zoneTitle,
                }
            end
        end
    end

    return rows
end

function ns.ReadLog()
    return readLog()
end

local function pruneSaved(rows)
    if type(rows) ~= "table" then return end
    local live = {}
    for _, row in ipairs(rows) do live[row.id] = true end
    local db = ns.CharDB()
    for _, bucket in ipairs({
        db.tracked, db.chain, db.decided, db.ignored, db.selected, db.chainOff, db.chainThrough,
    }) do
        for questId in pairs(bucket) do
            if not live[questId] then bucket[questId] = nil end
        end
    end
end

-- Objective text often arrives a moment after the quest. An empty read must not
-- look like progress, or login would push a route.
local snapshot = {}

local function takeSnapshot(rows)
    local progress = false
    local seen = {}
    for _, row in ipairs(rows) do
        seen[row.id] = true
        if not row.secret then
            local finished = 0
            for _, objective in ipairs(row.objectives) do
                if objective.finished then finished = finished + 1 end
            end
            local prev = snapshot[row.id]
            local empty = #row.objectives == 0 and not row.complete
            if not (empty and prev) then
                local known = #row.objectives > 0 or row.complete or (prev and prev.known)
                if prev and prev.known and (finished > prev.finished or (row.complete and not prev.complete)) then
                    progress = true
                end
                snapshot[row.id] = {
                    finished = finished,
                    complete = row.complete and true or false,
                    known = known and true or false,
                }
            end
        end
    end
    for questId in pairs(snapshot) do
        if not seen[questId] then snapshot[questId] = nil end
    end
    return progress
end

local pending = {}
local IMMEDIATE = {
    manual = true, router = true, step = true, open = true, draw = true,
    plan = true, skip = true,
}

local function combatLocked()
    return InCombatLockdown and InCombatLockdown()
end

local function defer(reasons)
    local deferred = ns.deferred
    if type(deferred) ~= "table" then deferred = {} end
    for key, value in pairs(reasons) do deferred[key] = value end
    ns.deferred = deferred
end

function ns.RequestRefresh(reason)
    if reason and IMMEDIATE[reason] then
        ns.Refresh({ [reason] = true })
        return
    end
    if reason then pending[reason] = true end
    if ns.refreshPending then return end
    ns.refreshPending = true
    C_Timer.After(0.2, function()
        ns.refreshPending = false
        local reasons = pending
        pending = {}
        ns.Refresh(reasons)
    end)
end

function ns.RouteFrom(index)
    ns.routeFrom = index
    ns.RequestRefresh("step")
end

function ns.SkipStep(index)
    if not ns.ready then return end
    local plan = ns.lastPlan
    local steps = plan and plan.steps
    local stop = steps and steps[index]
    if not stop or stop.skipped or not ns.StepKey then return end
    if combatLocked() then
        ns.CharDB().skipped[ns.StepKey(stop)] = true
        ns.pendingSkip = index
        ns.routeFrom = nil
        ns.RequestRefresh("skip")
        return
    end
    ns.CharDB().skipped[ns.StepKey(stop)] = true
    table.remove(steps, index)
    stop.skipped = true
    steps[#steps + 1] = stop
    local start = ns.windowStart or 1
    if type(start) ~= "number" or start < 1 then start = 1 end
    if start > index then start = start - 1 end
    if #steps > 0 and start > #steps then start = #steps end
    ns.windowStart = start
    ns.routeFrom = nil
    if ns.PushRoute then ns.PushRoute(plan, start, { skip = true }) end
    if ns.Render then ns.Render(plan, ns.lastErr) end
end

function ns.UndoSkip(index)
    if not ns.ready then return end
    local plan = ns.lastPlan
    local stop = plan and plan.steps and plan.steps[index]
    if not stop or not ns.StepKey then return end
    ns.CharDB().skipped[ns.StepKey(stop)] = nil
    ns.routeFrom = nil
    ns.RequestRefresh("plan")
end

function ns.RefreshPlan()
    if not ns.ready then return end
    ns.routeFrom = nil
    ns.routeOrigin = nil
    ns.RequestRefresh("plan")
end

function ns.ToggleNavigation()
    if not ns.ready then return false end
    local db = ns.CharDB()
    if db.router ~= "tomtom" and db.router ~= "spf" then return false end
    db.navigating = not db.navigating
    ns.routeFrom = nil
    ns.RequestRefresh("router")
    return true
end

function ns.RestoreGuide()
    if not ns.ready or ns.CharDB().guideShown ~= true then return end
    ns.guideIntent = true
    if type(ns.ShowGuide) == "function" then ns.ShowGuide() end
end

function ns.NoteGuideShown()
    ns.guideIntent = true
    if ns.ready then ns.CharDB().guideShown = true end
end

-- Loading screens and logout hide the frame without the player closing it.
function ns.NoteGuideHidden()
    if ns.loggingOut or ns.worldHidden or not ns.worldReady then return end
    ns.guideIntent = false
    if ns.ready then ns.CharDB().guideShown = false end
end

function ns.SaveGuideState()
    ns.loggingOut = true
    if not ns.ready then return end
    local shown = ns.guideIntent == true
    if ns.guide and type(ns.guide.IsShown) == "function" and ns.guide:IsShown() then
        shown = true
    end
    ns.CharDB().guideShown = shown and true or false
end

function ns.RecalculateFromStep(index)
    if not ns.ready or not ns.StepKey then return end
    local stop = ns.lastPlan and ns.lastPlan.steps and ns.lastPlan.steps[index]
    if not stop then return end
    local key = ns.StepKey(stop)
    ns.CharDB().skipped[key] = nil
    ns.routeOrigin = {
        key = key,
        areaId = stop.areaId,
        x = stop.x,
        y = stop.y,
    }
    ns.routeFrom = nil
    ns.RequestRefresh("plan")
end

function ns.OpenQuestLog(questId)
    if type(questId) ~= "number" or questId <= 0 then return end
    if InCombatLockdown and InCombatLockdown() then
        ns.Say("The quest log cannot be opened in combat.")
        return
    end
    if C_QuestLog and type(C_QuestLog.SetSelectedQuest) == "function" then
        pcall(C_QuestLog.SetSelectedQuest, questId)
    end
    if QuestUtil and type(QuestUtil.OpenQuestDetails) == "function" then
        local ok = pcall(QuestUtil.OpenQuestDetails, questId)
        if ok then return end
    end
    local frame = QuestLogFrame or QuestLogExFrame
    if frame and ShowUIPanel then
        pcall(ShowUIPanel, frame)
    end
end

local function pruneSkips(rows, plan)
    local skipped = ns.CharDB().skipped
    if type(skipped) ~= "table" then return end
    local live = {}
    for _, row in ipairs(rows or {}) do
        if type(row.id) == "number" then live[row.id] = true end
    end
    for _, stop in ipairs(plan and plan.steps or {}) do
        if type(stop.questId) == "number" then live[stop.questId] = true end
    end
    for key in pairs(skipped) do
        local questId = tonumber(tostring(key):match("^(%d+)"))
        if not questId or not live[questId] then skipped[key] = nil end
    end
end

local function questInPlan(plan, questId)
    local steps = plan and plan.steps
    if type(steps) ~= "table" or type(questId) ~= "number" then return false end
    for index = 1, #steps do
        if steps[index].questId == questId then return true end
    end
    return false
end

local function eachAccepted(accepts, fn)
    if type(accepts) ~= "table" then return end
    for questId, on in pairs(accepts) do
        if on and type(questId) == "number" and questId > 0 then fn(questId) end
    end
end

-- A follow-up that was already routed keeps that chain when it enters the log.
local function keepPlannedChain(questId, plan)
    local db = ns.CharDB()
    db.tracked[questId] = true
    db.decided[questId] = true
    if type(ns.ChainInfo) ~= "function" then return end
    local chain = ns.ChainInfo(questId)
    if type(chain) ~= "table" or type(chain.ids) ~= "table" then return end
    local indexOf = {}
    for index, id in ipairs(chain.ids) do indexOf[id] = index end
    local home = chain.index or indexOf[questId] or 1
    local furthest = home
    local throughId = chain.ids[home]
    for _, stop in ipairs(plan and plan.steps or {}) do
        local at = indexOf[stop.questId]
        if at and at > furthest then
            furthest = at
            throughId = stop.questId
        end
    end
    if type(db.chainThrough) ~= "table" then db.chainThrough = {} end
    db.chainOff[questId] = nil
    if furthest >= #chain.ids then
        db.chain[questId] = true
        db.chainThrough[questId] = nil
    elseif furthest > home then
        db.chain[questId] = true
        db.chainThrough[questId] = throughId
    else
        db.chain[questId] = false
        db.chainThrough[questId] = questId
    end
end

local function rowsById(rows)
    local byId = {}
    for _, row in ipairs(rows) do
        if type(row.id) == "number" then byId[row.id] = row end
    end
    return byId
end

local function applyPendingSkip(plan)
    local index = ns.pendingSkip
    ns.pendingSkip = nil
    local steps = plan and plan.steps
    if type(index) ~= "number" or type(steps) ~= "table" or not ns.StepKey then return end
    local stop = steps[index]
    if not stop or not ns.CharDB().skipped[ns.StepKey(stop)] then return end
    stop.skipped = true
    table.remove(steps, index)
    steps[#steps + 1] = stop
    local start = ns.windowStart or 1
    if type(start) ~= "number" or start < 1 then start = 1 end
    if start > index then start = start - 1 end
    if #steps > 0 and start > #steps then start = #steps end
    if start < 1 then start = 1 end
    ns.windowStart = start
end

-- Finished steps at the front of the window drop away. Later finished steps wait.
local function catchUp(plan, rows)
    if type(ns.SyncStop) ~= "function" then return false end
    local steps = plan and plan.steps or {}
    local byId = rowsById(rows)
    for index = 1, #steps do
        ns.SyncStop(steps[index], byId[steps[index].questId], byId)
    end
    local start = ns.windowStart or 1
    if type(start) ~= "number" or start < 1 then start = 1 end
    local before = start
    while start <= #steps do
        local stop = steps[start]
        if stop.skipped then break end
        if not ns.SyncStop(stop, byId[stop.questId], byId) then break end
        start = start + 1
    end
    ns.windowStart = start
    return start ~= before
end

local function handoffParent(questId)
    local handoff = ns.CharDB().handoff
    if type(handoff) ~= "table" or type(questId) ~= "number" then return false end
    for _, fromId in pairs(handoff) do
        if fromId == questId then return true end
    end
    return false
end

-- Drop the quest that was reserved from this one, and anything reserved from that.
local function dropHandoffFrom(questId)
    local handoff = ns.CharDB().handoff
    if type(handoff) ~= "table" then return end
    local queue = { questId }
    local index = 1
    while queue[index] do
        local id = queue[index]
        index = index + 1
        local children = {}
        for acceptId, fromId in pairs(handoff) do
            if fromId == id then children[#children + 1] = acceptId end
        end
        for _, acceptId in ipairs(children) do
            handoff[acceptId] = nil
            queue[#queue + 1] = acceptId
        end
    end
end

-- A removed quest that still owes a planned follow-up is a turn-in, not an abandon.
local function classifyRemovals(reasons)
    local removed = ns.removedIds
    ns.removedIds = nil
    if type(removed) ~= "table" then return end
    local steps = ns.lastPlan and ns.lastPlan.steps
    local current = steps and steps[ns.windowStart or 1]
    local abandon = false
    local handoffTurnin = false
    for questId in pairs(removed) do
        local prev = snapshot[questId]
        local ready = prev and prev.complete
        local onTurnin = current and current.kind == "turnin" and current.questId == questId and current.acceptId
        if handoffParent(questId) and (reasons.turnin or ready or onTurnin) then
            handoffTurnin = true
        else
            abandon = true
            dropHandoffFrom(questId)
        end
    end
    if reasons.removed and not reasons.turnin then
        if abandon then reasons.abandon = true end
        if handoffTurnin and not abandon then reasons.turnin = true end
    end
end

local function rememberHandoffs(plan, rows)
    local db = ns.CharDB()
    local live = {}
    for _, row in ipairs(rows or {}) do
        if type(row.id) == "number" then live[row.id] = true end
    end
    local found = {}
    for _, stop in ipairs(plan and plan.steps or {}) do
        if stop.kind == "turnin" and type(stop.acceptId) == "number" and not live[stop.acceptId] then
            found[stop.acceptId] = stop.questId
        elseif stop.kind == "accept" and type(stop.questId) == "number" and not live[stop.questId]
            and not found[stop.questId] then
            local fromId = stop.afterTurnin
            if type(fromId) ~= "number" or fromId <= 0 then fromId = stop.questId end
            found[stop.questId] = fromId
        end
    end
    local previous = db.handoff
    local handoff = {}
    for acceptId, fromId in pairs(found) do
        handoff[acceptId] = fromId
    end
    if type(previous) == "table" then
        for acceptId, fromId in pairs(previous) do
            if not live[acceptId] and not live[fromId] and not handoff[acceptId]
                and (not ns.IsIncluded or ns.IsIncluded(acceptId)) then
                handoff[acceptId] = fromId
            end
        end
    end
    db.handoff = handoff
end

-- Login, the refresh button, shift-click, membership edits, an abandoned quest,
-- and a brand-new auto-added quest build a new order. A follow-up that is
-- already a step never does, and neither does finishing a step.
local function needsRebuild(reasons, accepts, rows)
    if reasons.login or reasons.plan or reasons.manual or reasons.abandon then
        return true
    end
    if reasons.accept and ns.CharDB().autoTrack == true then
        local live = rowsById(rows)
        local rebuild = false
        eachAccepted(accepts, function(questId)
            if live[questId] and not questInPlan(ns.lastPlan, questId) then rebuild = true end
        end)
        if rebuild then return true end
    end
    if not ns.lastPlan then return true end
    return false
end

function ns.Refresh(reasons)
    if not ns.ready then return end
    reasons = reasons or {}
    if combatLocked() then
        defer(reasons)
        return
    end

    local routeFrom = ns.routeFrom
    ns.routeFrom = nil
    local origin = ns.routeOrigin
    ns.routeOrigin = nil

    local rows, err = readLog()
    if not rows then
        if reasons.step then ns.routeFrom = routeFrom end
        if origin then ns.routeOrigin = origin end
        ns.lastPlan, ns.lastErr = nil, err
        if ns.Render then ns.Render(nil, err) end
        return
    end

    -- The accept event can land before the quest is in the log. The log refresh
    -- that first sees it still counts, so auto-add is not lost on the way.
    local accepts = nil
    if type(ns.fresh) == "table" then
        for _, row in ipairs(rows) do
            if ns.fresh[row.id] then
                reasons.accept = true
                if type(accepts) ~= "table" then accepts = {} end
                accepts[row.id] = true
            end
        end
    end
    if reasons.accept and type(ns.pendingAccepts) == "table" then
        if type(accepts) ~= "table" then accepts = {} end
        for questId, on in pairs(ns.pendingAccepts) do
            if on and type(questId) == "number" then accepts[questId] = true end
        end
        ns.pendingAccepts = nil
    end

    pruneSaved(rows)
    for _, row in ipairs(rows) do ns.DecideQuest(row.id) end
    classifyRemovals(reasons)
    if takeSnapshot(rows) then reasons.objective = true end
    if reasons.removed and not reasons.turnin and not reasons.abandon then reasons.abandon = true end
    eachAccepted(accepts, function(questId)
        if questInPlan(ns.lastPlan, questId) then keepPlannedChain(questId, ns.lastPlan) end
    end)

    local rebuild = needsRebuild(reasons, accepts, rows)
    if rebuild then
        ns.pendingSkip = nil
        reasons.rebuild = true
        local player = ns.PlayerLocation()
        if reasons.plan and type(origin) == "table" and type(origin.areaId) == "number" and origin.areaId > 0 then
            player = {
                areaId = origin.areaId,
                x = origin.x,
                y = origin.y,
                zoneName = ns.ZoneName(origin.areaId),
                continent = ns.ContinentOfArea(origin.areaId),
            }
        end
        local plan = ns.BuildPlan(rows, player)
        if reasons.plan and type(origin) == "table" and origin.key and ns.PromoteStep then
            ns.PromoteStep(plan.steps, origin.key)
        end
        pruneSkips(rows, plan)
        rememberHandoffs(plan, rows)
        ns.lastPlan, ns.lastErr = plan, err
        ns.windowStart = 1
        local first = plan.steps and plan.steps[1]
        local giver = first and ns.AcceptTarget and ns.AcceptTarget(first)
        ns.acceptRouted = (type(giver) == "table" and ns.HasMapPoint and ns.HasMapPoint(giver)) and true or nil
        if ns.ShouldPushRoute and ns.ShouldPushRoute(reasons) and ns.PushRoute then
            ns.PushRoute(plan, 1, reasons)
        end
        if ns.PaintOptions then ns.PaintOptions() end
        if ns.Render then ns.Render(plan, err) end
        return
    end

    local plan = ns.lastPlan
    if ns.QuestView then
        plan.quests = ns.QuestView(rows)
        if ns.WithPendingQuests then
            plan.quests = ns.WithPendingQuests(plan.quests, rows, plan.steps)
        end
    end
    rememberHandoffs(plan, rows)
    ns.lastErr = err
    if reasons.step and type(routeFrom) == "number" and routeFrom >= 1 then
        ns.windowStart = routeFrom
    end
    if reasons.skip then applyPendingSkip(plan) end
    if catchUp(plan, rows) then reasons.advance = true end
    local current = plan and plan.steps and plan.steps[ns.windowStart or 1]
    local giver = current and ns.AcceptTarget and ns.AcceptTarget(current)
    local redirect = type(giver) == "table" and ns.HasMapPoint and ns.HasMapPoint(giver)
    if redirect or ns.acceptRouted then reasons.handoff = true end
    ns.acceptRouted = redirect and true or nil
    local fromIndex = ns.windowStart or 1
    if ns.ShouldPushRoute and ns.ShouldPushRoute(reasons) and ns.PushRoute then
        ns.PushRoute(plan, fromIndex, reasons)
    end
    if ns.PaintOptions then ns.PaintOptions() end
    if ns.Render then ns.Render(plan, err) end
end

local function eventQuestId(first, second)
    first, second = ns.Plain(first), ns.Plain(second)
    if type(second) == "number" and second > 0 then return second end
    if type(first) == "number" and first > 0 then return first end
    return nil
end

local function noteAccepted(questId)
    if type(questId) ~= "number" or questId <= 0 then return end
    ns.fresh = ns.fresh or {}
    ns.fresh[questId] = true
    ns.pendingAccepts = ns.pendingAccepts or {}
    ns.pendingAccepts[questId] = true
end

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "ADDON_LOADED" and arg1 == addonName then
        ns.ready = true
        ns.CharDB()
        if ns.PlaceMinimap then ns.PlaceMinimap() end
    elseif event == "PLAYER_LOGIN" then
        ns.OpenDatabase()
        ns.RestoreGuide()
        ns.RequestRefresh("login")
    elseif event == "PLAYER_LEAVING_WORLD" then
        ns.worldHidden = true
        ns.worldReady = false
    elseif event == "PLAYER_ENTERING_WORLD" then
        ns.worldHidden = false
        ns.RestoreGuide()
        local function settle()
            ns.worldHidden = false
            ns.worldReady = true
            ns.RestoreGuide()
        end
        if C_Timer and C_Timer.After then
            C_Timer.After(0, settle)
        else
            settle()
        end
    elseif event == "PLAYER_LOGOUT" then
        ns.SaveGuideState()
    elseif event == "PLAYER_REGEN_ENABLED" then
        local deferred = ns.deferred
        ns.deferred = nil
        if type(deferred) == "table" then ns.Refresh(deferred) end
    elseif event == "QUEST_ACCEPTED" then
        noteAccepted(eventQuestId(arg1, arg2))
        ns.RequestRefresh("accept")
    elseif event == "QUEST_TURNED_IN" then
        ns.RequestRefresh("turnin")
    elseif event == "QUEST_REMOVED" then
        local removedId = eventQuestId(arg1, arg2)
        if type(removedId) == "number" then
            ns.removedIds = ns.removedIds or {}
            ns.removedIds[removedId] = true
        end
        ns.RequestRefresh("removed")
    elseif event == "QUEST_LOG_UPDATE" then
        ns.RequestRefresh("log")
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        ns.RequestRefresh("zone")
    end
end)
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_LOGOUT")
eventFrame:RegisterEvent("PLAYER_LEAVING_WORLD")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("QUEST_LOG_UPDATE")
eventFrame:RegisterEvent("QUEST_ACCEPTED")
eventFrame:RegisterEvent("QUEST_REMOVED")
eventFrame:RegisterEvent("QUEST_TURNED_IN")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")

SLASH_CLEARTHELOG1 = "/ctl"
SLASH_CLEARTHELOG2 = "/clearthelog"
SlashCmdList.CLEARTHELOG = function(message)
    if not ns.ready then
        ns.Say("Not loaded yet.")
        return
    end
    local argument = (message or ""):match("^%s*(.-)%s*$")
    argument = argument and argument:lower() or ""
    if argument == "route" or argument == "guide" then
        if ns.ToggleGuide then ns.ToggleGuide() end
        return
    end
    if argument == "reset" then
        local db = ns.CharDB()
        db.tracked, db.chain, db.decided = {}, {}, {}
        db.ignored, db.selected, db.chainOff, db.chainThrough = {}, {}, {}, {}
        db.legacyMode = nil
        db.mode = nil
        ns.Say("Quest selection reset. Quests in your log are in the guide again.")
        ns.RequestRefresh("manual")
        return
    end
    if argument == "" or argument == "options" or argument == "optionen" then
        if ns.ToggleOptions then ns.ToggleOptions() end
        return
    end
    ns.Say("Commands: /ctl, /ctl route, /ctl reset")
end
