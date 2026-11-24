local _, ns = ...

local ROW_QUEST = 32
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

local function texCoord(region, left, right, top, bottom)
    if region then region:SetTexCoord(left, right, top, bottom) end
end

local function styleRadio(radio)
    radio:SetNormalTexture("Interface\\Buttons\\UI-RadioButton")
    texCoord(radio:GetNormalTexture(), 0, 0.25, 0, 1)
    radio:SetCheckedTexture("Interface\\Buttons\\UI-RadioButton")
    texCoord(radio:GetCheckedTexture(), 0.25, 0.5, 0, 1)
    radio:SetHighlightTexture("Interface\\Buttons\\UI-RadioButton", "ADD")
    texCoord(radio:GetHighlightTexture(), 0.5, 0.75, 0, 1)
    radio:SetPushedTexture("Interface\\Buttons\\UI-RadioButton")
    texCoord(radio:GetPushedTexture(), 0, 0.25, 0, 1)
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

local options = chrome("ClearTheLogOptions", 480, 484, "posOptions", -260, 40, nil, {
    minW = 440, minH = 460, sizeKey = "sizeOptions",
})
options.title:SetText(ns.TITLE)
options.subtitle:SetText("/ctl")
ns.options = options

section(options, "Routing", -46)

local radios = {}
local routerStatus = options:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")

local function chooseRouter(value)
    if silent or not ns.ready then return end
    local stored = (value == "tomtom" or value == "spf") and value or nil
    ns.CharDB().router = stored
    ns.PaintOptions()
    ns.RequestRefresh("router")
end

