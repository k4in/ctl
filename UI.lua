local _, ns = ...

local ROW_QUEST = 32
local ZONE_GAP = 20
local ZONE_HEADER = 28
local ROW_STEP = 44
local BACKDROP = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
}

local silent = false

local DUNGEON_R, DUNGEON_G, DUNGEON_B = 0.36, 0.87, 0.94
local GROUP_R, GROUP_G, GROUP_B = 1, 0.8, 0

local function hexColor(r, g, b)
    return string.format("|cff%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

local DUNGEON_CODE = hexColor(DUNGEON_R, DUNGEON_G, DUNGEON_B)
local GROUP_CODE = hexColor(GROUP_R, GROUP_G, GROUP_B)
local CHAIN_CURRENT = hexColor(0.75, 0.48, 0.95)
local CHAIN_DONE = hexColor(0.30, 0.55, 0.32)
local CHAIN_NEXT = hexColor(0.70, 0.70, 0.70)
local CHAIN_ACCEPT = hexColor(1, 0.10, 0.10)

local function levelPrefix(level, questId)
    if type(level) ~= "number" or level <= 0 or type(ns.LevelTone) ~= "function" then return "" end
    local r, g, b = ns.LevelTone(level)
    if not r then return "" end
    local color = hexColor(r, g, b)
    local badge = ""
    if type(questId) == "number" then
        if ns.IsDungeonQuest and ns.IsDungeonQuest(questId) then
            badge = DUNGEON_CODE .. "D|r" .. color
        elseif ns.IsGroupQuest and ns.IsGroupQuest(questId) then
            badge = GROUP_CODE .. "+|r" .. color
        end
    end
    return color .. "[" .. level .. badge .. "]|r "
end

local function addQuestKind(questId)
    if ns.IsDungeonQuest and ns.IsDungeonQuest(questId) then
        GameTooltip:AddLine("Dungeon Quest", DUNGEON_R, DUNGEON_G, DUNGEON_B)
    elseif ns.IsGroupQuest and ns.IsGroupQuest(questId) then
        GameTooltip:AddLine("Group Quest", GROUP_R, GROUP_G, GROUP_B)
    end
end

local function bindTip(widget, title, body)
    widget:SetScript("OnEnter", function()
        GameTooltip:SetOwner(widget, "ANCHOR_RIGHT")
        GameTooltip:SetText(title, 1, 0.82, 0)
        if body and body ~= "" then GameTooltip:AddLine(body, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    widget:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function chrome(name, width, height, posKey, defaultX, defaultY, rightInset, limits)
    limits = limits or {}
    local minW, minH = limits.minW or 360, limits.minH or 240
    local maxW, maxH = limits.maxW or 1200, limits.maxH or 1000
    local sizeKey = limits.sizeKey or (posKey .. "Size")

    local frame = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    frame:SetSize(width, height)
    frame:SetPoint("CENTER", defaultX or 0, defaultY or 0)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:SetResizable(true)
    frame:EnableMouse(true)
    frame:SetBackdrop(BACKDROP)
    frame:SetBackdropColor(0, 0, 0, 0)
    frame:SetBackdropBorderColor(1, 1, 1, 1)
    local plate = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    plate:SetPoint("TOPLEFT", 12, -12)
    plate:SetPoint("BOTTOMRIGHT", -12, 12)
    plate:SetColorTexture(0.06, 0.07, 0.09, 0.95)
    frame.plate = plate
    frame:Hide()
    if frame.SetResizeBounds then
        frame:SetResizeBounds(minW, minH, maxW, maxH)
    else
        if frame.SetMinResize then frame:SetMinResize(minW, minH) end
        if frame.SetMaxResize then frame:SetMaxResize(maxW, maxH) end
    end
    tinsert(UISpecialFrames, name)

    local titleBar = CreateFrame("Frame", nil, frame)
    titleBar:SetPoint("TOPLEFT", 12, -8)
    titleBar:SetPoint("TOPRIGHT", -(rightInset or 40), -8)
    titleBar:SetHeight(32)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() frame:StartMoving() end)
    titleBar:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        if not ns.ready then return end
        local point, _, relative, x, y = frame:GetPoint(1)
        ns.CharDB()[posKey] = { point, relative, x, y }
    end)
    frame.titleBar = titleBar

    local title = titleBar:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("LEFT", 12, 0)
    frame.title = title

    local subtitle = titleBar:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    subtitle:SetPoint("LEFT", title, "RIGHT", 10, -1)
    subtitle:SetJustifyH("LEFT")
    frame.subtitle = subtitle

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)

    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -4, 4)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then frame:StartSizing("BOTTOMRIGHT") end
    end)
    grip:SetScript("OnMouseUp", function(_, button)
        if button ~= "LeftButton" then return end
        frame:StopMovingOrSizing()
        if not ns.ready then return end
        ns.CharDB()[sizeKey] = { frame:GetWidth(), frame:GetHeight() }
    end)

    local placed = false
    frame:SetScript("OnShow", function(self)
        if not placed and ns.ready then
            local db = ns.CharDB()
            local pos = db[posKey]
            if type(pos) == "table" and type(pos[1]) == "string" and type(pos[2]) == "string" then
                self:ClearAllPoints()
                self:SetPoint(pos[1], UIParent, pos[2], pos[3] or 0, pos[4] or 0)
            end
            local size = db[sizeKey]
            if type(size) == "table" and type(size[1]) == "number" and type(size[2]) == "number" then
                self:SetSize(
                    math.max(minW, math.min(maxW, size[1])),
                    math.max(minH, math.min(maxH, size[2]))
                )
            end
            placed = true
        end
        if self.onPresent then self.onPresent() end
    end)
    return frame
end

local function section(parent, text, y)
    local label = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("TOPLEFT", 24, y)
    label:SetText(text)
    return label
end

local function styleCheck(box)
    box:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    box:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
    box:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight")
    box:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
end

local fit

