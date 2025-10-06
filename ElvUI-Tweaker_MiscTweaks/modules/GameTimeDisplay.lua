-- GameTimeDisplay.lua
-- MiscTweaks submodule: "Game Time Display"
-- By default: disabled. When enabled, persists until user disables. Integrates with ElvUI-WotLK-Tweaker core.

local core = EWTweaker and EWTweaker.GetCore and EWTweaker.GetCore()
if not core then return end

local MOD = core.modules and core.modules.MiscTweaks
if not MOD then return end

local SUB = { name = "Game Time Display" }

SUB.defaults = {
    enabled = false,
    mode = "Minimap",
    anchor = "BOTTOMLEFT",
    xOffset = 2,
    yOffset = 2,
    scale = 1.0,
    onlyOnMinimapHover = false,
}

local saved = {
    frame = nil,
    orig = nil,
    fallbackCreated = false,
    minimapScriptBackup = { OnEnter = nil, OnLeave = nil },
    minimapHooked = false,
    ticker = nil,
}

local E = _G.ElvUI and unpack(_G.ElvUI) or nil
local NP = _G.Minimap
local TimeMgr = _G.TimeManagerFrame
local C_Timer = _G.C_Timer

local function FindGameTimeFrame()
    if _G.GameTimeFrame then return _G.GameTimeFrame end
    if _G.GameTimeButton then return _G.GameTimeButton end
    if _G.MinimapClock and type(_G.MinimapClock) == "table" then return _G.MinimapClock end
    return nil
end

local function CreateFallbackFrame()
    if saved.fallbackCreated and saved.frame then return saved.frame end
    local parent = NP or UIParent
    local f = CreateFrame("Frame", "EWT_GameTimeFallbackFrame", parent)
    f:SetSize(36, 14)
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.text:SetPoint("CENTER", f, "CENTER", 0, 0)
    local fontPath, fontSize, fontFlags = f.text:GetFont()
    saved.fallbackFont = { path = fontPath, size = fontSize or 12, flags = fontFlags }
    saved.fallbackCreated = true
    saved.frame = f
    return f
end

local function IsDayTime()
    local hour = select(1, GetGameTime()) or 12
    return hour >= 6 and hour < 18
end

local function UpdateFallback()
    if not saved.frame or not saved.fallbackCreated then return end
    if IsDayTime() then
        saved.frame.text:SetText("Day")
        saved.frame.text:SetTextColor(1, 0.85, 0.2)
    else
        saved.frame.text:SetText("Night")
        saved.frame.text:SetTextColor(0.6, 0.7, 1)
    end
end

local function PositionFrameToParent(frame, parent, anchor, x, y)
    if not frame or not parent then return end
    frame:ClearAllPoints()
    pcall(frame.SetPoint, frame, anchor, parent, anchor, x or 0, y or 0)
end

local function SaveOriginalState(gtf)
    if not gtf or saved.orig then return end
    saved.orig = {}
    saved.orig.parent = gtf:GetParent()
    saved.orig.points = {}
    local num = gtf.GetNumPoints and (gtf:GetNumPoints() or 0) or 0
    for i = 1, num do
        local p, rp, rp2, x, y = gtf:GetPoint(i)
        saved.orig.points[i] = { p = p, rp = rp, rp2 = rp2, x = x, y = y }
    end
    saved.orig.shown = gtf:IsShown()
    saved.orig.scale = gtf:GetScale()
    local w, h = gtf:GetSize()
    if w and h and w > 0 and h > 0 then
        saved.orig.size = { w = w, h = h }
    end
    saved.orig.strata = (gtf.GetFrameStrata and gtf:GetFrameStrata()) or nil
end

local function RestoreOriginalState(gtf)
    if not gtf or not saved.orig then return end
    if saved.orig.parent then pcall(gtf.SetParent, gtf, saved.orig.parent) end
    if saved.orig.points then
        pcall(gtf.ClearAllPoints, gtf)
        for i, pt in ipairs(saved.orig.points) do
            if pt and pt.p then
                pcall(gtf.SetPoint, gtf, pt.p, pt.rp, pt.rp2, pt.x, pt.y)
            end
        end
    end
    if saved.orig.size then
        pcall(gtf.SetSize, gtf, saved.orig.size.w, saved.orig.size.h)
    end
    if saved.orig.scale then pcall(gtf.SetScale, gtf, saved.orig.scale) end
    if saved.orig.strata and gtf.SetFrameStrata then pcall(gtf.SetFrameStrata, gtf, saved.orig.strata) end
    if not saved.orig.shown then pcall(gtf.Hide, gtf) end
    saved.orig = nil
end

local function MinimapOnEnter(self)
    if saved.minimapScriptBackup.OnEnter then pcall(saved.minimapScriptBackup.OnEnter, self) end
    if saved.frame and saved.frame.db and saved.frame.db.onlyOnMinimapHover then
        saved.frame:Show()
    end