local function addRadio(text, value, y, tipTitle, tipBody)
    local radio = CreateFrame("CheckButton", nil, options)
    radio:SetSize(24, 24)
    radio:SetPoint("TOPLEFT", 24, y)
    styleRadio(radio)
    radio.value = value
    local label = options:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("LEFT", radio, "RIGHT", 4, 0)
    label:SetText(text)
    local hit = CreateFrame("Button", nil, options)
    hit:SetPoint("TOPLEFT", radio, "TOPRIGHT", 2, 0)
    hit:SetSize(300, 24)
    radio:SetScript("OnClick", function()
        if silent then return end
        chooseRouter(value)
    end)
    hit:SetScript("OnClick", function()
        if silent then return end
        chooseRouter(value)
    end)
    bindTip(radio, tipTitle, tipBody)
    bindTip(hit, tipTitle, tipBody)
    radios[#radios + 1] = radio
    return radio
end

addRadio("Keins", "none", -70, "Kein Routing", "Der Guide zeigt die Schritte, setzt aber keinen Wegpunkt.")
addRadio("TomTom", "tomtom", -96, "TomTom", "Wegpunkte für die nächsten 5 Schritte. Der Pfeil zeigt auf den ersten.")
addRadio("Shortest Path Forever", "spf", -122, "Shortest Path Forever", "Die nächsten 5 Schritte werden als eine Reise geplant, inklusive Flug, Boot und Portal.")

local routerHint = options:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
routerHint:SetPoint("TOPLEFT", 28, -154)
routerHint:SetPoint("RIGHT", options, "RIGHT", -28, 0)
routerHint:SetJustifyH("LEFT")
routerHint:SetWordWrap(true)
routerHint:SetText("TomTom und Shortest Path bekommen Wegpunkte für die nächsten 5 Schritte. Nur eins von beiden, oder keins.")

routerStatus:SetPoint("TOPLEFT", 28, -198)
routerStatus:SetPoint("RIGHT", options, "RIGHT", -28, 0)
routerStatus:SetJustifyH("LEFT")

section(options, "Route automatisch aktualisieren", -226)

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

addToggle("Nach Annahme einer neuen Quest", -250, "refreshAccept", "Nach dem Annehmen", "Der Wegpunkt wird neu gesetzt, wenn du eine Quest annimmst.")
addToggle("Nach Abgabe einer Quest", -276, "refreshTurnin", "Nach der Abgabe", "Der Wegpunkt wird neu gesetzt, wenn du eine Quest abgibst.")
addToggle("Nach Erfüllen einer Questaufgabe", -302, "refreshObjective", "Nach einem Ziel", "Der Wegpunkt rückt vor, wenn ein Ziel fertig wird. Quests mit mehreren Zielen gehen Schritt für Schritt weiter.")

section(options, "Neue Quests", -336)

addToggle("Automatisch in den Guide aufnehmen", -360, "autoTrack", "Automatisch aufnehmen", "Eine Quest, die du neu annimmst, kommt sofort in den Guide.")
addToggle("Questreihe automatisch berücksichtigen", -386, "autoChain", "Reihe automatisch", "Für eine neu angenommene Quest wird die Folgequest mitgeplant.")

local guideButton = CreateFrame("Button", nil, options, "UIPanelButtonTemplate")
guideButton:SetSize(170, 24)
guideButton:SetPoint("BOTTOMLEFT", 24, 18)
guideButton:SetText("Guide anzeigen")
bindTip(guideButton, "Guide", "Öffnet oder schließt das Route-Fenster. Gleicher Befehl: /ctl route.")

local function paintGuideButton()
    local shown = ns.guide and ns.guide:IsShown()
    guideButton:SetText(shown and "Guide schließen" or "Guide anzeigen")
end

guideButton:SetScript("OnClick", function()
    if ns.ToggleGuide then ns.ToggleGuide() end
    paintGuideButton()
end)

function ns.PaintOptions()
    if not options then return end
    silent = true
    local db = ns.ready and ns.CharDB() or {}
    local router = db.router or "none"
    for _, radio in ipairs(radios) do
        radio:SetChecked(radio.value == router)
    end
    for field, box in pairs(optionBoxes) do
        box:SetChecked(db[field] and true or false)
    end
    local missing
    if router == "tomtom" and not ns.TomTomReady() then
        missing = "TomTom ist nicht geladen."
    elseif router == "spf" and not ns.SpfReady() then
        missing = "Shortest Path Forever ist nicht geladen."
    end
    routerStatus:SetText(missing or "")
    if missing then
        routerStatus:SetTextColor(1, 0.35, 0.35)
    end
    paintGuideButton()
    silent = false
end

options.onPresent = function()
    ns.PaintOptions()
end

local guide = chrome("ClearTheLogGuide", 440, 580, "pos", 180, 0, 124, {
    minW = 380, minH = 320, sizeKey = "sizeGuide",
})
guide.title:SetText("Route")
guide.subtitle:SetText("/ctl route")
ns.guide = guide

local questsButton = CreateFrame("Button", nil, guide, "UIPanelButtonTemplate")
questsButton:SetSize(80, 22)
questsButton:SetPoint("TOPRIGHT", -36, -12)
questsButton:SetText("Quests")
guide.subtitle:SetPoint("RIGHT", questsButton, "LEFT", -8, 0)

local stepScroll = scroller(guide, "ClearTheLogStepScroll", 16, -48, -34, 100)
local stepRows = {}

local summary = guide:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
summary:SetPoint("BOTTOMLEFT", 24, 78)
summary:SetPoint("RIGHT", guide, "RIGHT", -28, 0)
summary:SetJustifyH("LEFT")
clip(summary)

local routeLine = guide:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
routeLine:SetPoint("BOTTOMLEFT", 24, 62)
routeLine:SetPoint("RIGHT", guide, "RIGHT", -28, 0)
routeLine:SetJustifyH("LEFT")
clip(routeLine)

local warning = guide:CreateFontString(nil, "ARTWORK", "GameFontRedSmall")
warning:SetPoint("BOTTOMLEFT", 24, 46)
warning:SetPoint("RIGHT", guide, "RIGHT", -28, 0)
warning:SetJustifyH("LEFT")
clip(warning)

local refreshButton = CreateFrame("Button", nil, guide, "UIPanelButtonTemplate")
refreshButton:SetSize(170, 22)
refreshButton:SetPoint("BOTTOMLEFT", 16, 12)
refreshButton:SetText("Plan neu berechnen")
refreshButton:SetScript("OnClick", function()
    if ns.RefreshPlan then ns.RefreshPlan() end
end)
bindTip(refreshButton, "Plan neu berechnen", "Berechnet die Schritte vom aktuellen Ort neu und setzt die Route.")

local function stepRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_STEP)
    row:EnableMouse(true)

    row.current = row:CreateTexture(nil, "BACKGROUND")
    row.current:SetAllPoints()
    row.current:SetColorTexture(0.9, 0.75, 0.2, 0.18)
    row.current:Hide()

    row.hover = row:CreateTexture(nil, "BORDER")
    row.hover:SetAllPoints()
    row.hover:SetColorTexture(1, 1, 1, 0.05)
    row.hover:Hide()

    row.action = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.action:SetSize(118, 20)
    row.action:SetPoint("RIGHT", -4, 0)
    row.action:Hide()
    row.action:SetScript("OnClick", function()
        if silent or not row.index or not row.stop then return end
        if row.stop.skipped then
            if ns.UndoSkip then ns.UndoSkip(row.index) end
        elseif ns.SkipStep then
            ns.SkipStep(row.index)
        end
    end)
    row.action:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if row.stop and row.stop.skipped then
            GameTooltip:SetText("Rückgängig", 1, 0.82, 0)
            GameTooltip:AddLine("Nimmt das Überspringen zurück und berechnet den Plan vom aktuellen Ort neu.", 1, 1, 1, true)
        else
            GameTooltip:SetText("Überspringen", 1, 0.82, 0)
            GameTooltip:AddLine("Setzt diesen Schritt ans Ende des Plans.", 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    row.action:SetScript("OnLeave", function() GameTooltip:Hide() end)

    row.line = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.line:SetPoint("TOPLEFT", 8, -4)
    row.line:SetPoint("RIGHT", row, "RIGHT", -128, 0)
    clip(row.line)

    row.sub = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    row.sub:SetPoint("TOPLEFT", row.line, "BOTTOMLEFT", 16, -2)
    row.sub:SetPoint("RIGHT", row, "RIGHT", -128, 0)
    clip(row.sub)

    row:SetScript("OnEnter", function()
        row.hover:Show()
        if not row.stop then return end
        local stop = row.stop
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:SetText(stop.questName or "Schritt", 1, 0.82, 0)
        if stop.text then GameTooltip:AddLine(stop.text, 1, 1, 1, true) end
        if stop.note and stop.note ~= "" then GameTooltip:AddLine(stop.note, 0.8, 0.8, 0.8, true) end
        local db = ns.ready and ns.CharDB() or {}
        if db.router then
            GameTooltip:AddLine("Linksklick setzt die Route auf diesen Schritt.", 0.7, 0.7, 0.7, true)
        else
            GameTooltip:AddLine("Unter /ctl ein Routing wählen. Ein Klick setzt dann die Route.", 0.7, 0.7, 0.7, true)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function()
        row.hover:Hide()
        GameTooltip:Hide()
    end)
    row:SetScript("OnMouseUp", function(_, button)
        if silent or button ~= "LeftButton" or not row.index then return end
        ns.RouteFrom(row.index)
    end)
    return row
end

local function placeRows(scroll, rows, count, factory, height)
    for index = #rows + 1, count do
        rows[index] = factory(scroll.child)
    end
    for index = 1, count do
        local row = rows[index]
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", scroll.child, "TOPLEFT", 0, -((index - 1) * height))
        row:SetPoint("TOPRIGHT", scroll.child, "TOPRIGHT", 0, -((index - 1) * height))
        row:Show()
    end
    for index = count + 1, #rows do rows[index]:Hide() end
    fit(scroll, math.max(count * height, 1))
end

local function coordText(stop)
    if type(stop.x) ~= "number" or type(stop.y) ~= "number" then return nil end
    return string.format("%.0f, %.0f", stop.x, stop.y)
end

local function fillSteps(steps)
    local list = steps or {}
    local indexes = ns.VisibleStepIndexes and ns.VisibleStepIndexes(list) or {}
    if #list == 0 or #indexes == 0 then
        placeRows(stepScroll, stepRows, 1, stepRow, ROW_STEP)
        local row = stepRows[1]
        row.index = nil
        row.stop = nil
        row.current:Hide()
        row.action:Hide()
        row.line:SetText("Keine Schritte. Der Log ist leer, oder keine Quest ist im Guide.")
        row.line:SetTextColor(0.7, 0.7, 0.7)
        row.sub:SetText("")
        return 0
    end

    local focus = ns.activeStep
    if type(focus) ~= "number" or not list[focus] then focus = indexes[1] end
    local current = indexes[1]
    placeRows(stepScroll, stepRows, #indexes, stepRow, ROW_STEP)
    for rowIndex, index in ipairs(indexes) do
        local stop = list[index]
        local row = stepRows[rowIndex]
        row.index = index
        row.stop = stop
        row.hover:Hide()
        row.current:SetShown(index == focus)
        if stop.skipped then
            row.action:SetText("Rückgängig")
            row.action:Show()
        elseif index == current then
            row.action:SetText("Überspringen")
            row.action:Show()
        else
            row.action:Hide()
        end
        local tag = stop.kind == "turnin" and "Abgabe" or "Ziel"
        if stop.followup then tag = tag .. " · Folgequest" end
        local mark = stop.dungeon and "|cffffcc00D|r  " or ""
        row.line:SetText(string.format("%d.  %s%s: %s", index, mark, tag, stop.text or ""))
        if stop.skipped then
            row.line:SetTextColor(0.55, 0.55, 0.55)
        elseif index == focus then
            row.line:SetTextColor(1, 0.82, 0)
        elseif stop.followup then
            row.line:SetTextColor(0.95, 0.8, 0.45)
        elseif stop.kind == "turnin" then
            row.line:SetTextColor(0.55, 1, 0.65)
        else
            row.line:SetTextColor(1, 1, 1)
        end

        local bits = {}
        local place = ns.ZoneName and ns.ZoneName(stop.areaId) or nil
        if place and place ~= "" then bits[#bits + 1] = place end
        local coord = coordText(stop)
        if coord then bits[#bits + 1] = coord end
        if stop.questName and stop.questName ~= "" then bits[#bits + 1] = stop.questName end
        if stop.note and stop.note ~= "" then bits[#bits + 1] = stop.note end
        if stop.skipped then bits[#bits + 1] = "übersprungen" end
        if ns.DBReady and ns.DBReady() and not ns.HasMapPoint(stop) then
            bits[#bits + 1] = "ohne Karte"
        end
        row.sub:SetText(table.concat(bits, "   ·   "))
    end
    return #indexes
end

local function routeSentence()
    local db = ns.ready and ns.CharDB() or {}
    if not db.router then
        return "Kein Routing. Unter /ctl TomTom oder Shortest Path wählen.", false
    end
    if ns.routeStatus and ns.routeStatus ~= "" then
        return ns.routeStatus, ns.routeStatusError and true or false
    end
    if db.router == "tomtom" and not ns.TomTomReady() then
        return "TomTom ist nicht geladen.", true
    end
    if db.router == "spf" and not ns.SpfReady() then
        return "Shortest Path Forever ist nicht geladen.", true
    end
    return "Die Route wird beim nächsten Anlass gesetzt.", false
end

function ns.RenderGuide(plan, err)
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
    summary:SetText(string.format(
        "%d von %d Schritten · %d von %d Quests im Guide",
        shown, #(plan.steps or {}), included, #(plan.quests or {})
    ))
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

guide.onPresent = function()
    if ns.lastPlan then ns.RenderGuide(ns.lastPlan, ns.lastErr) end
    ns.RequestRefresh("open")
    paintGuideButton()
end
guide:SetScript("OnHide", paintGuideButton)

function ns.ToggleGuide()
    if guide:IsShown() then guide:Hide() else guide:Show() end
end

local quests = chrome("ClearTheLogQuests", 500, 540, "posQuests", 0, -10, nil, {
    minW = 400, minH = 280, sizeKey = "sizeQuests",
})
quests.title:SetText("Quests")
quests.subtitle:SetText("Log")
ns.quests = quests

local questHint = quests:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
questHint:SetPoint("TOPLEFT", 24, -46)
questHint:SetPoint("RIGHT", quests, "RIGHT", -24, 0)
questHint:SetJustifyH("LEFT")
questHint:SetWordWrap(true)
questHint:SetText("Haken links: die Quest steht im Guide. Reihe plant die Folgequest mit und erscheint nur bei einer aktiven Quest.")

local questScroll = scroller(quests, "ClearTheLogQuestScroll", 16, -78, -34, 36)
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

local function questRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_QUEST)

    row.shade = row:CreateTexture(nil, "BACKGROUND")
    row.shade:SetAllPoints()
    row.shade:SetColorTexture(1, 1, 1, 0.04)

    row.check = CreateFrame("CheckButton", nil, row)
    row.check:SetSize(24, 24)
    row.check:SetPoint("LEFT", 2, 0)
    styleCheck(row.check)
    row.check:SetScript("OnClick", function(self)
        if silent or not row.questId then return end
        ns.SetIncluded(row.questId, self:GetChecked() and true or false)
        ns.RequestRefresh("manual")
    end)
    row.check:SetScript("OnEnter", function(self)
        if not row.questId then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(row.tipName or "Quest", 1, 1, 1)
        GameTooltip:AddLine("Quest-ID " .. row.questId, 0.7, 0.7, 0.7)
        if row.known == false then GameTooltip:AddLine("Nicht in QuestieDB.", 0.8, 0.8, 0.8) end
        if row.dungeon then GameTooltip:AddLine("Dungeon", 1, 0.82, 0) end
        GameTooltip:AddLine("Im Guide führen.", 1, 0.82, 0)
        GameTooltip:Show()
    end)
    row.check:SetScript("OnLeave", function() GameTooltip:Hide() end)

    row.chain = CreateFrame("CheckButton", nil, row)
    row.chain:SetSize(24, 24)
    styleCheck(row.chain)
    row.chainLabel = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.chainLabel:SetPoint("RIGHT", -4, 0)
    row.chainLabel:SetText("Reihe")
    row.chain:SetPoint("RIGHT", row.chainLabel, "LEFT", -2, 0)
    row.chain:SetScript("OnClick", function(self)
        if silent or not row.questId or not row.hasChain then return end
        ns.SetChainEnabled(row.questId, self:GetChecked() and true or false)
        ns.RequestRefresh("manual")
    end)
    row.chain:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if row.hasChain then
            GameTooltip:SetText("Reihe", 1, 0.82, 0)
            GameTooltip:AddLine("Die Folgequest wird mitgeplant, auch wenn sie noch nicht im Log ist.", 1, 1, 1, true)
        else
            GameTooltip:SetText("Keine Reihe", 1, 0.82, 0)
            GameTooltip:AddLine("Für diese Quest ist keine Folgequest bekannt.", 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    row.chain:SetScript("OnLeave", function() GameTooltip:Hide() end)

    row.name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    clip(row.name)

    row.hit = CreateFrame("Button", nil, row)
    row.hit:SetPoint("TOPLEFT", row.check, "TOPRIGHT", 0, 0)
    row.hit:SetPoint("BOTTOMLEFT", row.check, "BOTTOMRIGHT", 0, 0)
    row.hit:SetPoint("RIGHT", row.chain, "LEFT", -4, 0)
    row.hit:SetScript("OnClick", function()
        if silent or not row.questId then return end
        ns.SetIncluded(row.questId, not ns.IsIncluded(row.questId))
        ns.RequestRefresh("manual")
    end)
    row.hit:SetScript("OnEnter", function()
        row.check:GetScript("OnEnter")(row.check)
    end)
    row.hit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

local function grouped(quests)
    local order, buckets = {}, {}
    for _, quest in ipairs(quests or {}) do
        local zone = quest.zone or "Ohne Gebiet"
        if zone == "" then zone = "Ohne Gebiet" end
        if not buckets[zone] then
            buckets[zone] = {}
            order[#order + 1] = zone
        end
        local list = buckets[zone]
        list[#list + 1] = quest
    end
    table.sort(order, function(a, b)
        if a == b then return false end
        if a == "Ohne Gebiet" then return false end
        if b == "Ohne Gebiet" then return true end
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
    local y, usedRows, usedHeaders = 0, 0, 0
    local child = questScroll.child

    if #list == 0 then
        questEmpty:SetText(plan and "Keine Quests im Log." or (ns.lastErr or ""))
        questEmpty:Show()
        y = 24
    else
        questEmpty:Hide()
    end

    for _, group in ipairs(groups) do
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
        y = y + 22

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
            row.hasChain = quest.chain ~= nil
            row.known = quest.known
            row.dungeon = quest.dungeon
            row.tipName = quest.name
            row.shade:SetShown(usedRows % 2 == 0)

            local showChain = quest.included and true or false
            if showChain then
                row.chain:Show()
                row.chainLabel:Show()
                if row.hasChain then row.chain:Enable() else row.chain:Disable() end
                row.chain:SetChecked(row.hasChain and quest.chainEnabled and true or false)
                if row.hasChain then
                    row.chainLabel:SetTextColor(1, 0.82, 0)
                else
                    row.chainLabel:SetTextColor(0.5, 0.5, 0.5)
                end
            else
                row.chain:Hide()
                row.chainLabel:Hide()
            end

            row.name:ClearAllPoints()
            row.name:SetPoint("LEFT", row.check, "RIGHT", 2, 0)
            row.hit:ClearAllPoints()
            row.hit:SetPoint("TOPLEFT", row.check, "TOPRIGHT", 0, 0)
            row.hit:SetPoint("BOTTOMLEFT", row.check, "BOTTOMRIGHT", 0, 0)
            if showChain then
                row.name:SetPoint("RIGHT", row.chain, "LEFT", -6, 0)
                row.hit:SetPoint("RIGHT", row.chain, "LEFT", -4, 0)
            else
                row.name:SetPoint("RIGHT", row, "RIGHT", -8, 0)
                row.hit:SetPoint("RIGHT", row, "RIGHT", -4, 0)
            end
            local level = (quest.level and quest.level > 0) and ("[" .. quest.level .. "] ") or ""
            local done = quest.complete and "|cff40ff40fertig|r  " or ""
            local mark = quest.dungeon and "|cffffcc00D|r  " or ""
            row.name:SetText(done .. mark .. level .. (quest.name or "Quest"))
            row.name:SetAlpha(quest.included and 1 or 0.45)
            row.check:SetChecked(quest.included and true or false)
            y = y + ROW_QUEST
        end
    end

    for index = usedHeaders + 1, #questHeaders do questHeaders[index]:Hide() end
    for index = usedRows + 1, #questRows do questRows[index]:Hide() end
    fit(questScroll, math.max(y, 1))

    local included = 0
    for _, quest in ipairs(list) do
        if quest.included then included = included + 1 end
    end
    if plan then
        questStatus:SetText(string.format("%d von %d Quests im Guide", included, #list))
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
    if ns.lastPlan or ns.lastErr then ns.RenderQuests(ns.lastPlan, ns.lastErr) end
    ns.RequestRefresh("draw")
end

questsButton:SetScript("OnClick", function()
    if quests:IsShown() then quests:Hide() else quests:Show() end
end)
bindTip(questsButton, "Quests", "Wählt, welche Quests im Guide stehen und wo die Reihe mitgeplant wird.")

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