local function scroller(parent, name, x, yTop, right, yBottom)
    local scroll = CreateFrame("ScrollFrame", name, parent, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", x, yTop)
    scroll:SetPoint("BOTTOMRIGHT", right, yBottom)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(1, 1)
    scroll:SetScrollChild(child)
    scroll.child = child
    scroll:SetScript("OnSizeChanged", function(self)
        if self.contentHeight then fit(self, self.contentHeight) end
    end)
    return scroll
end

function fit(scroll, height)
    scroll.contentHeight = height
    local width = scroll:GetWidth()
    if width < 80 then width = 420 end
    scroll.child:SetWidth(width)
    local view = scroll:GetHeight() or 0
    if view < 0 then view = 0 end
    scroll.child:SetHeight(math.max(height, view, 1))
    local maxScroll = math.max(0, scroll.child:GetHeight() - view)
    if scroll:GetVerticalScroll() > maxScroll then scroll:SetVerticalScroll(maxScroll) end
end

local function clip(line)
    line:SetJustifyH("LEFT")
    line:SetWordWrap(false)
    if line.SetMaxLines then line:SetMaxLines(1) end
end

local options = chrome("ClearTheLogOptions", 480, 360, "posOptions", -260, 40, nil, {
    minW = 440, minH = 340, sizeKey = "sizeOptions",
})
options.title:SetText(ns.TITLE)
options.subtitle:SetText("/ctl")
ns.options = options

section(options, "Navigation", -46)

local routerHint = options:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
routerHint:SetPoint("TOPLEFT", 28, -70)
routerHint:SetPoint("RIGHT", options, "RIGHT", -28, 0)
routerHint:SetJustifyH("LEFT")
routerHint:SetWordWrap(true)
routerHint:SetText("Shortest Path Forever leads the next 5 steps. The button in the guide turns it on and off.")

local routerStatus = options:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
routerStatus:SetPoint("TOPLEFT", 28, -108)
routerStatus:SetPoint("RIGHT", options, "RIGHT", -28, 0)
routerStatus:SetJustifyH("LEFT")

local optionBoxes = {}

local function addToggle(text, y, field, tipTitle, tipBody)
    local box = CreateFrame("CheckButton", nil, options)
    box:SetSize(24, 24)
    box:SetPoint("TOPLEFT", 24, y)
    styleCheck(box)
    local label = options:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("LEFT", box, "RIGHT", 4, 0)
    label:SetText(text)
    local hit = CreateFrame("Button", nil, options)
    hit:SetPoint("TOPLEFT", box, "TOPRIGHT", 0, 0)
    hit:SetSize(400, 24)
    local function commit(on)
        if silent or not ns.ready then return end
        ns.CharDB()[field] = on and true or false
    end
    box:SetScript("OnClick", function(self)
        commit(self:GetChecked())
    end)
    hit:SetScript("OnClick", function()
        if silent then return end
        box:SetChecked(not box:GetChecked())
        commit(box:GetChecked())
    end)
    bindTip(box, tipTitle, tipBody)
    bindTip(hit, tipTitle, tipBody)
    optionBoxes[field] = box
    return box
end

section(options, "New quests", -136)

addToggle("Add new quests to the guide", -160, "autoTrack", "Add automatically", "A quest you accept is added to the guide. A follow-up that is already a step stays where it is.")

section(options, "Quest dialogs", -200)

addToggle("Turn in completed quests", -224, "autoTurnIn", "Turn in automatically", "Turns in every completed quest when you talk to someone. A reward choice waits for you. An item quest in the guide is confirmed too.")
addToggle("Accept planned quests", -250, "autoAcceptQuest", "Accept automatically", "Accepts a quest only when it is already a step in the guide.")

local guideButton = CreateFrame("Button", nil, options, "UIPanelButtonTemplate")
guideButton:SetSize(170, 24)
guideButton:SetPoint("BOTTOMLEFT", 24, 18)
guideButton:SetText("Show guide")
bindTip(guideButton, "Guide", "Opens or closes the route window. Same command: /ctl route.")

local function paintGuideButton()
    local shown = ns.guide and ns.guide:IsShown()
    guideButton:SetText(shown and "Hide guide" or "Show guide")
end

guideButton:SetScript("OnClick", function()
    if ns.ToggleGuide then ns.ToggleGuide() end
    paintGuideButton()
end)

function ns.PaintOptions()
    if not options then return end
    silent = true
    local db = ns.ready and ns.CharDB() or {}
    for field, box in pairs(optionBoxes) do
        box:SetChecked(db[field] and true or false)
    end
    local missing
    if ns.SpfReady and not ns.SpfReady() then
        missing = "Shortest Path Forever is not loaded."
    end
    routerStatus:SetText(missing or "")
    if missing then
        routerStatus:SetTextColor(1, 0.35, 0.35)
    end
    paintGuideButton()
    if ns.PaintNavigation then ns.PaintNavigation() end
    silent = false
end

options.onPresent = function()
    ns.PaintOptions()
end

local guide = chrome("ClearTheLogGuide", 440, 580, "pos", 180, 0, 220, {
    minW = 380, minH = 320, sizeKey = "sizeGuide",
})
guide.title:SetText("Guide")
guide.subtitle:SetText("/ctl route")
ns.guide = guide

local function redIconButton(parent, texture, fallback)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(22, 22)
    button:SetText("")
    local icon = button:CreateTexture(nil, "OVERLAY")
    icon:SetPoint("TOPLEFT", 3, -3)
    icon:SetPoint("BOTTOMRIGHT", -3, 3)
    local drawn = icon:SetTexture(texture)
    if drawn == false and fallback then
        icon:SetTexture(fallback)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    button.icon = icon
    return button
end

local questsButton = CreateFrame("Button", nil, guide, "UIPanelButtonTemplate")
questsButton:SetSize(80, 22)
questsButton:SetPoint("TOPRIGHT", -36, -12)
questsButton:SetText("Quests")

local optionsButton = redIconButton(guide, "Interface\\Buttons\\UI-OptionsButton", "Interface\\Icons\\INV_Misc_Gear_01")
optionsButton:SetPoint("RIGHT", questsButton, "LEFT", -6, 0)
optionsButton:SetScript("OnClick", function()
    if ns.ToggleOptions then ns.ToggleOptions() end
end)
bindTip(optionsButton, "Options", "Opens the options. Same command: /ctl.")

local refreshButton = redIconButton(guide, "Interface\\Buttons\\UI-RefreshButton")
refreshButton:SetPoint("RIGHT", optionsButton, "LEFT", -6, 0)
refreshButton:SetScript("OnClick", function()
    if ns.RefreshPlan then ns.RefreshPlan() end
end)
bindTip(refreshButton, "Recalculate plan", "Rebuilds the steps from your current location. Waypoints update while navigation is on.")

local navButton = redIconButton(guide, "Interface\\Minimap\\Tracking\\Target", "Interface\\Icons\\Ability_Hunter_SniperShot")
navButton:SetPoint("RIGHT", refreshButton, "LEFT", -6, 0)
if navButton.SetMotionScriptsWhileDisabled then navButton:SetMotionScriptsWhileDisabled(true) end
navButton:SetScript("OnClick", function()
    if not ns.ToggleNavigation or not ns.ToggleNavigation() then return end
    if ns.PaintNavigation then ns.PaintNavigation() end
end)
navButton:SetScript("OnEnter", function()
    local db = ns.ready and ns.CharDB() or {}
    GameTooltip:SetOwner(navButton, "ANCHOR_RIGHT")
    if db.navigating then
        GameTooltip:SetText("Navigation on", 1, 0.82, 0)
        GameTooltip:AddLine("Turns Shortest Path Forever off.", 1, 1, 1, true)
    else
        GameTooltip:SetText("Navigation off", 1, 0.82, 0)
        GameTooltip:AddLine("Turns Shortest Path Forever on and sends the next 5 steps.", 1, 1, 1, true)
    end
    GameTooltip:Show()
end)
navButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

function ns.PaintNavigation()
    local db = ns.ready and ns.CharDB() or {}
    local icon = navButton.icon
    navButton:Enable()
    if icon.SetDesaturated then icon:SetDesaturated(false) end
    if db.navigating then
        icon:SetVertexColor(1, 0.84, 0.25)
    else
        icon:SetVertexColor(0.75, 0.75, 0.75)
    end
end

guide.subtitle:SetPoint("RIGHT", navButton, "LEFT", -8, 0)

local stepScroll = scroller(guide, "ClearTheLogStepScroll", 16, -48, -34, 68)
local stepRows = {}

local summary = guide:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
summary:SetPoint("BOTTOMLEFT", 24, 50)
summary:SetPoint("RIGHT", guide, "RIGHT", -28, 0)
summary:SetJustifyH("LEFT")
clip(summary)

local routeLine = guide:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
routeLine:SetPoint("BOTTOMLEFT", 24, 34)
routeLine:SetPoint("RIGHT", guide, "RIGHT", -28, 0)
routeLine:SetJustifyH("LEFT")
clip(routeLine)

local warning = guide:CreateFontString(nil, "ARTWORK", "GameFontRedSmall")
warning:SetPoint("BOTTOMLEFT", 24, 18)
warning:SetPoint("RIGHT", guide, "RIGHT", -28, 0)
warning:SetJustifyH("LEFT")
clip(warning)

local function cleanTip(text)
    if type(text) ~= "string" then return nil end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h", ""):gsub("|h", "")
    text = text:match("^%s*(.-)%s*$")
    if not text or text == "" then return nil end
    return text
end

local function addQuestBody(questId, objectives)
    local blurb = ns.QuestBlurb and ns.QuestBlurb(questId)
    if type(blurb) == "string" and blurb ~= "" then
        GameTooltip:AddLine(blurb, 1, 1, 1, true)
    end
    local lines = objectives
    local structured = type(lines) == "table" and #lines > 0 and type(lines[1]) == "table"
    if not structured and ns.QuestObjectiveLines then
        lines = ns.QuestObjectiveLines(questId)
        structured = false
    end
    if type(lines) ~= "table" or #lines == 0 then return end
    GameTooltip:AddLine("Objectives", 1, 0.82, 0)
    for _, line in ipairs(lines) do
        local text = structured and line.text or line
        text = cleanTip(text)
        if text then
            if structured and line.finished then
                GameTooltip:AddLine(text, 0.55, 0.55, 0.55, true)
            else
                GameTooltip:AddLine(text, 1, 1, 1, true)
            end
        end
    end
end

local function addContacts(questId)
    if not ns.QuestContacts or not ns.ContactText then return end
    local giver, turnin = ns.QuestContacts(questId)
    local giverText = ns.ContactText(giver)
    local turninText = ns.ContactText(turnin)
    if giverText then
        GameTooltip:AddLine("Quest giver: " .. giverText, 0.75, 0.9, 1, true)
    end
    if turninText then
        GameTooltip:AddLine("Turn in: " .. turninText, 0.7, 1, 0.75, true)
    end
end

local function questObjectives(questId, stored)
    if type(stored) == "table" and #stored > 0 then return stored end
    local quests = ns.lastPlan and ns.lastPlan.quests
    if type(quests) == "table" then
        for _, quest in ipairs(quests) do
            if quest.id == questId and type(quest.objectives) == "table" and #quest.objectives > 0 then
                return quest.objectives
            end
        end
    end
    return nil
end

local function addFollowups(questId)
    GameTooltip:AddLine("Follow-ups", 1, 0.82, 0)
    local briefs = ns.FollowupBriefs and ns.FollowupBriefs(questId) or {}
    if #briefs == 0 then
        GameTooltip:AddLine("No follow-ups.", 0.7, 0.7, 0.7)
        return
    end
    for _, brief in ipairs(briefs) do
        local name = brief.name or "Quest"
        local zone = brief.zone or "No zone"
        GameTooltip:AddLine(name .. " — " .. zone, 0.85, 0.85, 0.85, true)
    end
end

local function paintSkipIcon(button, undo)
    local base = undo and "Interface\\Buttons\\UI-SpellbookIcon-PrevPage"
        or "Interface\\Buttons\\UI-SpellbookIcon-NextPage"
    button:SetNormalTexture(base .. "-Up")
    button:SetPushedTexture(base .. "-Down")
    button:SetDisabledTexture(base .. "-Disabled")
end

local function hideDetails(row)
    if row.header then row.header:Hide() end
    if row.details then
        for _, line in ipairs(row.details) do line:Hide() end
    end
end

local function stepRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_STEP)
    row:EnableMouse(true)

    row.current = row:CreateTexture(nil, "BACKGROUND")
    row.current:SetAllPoints()
    row.current:SetColorTexture(0.95, 0.78, 0.25, 0.34)
    row.current:Hide()

    row.edge = row:CreateTexture(nil, "ARTWORK")
    row.edge:SetPoint("TOPLEFT", 0, 0)
    row.edge:SetPoint("BOTTOMLEFT", 0, 0)
    row.edge:SetWidth(4)
    row.edge:SetColorTexture(1, 0.82, 0, 1)
    row.edge:Hide()

    row.hover = row:CreateTexture(nil, "BORDER")
    row.hover:SetAllPoints()
    row.hover:SetColorTexture(1, 1, 1, 0.05)
    row.hover:Hide()

    row.badge = CreateFrame("Frame", nil, row)
    row.badge:SetSize(18, 18)
    row.badge:SetPoint("TOPLEFT", 8, -4)
    row.mark = row.badge:CreateTexture(nil, "ARTWORK")
    row.mark:SetAllPoints()
    row.badge:Hide()

    row.action = CreateFrame("Button", nil, row)
    row.action:SetSize(22, 22)
    row.action:SetPoint("RIGHT", -8, 0)
    row.action:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row.action:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    paintSkipIcon(row.action, false)
    row.action:Hide()
    row.action:SetScript("OnClick", function(_, mouseButton)
        if silent or not row.index or not row.stop then return end
        if mouseButton == "LeftButton" and IsShiftKeyDown and IsShiftKeyDown() then
            if ns.RecalculateFromStep then ns.RecalculateFromStep(row.index) end
            return
        end
        if mouseButton == "RightButton" then
            if ns.SkipStep then ns.SkipStep(row.index) end
            return
        end
        if row.stop.skipped then
            if ns.UndoSkip then ns.UndoSkip(row.index) end
        elseif ns.SkipStep then
            ns.SkipStep(row.index)
        end
    end)
    row.action:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if row.stop and row.stop.skipped then
            GameTooltip:SetText("Undo", 1, 0.82, 0)
            GameTooltip:AddLine("Clears the skip and recalculates the plan from your current location.", 1, 1, 1, true)
        else
            GameTooltip:SetText("Skip", 1, 0.82, 0)
            GameTooltip:AddLine("Moves this step to the end of the plan.", 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    row.action:SetScript("OnLeave", function() GameTooltip:Hide() end)

    row.drop = CreateFrame("Button", nil, row)
    row.drop:SetSize(22, 22)
    row.drop:SetPoint("RIGHT", row.action, "LEFT", -4, 0)
    row.drop:RegisterForClicks("LeftButtonUp")
    row.drop:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    row.drop.label = row.drop:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.drop.label:SetPoint("CENTER", 1, 0)
    row.drop.label:SetText("x")
    row.drop.label:SetTextColor(1, 0.25, 0.25)
    row.drop:Hide()
    row.drop:SetScript("OnClick", function()
        if silent or not row.stop or type(ns.DropQuestLine) ~= "function" then return end
        local stop = row.stop
        local questId
        if stop.awaitAccept and type(stop.acceptId) == "number" and stop.acceptId > 0 then
            questId = stop.acceptId
        elseif type(stop.questId) == "number" and stop.questId > 0 then
            questId = stop.questId
        end
        if type(questId) == "number" then ns.DropQuestLine(questId) end
    end)
    row.drop:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Remove", 1, 0.82, 0)
        GameTooltip:AddLine("Removes this quest chain from the guide and the quest list.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    row.drop:SetScript("OnLeave", function() GameTooltip:Hide() end)

    row.header = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.header:SetPoint("TOPLEFT", 12, -8)
    row.header:SetText("CURRENT STEP")
    row.header:Hide()

    row.line = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.line:SetPoint("TOPLEFT", 10, -4)
    row.line:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    clip(row.line)

    row.sub = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.sub:SetPoint("TOPLEFT", 22, -22)
    row.sub:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    clip(row.sub)

    row.details = {}
    for index = 1, 6 do
        local line = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        line:SetJustifyH("LEFT")
        line:SetWordWrap(false)
        if line.SetMaxLines then line:SetMaxLines(1) end
        line:Hide()
        row.details[index] = line
    end

    row:SetScript("OnEnter", function()
        row.hover:Show()
        if not row.stop then return end
        local stop = row.stop
        local tipId = stop.questId
        local title = stop.questName or "Step"
        if stop.awaitAccept and type(stop.acceptId) == "number" and stop.acceptId > 0 then
            tipId = stop.acceptId
            if type(stop.acceptName) == "string" and stop.acceptName ~= "" then title = stop.acceptName end
        end
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:SetText(title, 1, 0.82, 0)
        if not stop.awaitAccept and stop.text and stop.text ~= title then
            GameTooltip:AddLine(cleanTip(stop.text), 1, 1, 1, true)
        end
        if not stop.awaitAccept and stop.note and stop.note ~= "" then
            GameTooltip:AddLine(stop.note, 0.8, 0.8, 0.8, true)
        end
        if stop.dungeon then GameTooltip:AddLine("Dungeon Quest", DUNGEON_R, DUNGEON_G, DUNGEON_B) end
        addQuestBody(tipId, questObjectives(tipId))
        addContacts(tipId)
        addFollowups(tipId)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Left click opens the quest in the quest log.", 0.7, 0.7, 0.7, true)
        GameTooltip:AddLine("Shift+Left click recalculates the guide with this step as the start.", 0.7, 0.7, 0.7, true)
        GameTooltip:AddLine("Right click skips this step.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function()
        row.hover:Hide()
        GameTooltip:Hide()
    end)
    row:SetScript("OnMouseUp", function(_, button)
        if silent or not row.index or not row.stop then return end
        if button == "RightButton" then
            if ns.SkipStep then ns.SkipStep(row.index) end
            return
        end
        if button ~= "LeftButton" then return end
        if IsShiftKeyDown and IsShiftKeyDown() then
            if ns.RecalculateFromStep then ns.RecalculateFromStep(row.index) end
            return
        end
        if ns.OpenQuestLog then ns.OpenQuestLog(row.stop.questId) end
    end)
    return row
end

local function ensureStepRow(index)
    local row = stepRows[index]
    if not row then
        row = stepRow(stepScroll.child)
        stepRows[index] = row
    end
    return row
end

local function locationText(areaId, x, y)
    local zone, subzone
    if ns.ZonePair then
        zone, subzone = ns.ZonePair(areaId)
    elseif ns.ZoneName and type(areaId) == "number" and areaId > 0 then
        zone = ns.ZoneName(areaId)
        if zone == "No zone" then zone = nil end
    end
    local place = zone
    if type(subzone) == "string" and subzone ~= "" then
        place = place and (place .. ", " .. subzone) or subzone
    end
    local coord
    if type(x) == "number" and type(y) == "number" then
        coord = string.format("%.0f, %.0f", x, y)
    end
    if place and coord then return place .. " (" .. coord .. ")" end
    return place or coord
end

local function anchorLine(row, top, inset, large, left)
    row.line:ClearAllPoints()
    row.line:SetPoint("TOPLEFT", left or 12, top)
    row.line:SetPoint("RIGHT", row, "RIGHT", -inset, 0)
    local font = GameFontHighlight
    if large and GameFontNormalLarge then font = GameFontNormalLarge end
    if font then row.line:SetFontObject(font) end
    row.line:SetWordWrap(large and true or false)
    if row.line.SetMaxLines then row.line:SetMaxLines(large and 2 or 1) end
end

local function questTitle(stop)
    if type(stop.questName) == "string" and stop.questName ~= "" then return stop.questName end
    return stop.text or ""
end

local function waitingToAccept(stop)
    return stop.kind == "accept"
end

-- Turn-in and accept steps name the quest. Objectives keep their own text.
local function stepCaption(stop, current)
    if stop.kind == "accept" then
        local name = stop.acceptName
        if type(name) ~= "string" or name == "" then name = questTitle(stop) end
        return "Accept", name
    end
    if stop.kind == "turnin" then
        local tag = "Turn in"
        if stop.followup then tag = tag .. " · Follow-up" end
        return tag, questTitle(stop)
    end
    local tag = "Objective"
    if stop.followup then tag = tag .. " · Follow-up" end
    return tag, stop.text or ""
end

local function currentDetails(stop)
    local lines = {}
    local function add(text, r, g, b)
        if type(text) == "string" and text ~= "" then
            lines[#lines + 1] = { text = text, r = r, g = g, b = b }
        end
    end
    local accepting = waitingToAccept(stop)
    if not accepting and stop.kind == "objective" and ns.ProgressLabel then
        add(ns.ProgressLabel(stop), 1, 0.9, 0.55)
    end
    local shown = stop
    if accepting and ns.RouteStop then shown = ns.RouteStop(stop) or stop end
    add(locationText(shown.areaId, shown.x, shown.y), 0.9, 0.9, 0.9)
    if ns.QuestContacts and ns.ContactText then
        local contactId = stop.questId
        if accepting and type(stop.acceptId) == "number" and stop.acceptId > 0 then
            contactId = stop.acceptId
        end
        local giver, turnin = ns.QuestContacts(contactId)
        local giverText = ns.ContactText(giver)
        local turninText = ns.ContactText(turnin)
        if giverText then add("Quest giver: " .. giverText, 0.75, 0.9, 1) end
        if turninText and not accepting then add("Turn in: " .. turninText, 0.7, 1, 0.75) end
    end
    if type(stop.acceptName) == "string" and stop.acceptName ~= "" and not accepting then
        add("Accept: " .. stop.acceptName, 0.75, 0.9, 1)
    end
    local meta = {}
    if not accepting and stop.questName and stop.questName ~= "" then meta[#meta + 1] = stop.questName end
    if not accepting and stop.note and stop.note ~= "" then meta[#meta + 1] = stop.note end
    if stop.dungeon then meta[#meta + 1] = DUNGEON_CODE .. "Dungeon Quest|r" end
    if stop.skipped then meta[#meta + 1] = "skipped" end
    if ns.DBReady and ns.DBReady() and not ns.HasMapPoint(shown) then
        meta[#meta + 1] = "no map"
    end
    add(table.concat(meta, "   ·   "), 0.7, 0.7, 0.7)
    return lines
end

local function showCurrent(row, lines, inset, left)
    row.header:Show()
    row.sub:Hide()
    local top = -78
    local shown = 0
    left = left or 24
    for index, line in ipairs(lines) do
        if index > #row.details then break end
        local widget = row.details[index]
        widget:ClearAllPoints()
        widget:SetPoint("TOPLEFT", left, top)
        widget:SetPoint("RIGHT", row, "RIGHT", -inset, 0)
        widget:SetText(line.text)
        widget:SetTextColor(line.r, line.g, line.b)
        widget:Show()
        top = top - 16
        shown = shown + 1
    end
    for index = shown + 1, #row.details do row.details[index]:Hide() end
    return math.max(124, 86 + shown * 16)
end

local function paintMark(row, stop, here)
    local badge = row.badge
    local mark = row.mark
    if not stop or not badge or not mark then
        if badge then badge:Hide() end
        return false
    end
    local path = ns.StepIcon and ns.StepIcon(stop)
    if type(path) ~= "string" or path == "" then
        badge:Hide()
        return false
    end
    badge:Show()
    if mark:SetTexture(path) == false then
        badge:Hide()
        return false
    end
    mark:SetTexCoord(0, 1, 0, 1)
    badge:ClearAllPoints()
    if here then
        badge:SetSize(22, 22)
        badge:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -30)
    else
        badge:SetSize(18, 18)
        badge:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -4)
    end
    if badge.SetFrameLevel and row.GetFrameLevel then
        badge:SetFrameLevel(row:GetFrameLevel() + 5)
    end
    if stop.skipped then
        if mark.SetDesaturated then mark:SetDesaturated(true) end
        mark:SetVertexColor(0.55, 0.55, 0.55)
    else
        if mark.SetDesaturated then mark:SetDesaturated(false) end
        mark:SetVertexColor(1, 1, 1)
    end
    mark:Show()
    return true
end

local function fillSteps(steps)
    local list = steps or {}
    local indexes = ns.VisibleStepIndexes and ns.VisibleStepIndexes(list) or {}
    local count = (#list == 0 or #indexes == 0) and 1 or #indexes
    local current = ns.windowStart or 1
    if type(current) ~= "number" or current < 1 then current = 1 end
    if #list > 0 and current > #list then current = #list end
    local y = 0
    for rowIndex = 1, count do
        local row = ensureStepRow(rowIndex)
        local index = indexes[rowIndex]
        local stop = index and list[index]
        local here = stop and index == current
        local showIcon = stop and (here or stop.skipped) or false
        local showDrop = here and stop and waitingToAccept(stop) or false
        local inset = showDrop and 64 or (showIcon and 36 or 10)
        row.index = stop and index or nil
        row.stop = stop
        row.hover:Hide()
        row.current:SetShown(here and true or false)
        row.edge:SetShown(here and true or false)
        row.action:ClearAllPoints()
        if here then
            row.action:SetPoint("TOPRIGHT", -8, -28)
        else
            row.action:SetPoint("RIGHT", -8, 0)
        end
        if showIcon then
            paintSkipIcon(row.action, stop.skipped and true or false)
            row.action:Show()
        else
            row.action:Hide()
        end
        if showDrop then
            row.drop:Show()
        else
            row.drop:Hide()
        end

        local height = ROW_STEP
        local marked = paintMark(row, stop, here)
        local textLeft = marked and (here and 40 or 32) or 12
        if not stop then
            hideDetails(row)
            row.sub:Show()
            row.sub:SetText("")
            anchorLine(row, -12, 10, false, textLeft)
            row.line:SetText("No steps. The log is empty, or no quest is in the guide.")
            row.line:SetTextColor(0.7, 0.7, 0.7)
        elseif here then
            row.header:ClearAllPoints()
            row.header:SetPoint("TOPLEFT", textLeft, -8)
            anchorLine(row, -28, inset, true, textLeft)
            local tag, label = stepCaption(stop, true)
            local mark = stop.dungeon and (DUNGEON_CODE .. "D|r  ") or ""
            row.line:SetText(string.format("%d.  %s%s: %s", index, mark, tag, label))
            row.line:SetTextColor(1, 0.86, 0.35)
            height = showCurrent(row, currentDetails(stop), inset, textLeft)
        else
            hideDetails(row)
            row.sub:Show()
            anchorLine(row, -4, inset, false, textLeft)
            local tag, label = stepCaption(stop, false)
            local mark = stop.dungeon and (DUNGEON_CODE .. "D|r  ") or ""
            row.line:SetText(string.format("%d.  %s%s: %s", index, mark, tag, label))
            if stop.skipped then
                row.line:SetTextColor(0.55, 0.55, 0.55)
            elseif stop.followup then
                row.line:SetTextColor(0.95, 0.8, 0.45)
            elseif stop.kind == "turnin" then
                row.line:SetTextColor(0.55, 1, 0.65)
            else
                row.line:SetTextColor(1, 1, 1)
            end
            local bits = {}
            local place = locationText(stop.areaId, stop.x, stop.y)
            if place then bits[#bits + 1] = place end
            if stop.questName and stop.questName ~= "" then bits[#bits + 1] = stop.questName end
            if stop.note and stop.note ~= "" then bits[#bits + 1] = stop.note end
            if stop.skipped then bits[#bits + 1] = "skipped" end
            if ns.DBReady and ns.DBReady() and not ns.HasMapPoint(stop) then
                bits[#bits + 1] = "no map"
            end
            row.sub:ClearAllPoints()
            row.sub:SetPoint("TOPLEFT", marked and textLeft or 24, -22)
            row.sub:SetPoint("RIGHT", row, "RIGHT", -inset, 0)
            row.sub:SetText(table.concat(bits, "   ·   "))
            if stop.skipped then
                row.sub:SetTextColor(0.45, 0.45, 0.45)
            else
                row.sub:SetTextColor(0.65, 0.65, 0.65)
            end
        end

        row:ClearAllPoints()
        row:SetHeight(height)
        row:SetPoint("TOPLEFT", stepScroll.child, "TOPLEFT", 0, -y)
        row:SetPoint("TOPRIGHT", stepScroll.child, "TOPRIGHT", 0, -y)
        row:Show()
        y = y + height
    end
    for index = count + 1, #stepRows do stepRows[index]:Hide() end
    fit(stepScroll, math.max(y, 1))
    return #indexes
end

local function routeSentence()
    local db = ns.ready and ns.CharDB() or {}
    if db.navigating ~= true then
        return "Navigation is off.", false
    end
    if ns.routeStatus and ns.routeStatus ~= "" then
        return ns.routeStatus, ns.routeStatusError and true or false
    end
    if ns.SpfReady and not ns.SpfReady() then
        return "Shortest Path Forever is not loaded.", true
    end
    return "Waypoints update when the current step is finished.", false
end

function ns.RenderGuide(plan, err)
    if ns.PaintNavigation then ns.PaintNavigation() end
    silent = true
    if not plan then
        fillSteps(nil)
        summary:SetText("")
        routeLine:SetText("")
        warning:SetText(err or "")
        silent = false
        return
    end
    local shown = fillSteps(plan.steps)
    local included = 0
    for _, quest in ipairs(plan.quests or {}) do
        if quest.included then included = included + 1 end
    end
    local summaryText = string.format(
        "%d of %d steps · %d of %d quests in the guide",
        shown, #(plan.steps or {}), included, #(plan.quests or {})
    )
    if ns.tourPending then summaryText = summaryText .. "  ·  Sorting route…" end
    summary:SetText(summaryText)
    local text, bad = routeSentence()
    routeLine:SetText(text or "")
    if bad then
        routeLine:SetTextColor(1, 0.35, 0.35)
    else
        routeLine:SetTextColor(0.5, 0.5, 0.5)
    end
    warning:SetText(plan.warning or err or "")
    silent = false
end

local guideHideToken = 0

local function rememberGuideOpen()
    guideHideToken = guideHideToken + 1
    if ns.NoteGuideShown then
        ns.NoteGuideShown()
    else
        ns.guideIntent = true
        if ns.ready then ns.CharDB().guideShown = true end
    end
end

local function scheduleGuideClosed()
    -- A loading screen hides the frame too. Only a hide while the world is up counts.
    guideHideToken = guideHideToken + 1
    local token = guideHideToken
    local ignore = ns.loggingOut or ns.worldHidden or not ns.worldReady
    local function apply()
        if token ~= guideHideToken or ignore or ns.loggingOut or ns.worldHidden or not ns.worldReady then
            return
        end
        if guide:IsShown() then return end
        if ns.NoteGuideHidden then ns.NoteGuideHidden() end
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0, apply)
    else
        apply()
    end
end

guide.onPresent = function()
    rememberGuideOpen()
    if ns.lastPlan then ns.RenderGuide(ns.lastPlan, ns.lastErr) end
    ns.RequestRefresh("open")
    paintGuideButton()
    if ns.PaintNavigation then ns.PaintNavigation() end
end
guide:SetScript("OnHide", function()
    paintGuideButton()
    scheduleGuideClosed()
end)

function ns.ShowGuide()
    if not guide:IsShown() then guide:Show() end
end

function ns.ToggleGuide()
    if guide:IsShown() then guide:Hide() else guide:Show() end
end

local quests = chrome("ClearTheLogQuests", 500, 540, "posQuests", 0, -10, nil, {
    minW = 400, minH = 280, sizeKey = "sizeQuests",
})
quests.title:SetText("Quests")
quests.subtitle:SetText("Log")
ns.quests = quests

local addAll = CreateFrame("Button", nil, quests, "UIPanelButtonTemplate")
addAll:SetSize(120, 22)
addAll:SetPoint("TOPLEFT", 24, -44)
addAll:SetText("Add all")
bindTip(addAll, "Add all", "Puts every quest in the log into the guide. Follow-ups stay as you set them on each chain.")
addAll:SetScript("OnClick", function()
    if ns.SetAllQuests then ns.SetAllQuests(true) end
end)

local removeAll = CreateFrame("Button", nil, quests, "UIPanelButtonTemplate")
removeAll:SetSize(120, 22)
removeAll:SetPoint("LEFT", addAll, "RIGHT", 8, 0)
removeAll:SetText("Reset")
bindTip(removeAll, "Reset", "Clears the guide. Every quest comes out, including chain follow-ups.")
removeAll:SetScript("OnClick", function()
    if ns.ResetGuide then ns.ResetGuide() end
end)

local questHint = quests:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
questHint:SetPoint("TOPLEFT", 24, -72)
questHint:SetPoint("RIGHT", quests, "RIGHT", -24, 0)
questHint:SetJustifyH("LEFT")
questHint:SetWordWrap(true)
questHint:SetText("Check a quest to put it in the guide. Toggle all turns every later quest in its chain on or off.")

local questScroll = scroller(quests, "ClearTheLogQuestScroll", 16, -116, -34, 36)
local questRows = {}
local questHeaders = {}
local questEmpty = questScroll.child:CreateFontString(nil, "ARTWORK", "GameFontDisable")
questEmpty:SetPoint("TOPLEFT", questScroll.child, "TOPLEFT", 4, 0)
questEmpty:SetJustifyH("LEFT")
questEmpty:Hide()

local questStatus = quests:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
questStatus:SetPoint("BOTTOMLEFT", 24, 16)
questStatus:SetPoint("RIGHT", quests, "RIGHT", -24, 0)
questStatus:SetJustifyH("LEFT")

local ROW_CHAIN = 24
local chainRows = {}
-- Nil means expanded. False means the player collapsed this chain.
local openChains = {}

local function chainExpanded(questId)
    return openChains[questId] ~= false
end

local function addArea(questId)
    if not ns.ObjectiveZoneLabel then return end
    local zone = ns.ObjectiveZoneLabel(questId)
    if type(zone) ~= "string" or zone == "" or zone == "No zone" then return end
    GameTooltip:AddLine("Area: " .. zone, 0.8, 0.85, 1, true)
end

local function showQuestTip(row, owner)
    if not row or not row.questId then return end
    GameTooltip:SetOwner(owner or row, "ANCHOR_RIGHT")
    GameTooltip:SetText(row.tipName or "Quest", 1, 0.82, 0)
    if row.chainText then GameTooltip:AddLine(row.chainText, 1, 0.82, 0) end
    addQuestBody(row.questId, row.objectives)
    addContacts(row.questId)
    addArea(row.questId)
    if row.known == false then GameTooltip:AddLine("Not in QuestieDB.", 0.8, 0.8, 0.8) end
    addQuestKind(row.questId)
    if row.pending then
        GameTooltip:AddLine("Accept this quest to continue the chain.", 1, 0.35, 0.35, true)
        GameTooltip:AddLine("Uncheck to remove this chain from the guide and the quest list.", 0.7, 0.7, 0.7, true)
    end
    if row.chainText then
        GameTooltip:AddLine("Expand the chain to choose follow-ups.", 0.7, 0.7, 0.7, true)
    end
    GameTooltip:Show()
end

local function showChainTip(row, owner)
    if not row or not row.memberId then return end
    GameTooltip:SetOwner(owner or row, "ANCHOR_RIGHT")
    GameTooltip:SetText(row.tipName or "Quest", 1, 0.82, 0)
    if type(row.level) == "number" and row.level > 0 and type(ns.LevelTone) == "function" then
        local r, g, b = ns.LevelTone(row.level)
        if r then GameTooltip:AddLine("Level " .. row.level, r, g, b) end
    end
    addQuestBody(row.memberId, questObjectives(row.memberId))
    addContacts(row.memberId)
    addArea(row.memberId)
    addQuestKind(row.memberId)
    if row.role == "followup" then
        if row.included then
            GameTooltip:AddLine("Uncheck to drop this quest and every quest after it.", 0.8, 0.8, 0.8, true)
        else
            GameTooltip:AddLine("Check to include every quest through this one.", 0.8, 0.8, 0.8, true)
        end
    elseif row.role == "current" then
        if row.pendingAccept then
            GameTooltip:AddLine("Accept this quest to continue the chain.", 1, 0.35, 0.35, true)
        else
            GameTooltip:AddLine("This is the quest in your log.", 0.8, 0.8, 0.8, true)
        end
    else
        GameTooltip:AddLine("Earlier in the chain.", 0.8, 0.8, 0.8, true)
    end
    GameTooltip:Show()
end

local function hideQuestTip()
    GameTooltip:Hide()
end

local function paintExpand(button, open)
    local base = open and "Interface\\Buttons\\UI-MinusButton-" or "Interface\\Buttons\\UI-PlusButton-"
    button:SetNormalTexture(base .. "UP")
    button:SetPushedTexture(base .. "DOWN")
    button:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight")
end

local function chainMemberText(member, finished, accepting)
    local tone = CHAIN_NEXT
    if accepting and member.role == "current" then
        tone = CHAIN_ACCEPT
    elseif member.role == "current" then
        tone = CHAIN_CURRENT
    elseif finished then
        tone = CHAIN_DONE
    end
    return member.index .. ".  " .. levelPrefix(member.level, member.id) .. tone .. (member.name or "Quest") .. "|r"
end

local function tintCheck(check, r, g, b)
    for _, name in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetCheckedTexture" }) do
        local getter = check[name]
        local texture = type(getter) == "function" and getter(check) or nil
        if texture and texture.SetVertexColor then texture:SetVertexColor(r, g, b) end
    end
end

local function chainMemberRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_CHAIN)

    row.shade = row:CreateTexture(nil, "BACKGROUND")
    row.shade:SetAllPoints()
    row.shade:SetColorTexture(1, 0.82, 0, 0.06)

    row.rail = row:CreateTexture(nil, "ARTWORK")
    row.rail:SetPoint("TOPLEFT", 22, 0)
    row.rail:SetPoint("BOTTOMLEFT", 22, 0)
    row.rail:SetWidth(2)
    row.rail:SetColorTexture(1, 0.82, 0, 0.55)

    row.check = CreateFrame("CheckButton", nil, row)
    row.check:SetSize(22, 22)
    row.check:SetPoint("LEFT", 30, 0)
    styleCheck(row.check)
    if row.check.SetMotionScriptsWhileDisabled then row.check:SetMotionScriptsWhileDisabled(true) end
    row.check:SetScript("OnClick", function(self)
        if silent or row.done or row.role ~= "followup" or not row.logQuestId or not row.memberId then
            if row.role == "current" then
                self:SetChecked(row.parentIncluded and true or false)
            else
                self:SetChecked(row.done and true or false)
            end
            return
        end
        if ns.AdjustChain then ns.AdjustChain(row.logQuestId, row.memberId) end
        if ns.RequestRefresh then ns.RequestRefresh("manual") end
    end)
    row.check:SetScript("OnEnter", function(self)
        showChainTip(row, self)
    end)
    row.check:SetScript("OnLeave", hideQuestTip)

    row.name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row.check, "RIGHT", 2, 0)
    row.name:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.name:SetJustifyH("LEFT")
    clip(row.name)

    row.hit = CreateFrame("Button", nil, row)
    row.hit:SetPoint("TOPLEFT", row.check, "TOPRIGHT", 0, 0)
    row.hit:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -4, 0)
    row.hit:SetScript("OnClick", function()
        if silent or row.role ~= "followup" then return end
        row.check:Click()
    end)
    row.hit:SetScript("OnEnter", function()
        row.check:GetScript("OnEnter")(row.check)
    end)
    row.hit:SetScript("OnLeave", hideQuestTip)
    return row
end

local function questRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_QUEST)
    row:EnableMouse(true)
    row:SetScript("OnEnter", function() showQuestTip(row, row) end)
    row:SetScript("OnLeave", hideQuestTip)

    row.shade = row:CreateTexture(nil, "BACKGROUND")
    row.shade:SetAllPoints()
    row.shade:SetColorTexture(1, 1, 1, 0.04)

    row.check = CreateFrame("CheckButton", nil, row)
    row.check:SetSize(24, 24)
    row.check:SetPoint("LEFT", 2, 0)
    styleCheck(row.check)
    row.check:SetScript("OnClick", function(self)
        if silent or not row.questId then return end
        local on = self:GetChecked() and true or false
        if row.pending and not on and type(ns.DropQuestLine) == "function" then
            ns.DropQuestLine(row.questId)
            return
        end
        ns.SetIncluded(row.questId, on)
        ns.RequestRefresh("manual")
    end)
    row.check:SetScript("OnEnter", function(self)
        showQuestTip(row, self)
    end)
    row.check:SetScript("OnLeave", hideQuestTip)

    row.expand = CreateFrame("Button", nil, row)
    row.expand:SetSize(18, 18)
    row.expand:SetPoint("RIGHT", -6, 0)
    row.expand:SetScript("OnClick", function()
        if silent or not row.questId then return end
        if chainExpanded(row.questId) then
            openChains[row.questId] = false
        else
            openChains[row.questId] = nil
        end
        if ns.RenderQuests then ns.RenderQuests(ns.lastPlan, ns.lastErr) end
    end)
    row.expand:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(chainExpanded(row.questId) and "Hide chain" or "Show chain", 1, 0.82, 0)
        GameTooltip:AddLine("Opens every quest in this chain. Check the follow-ups you want in the route.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    row.expand:SetScript("OnLeave", hideQuestTip)
    paintExpand(row.expand, false)
    row.expand:Hide()

    row.chainLabel = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.chainLabel:SetPoint("RIGHT", row.expand, "LEFT", -2, 0)
    row.chainLabel:SetWidth(48)
    row.chainLabel:SetJustifyH("RIGHT")
    row.chainLabel:Hide()

    row.toggleAll = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.toggleAll:SetSize(100, 20)
    row.toggleAll:SetPoint("RIGHT", row.chainLabel, "LEFT", -4, 0)
    row.toggleAll:SetText("Toggle all")
    local toggleLabel = row.toggleAll:GetFontString()
    if toggleLabel then toggleLabel:SetFontObject("GameFontHighlightSmall") end
    row.toggleAll:SetScript("OnClick", function()
        if silent or not row.questId then return end
        if ns.ToggleChainFollowups then ns.ToggleChainFollowups(row.questId) end
        if ns.RequestRefresh then ns.RequestRefresh("manual") end
    end)
    row.toggleAll:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Toggle all", 1, 0.82, 0)
        local allOn = ns.AllFollowupsIncluded and ns.AllFollowupsIncluded(row.questId)
        if allOn then
            GameTooltip:AddLine("Turns off every later quest in this chain.", 1, 1, 1, true)
        else
            GameTooltip:AddLine("Turns on every later quest in this chain.", 1, 1, 1, true)
        end
        GameTooltip:AddLine("The quest in your log stays as it is.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    row.toggleAll:SetScript("OnLeave", hideQuestTip)
    row.toggleAll:Hide()

    row.name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    clip(row.name)

    row.hit = CreateFrame("Button", nil, row)
    row.hit:SetPoint("TOPLEFT", row.check, "TOPRIGHT", 0, 0)
    row.hit:SetPoint("BOTTOMLEFT", row.check, "BOTTOMRIGHT", 0, 0)
    row.hit:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.hit:SetScript("OnClick", function()
        if silent or not row.questId then return end
        if row.pending and ns.IsIncluded(row.questId) and type(ns.DropQuestLine) == "function" then
            ns.DropQuestLine(row.questId)
            return
        end
        ns.SetIncluded(row.questId, not ns.IsIncluded(row.questId))
        ns.RequestRefresh("manual")
    end)
    row.hit:SetScript("OnEnter", function()
        showQuestTip(row, row.hit)
    end)
    row.hit:SetScript("OnLeave", hideQuestTip)
    return row
end

local function grouped(quests)
    local order, buckets = {}, {}
    for _, quest in ipairs(quests or {}) do
        local zone = quest.zone or "No zone"
        if zone == "" then zone = "No zone" end
        if not buckets[zone] then
            buckets[zone] = {}
            order[#order + 1] = zone
        end
        local list = buckets[zone]
        list[#list + 1] = quest
    end
    table.sort(order, function(a, b)
        if a == b then return false end
        if a == "No zone" then return false end
        if b == "No zone" then return true end
        return a < b
    end)
    local groups = {}
    for _, zone in ipairs(order) do
        local list = buckets[zone]
        table.sort(list, function(a, b)
            local left, right = a.level or 0, b.level or 0
            if left ~= right then return left < right end
            return (a.name or "") < (b.name or "")
        end)
        groups[#groups + 1] = { zone = zone, quests = list }
    end
    return groups
end

local function fillQuests(plan)
    local list = plan and plan.quests or {}
    local groups = grouped(list)
    local y, usedRows, usedHeaders, usedChain = 0, 0, 0, 0
    local child = questScroll.child

    if #list == 0 then
        questEmpty:SetText(plan and "No quests in the log." or (ns.lastErr or ""))
        questEmpty:Show()
        y = 24
    else
        questEmpty:Hide()
    end

    for index, group in ipairs(groups) do
        if index > 1 then y = y + ZONE_GAP end
        usedHeaders = usedHeaders + 1
        local header = questHeaders[usedHeaders]
        if not header then
            header = child:CreateFontString(nil, "ARTWORK", "GameFontNormal")
            header:SetJustifyH("LEFT")
            questHeaders[usedHeaders] = header
        end
        header:ClearAllPoints()
        header:SetPoint("TOPLEFT", child, "TOPLEFT", 4, -y)
        header:SetPoint("RIGHT", child, "RIGHT", -8, 0)
        header:SetText(group.zone)
        header:Show()
        y = y + ZONE_HEADER

        for _, quest in ipairs(group.quests) do
            usedRows = usedRows + 1
            local row = questRows[usedRows]
            if not row then
                row = questRow(child)
                questRows[usedRows] = row
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
            row:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, -y)
            row:Show()
            row.questId = quest.id
            row.pending = quest.pending and true or false
            row.known = quest.known
            row.dungeon = quest.dungeon
            row.tipName = quest.name
            row.objectives = quest.objectives
            row.shade:SetShown(usedRows % 2 == 0)

            local chain = quest.chain
            local opened = chain and chainExpanded(quest.id) or false
            row.chainText = chain and string.format("Chain %d/%d", chain.index, chain.total) or nil
            if chain then
                row.expand:Show()
                paintExpand(row.expand, opened)
                row.chainLabel:SetText(string.format("%d/%d", chain.index, chain.total))
                row.chainLabel:Show()
                if quest.included then
                    row.chainLabel:SetTextColor(1, 0.82, 0)
                else
                    row.chainLabel:SetTextColor(0.45, 0.45, 0.45)
                end
            else
                row.expand:Hide()
                row.chainLabel:SetText("")
                row.chainLabel:Hide()
                openChains[quest.id] = nil
            end

            local hasLater = chain and type(chain.index) == "number" and type(chain.total) == "number" and chain.index < chain.total
            row.name:ClearAllPoints()
            row.name:SetPoint("LEFT", row.check, "RIGHT", 2, 0)
            row.hit:ClearAllPoints()
            row.hit:SetPoint("TOPLEFT", row.check, "TOPRIGHT", 0, 0)
            row.hit:SetPoint("BOTTOMLEFT", row.check, "BOTTOMRIGHT", 0, 0)
            if hasLater then
                row.toggleAll:Show()
                row.name:SetPoint("RIGHT", row.toggleAll, "LEFT", -6, 0)
                row.hit:SetPoint("RIGHT", row.toggleAll, "LEFT", -4, 0)
            elseif chain then
                row.toggleAll:Hide()
                row.name:SetPoint("RIGHT", row.chainLabel, "LEFT", -6, 0)
                row.hit:SetPoint("RIGHT", row.chainLabel, "LEFT", -4, 0)
            else
                row.toggleAll:Hide()
                row.name:SetPoint("RIGHT", row, "RIGHT", -8, 0)
                row.hit:SetPoint("RIGHT", row, "RIGHT", 0, 0)
            end
            local ready = (quest.complete and not quest.pending) and "  |cff40ff40- done -|r" or ""
            local titleColor = quest.pending and CHAIN_ACCEPT or "|cffffffff"
            row.name:SetTextColor(1, 1, 1)
            row.name:SetAlpha(1)
            row.name:SetText(levelPrefix(quest.level, quest.id) .. titleColor .. (quest.name or "Quest") .. "|r" .. ready)
            row.check:SetChecked(quest.included and true or false)
            y = y + ROW_QUEST

            if opened then
                local view = ns.ChainView and ns.ChainView(quest.id)
                for _, member in ipairs(view and view.members or {}) do
                    usedChain = usedChain + 1
                    local childRow = chainRows[usedChain]
                    if not childRow then
                        childRow = chainMemberRow(child)
                        chainRows[usedChain] = childRow
                    end
                    childRow:ClearAllPoints()
                    childRow:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
                    childRow:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, -y)
                    childRow:Show()
                    childRow.logQuestId = quest.id
                    childRow.memberId = member.id
                    childRow.role = member.role
                    childRow.pendingAccept = quest.pending and member.role == "current" or false
                    childRow.parentIncluded = quest.included and true or false
                    childRow.included = member.included and true or false
                    childRow.level = member.level
                    childRow.dungeon = member.dungeon
                    childRow.tipName = member.name
                    local finished = member.role == "past"
                    if not finished and member.role ~= "current" and ns.IsQuestDone and ns.IsQuestDone(member.id) then
                        finished = true
                    end
                    childRow.done = finished
                    childRow.name:SetTextColor(1, 1, 1)
                    childRow.name:SetText(chainMemberText(member, finished, childRow.pendingAccept))
                    if member.role == "current" then
                        childRow.check:Enable()
                        childRow.check:SetChecked(quest.included and true or false)
                        childRow.check:Disable()
                        childRow.check:SetAlpha(1)
                        tintCheck(childRow.check, 1, 1, 1)
                    elseif finished then
                        childRow.check:Disable()
                        childRow.check:SetAlpha(1)
                        tintCheck(childRow.check, 0.55, 0.55, 0.55)
                        childRow.check:SetChecked(true)
                    else
                        childRow.check:Enable()
                        childRow.check:SetAlpha(1)
                        tintCheck(childRow.check, 1, 1, 1)
                        childRow.check:SetChecked(member.included and true or false)
                    end
                    y = y + ROW_CHAIN
                end
            end
        end
    end

    for index = usedHeaders + 1, #questHeaders do questHeaders[index]:Hide() end
    for index = usedRows + 1, #questRows do questRows[index]:Hide() end
    for index = usedChain + 1, #chainRows do chainRows[index]:Hide() end
    fit(questScroll, math.max(y, 1))

    local included = 0
    for _, quest in ipairs(list) do
        if quest.included then included = included + 1 end
    end
    if plan then
        questStatus:SetText(string.format("%d of %d quests in the guide", included, #list))
    else
        questStatus:SetText("")
    end
end

function ns.RenderQuests(plan, err)
    silent = true
    fillQuests(plan)
    if err and err ~= "" and (not plan) then
        questStatus:SetText(err)
    end
    silent = false
end

quests.onPresent = function()
    openChains = {}
    if ns.lastPlan or ns.lastErr then ns.RenderQuests(ns.lastPlan, ns.lastErr) end
    ns.RequestRefresh("draw")
end

questsButton:SetScript("OnClick", function()
    if quests:IsShown() then quests:Hide() else quests:Show() end
end)
bindTip(questsButton, "Quests", "Chooses which quests are in the guide. Toggle all turns every later quest in a chain on or off.")

function ns.ToggleQuests()
    if quests:IsShown() then quests:Hide() else quests:Show() end
end

function ns.Render(plan, err)
    if guide:IsShown() then ns.RenderGuide(plan, err) end
    if quests:IsShown() then ns.RenderQuests(plan, err) end
end

function ns.ToggleOptions()
    if options:IsShown() then options:Hide() else options:Show() end
end

local minimapButton
local minimapMoved = false

function ns.PlaceMinimap()
    if not minimapButton or not Minimap then return end
    local angle = 225
    if ns.ready then
        local saved = ns.CharDB().minimapAngle
        if type(saved) == "number" then angle = saved end
    end
    local radius = (Minimap:GetWidth() / 2) + 8
    local rad = math.rad(angle)
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(rad) * radius, math.sin(rad) * radius)
end

if Minimap then
    minimapButton = CreateFrame("Button", "ClearTheLogMinimapButton", Minimap)
    minimapButton:SetSize(31, 31)
    minimapButton:SetFrameStrata("MEDIUM")
    minimapButton:SetFrameLevel(8)
    minimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    minimapButton:RegisterForClicks("LeftButtonUp")
    minimapButton:RegisterForDrag("LeftButton")

    local overlay = minimapButton:CreateTexture(nil, "OVERLAY")
    overlay:SetSize(53, 53)
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    overlay:SetPoint("TOPLEFT")

    local background = minimapButton:CreateTexture(nil, "BACKGROUND")
    background:SetSize(20, 20)
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetPoint("CENTER")

    local icon = minimapButton:CreateTexture(nil, "ARTWORK")
    icon:SetSize(17, 17)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    icon:SetPoint("CENTER")

    minimapButton:SetScript("OnDragStart", function(self)
        minimapMoved = true
        self:SetScript("OnUpdate", function()
            if not ns.ready or not Minimap then return end
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            px, py = px / scale, py / scale
            ns.CharDB().minimapAngle = math.deg(math.atan2(py - my, px - mx))
            ns.PlaceMinimap()
        end)
    end)
    minimapButton:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)
    minimapButton:SetScript("OnClick", function(_, button)
        if minimapMoved then
            minimapMoved = false
            return
        end
        if button ~= "LeftButton" then return end
        if IsShiftKeyDown and IsShiftKeyDown() then
            if ns.ToggleOptions then ns.ToggleOptions() end
        elseif ns.ToggleGuide then
            ns.ToggleGuide()
        end
    end)
    minimapButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Clear the Log", 1, 0.82, 0)
        GameTooltip:AddLine("Left click: open the guide.", 1, 1, 1, true)
        GameTooltip:AddLine("Shift+Left click: open options.", 1, 1, 1, true)
        GameTooltip:AddLine("Drag to move.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    minimapButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ns.PlaceMinimap()
end