end
local function MinimapOnLeave(self)
    if saved.minimapScriptBackup.OnLeave then pcall(saved.minimapScriptBackup.OnLeave, self) end
    if saved.frame and saved.frame.db and saved.frame.db.onlyOnMinimapHover then
        saved.frame:Hide()
    end
end

local function SetupMinimapHoverHook(enable)
    if not NP then return end
    if enable then
        if not saved.minimapHooked then
            saved.minimapScriptBackup.OnEnter = NP:GetScript("OnEnter")
            saved.minimapScriptBackup.OnLeave = NP:GetScript("OnLeave")
            NP:SetScript("OnEnter", MinimapOnEnter)
            NP:SetScript("OnLeave", MinimapOnLeave)
            saved.minimapHooked = true
        else
            NP:SetScript("OnEnter", MinimapOnEnter)
            NP:SetScript("OnLeave", MinimapOnLeave)
        end
    else
        if saved.minimapHooked then
            NP:SetScript("OnEnter", saved.minimapScriptBackup.OnEnter)
            NP:SetScript("OnLeave", saved.minimapScriptBackup.OnLeave)
            saved.minimapHooked = false
            saved.minimapScriptBackup.OnEnter = nil
            saved.minimapScriptBackup.OnLeave = nil
        end
    end
end

local function Cleanup()
    if saved.frame then
        -- No ElvUI skin to remove
    end
    local gtf = FindGameTimeFrame()
    if gtf and saved.orig then RestoreOriginalState(gtf) end
    SetupMinimapHoverHook(false)
    if saved.fallbackCreated and saved.frame then
        if saved.ticker and saved.ticker.Cancel then pcall(saved.ticker.Cancel, saved.ticker) end
        saved.frame:SetScript("OnUpdate", nil)
        pcall(saved.frame.Hide, saved.frame)
    end
    saved.frame = nil
    saved.ticker = nil
end

local function ApplyScaleToFrame(frame, scale)
    if not frame then return end
    pcall(frame.SetScale, frame, scale or 1.0)
    if saved.orig and saved.orig.size and frame ~= nil then
        local w = math.max(1, math.floor((saved.orig.size.w or 0) * (scale or 1.0)))
        local h = math.max(1, math.floor((saved.orig.size.h or 0) * (scale or 1.0)))
        pcall(frame.SetSize, frame, w, h)
        return
    end
    if saved.fallbackCreated and saved.frame == frame then
        local baseW, baseH = 36, 14
        local w = math.max(1, math.floor(baseW * (scale or 1.0)))
        local h = math.max(1, math.floor(baseH * (scale or 1.0)))
        pcall(frame.SetSize, frame, w, h)
        if saved.fallbackFont and frame.text then
            local newSize = math.max(6, math.floor((saved.fallbackFont.size or 12) * (scale or 1.0)))
            pcall(frame.text.SetFont, frame.text, saved.fallbackFont.path, newSize, saved.fallbackFont.flags)
        end
    end
end

local function ApplyConfig(db)
    Cleanup()
    if not db.enabled then return end
    local gtf = FindGameTimeFrame()
    local frameToManage = gtf or CreateFallbackFrame()
    saved.frame = frameToManage
    frameToManage.db = db -- for event handlers
    ApplyScaleToFrame(frameToManage, db.scale or 1.0)

    if db.mode == "Minimap" then
        if not NP then
            pcall(frameToManage.SetParent, frameToManage, UIParent)
            PositionFrameToParent(frameToManage, UIParent, db.anchor or "TOPLEFT", db.xOffset, db.yOffset)
            frameToManage:Show()
        else
            if gtf then SaveOriginalState(gtf) end
            pcall(frameToManage.SetParent, frameToManage, NP)
            PositionFrameToParent(frameToManage, NP, db.anchor or "TOPLEFT", db.xOffset, db.yOffset)
            if db.onlyOnMinimapHover then SetupMinimapHoverHook(true); frameToManage:Hide() else SetupMinimapHoverHook(false); frameToManage:Show() end
        end
    elseif db.mode == "TimeManager" then
        local tm = _G.TimeManagerFrame or TimeMgr
        if tm then
            if gtf then SaveOriginalState(gtf) end
            pcall(frameToManage.SetParent, frameToManage, tm)
            local anchor = db.anchor or "BOTTOMLEFT"
            PositionFrameToParent(frameToManage, tm, anchor, db.xOffset, db.yOffset)
            SetupMinimapHoverHook(false)
            frameToManage:Show()
        else
            if NP then pcall(frameToManage.SetParent, frameToManage, NP); PositionFrameToParent(frameToManage, NP, db.anchor or "TOPLEFT", db.xOffset, db.yOffset); frameToManage:Show()
            else pcall(frameToManage.SetParent, frameToManage, UIParent); PositionFrameToParent(frameToManage, UIParent, "TOPLEFT", db.xOffset, db.yOffset); frameToManage:Show() end
        end
    else
        if NP then pcall(frameToManage.SetParent, frameToManage, NP); PositionFrameToParent(frameToManage, NP, "TOPLEFT", db.xOffset, db.yOffset); frameToManage:Show()
        else pcall(frameToManage.SetParent, frameToManage, UIParent); PositionFrameToParent(frameToManage, UIParent, "TOPLEFT", db.xOffset, db.yOffset); frameToManage:Show() end
    end

    if saved.fallbackCreated and saved.frame then
        if saved.ticker and saved.ticker.Cancel then
        else
            if C_Timer and C_Timer.NewTicker then
                saved.ticker = C_Timer.NewTicker(30, UpdateFallback)
            else
                if not saved.frame.__EWT_onupdate then
                    saved.frame.__EWT_onupdate = true
                    saved.frame:SetScript("OnUpdate", function(self, elapsed)
                        self._acc = (self._acc or 0) + elapsed
                        if self._acc >= 30 then
                            self._acc = 0
                            UpdateFallback()
                        end
                    end)
                end
            end
            UpdateFallback()
        end
    end
