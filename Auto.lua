local _, ns = ...

-- Dialog automation. Turn-in covers every completed quest. Accept covers only
-- quests that are already steps in the guide. A reward choice is left open.

local function plain(value)
    if ns.Plain then return ns.Plain(value) end
    return value
end

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if not ok then return nil end
    return plain(value)
end

function ns.QuestIsPlanned(questId, title)
    if type(questId) == "number" and questId > 0 then
        local steps = ns.lastPlan and ns.lastPlan.steps
        if type(steps) == "table" then
            for index = 1, #steps do
                if steps[index].questId == questId or steps[index].acceptId == questId then
                    return true
                end
            end
        end
        local handoff = ns.ready and ns.CharDB().handoff
        if type(handoff) == "table" and handoff[questId] then return true end
        return false
    end
    if type(title) ~= "string" or title == "" then return false end
    local steps = ns.lastPlan and ns.lastPlan.steps
    if type(steps) ~= "table" then return false end
    for index = 1, #steps do
        local stop = steps[index]
        if stop.questName == title or stop.acceptName == title then return true end
    end
    return false
end

local function autoTurnIn()
    return ns.ready and ns.CharDB().autoTurnIn == true
end

local function autoAccept()
    return ns.ready and ns.CharDB().autoAcceptQuest == true
end

-- Classic returns 1, modern clients return true. Zero is not complete.
local function doneFlag(value)
    return value == true or value == 1
end

local function rewardNeedsChoice()
    local choices = call(GetNumQuestChoices)
    return type(choices) == "number" and choices > 1
end

local function acceptDetail()
    if not autoAccept() then return end
    local questId = call(GetQuestID)
    local title = call(GetTitleText)
    if not ns.QuestIsPlanned(questId, title) then return end
    call(AcceptQuest)
end

local function completeIfReady()
    if not autoTurnIn() then return end
    if not doneFlag(call(IsQuestCompletable)) then return end
    call(CompleteQuest)
end

local function takeReward()
    if not autoTurnIn() or rewardNeedsChoice() then return end
    local reward = GetQuestReward
    if type(reward) ~= "function" then return end
    pcall(reward, 1)
end

local function modernGossip()
    return C_GossipInfo
        and type(C_GossipInfo.GetActiveQuests) == "function"
        and type(C_GossipInfo.GetAvailableQuests) == "function"
end

local function selectCompleteModern()
    local listed = call(C_GossipInfo.GetActiveQuests)
    if type(listed) ~= "table" then return false end
    for _, quest in ipairs(listed) do
        if type(quest) == "table" and doneFlag(quest.isComplete) and type(quest.questID) == "number" then
            call(C_GossipInfo.SelectActiveQuest, quest.questID)
            return true
        end
    end
    return false
end

local function selectPlannedModern()
    local listed = call(C_GossipInfo.GetAvailableQuests)
    if type(listed) ~= "table" then return false end
    for _, quest in ipairs(listed) do
        if type(quest) == "table" and ns.QuestIsPlanned(quest.questID, quest.title) then
            call(C_GossipInfo.SelectAvailableQuest, quest.questID)
            return true
        end
    end
    return false
end

local function flatList(fn)
    if type(fn) ~= "function" then return nil end
    local ok, listed = pcall(function() return { fn() } end)
    if not ok or type(listed) ~= "table" then return nil end
    return listed
end

-- Gossip and the plain quest greeting are different lists. A greeting NPC
-- still uses GetNumActiveQuests even when the gossip API exists.
local function selectCompleteGossipLegacy()
    local listed = flatList(GetGossipActiveQuests)
    if not listed or type(SelectGossipActiveQuest) ~= "function" then return false end
    local questIndex = 0
    for index = 1, #listed, 6 do
        questIndex = questIndex + 1
        if doneFlag(plain(listed[index + 3])) then
            call(SelectGossipActiveQuest, questIndex)
            return true
        end
    end
    return false
