local _, ns = ...

local ROW_QUEST = 42
local ROW_STEP = 36

local frame = CreateFrame("Frame", "ClearTheLogFrame", UIParent, "BackdropTemplate")
frame:SetSize(580, 660)
frame:SetPoint("CENTER")
frame:SetFrameStrata("DIALOG")
frame:SetClampedToScreen(true)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
})
frame:Hide()
tinsert(UISpecialFrames, "ClearTheLogFrame")
ns.window = frame

local titleBar = CreateFrame("Frame", nil, frame)
titleBar:SetPoint("TOPLEFT", 16, -10)
titleBar:SetPoint("TOPRIGHT", -36, -10)
titleBar:SetHeight(28)
titleBar:EnableMouse(true)
titleBar:RegisterForDrag("LeftButton")
titleBar:SetScript("OnDragStart", function() frame:StartMoving() end)
titleBar:SetScript("OnDragStop", function()
    frame:StopMovingOrSizing()
    if not ns.ready then return end
    local point, _, relative, x, y = frame:GetPoint(1)
    ns.CharDB().pos = { point, relative, x, y }
end)

local title = titleBar:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("LEFT", 8, 0)
title:SetText(ns.TITLE)

local subtitle = titleBar:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
subtitle:SetPoint("LEFT", title, "RIGHT", 10, -1)
subtitle:SetText("/ctl")

