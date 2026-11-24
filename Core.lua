local addonName, ns = ...

ns.addonName = addonName
ns.TITLE = "Clear the Log"

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

function ns.CharDB()
    if not ns.ready then
        return { mode = "ignore", ignored = {}, selected = {}, chainOff = {} }
    end
    local db = ClearTheLogCharDB
    if type(db) ~= "table" then
        db = {}
        ClearTheLogCharDB = db
    end
    if db.mode ~= "ignore" and db.mode ~= "select" then db.mode = "ignore" end
    if type(db.ignored) ~= "table" then db.ignored = {} end
    if type(db.selected) ~= "table" then db.selected = {} end
    if type(db.chainOff) ~= "table" then db.chainOff = {} end
    return db
end

function ns.IsIncluded(questId)
    local db = ns.CharDB()
    if db.mode == "select" then return db.selected[questId] == true end
    return db.ignored[questId] ~= true
end

function ns.ChainEnabled(questId)
    return ns.CharDB().chainOff[questId] ~= true
end

function ns.SetIncluded(questId, included)
    local db = ns.CharDB()
    if db.mode == "select" then
        db.selected[questId] = included and true or nil
    else
        db.ignored[questId] = included and nil or true
    end
end

function ns.SetChainEnabled(questId, enabled)
    ns.CharDB().chainOff[questId] = enabled and nil or true
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
        return rows, "Questlog-API fehlt."
    end

    local ok, count = pcall(C_QuestLog.GetNumQuestLogEntries)
    count = ok and ns.Plain(count) or nil
    if type(count) ~= "number" then
        return nil, "Questlog ist gerade nicht lesbar."
    end

    for index = 1, count do
        local infoOk, info = pcall(C_QuestLog.GetInfo, index)
        if infoOk and type(info) == "table" then
            local questId = ns.Plain(info.questID)
            local isHeader = ns.Plain(info.isHeader)
            local isHidden = ns.Plain(info.isHidden)
            if not isHeader and not isHidden and type(questId) == "number" and questId > 0 then
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
                                if text == nil and finished == nil then
                                    secret = true
                                else
                                    objectives[#objectives + 1] = {
                                        text = text,
                                        finished = finished and true or false,
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
    for _, bucket in ipairs({ db.ignored, db.selected, db.chainOff }) do
        for questId in pairs(bucket) do
            if not live[questId] then bucket[questId] = nil end
        end
    end
end

function ns.RequestRefresh()
    if not ns.window or not ns.window:IsShown() then return end
    if ns.refreshPending then return end
    ns.refreshPending = true
    C_Timer.After(0.2, function()
        ns.refreshPending = false
        if ns.window and ns.window:IsShown() then ns.Refresh() end
    end)
end

function ns.Refresh()
    if not ns.ready or not ns.Render then return end
    if InCombatLockdown and InCombatLockdown() then
        ns.deferred = true
        return
    end

    local rows, err = readLog()
    if not rows then
        ns.Render(nil, err)
        return
    end
    pruneSaved(rows)
    local plan = ns.BuildPlan(rows, ns.PlayerLocation())
    ns.Render(plan, err)
end

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        ns.ready = true
        ns.CharDB()
    elseif event == "PLAYER_LOGIN" then
        ns.OpenDatabase()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if ns.deferred then
            ns.deferred = false
            ns.Refresh()
        end
    elseif event == "QUEST_LOG_UPDATE" or event == "QUEST_ACCEPTED"
        or event == "QUEST_REMOVED" or event == "QUEST_TURNED_IN"
        or event == "ZONE_CHANGED_NEW_AREA" then
        ns.RequestRefresh()
    end
end)
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
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
        ns.Say("Noch nicht geladen.")
        return
    end
    local argument = (message or ""):match("^%s*(.-)%s*$"):lower()
    if argument == "reset" then
        local db = ns.CharDB()
        db.ignored, db.selected, db.chainOff = {}, {}, {}
        ns.Say("Auswahl zurückgesetzt.")
        ns.Refresh()
        return
    end
    if argument == "ignore" or argument == "select" then
        ns.CharDB().mode = argument
        ns.Say(argument == "ignore" and "Modus: Ignorieren." or "Modus: Auswählen.")
        if ns.window and ns.window:IsShown() then ns.Refresh() end
        return
    end
    if ns.Toggle then ns.Toggle() end
end