end

local function selectPlannedGossipLegacy()
    local listed = flatList(GetGossipAvailableQuests)
    if not listed or type(SelectGossipAvailableQuest) ~= "function" then return false end
    local questIndex = 0
    for index = 1, #listed, 7 do
        questIndex = questIndex + 1
        if ns.QuestIsPlanned(nil, plain(listed[index])) then
            call(SelectGossipAvailableQuest, questIndex)
            return true
        end
    end
    return false
end

local function selectCompleteGreeting()
    local count = call(GetNumActiveQuests)
    if type(count) ~= "number" or type(GetActiveTitle) ~= "function" or type(SelectActiveQuest) ~= "function" then
        return false
    end
    for index = 1, count do
        local _, complete = GetActiveTitle(index)
        if doneFlag(plain(complete)) then
            call(SelectActiveQuest, index)
            return true
        end
    end
    return false
end

local function selectPlannedGreeting()
    local count = call(GetNumAvailableQuests)
    if type(count) ~= "number" or type(SelectAvailableQuest) ~= "function" then return false end
    for index = 1, count do
        local questId, title
        if type(GetAvailableQuestInfo) == "function" then
            questId = plain(select(5, GetAvailableQuestInfo(index)))
        end
        if type(GetAvailableTitle) == "function" then title = plain(GetAvailableTitle(index)) end
        if ns.QuestIsPlanned(questId, title) then
            call(SelectAvailableQuest, index)
            return true
        end
    end
    return false
end

local function onGossip()
    local modern = modernGossip()
    if autoTurnIn() then
        local turned
        if modern then turned = selectCompleteModern() else turned = selectCompleteGossipLegacy() end
        if turned then return end
    end
    if not autoAccept() then return end
    if modern then selectPlannedModern() else selectPlannedGossipLegacy() end
end

local function onGreeting()
    if autoTurnIn() and selectCompleteGreeting() then return end
    if autoAccept() then selectPlannedGreeting() end
end

local function logIndex(questId)
    if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then
        local index = call(C_QuestLog.GetLogIndexForQuestID, questId)
        if type(index) == "number" and index > 0 then return index end
    end
    if GetQuestLogIndexByID then
        local index = call(GetQuestLogIndexByID, questId)
        if type(index) == "number" and index > 0 then return index end
    end
end

local function onAutocomplete(questId)
    if not autoTurnIn() then return end
    questId = plain(questId)
    if type(questId) ~= "number" or not ns.IsIncluded(questId) then return end
    local index = logIndex(questId)
    if index and ShowQuestComplete then call(ShowQuestComplete, index) end
end

-- The gossip and quest frames need a moment before a click lands.
local AUTO_DELAY = 0.25
local waiting

local function later(action)
    if waiting then return end
    waiting = true
    local function run()
        waiting = false
        action()
    end
    if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
        C_Timer.After(AUTO_DELAY, run)
        return
    end
    run()
end

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, event, arg1)
    if not (autoTurnIn() or autoAccept()) then return end
    later(function()
        if event == "GOSSIP_SHOW" then
            onGossip()
        elseif event == "QUEST_GREETING" then
            onGreeting()
        elseif event == "QUEST_DETAIL" then
            acceptDetail()
        elseif event == "QUEST_PROGRESS" then
            completeIfReady()
        elseif event == "QUEST_COMPLETE" then
            takeReward()
        elseif event == "QUEST_AUTOCOMPLETE" then
            onAutocomplete(arg1)
        end
    end)
end)
frame:RegisterEvent("GOSSIP_SHOW")
frame:RegisterEvent("QUEST_GREETING")
frame:RegisterEvent("QUEST_DETAIL")
frame:RegisterEvent("QUEST_PROGRESS")
frame:RegisterEvent("QUEST_COMPLETE")
frame:RegisterEvent("QUEST_AUTOCOMPLETE")
