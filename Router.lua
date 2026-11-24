local _, ns = ...

local OWNER = "ClearTheLog"
local STOP_CAP = 64

-- TomTom gets one arrow. Shortest Path Forever gets the remaining mapped steps
-- as one journey and waits on each stop until we send the next plan, so walking
-- onto a coordinate is not treated as finishing the quest objective.

local function addonLoaded(name)
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        local ok, loaded = pcall(C_AddOns.IsAddOnLoaded, name)
        if ok and loaded then return true end
    end
    if IsAddOnLoaded then
        local ok, loaded = pcall(IsAddOnLoaded, name)
        if ok and loaded then return true end
    end
    return false
end

function ns.TomTomReady()
    if type(TomTom) ~= "table" or type(TomTom.AddWaypoint) ~= "function" then return false end
    if addonLoaded("TomTom") then return true end
    -- Shortest Path publishes a TomTom stand-in when TomTom itself is absent.
    return type(TomTom.db) == "table" or type(TomTom.SetWaypoint) == "function"
end

function ns.SpfReady()
    local api = type(ShortestPathForever) == "table" and ShortestPathForever.API or nil
    if type(api) ~= "table" or type(api.NavigateRoute) ~= "function" then return false end
    if type(api.version) == "number" and (api.version < 1 or api.version > 2) then return false end
    return true
end

function ns.ShouldPushRoute(reasons)
    local db = ns.CharDB()
    if reasons.step or reasons.manual or reasons.router or reasons.abandon then return true end
    if reasons.open and db.router then return true end
    if not db.router then return false end
    if reasons.accept and db.refreshAccept then return true end
    if reasons.turnin and db.refreshTurnin then return true end
    if reasons.objective and db.refreshObjective then return true end
    return false
end

local function stopTitle(stop)
    if stop.questName and stop.text and stop.questName ~= stop.text then
        return stop.questName .. ": " .. stop.text
    end
    return stop.text or stop.questName or "Schritt"
end