end

function SUB:OnEnable(db)
    for k, v in pairs(SUB.defaults) do
        if db[k] == nil then db[k] = v end
    end
    ApplyConfig(db)
end

function SUB:OnDisable(db)
    Cleanup()
end

function SUB:GetOptions(db)
    for k, v in pairs(SUB.defaults) do
        if db[k] == nil then db[k] = v end
    end
    local values = {
        mode = { Minimap = "Minimap", TimeManager = "TimeManager" },
        anchor = { TOPLEFT = "TOPLEFT", TOPRIGHT = "TOPRIGHT", BOTTOMLEFT = "BOTTOMLEFT", BOTTOMRIGHT = "BOTTOMRIGHT" },
    }
    local disabled = function() return not db.enabled end
    return {
        type = "group",
        name = SUB.name,
        args = {
            header = {
                order = 0,
                type = "header",
                name = "Game Time Display",
            },
            description = {
                order = 0.5,
                type = "description",
                name = "This module adds back a Day/Night cycle indicator since ElvUI removes it entirely.\n",
            },
            enabled = {
                order = 1, type = "toggle",
                name = function()
                    return db.enabled
                        and "|cff00ff00Enabled|r"
                        or "|cffff0000Disabled|r"
                end,
                get = function() return db.enabled end,
                set = function(_, v)
                    db.enabled = v
                    if v then SUB:OnEnable(db) else SUB:OnDisable(db) end
                end,
            },
            spacer1 = {
                order = 2,
                type = "description",
                name = " ",
            },
            mode = {
                order = 3, type = "select", name = "Mode", desc = "Where to display the indicator",
                values = values.mode,
                get = function() return db.mode end,
                set = function(_, v) db.mode = v; if db.enabled then ApplyConfig(db) end end,
                disabled = disabled,
            },
                onlyOnMinimapHover = {
                order = 4, type = "toggle", name = "Only show on mouseover",
                desc = "Only display the indicator on Minimap mouseover.",
                get = function() return db.onlyOnMinimapHover end,
                set = function(_, v) db.onlyOnMinimapHover = v; if db.enabled then ApplyConfig(db) end end,
                disabled = function() return disabled() or db.mode ~= "Minimap" end,
            },
                spacer2 = {
                order = 10,
                type = "description",
                name = " ",
            },
            anchor = {
                order = 11, type = "select", name = "Anchor", desc = "Anchor point on parent",
                values = values.anchor,
                get = function() return db.anchor end,
                set = function(_, v) db.anchor = v; if db.enabled then ApplyConfig(db) end end,
                disabled = disabled,
            },
            xOffset = {
                order = 12, type = "range", name = "X Offset", min = -200, max = 200, step = 1,
                get = function() return db.xOffset end,
                set = function(_, v) db.xOffset = v; if db.enabled then ApplyConfig(db) end end,
                disabled = disabled,
            },
            yOffset = {
                order = 13, type = "range", name = "Y Offset", min = -200, max = 200, step = 1,
                get = function() return db.yOffset end,
                set = function(_, v) db.yOffset = v; if db.enabled then ApplyConfig(db) end end,
                disabled = disabled,
            },
            spacer3 = {
                order = 20,
                type = "description",
                name = " ",
                width = "full",
            },
            scale = {
                order = 21, type = "range", name = "Scale", min = 0.5, max = 2.0, step = 0.01,
                get = function() return db.scale end,
                set = function(_, v) db.scale = v; if db.enabled then ApplyConfig(db) end end,
                disabled = disabled,
            },
        }
    }
end

MOD:RegisterSubmodule("GameTimeDisplay", SUB)