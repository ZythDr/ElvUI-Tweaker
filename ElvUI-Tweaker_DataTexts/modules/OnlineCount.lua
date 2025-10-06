-- OnlineCount.lua
-- DataTexts submodule: "Online Count"
-- Optimized WHO polling with proven ghost-frame prevention.
-- Uses simplified frame hiding approach that successfully prevents UI stack contamination.

local core = EWTweaker and EWTweaker.GetCore and EWTweaker.GetCore()
if not core then return end
local MOD = core.modules and core.modules.DataTexts
if not MOD then return end

local SUB = { name = "Online Count" }
SUB.defaults = {
    enabled = true,
    updateInterval = 60, -- seconds
    manualClickCooldown = 10,
    preferLibWhoOnly = false,
    debug = false,
}

local db_local

local E, L, V, P, G = unpack(ElvUI)
local DT = E:GetModule("DataTexts")
local REG_NAME = "Online Count"
local displayName = "|cff00FF96Online|r"
local valueColor = E.media.hexvaluecolor or "|cffffffff"

-- State variables
local onlineCount, lastUpdateTime = nil, nil
local sessionMax, sessionMin, sessionSum, sessionCount = nil, nil, 0, 0
local pending = false
local pendingSince = nil
local lastAttempt = 0
local queryStartTime = nil
local whoFrameWasShown = false

-- Constants
local WHO_TIMEOUT = 5
local QUERY_WINDOW = 5
local MIN_RETRY_AFTER_FAILURE = 10

-- Ticker/Driver
local driver, ticker = nil, nil
local activePanel = nil
local panelTextSetterCache = setmetatable({}, { __mode = "k" })

-- LibWho detection
local LibWho = nil

-- Localize for performance
local CreateFrame = CreateFrame
local SendWho = SendWho
local GetNumWhoResults = GetNumWhoResults
local GetTime = GetTime
local tonumber = tonumber
local match = string.match
local date = date
local time = time

-- ========================================
-- Helper Functions
-- ========================================