local close = CreateFrame("Button", "ClearTheLogClose", frame, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", -4, -4)

local serial = 0
local function widgetName(kind)
    serial = serial + 1
    return "ClearTheLog" .. kind .. serial
end

local function modeButton(text, mode, x)
    local button = CreateFrame("Button", widgetName("Mode"), frame, "UIPanelButtonTemplate")
    button:SetSize(120, 22)
    button:SetPoint("TOPLEFT", x, -46)
    button:SetText(text)
    button.mode = mode
    button:SetScript("OnClick", function()
        if not ns.ready then return end
        ns.CharDB().mode = mode
        ns.Refresh()
    end)
    return button
end

local ignoreButton = modeButton("Ignorieren", "ignore", 24)
local selectButton = modeButton("Auswählen", "select", 150)

local hint = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
hint:SetPoint("TOPLEFT", 24, -74)
hint:SetPoint("RIGHT", frame, "RIGHT", -24, 0)
hint:SetJustifyH("LEFT")
hint:SetText("Haken bedeutet: diese Quest kommt in die Route.")

local function sectionLabel(text, y)
    local label = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("TOPLEFT", 24, y)
    label:SetText(text)
    return label
end

sectionLabel("Questlog", -98)

local routeLabel = sectionLabel("Route", -332)
local routeHint = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
routeHint:SetPoint("LEFT", routeLabel, "RIGHT", 8, 0)
routeHint:SetPoint("RIGHT", frame, "RIGHT", -24, 0)
routeHint:SetJustifyH("LEFT")
routeHint:SetText("Folgequest schiebt die Abgabe vor das Gebiet, in das sie dich schickt.")

local warning = frame:CreateFontString(nil, "ARTWORK", "GameFontRedSmall")
warning:SetPoint("BOTTOMLEFT", 24, 16)
warning:SetPoint("RIGHT", frame, "RIGHT", -24, 0)
warning:SetJustifyH("LEFT")
warning:SetText("")

local status = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
status:SetPoint("BOTTOMLEFT", 24, 32)
status:SetPoint("RIGHT", frame, "RIGHT", -24, 0)
status:SetJustifyH("LEFT")

local function scroller(name, yTop, yBottom)
    local scroll = CreateFrame("ScrollFrame", name, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 20, yTop)
    scroll:SetPoint("BOTTOMRIGHT", -32, yBottom)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(500, 1)
    scroll:SetScrollChild(child)
    scroll.child = child
    scroll.rows = {}
    return scroll
end

local questScroll = scroller("ClearTheLogQuestScroll", -118, 348)
local stepScroll = scroller("ClearTheLogStepScroll", -354, 48)

local rendering = false

local function paintMode()
    local mode = ns.ready and ns.CharDB().mode or "ignore"
    local function paint(button)
        local font = button:GetFontString()
        if not font then return end
        if button.mode == mode then
            font:SetTextColor(1, 0.82, 0)
        else
            font:SetTextColor(0.75, 0.75, 0.75)
        end
    end
    paint(ignoreButton)
    paint(selectButton)
    if mode == "select" then
        hint:SetText("Nur Quests mit Haken kommen in die Route.")
    else
        hint:SetText("Haken bedeutet: diese Quest kommt in die Route. Haken weg lässt sie liegen.")
    end
end

local function questRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_QUEST)

    row.shade = row:CreateTexture(nil, "BACKGROUND")
    row.shade:SetAllPoints()
    row.shade:SetColorTexture(1, 1, 1, 0.04)

    row.check = CreateFrame("CheckButton", widgetName("Check"), row)
    row.check:SetSize(26, 26)
    row.check:SetPoint("LEFT", 2, 0)
    row.check:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    row.check:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
    row.check:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight")
    row.check:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    row.check:SetScript("OnClick", function(self)
        if rendering or not row.questId then return end
        ns.SetIncluded(row.questId, self:GetChecked())
        ns.Refresh()
    end)

    row.name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.name:SetPoint("LEFT", row.check, "RIGHT", 0, 7)
    row.name:SetPoint("RIGHT", row, "RIGHT", -108, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row.meta = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    row.meta:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -1)
    row.meta:SetPoint("RIGHT", row.name, "RIGHT", 0, 0)
    row.meta:SetJustifyH("LEFT")
    row.meta:SetWordWrap(false)

    row.chain = CreateFrame("Button", widgetName("Chain"), row, "UIPanelButtonTemplate")
    row.chain:SetSize(100, 22)
    row.chain:SetPoint("RIGHT", -2, 0)
    row.chain:SetScript("OnClick", function()
        if rendering or not row.questId or not row.hasChain then return end
        ns.SetChainEnabled(row.questId, not ns.ChainEnabled(row.questId))
        ns.Refresh()
    end)
    row.chain:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Kette in die Route einrechnen", 1, 0.82, 0)
        GameTooltip:AddLine("An: die nächste Quest der Reihe wird mitgeplant, auch wenn sie noch nicht im Log ist.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    row.chain:SetScript("OnLeave", function() GameTooltip:Hide() end)

    row.check:SetScript("OnEnter", function(self)
        if not row.questId then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(row.tipName or "Quest", 1, 1, 1)
        GameTooltip:AddLine("Quest-ID " .. row.questId, 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    row.check:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

local function stepRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_STEP)
    row.line = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.line:SetPoint("TOPLEFT", 4, -2)
    row.line:SetPoint("RIGHT", -4, 0)
    row.line:SetJustifyH("LEFT")
    row.line:SetWordWrap(false)
    row.sub = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    row.sub:SetPoint("TOPLEFT", row.line, "BOTTOMLEFT", 12, -1)
    row.sub:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.sub:SetJustifyH("LEFT")
    row.sub:SetWordWrap(false)
    return row
end

local function ensure(scroll, count, factory, height)
    local rows = scroll.rows
    for index = #rows + 1, count do
        rows[index] = factory(scroll.child)
    end
    local width = scroll:GetWidth()
    if width < 80 then width = 500 end
    scroll.child:SetWidth(width)
    for index = 1, count do
        local row = rows[index]
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", scroll.child, "TOPLEFT", 0, -((index - 1) * height))
        row:SetPoint("TOPRIGHT", scroll.child, "TOPRIGHT", 0, -((index - 1) * height))
        row:Show()
    end
    for index = count + 1, #rows do rows[index]:Hide() end
    local content = math.max(count * height, scroll:GetHeight() or 0)
    scroll.child:SetHeight(math.max(content, 1))
    local maxScroll = math.max(0, scroll.child:GetHeight() - (scroll:GetHeight() or 0))
    if scroll:GetVerticalScroll() > maxScroll then scroll:SetVerticalScroll(maxScroll) end
end

local function coordText(stop)
    if type(stop.x) ~= "number" or type(stop.y) ~= "number" then return nil end
    return string.format("%.0f, %.0f", stop.x, stop.y)
end

local function fillQuests(quests)
    local list = quests or {}
    ensure(questScroll, #list, questRow, ROW_QUEST)
    for index, quest in ipairs(list) do
        local row = questScroll.rows[index]
        row.questId = quest.id
        row.hasChain = quest.chain ~= nil
        row.tipName = quest.name
        row.shade:SetShown(index % 2 == 0)
        row.check:SetChecked(quest.included)
        local level = (quest.level and quest.level > 0) and ("[" .. quest.level .. "] ") or ""
        local done = quest.complete and "|cff40ff40fertig|r  " or ""
        row.name:SetText(done .. level .. (quest.name or "Quest"))
        row.name:SetAlpha(quest.included and 1 or 0.45)

        local meta = ns.ChainLabel(quest.chain)
        if not meta and not quest.known then meta = "nicht in QuestieDB" end
        row.meta:SetText(meta or "")

        if quest.chain then
            row.chain:Enable()
            row.chain:SetText(quest.chainEnabled and "Kette: an" or "Kette: aus")
        else
            row.chain:Disable()
            row.chain:SetText("keine Reihe")
        end
    end
end

local function fillSteps(steps)
    local list = steps or {}
    if #list == 0 then
        ensure(stepScroll, 1, stepRow, ROW_STEP)
        local row = stepScroll.rows[1]
        row.line:SetText("Keine Schritte. Der Log ist leer, oder keine Quest ist angehakt.")
        row.line:SetTextColor(0.7, 0.7, 0.7)
        row.sub:SetText("")
        return
    end

    ensure(stepScroll, #list, stepRow, ROW_STEP)
    for index, stop in ipairs(list) do
        local row = stepScroll.rows[index]
        local place = ns.ZoneName and ns.ZoneName(stop.areaId) or "Ohne Gebiet"
        local coord = coordText(stop)
        if coord then place = place .. "  " .. coord end
        local tag = stop.kind == "turnin" and "Abgabe" or "Ziel"
        if stop.followup then tag = tag .. " · Folgequest" end
        row.line:SetText(string.format("%d.  %s   %s: %s", index, place, tag, stop.text or ""))
        if stop.followup then
            row.line:SetTextColor(1, 0.82, 0)
        elseif stop.kind == "turnin" then
            row.line:SetTextColor(0.55, 1, 0.65)
        else
            row.line:SetTextColor(1, 1, 1)
        end
        local sub = stop.questName or ""
        if stop.note and stop.note ~= "" then
            sub = sub == "" and stop.note or (sub .. "  ·  " .. stop.note)
        end
        row.sub:SetText(sub)
    end
end

function ns.Render(plan, err)
    rendering = true
    paintMode()
    if not plan then
        fillQuests({})
        fillSteps({})
        status:SetText("")
        warning:SetText(err or "")
        rendering = false
        return
    end

    fillQuests(plan.quests)
    fillSteps(plan.steps)

    local included = 0
    for _, quest in ipairs(plan.quests) do
        if quest.included then included = included + 1 end
    end
    local modeText = plan.mode == "select" and "Auswählen" or "Ignorieren"
    status:SetText(string.format(
        "%d Schritte · %d von %d Quests im Plan · %s",
        #(plan.steps or {}), included, #(plan.quests or {}), modeText
    ))
    warning:SetText(plan.warning or err or "")
    rendering = false
end

local placed = false
frame:SetScript("OnShow", function()
    if not placed and ns.ready then
        local pos = ns.CharDB().pos
        if type(pos) == "table" and pos[1] and pos[2] then
            frame:ClearAllPoints()
            frame:SetPoint(pos[1], UIParent, pos[2], pos[3] or 0, pos[4] or 0)
        end
        placed = true
    end
    ns.Refresh()
end)

function ns.Toggle()
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
    end
end