local function mappedStops(steps, fromIndex)
    local mapped, skipped = {}, 0
    for index = fromIndex, #steps do
        local stop = steps[index]
        if ns.HasMapPoint(stop) then
            mapped[#mapped + 1] = { index = index, stop = stop }
        else
            skipped = skipped + 1
        end
    end
    return mapped, skipped
end

local function signatureOf(mapped, router)
    local parts = { router }
    local limit = router == "tomtom" and 1 or STOP_CAP
    for index = 1, math.min(#mapped, limit) do
        local stop = mapped[index].stop
        parts[#parts + 1] = string.format(
            "%d:%.4f:%.4f:%s",
            ns.UiMap(stop.areaId),
            ns.MapFraction(stop.x),
            ns.MapFraction(stop.y),
            stop.questId or 0
        )
    end
    return table.concat(parts, "|")
end

local function clearSpf()
    local api = type(ShortestPathForever) == "table" and ShortestPathForever.API or nil
    if type(api) == "table" and type(api.Cancel) == "function" then
        pcall(api.Cancel, OWNER)
    end
end

local function clearTomTom()
    if ns.tomtomUid and type(TomTom) == "table" and type(TomTom.RemoveWaypoint) == "function" then
        pcall(TomTom.RemoveWaypoint, TomTom, ns.tomtomUid)
    end
    ns.tomtomUid = nil
end

local function remember(signature, router)
    ns.lastRouteKey = signature
    ns.lastRouteRouter = router
end

local function pointTomTom(entry)
    local stop = entry.stop
    local title = stopTitle(stop)
    clearTomTom()
    local ok, uid = pcall(TomTom.AddWaypoint, TomTom, ns.UiMap(stop.areaId), ns.MapFraction(stop.x), ns.MapFraction(stop.y), {
        title = title,
        persistent = false,
        minimap = true,
        world = true,
        from = "Clear the Log",
        source = "Clear the Log",
        questID = stop.questId,
        arrivaldistance = 15,
        cleardistance = 0,
    })
    if not ok or uid == nil then return false end
    ns.tomtomUid = uid
    if type(TomTom.SetCrazyArrow) == "function" then
        local arrival = 15
        local profile = TomTom.db and TomTom.db.profile
        local arrow = profile and profile.arrow
        if type(arrow) == "table" and type(arrow.arrival) == "number" then arrival = arrow.arrival end
        pcall(TomTom.SetCrazyArrow, TomTom, uid, arrival, title)
    end
    return true
end

local function spfPayload(mapped, rich)
    local payload = {}
    local limit = math.min(#mapped, STOP_CAP)
    for index = 1, limit do
        local stop = mapped[index].stop
        local point = {
            map = ns.UiMap(stop.areaId),
            x = ns.MapFraction(stop.x),
            y = ns.MapFraction(stop.y),
            title = stopTitle(stop),
        }
        if rich then
            if type(stop.questName) == "string" and stop.questName ~= "" then
                point.tooltip = stop.questName
            end
            point.kind = stop.kind == "turnin" and "turnin" or "objective"
            if type(stop.questId) == "number" then point.questID = stop.questId end
            point.hold = true
        end
        payload[index] = point
    end
    return payload, limit < #mapped
end

local function pointSpf(mapped)
    local api = ShortestPathForever.API
    local payload, truncated = spfPayload(mapped, true)
    local ok, result, why = pcall(api.NavigateRoute, OWNER, payload)
    if not (ok and result == true) then
        payload, truncated = spfPayload(mapped, false)
        ok, result, why = pcall(api.NavigateRoute, OWNER, payload)
    end
    if ok and result == true then return true, truncated, #payload end
    if not ok then return false, truncated, 0, "Shortest Path hat die Route abgelehnt." end
    if type(why) == "string" and why ~= "" then return false, truncated, 0, why end
    return false, truncated, 0, "Shortest Path hat die Route gerade nicht übernommen."
end

local function noteSkipped(text, skipped)
    if skipped <= 0 then return text end
    if skipped == 1 then return text .. " 1 Schritt hat keine Karte." end
    return text .. " " .. skipped .. " Schritte haben keine Karte."
end

function ns.PushRoute(plan, fromIndex, reasons)
    reasons = reasons or {}
    local db = ns.CharDB()
    local steps = plan and plan.steps or {}
    if type(fromIndex) ~= "number" or fromIndex < 1 then fromIndex = 1 end
    if #steps > 0 and fromIndex > #steps then fromIndex = #steps end

    if not db.router then
        if ns.lastRouteRouter then
            clearSpf()
            clearTomTom()
        end
        ns.lastRouteKey = nil
        ns.lastRouteRouter = nil
        ns.activeStep = nil
        ns.routeStatus = nil
        ns.routeStatusError = false
        return
    end

    local mapped, skipped = mappedStops(steps, fromIndex)
    local signature = signatureOf(mapped, db.router)
    local force = reasons.step or reasons.router or reasons.manual
    if not force and signature == ns.lastRouteKey and db.router == ns.lastRouteRouter then return end

    ns.activeStep = #steps > 0 and fromIndex or nil

    if db.router == "tomtom" then
        clearSpf()
        if not ns.TomTomReady() then
            ns.routeStatus = "TomTom ist nicht geladen."
            ns.routeStatusError = true
            ns.lastRouteKey = nil
            ns.lastRouteRouter = nil
            return
        end
        if #mapped == 0 then
            clearTomTom()
            ns.routeStatus = "Kein Schritt mit Koordinaten."
            ns.routeStatusError = true
            remember(signature, db.router)
            return
        end
        if not pointTomTom(mapped[1]) then
            ns.routeStatus = "TomTom hat den Wegpunkt nicht übernommen."
            ns.routeStatusError = true
            ns.lastRouteKey = nil
            ns.lastRouteRouter = nil
            return
        end
        ns.activeStep = mapped[1].index
        ns.routeStatus = noteSkipped("TomTom zeigt Schritt " .. mapped[1].index .. ".", skipped)
        ns.routeStatusError = false
        remember(signature, db.router)
        return
    end

    clearTomTom()
    if not ns.SpfReady() then
        ns.routeStatus = "Shortest Path Forever ist nicht geladen."
        ns.routeStatusError = true
        ns.lastRouteKey = nil
        ns.lastRouteRouter = nil
        return
    end
    if #mapped == 0 then
        clearSpf()
        ns.routeStatus = "Kein Schritt mit Koordinaten."
        ns.routeStatusError = true
        remember(signature, db.router)
        return
    end

    local accepted, truncated, count, why = pointSpf(mapped)
    if not accepted then
        ns.routeStatus = why
        ns.routeStatusError = true
        ns.lastRouteKey = nil
        ns.lastRouteRouter = nil
        return
    end
    ns.activeStep = mapped[1].index
    local text = truncated and "Shortest Path führt die ersten 64 Stopps."
        or ("Shortest Path führt " .. count .. (count == 1 and " Stopp." or " Stopps."))
    ns.routeStatus = noteSkipped(text, skipped)
    ns.routeStatusError = false
    remember(signature, db.router)
end