local function dbg(...)
    if db_local and db_local.debug then
        local parts = {}
        for i = 1, select("#", ...) do 
            parts[#parts+1] = tostring(select(i, ...)) 
        end
        print("|cff00aaff[OnlineCount]|r " .. table.concat(parts, " "))
    end
end

local function updateSessionStats(n)
    if not n then return end
    if not sessionMax or n > sessionMax then sessionMax = n end
    if not sessionMin or n < sessionMin then sessionMin = n end
    sessionSum = (sessionSum or 0) + n
    sessionCount = (sessionCount or 0) + 1
end

local function sessionAverage()
    if not sessionCount or sessionCount <= 0 then return nil end
    return math.floor((sessionSum / sessionCount) + 0.5)
end

-- ========================================
-- Panel Text Management (Cached)
-- ========================================

local function GetOrCachePanelTextSetter(panel)
    if not panel then return nil end
    local cached = panelTextSetterCache[panel]
    if cached then return cached end

    if panel.text and type(panel.text.SetText) == "function" then
        panelTextSetterCache[panel] = function(s) pcall(panel.text.SetText, panel.text, s) end
        return panelTextSetterCache[panel]
    end
    if panel.Text and type(panel.Text.SetText) == "function" then
        panelTextSetterCache[panel] = function(s) pcall(panel.Text.SetText, panel.Text, s) end
        return panelTextSetterCache[panel]
    end
    if panel.Value and type(panel.Value.SetText) == "function" then
        panelTextSetterCache[panel] = function(s) pcall(panel.Value.SetText, panel.Value, s) end
        return panelTextSetterCache[panel]
    end
    if type(panel.SetFormattedText) == "function" then
        panelTextSetterCache[panel] = function(s) pcall(panel.SetFormattedText, panel, "%s", s) end
        return panelTextSetterCache[panel]
    end
    if type(panel.SetText) == "function" then
        panelTextSetterCache[panel] = function(s) pcall(panel.SetText, panel, s) end
        return panelTextSetterCache[panel]
    end

    panelTextSetterCache[panel] = nil
    return nil
end

local function WriteTextToPanel(panel, str)
    if not panel then return end
    local setter = GetOrCachePanelTextSetter(panel)
    if setter then 
        setter(str)
        return 
    end
    pcall(function()
        if panel.text and type(panel.text.SetText) == "function" then panel.text:SetText(str) end
        if panel.Text and type(panel.Text.SetText) == "function" then panel.Text:SetText(str) end
        if panel.Value and type(panel.Value.SetText) == "function" then panel.Value:SetText(str) end
    end)
end

local function UpdateDisplay(panel)
    panel = panel or activePanel
    if not panel then return end
    local count = onlineCount or 0
    local str
    if pending then
        str = ("Online: %s%d...|r"):format(valueColor, count)
    else
        str = ("Online: %s%d|r"):format(valueColor, count)
    end
    WriteTextToPanel(panel, str)
end

local function UpdateAllDisplays()
    if activePanel then UpdateDisplay(activePanel) end
    if DT.RegisteredDataTexts and DT.RegisteredDataTexts[REG_NAME] and DT.RegisteredDataTexts[REG_NAME].frame then
        UpdateDisplay(DT.RegisteredDataTexts[REG_NAME].frame)
    end
end

-- ========================================
-- WhoFrame Management (Simplified & Proven)
-- ========================================

local function EnsureWhoFrameLoaded()
    if not FriendsFrame then
        UIParentLoadAddOn("Blizzard_FriendsFrame")
    end
    
    -- Install hooks to prevent FriendsFrame from showing during queries
    if FriendsFrame and not FriendsFrame.ocInitialized then
        FriendsFrame.ocInitialized = true
        FriendsFrame:Hide()
        
        -- Hook Show() to prevent automatic showing during our queries
        if not FriendsFrame.ocOriginalShow then
            FriendsFrame.ocOriginalShow = FriendsFrame.Show
            FriendsFrame.Show = function(self)
                if pending then
                    dbg("Blocked FriendsFrame:Show() during query")
                    return
                end
                return self.ocOriginalShow(self)
            end
        end
        
        -- Hook ShowUIPanel to prevent FriendsFrame from being registered in UI stack
        if not _G.ocOriginalShowUIPanel then
            _G.ocOriginalShowUIPanel = ShowUIPanel
            ShowUIPanel = function(frame, ...)
                if frame == FriendsFrame and pending then
                    dbg("Blocked ShowUIPanel for FriendsFrame during query")
                    FriendsFrame:Hide()
                    return
                end
                return _G.ocOriginalShowUIPanel(frame, ...)
            end
        end
    end
end

local function ScanRegionForTotal(region)
    if not region or type(region.GetText) ~= "function" then 
        return nil 
    end
    
    local txt = region:GetText()
    if not txt or type(txt) ~= "string" then 
        return nil 
    end
    
    -- Only process if it looks like a WHO results message
    if not (txt:find("[Pp]eople") or txt:find("[Ff]ound") or txt:find("%d+%s*%(")) then 
        return nil 
    end
    
    -- Extract the largest number from the text
    local best = 0
    for token in txt:gmatch("(%d[%d%.,%s]*)") do
        local clean = token:gsub("[%s,%.]", "")
        local n = tonumber(clean)
        if n and n > best then 
            best = n 
        end
    end
    
    if best > 0 then 
        return best, txt 
    end
    
    return nil
end

local function ReadWhoFrameTotalFromUI()
    EnsureWhoFrameLoaded()
    
    local wf = _G.WhoFrame
    if not wf then 
        dbg("WhoFrame not found")
        return nil 
    end
    
    -- Scan all regions of WhoFrame itself
    for i = 1, select("#", wf:GetRegions()) do
        local region = select(i, wf:GetRegions())
        local n, raw = ScanRegionForTotal(region)
        if n then 
            dbg("Found total in WhoFrame region:", n, "from text:", raw)
            return n 
        end
    end
    
    -- Scan all regions of WhoFrame's children
    for _, child in ipairs({ wf:GetChildren() }) do
        for i = 1, select("#", child:GetRegions()) do
            local region = select(i, child:GetRegions())
            local n, raw = ScanRegionForTotal(region)
            if n then 
                dbg("Found total in WhoFrame child region:", n, "from text:", raw)
                return n 
            end
        end
    end
    
    dbg("Could not find total count in any WhoFrame region")
    return nil
end

-- Restore frame to previous state after query
local function RestoreWhoFrame()
    if not FriendsFrame then return end
    
    -- Hide WhoFrame first (this is what was missing!)
    if _G.WhoFrame and _G.WhoFrame:IsShown() then
        _G.WhoFrame:Hide()
        dbg("Hiding WhoFrame after query")
    end
    
    -- We only run queries when frame is NOT shown, so always hide it after
    if FriendsFrame:IsShown() then
        dbg("Hiding FriendsFrame after query")
        FriendsFrame:Hide()
    end
    
    -- Use HideUIPanel to properly remove from UI stack
    if HideUIPanel then
        HideUIPanel(FriendsFrame)
        dbg("Called HideUIPanel on FriendsFrame")
    end
    
    -- Cleanup UI stack
    pcall(function()
        if UISpecialFrames then
            for i, frameName in ipairs(UISpecialFrames) do
                if frameName == "FriendsFrame" then
                    local frame = _G[frameName]
                    if frame and frame:IsShown() then
                        frame:Hide()
                    end
                end
            end
        end
        
        if UIParent_ManageFramePositions then
            UIParent_ManageFramePositions()
        end
    end)
    
    dbg("Cleaned up UI stack")
    whoFrameWasShown = false
end



-- ========================================
-- LibWho Support (Optional)
-- ========================================

local function TryLibWhoQuery()
    if not LibWho then return false end
    
    if type(LibWho.WhoInProgress) == "boolean" and LibWho.WhoInProgress then
        dbg("LibWho busy (WhoInProgress)")
        return false
    end
    
    if type(LibWho.state) == "function" then
        local ok, st = pcall(LibWho.state, LibWho)
        if ok and st == 2 then
            dbg("LibWho waiting for response")
            return false
        end
    end
    
    local ok, err = pcall(function()
        if type(LibWho.Who) == "function" then
            LibWho:Who("", function(query, results)
                if _G.WhoFrame and _G.WhoFrame:IsShown() then
                    pending = false
                    queryStartTime = nil
                    UpdateAllDisplays()
                    return
                end
                local total = results and #results or 0
                onlineCount = total
                lastUpdateTime = date("%H:%M")
                updateSessionStats(total)
                pending = false
                queryStartTime = nil
                UpdateAllDisplays()
                dbg("LibWho returned count:", total)
            end)
        else
            error("LibWho has no usable API")
        end
    end)
    
    if ok then
        pending = true
        queryStartTime = GetTime()
        UpdateAllDisplays()
        dbg("LibWho query initiated")
        return true
    else
        dbg("LibWho query failed:", tostring(err))
        return false
    end
end

-- ========================================
-- Native WHO Request (Simplified)
-- ========================================

local function RequestWho(force)
    local now = GetTime()
    
    -- Check if FriendsFrame/WhoFrame is open BEFORE doing anything else
    -- Skip update entirely if user has the frame open (don't interfere)
    if FriendsFrame and FriendsFrame:IsShown() then
        dbg("FriendsFrame is open, skipping query to avoid interfering with user")
        return
    end
    
    if _G.WhoFrame and _G.WhoFrame:IsShown() then
        dbg("WhoFrame is open, skipping query to avoid interfering with user")
        return
    end
    
    -- Basic throttles
    if pending and not force then
        dbg("Request aborted: already pending")
        return
    end
    
    if not force and lastAttempt > 0 and now - lastAttempt < 1 then
        dbg("Request aborted: too soon after last attempt")
        return
    end
    
    if not force and lastAttempt > 0 and (now - lastAttempt) < MIN_RETRY_AFTER_FAILURE and not onlineCount then
        dbg("Last attempt failed recently, delaying")
        return
    end
    
    dbg("Sending blank /who")
    
    -- Track that frame was NOT shown before our query (we already checked above)
    whoFrameWasShown = false
    
    -- Load the frame and ensure hooks are installed
    EnsureWhoFrameLoaded()
    
    -- Send the WHO query FIRST (before setting pending)
    SendWho("")
    
    -- THEN set state (this is critical - matches standalone addon)
    pending = true
    pendingSince = now
    lastAttempt = now
    queryStartTime = now
    
    dbg("Query initiated at time:", now)
end

-- ========================================
-- WHO_LIST_UPDATE Handler
-- ========================================

local function OnWhoListUpdate()
    local now = GetTime()
    
    -- Check if this WHO result is from our query (within time window)
    if not queryStartTime or (now - queryStartTime) > QUERY_WINDOW then
        dbg("WHO_LIST_UPDATE ignored - not from our query (time diff:", queryStartTime and (now - queryStartTime) or "no query", ")")
        return
    end
    
    if not pending then
        dbg("WHO_LIST_UPDATE but not pending; ignoring")
        return
    end
    
    dbg("Processing WHO_LIST_UPDATE from our query...")
    
    -- Give WhoFrame minimal time to update its UI
    C_Timer.After(0.1, function()
        if not pending then
            return
        end
        
        -- Use the robust region-scanning method
        local totalCount = ReadWhoFrameTotalFromUI()
        
        if totalCount and totalCount > 0 then
            onlineCount = totalCount
            lastUpdateTime = date("%H:%M")
            updateSessionStats(totalCount)
            pending = false
            pendingSince = nil
            queryStartTime = nil
            dbg("Successfully captured total count:", totalCount)
            UpdateAllDisplays()
        else
            -- Fallback to GetNumWhoResults if parsing failed
            local num = GetNumWhoResults()
            if num and num >= 0 then
                onlineCount = num
                lastUpdateTime = date("%H:%M")
                updateSessionStats(num)
                pending = false
                pendingSince = nil
                queryStartTime = nil
                dbg("Using fallback GetNumWhoResults:", num)
                UpdateAllDisplays()
            else
                dbg("Failed to get count from any method")
                pending = false
                pendingSince = nil
                queryStartTime = nil
            end
        end
        
        -- Restore frame state after capturing data
        C_Timer.After(0.05, function()
            RestoreWhoFrame()
        end)
    end)
end

-- ========================================
-- DataText Callbacks
-- ========================================

local function OnEvent(self, event, ...)
    activePanel = self
    GetOrCachePanelTextSetter(self)
    UpdateDisplay(self)
    UpdateAllDisplays()
end

local function OnClick(self, button)
    if button == "LeftButton" then
        local now = GetTime()  -- Use GetTime() to match lastAttempt
        local cooldown = tonumber(db_local and db_local.manualClickCooldown) or SUB.defaults.manualClickCooldown
        if (lastAttempt or 0) + cooldown > now then 
            dbg("Manual click throttled")
            return 
        end
        lastAttempt = now
        dbg("Manual refresh requested via click")
        -- Reset pending flag before forcing query
        pending = false
        pendingSince = nil
        queryStartTime = nil
        RequestWho(true)
    end
end

local function OnEnter(self)
    activePanel = self
    DT:SetupTooltip(self)
    if DT.tooltip then
        DT.tooltip:AddLine("Online Player Count")
        if onlineCount then
            DT.tooltip:AddLine(("Current: |cffffffff%d|r"):format(onlineCount))
            DT.tooltip:AddLine(" ")
            DT.tooltip:AddLine("Session Stats")
            if sessionMax then DT.tooltip:AddLine(("Highest: |cffffffff%d|r"):format(sessionMax)) end
            local avg = sessionAverage()
            if avg then DT.tooltip:AddLine(("Average: |cffffffff%d|r"):format(avg)) end
            if sessionMin then DT.tooltip:AddLine(("Lowest: |cffffffff%d|r"):format(sessionMin)) end
            DT.tooltip:AddLine(" ")
            if lastUpdateTime then DT.tooltip:AddLine(("Last Updated: |cffffffff%s|r"):format(lastUpdateTime)) end
        else
            DT.tooltip:AddLine("Fetching...")
        end
        DT.tooltip:Show()
    end
end

local function OnLeave(self)
    if DT and DT.tooltip and DT.tooltip:IsShown() then 
        DT.tooltip:Hide() 
    end
end

-- ========================================
-- Driver / Ticker
-- ========================================

local function EnsureDriver()
    if driver then return end
    driver = CreateFrame("Frame")
    driver:SetScript("OnEvent", function(self, event, ...)
        if event == "WHO_LIST_UPDATE" then 
            OnWhoListUpdate() 
        end
    end)
    
    -- Add OnUpdate handler for timeout checking
    driver:SetScript("OnUpdate", function(self, elapsed)
        -- Check for WHO query timeout
        if pending and pendingSince then
            if GetTime() - pendingSince >= WHO_TIMEOUT then
                dbg("WHO request timed out")
                pending = false
                pendingSince = nil
                queryStartTime = nil
                RestoreWhoFrame()
            end
        end
    end)
end

local function StartTicker(interval)
    interval = tonumber(interval) or SUB.defaults.updateInterval
    if ticker and ticker.Cancel then 
        pcall(function() ticker:Cancel() end) 
    end
    ticker = nil
    
    if C_Timer and C_Timer.NewTicker then
        ticker = C_Timer.NewTicker(interval, function()
            if not pending then
                dbg("Periodic check triggered (interval:", interval, "seconds)")
                RequestWho(false)
            end
        end)
    else
        -- Fallback for older clients
        local accum = 0
        local frame = CreateFrame("Frame")
        frame:SetScript("OnUpdate", function(self, elapsed)
            accum = accum + elapsed
            if accum >= interval then 
                accum = 0
                if not pending then
                    dbg("Periodic check triggered (interval:", interval, "seconds)")
                    RequestWho(false)
                end
            end
        end)
        ticker = frame
    end
    
    dbg("Ticker started with interval:", interval)
end

local function StopTicker()
    if ticker then
        if ticker.Cancel then 
            pcall(function() ticker:Cancel() end) 
        elseif ticker.SetScript then
            ticker:SetScript("OnUpdate", nil)
        end
    end
    ticker = nil
    dbg("Ticker stopped")
end

-- ========================================
-- Registration / Lifecycle
-- ========================================

DT:RegisterDatatext(REG_NAME,
    {"PLAYER_ENTERING_WORLD"},
    OnEvent, nil, OnClick, OnEnter, OnLeave, displayName)

function SUB:OnEnable(db)
    db_local = db or {}
    for k, v in pairs(SUB.defaults) do 
        if db_local[k] == nil then 
            db_local[k] = v 
        end 
    end
    
    -- Reset session stats
    sessionMax = nil
    sessionMin = nil
    sessionSum = 0
    sessionCount = 0
    
    -- Load WhoFrame and install hooks early
    EnsureWhoFrameLoaded()
    
    -- Setup driver
    EnsureDriver()
    driver:RegisterEvent("WHO_LIST_UPDATE")
    driver:RegisterEvent("PLAYER_ENTERING_WORLD")
    
    -- Try to load LibWho if available
    if type(LibStub) == "function" and not LibWho then
        LibWho = LibStub("LibWho-3.0", true) or LibStub("LibWho-2.0", true)
        if LibWho then
            dbg("LibWho detected and loaded")
        end
    end
    
    -- Start polling after a delay
    if C_Timer and C_Timer.After then
        C_Timer.After(15, function()
            RequestWho(false)
            StartTicker(db_local.updateInterval)
        end)
    else
        RequestWho(false)
        StartTicker(db_local.updateInterval)
    end
    
    -- Setup active panel
    if DT.RegisteredDataTexts and DT.RegisteredDataTexts[REG_NAME] and DT.RegisteredDataTexts[REG_NAME].frame then
        activePanel = DT.RegisteredDataTexts[REG_NAME].frame
        GetOrCachePanelTextSetter(activePanel)
        UpdateAllDisplays()
    end
    
    dbg("OnlineCount enabled")
end

function SUB:OnDisable()
    if driver then
        driver:UnregisterEvent("WHO_LIST_UPDATE")
        driver:UnregisterEvent("PLAYER_ENTERING_WORLD")
    end
    
    StopTicker()
    
    -- Reset state
    onlineCount = nil
    lastUpdateTime = nil
    pending = false
    pendingSince = nil
    queryStartTime = nil
    activePanel = nil
    
    -- Reset hook initialization flag
    if FriendsFrame then
        FriendsFrame.ocInitialized = nil
    end
    
    UpdateAllDisplays()
    
    dbg("OnlineCount disabled")
end

function SUB:GetOptions(db)
    db = db or (MOD.db and MOD.db.OnlineCount or SUB.defaults)
    for k, v in pairs(SUB.defaults) do 
        if db[k] == nil then 
            db[k] = v 
        end 
    end
    
    return {
        type = "group",
        name = SUB.name,
        args = {
            header = {
                order = 0,
                type = "header",
                name = "OnlineCount DataText",
            },
            description = {
                order = 1,
                type = "description",
                name = "Displays the total number of online players by sending periodic /who queries invisibly.\n",
            },
            enabled = {
                order = 2, 
                type = "toggle",
                name = function() 
                    return db.enabled and "|cff00ff00Enabled|r" or "|cffff0000Disabled|r" 
                end,
                get = function() return db.enabled end,
                set = function(_, v) 
                    db.enabled = v 
                    if v then 
                        SUB:OnEnable(db) 
                    else 
                        SUB:OnDisable() 
                    end 
                end,
            },
            spacer1 = {
                order = 3,
                type = "description",
                name = " ",
                width = "full",
            },
            updateInterval = {
                order = 4, 
                type = "range", 
                name = "Update interval (sec)",
                desc = "How often to automatically check online player count",
                min = 10, 
                max = 600, 
                step = 5,
                get = function() return db.updateInterval end,
                set = function(_, v) 
                    local newInterval = tonumber(v) or SUB.defaults.updateInterval
                    db.updateInterval = newInterval
                    if db_local then db_local.updateInterval = newInterval end
                    if db.enabled then 
                        StopTicker() 
                        StartTicker(newInterval) 
                    end 
                end,
                disabled = function() return not db.enabled end,
            },
            manualClickCooldown = {
                order = 5, 
                type = "range", 
                name = "Manual refresh cooldown (sec)",
                desc = "Cooldown between manual clicks to refresh",
                min = 1, 
                max = 60, 
                step = 1,
                get = function() return db.manualClickCooldown or SUB.defaults.manualClickCooldown end,
                set = function(_, v) 
                    db.manualClickCooldown = tonumber(v) or SUB.defaults.manualClickCooldown 
                end,
                disabled = function() return not db.enabled end,
            },
            preferLibWhoOnly = {
                order = 6, 
                type = "toggle", 
                name = "Prefer LibWho only",
                desc = "Use LibWho-3.0/2.0 exclusively without native SendWho fallback",
                get = function() return db.preferLibWhoOnly end,
                set = function(_, v) db.preferLibWhoOnly = v end,
                disabled = function() return not db.enabled end,
            },
            spacer2 = {
                order = 7,
                type = "description",
                name = " ",
                width = "full",
            },
            debug = {
                order = 8, 
                type = "toggle", 
                name = "Debug",
                desc = "Show debug messages in chat window",
                get = function() return db.debug end,
                set = function(_, v) 
                    db.debug = v 
                    if db_local then db_local.debug = v end
                end,
                disabled = function() return not db.enabled end,
            },
        }
    }
end

MOD:RegisterSubmodule("OnlineCount", SUB)
