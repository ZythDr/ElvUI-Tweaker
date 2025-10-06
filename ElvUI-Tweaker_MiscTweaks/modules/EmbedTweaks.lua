-- EmbedTweaks.lua
-- Embed Tweaks submodule for MiscTweaks: toggles AddOnSkins embed visibility.
-- This variant keeps the robust token-guard timer behavior and discovery fallbacks,
-- but limits the discovery polling to run once every 2 seconds and stop after 30 seconds
-- to reduce continuous CPU work on slow/long-running sessions.

local core = EWTweaker and EWTweaker.GetCore and EWTweaker.GetCore()
if not core then return end
local MOD = core.modules and core.modules.MiscTweaks
if not MOD then return end

local L = LibStub("AceLocale-3.0-ElvUI"):GetLocale("ElvUI", true)
if not L then L = setmetatable({}, { __index = function(t, k) return k end }) end

local SUB = { name = "Embed Tweaks" }
SUB.defaults = {
    enabled = false,
    showOnCombat = true,
    hideOnLeave = true,
    hideDelay = 6,
    hideOnLogin = true,
    debug = false,
    -- Keep keys present in defaults for compatibility, not shown in the UI
    toggleButtonName = "RightChatToggleButton",
    mainFrameName = "ElvUI_AddOnSkins_Embed_MainWindow",
}

local _G = _G
local C_Timer = _G.C_Timer
local InCombatLockdown = _G.InCombatLockdown
local PLAYER_REGEN_DISABLED = "PLAYER_REGEN_DISABLED"
local PLAYER_REGEN_ENABLED = "PLAYER_REGEN_ENABLED"
local PLAYER_ENTERING_WORLD = "PLAYER_ENTERING_WORLD"
local ADDON_LOADED = "ADDON_LOADED"

local db_local
local driver = nil
local hideTimer = nil
local scanTicker = nil
local scanStopTimer = nil

-- cancel token to guard callbacks even when the timer object cannot be canceled
local hideToken = 0

-- cached ElvUI engine and EmbedSystem / mainFrame
local Eengine = nil
local EMB = nil

local function dbg(...)
    if not (db_local and db_local.debug) then return end
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts+1] = tostring(select(i, ...)) end
    local msg = "|cff00aaff[EmbedTweaks]|r " .. table.concat(parts, " ")
    print(msg)
end

local function alog(...)
    if not (db_local and db_local.debug) then return end
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts+1] = tostring(select(i, ...)) end
    local msg = "|cff00aaff[EmbedTweaks]|r " .. table.concat(parts, " ")
    print(msg)
end

local function EnsureEengine()
    if Eengine then return Eengine end
    if not _G.ElvUI then return nil end
    local ok, e = pcall(function() return unpack(_G.ElvUI) end)
    if ok and e then Eengine = e end
    return Eengine
end

-- Find EmbedSystem, AddOnSkins module or global mainFrame
local function FindEmbedSystem()
    if EMB then return EMB end
    if not EnsureEengine() then return nil end

    -- try E:GetModule("EmbedSystem")
    local ok, emb = pcall(function() return Eengine.GetModule and Eengine:GetModule("EmbedSystem") end)
    if ok and emb then EMB = emb; dbg("FindEmbedSystem: found EmbedSystem via E:GetModule"); return EMB end

    -- try via AddOnSkins module
    local okAS, AS = pcall(function() return Eengine.GetModule and Eengine:GetModule("AddOnSkins") end)
    if okAS and AS and AS.GetModule then
        local ok2, emb2 = pcall(function() return AS:GetModule("EmbedSystem") end)
        if ok2 and emb2 then EMB = emb2; dbg("FindEmbedSystem: found embed via AddOnSkins:GetModule"); return EMB end
    end

    -- fallback to global mainFrame
    local mfName = (db_local and db_local.mainFrameName) or SUB.defaults.mainFrameName
    local mf = _G[mfName] or _G["ElvUI_AddOnSkins_Embed_MainWindow"]
    if mf and type(mf) == "table" and mf.IsObjectType and mf:IsObjectType("Frame") then
        EMB = EMB or {}
        EMB.mainFrame = mf
        dbg("FindEmbedSystem: found global mainFrame:", mfName)
        return EMB
    end

    return nil
end

-- Cancel pending hide timer (robust across clients)
local function CancelPendingHide()
    -- increment token so any pending callback will no-op
    hideToken = hideToken + 1

    if hideTimer then
        -- try to cancel the timer object if it supports Cancel
        if hideTimer.Cancel then
            local ok, err = pcall(function() hideTimer:Cancel() end)
            if not ok then
                dbg("CancelPendingHide: hideTimer:Cancel error:", tostring(err))
                alog("CancelPendingHide: hideTimer:Cancel error: "..tostring(err))
            else
                dbg("CancelPendingHide: canceled hideTimer via Cancel()")
                alog("Cancelled hideTimer")
            end
        else
            dbg("CancelPendingHide: hideTimer present but has no Cancel; token incremented to guard callback")
            alog("CancelPendingHide: hideTimer present but has no Cancel; token incremented")
        end
        hideTimer = nil
    else
        dbg("CancelPendingHide: no hideTimer present; token incremented")
        alog("Cancelled hideTimer")
    end
end

local function ShowEmbed()
    if not db_local or not db_local.enabled then dbg("ShowEmbed: disabled"); alog("ShowEmbed: disabled"); return end
    alog("ShowEmbed invoked")
    local emb = FindEmbedSystem()
    local used = nil
    if emb and emb.mainFrame and emb.mainFrame.Show then
        local ok, err = pcall(function() emb.mainFrame:Show() end)
        if ok then used = "EMB.mainFrame:Show" end
        if not ok then dbg("mainFrame:Show failed:", tostring(err)); alog("mainFrame:Show failed: "..tostring(err)) end
    else
        dbg("ShowEmbed: no emb.mainFrame.Show available", "emb=", tostring(emb))
        alog("ShowEmbed: no emb.mainFrame.Show available")
    end
    alog("ShowEmbed result ->", tostring(used), " emb=", tostring(emb), " mainFrame=", tostring(emb and emb.mainFrame), " inCombat=", tostring((pcall(InCombatLockdown) and InCombatLockdown()) or false))
end

local function HideEmbed()
    if not db_local or not db_local.enabled then dbg("HideEmbed: disabled"); alog("HideEmbed: disabled"); return end
    alog("HideEmbed invoked")
    local emb = FindEmbedSystem()
    local used = nil
    if emb and emb.mainFrame and emb.mainFrame.Hide then
        local ok, err = pcall(function() emb.mainFrame:Hide() end)
        if ok then used = "EMB.mainFrame:Hide" end
        if not ok then dbg("mainFrame:Hide failed:", tostring(err)); alog("mainFrame:Hide failed: "..tostring(err)) end
    else
        dbg("HideEmbed: no emb.mainFrame.Hide available", "emb=", tostring(emb))
        alog("HideEmbed: no emb.mainFrame.Hide available")
    end
    alog("HideEmbed result ->", tostring(used), " emb=", tostring(emb), " mainFrame=", tostring(emb and emb.mainFrame), " inCombat=", tostring((pcall(InCombatLockdown) and InCombatLockdown()) or false))
end

-- Called when we detect the embed system
local function OnFound()
    dbg("OnFound: Embed system discovered")
    alog("OnFound: Embed system discovered")

    -- stop scanning if running
    if scanTicker then
        if scanTicker.Cancel then pcall(function() scanTicker:Cancel() end) end
        scanTicker = nil
    end
    if scanStopTimer then
        if scanStopTimer.Cancel then pcall(function() scanStopTimer:Cancel() end) end
        scanStopTimer = nil
    end

    if db_local and db_local.hideOnLogin then
        CancelPendingHide()
        -- schedule hide after 1 second (guarded by token and combat check)
        if C_Timer and C_Timer.After then
            hideToken = hideToken + 1
            local myToken = hideToken
            hideTimer = C_Timer.After(1, function()
                if myToken ~= hideToken then
                    dbg("OnFound scheduled hide skipped due to token mismatch")
                    return
                end
                local inCombat = false
                local ok, state = pcall(InCombatLockdown)
                if ok and state then inCombat = true end
                if inCombat then
                    dbg("OnFound scheduled hide skipped because player is in combat")
                    return
                end
                hideTimer = nil
                HideEmbed()
            end)
        else
            HideEmbed()
        end
        alog("Scheduled login hide in 1s (OnFound)")
    end
end

-- Event handlers
local function OnEnterCombat()
    CancelPendingHide()
    if db_local and db_local.showOnCombat then ShowEmbed() end
end

local function OnLeaveCombat()
    if not (db_local and db_local.hideOnLeave) then return end
    CancelPendingHide()
    local s = tonumber(db_local.hideDelay) or SUB.defaults.hideDelay
    if s and s > 0 and C_Timer and C_Timer.After then
        hideToken = hideToken + 1
        local myToken = hideToken
        hideTimer = C_Timer.After(s, function()
            if myToken ~= hideToken then
                dbg("OnLeaveCombat scheduled hide skipped due to token mismatch")
                return
            end
            local inCombat = false
            local ok, state = pcall(InCombatLockdown)
            if ok and state then inCombat = true end
            if inCombat then
                dbg("OnLeaveCombat scheduled hide skipped because player re-entered combat")
                return
            end
            hideTimer = nil
            HideEmbed()
        end)
        dbg("Scheduled hide after", s, "seconds")
        alog("Scheduled hide after " .. tostring(s) .. " seconds")
    else
        HideEmbed()
    end
end

local function OnPlayerRegenEnabled()
    -- nothing to recreate; just handle leftover hide scheduling
    OnLeaveCombat()
end

local function StartLimitedScan()
    -- Poll every 2 seconds, stop scanning after 30 seconds
    if not C_Timer or not C_Timer.NewTicker or scanTicker then return end

    dbg("StartLimitedScan: starting 2s ticker, will stop after 30s")
    scanTicker = C_Timer.NewTicker(2, function()
        if FindEmbedSystem() then
            if scanTicker and scanTicker.Cancel then pcall(function() scanTicker:Cancel() end) end
            scanTicker = nil
            if scanStopTimer and scanStopTimer.Cancel then pcall(function() scanStopTimer:Cancel() end) end
            scanStopTimer = nil
            OnFound()
        else
            dbg("Scan: EmbedSystem not found yet")
        end
    end)

    -- stop scanning after 30 seconds to bound CPU cost
    scanStopTimer = C_Timer.After(30, function()
        if scanTicker then
            if scanTicker.Cancel then pcall(function() scanTicker:Cancel() end) end
            scanTicker = nil
        end
        scanStopTimer = nil
        dbg("StartLimitedScan: stopped scanning after 30s timeout")
        alog("StartLimitedScan: stopped scanning after 30s timeout")
    end)
end

local function OnLoginOrAddonLoaded(event, addonName)
    -- rediscover embed system
    EMB = nil
    FindEmbedSystem()
    if FindEmbedSystem() then OnFound() end

    if event == PLAYER_ENTERING_WORLD or (event == ADDON_LOADED and db_local and db_local.hideOnLogin) then
        if db_local and db_local.hideOnLogin then
            CancelPendingHide()
            if C_Timer and C_Timer.After then
                hideToken = hideToken + 1
                local myToken = hideToken
                hideTimer = C_Timer.After(10, function()
                    if myToken ~= hideToken then
                        dbg("Login scheduled hide skipped due to token mismatch (event="..tostring(event)..")")
                        return
                    end
                    local inCombat = false
                    local ok, state = pcall(InCombatLockdown)
                    if ok and state then inCombat = true end
                    if inCombat then
                        dbg("Login scheduled hide skipped because player is in combat (event="..tostring(event)..")")
                        return
                    end
                    hideTimer = nil
                    HideEmbed()
                end)
                dbg("Scheduled login hide in 10s (event="..tostring(event)..")")
                alog("Scheduled login hide in 10s (event="..tostring(event)..")")
            else
                HideEmbed()
            end
        end
    end
end

-- Driver
local function EnsureDriver()
    if driver then return end
    driver = CreateFrame("Frame")
    driver:SetScript("OnEvent", function(self, event, ...)
        if event == PLAYER_REGEN_DISABLED then OnEnterCombat()
        elseif event == PLAYER_REGEN_ENABLED then OnPlayerRegenEnabled()
        elseif event == PLAYER_ENTERING_WORLD then OnLoginOrAddonLoaded(event, ...)
        elseif event == ADDON_LOADED then
            OnLoginOrAddonLoaded(event, ...)
            local addon = ...
            if addon == "ElvUI_AddOnSkins" then FindEmbedSystem(); if FindEmbedSystem() then OnFound() end end
        end
    end)
end

-- Submodule lifecycle
function SUB:OnEnable(db)
    for k, v in pairs(SUB.defaults) do if db[k] == nil then db[k] = v end end
    db_local = db

    EnsureDriver()
    driver:RegisterEvent(PLAYER_REGEN_DISABLED)
    driver:RegisterEvent(PLAYER_REGEN_ENABLED)
    driver:RegisterEvent(PLAYER_ENTERING_WORLD)
    driver:RegisterEvent(ADDON_LOADED)

    -- start a limited scan (2s interval, stop after 30s) if embed system not found
    if FindEmbedSystem() then
        OnFound()
    else
        StartLimitedScan()
    end

    -- run login hide if requested (OnFound will also schedule when found)
    if db_local.hideOnLogin and FindEmbedSystem() then
        OnLoginOrAddonLoaded(PLAYER_ENTERING_WORLD)
    end

    dbg("EmbedTweaks submodule enabled (limited scan)")
    alog("EmbedTweaks submodule enabled (limited scan)")
end

function SUB:OnDisable()
    if driver then
        driver:UnregisterEvent(PLAYER_REGEN_DISABLED)
        driver:UnregisterEvent(PLAYER_REGEN_ENABLED)
        driver:UnregisterEvent(PLAYER_ENTERING_WORLD)
        driver:UnregisterEvent(ADDON_LOADED)
    end
    if scanTicker and scanTicker.Cancel then scanTicker:Cancel() end
    scanTicker = nil
    if scanStopTimer and scanStopTimer.Cancel then scanStopTimer:Cancel() end
    scanStopTimer = nil
    CancelPendingHide()
    db_local = nil
    dbg("EmbedTweaks submodule disabled")
    alog("EmbedTweaks submodule disabled")
end

function SUB:GetOptions(db)
    for k, v in pairs(SUB.defaults) do if db[k] == nil then db[k] = v end end

    return {
        type = "group",
        name = SUB.name,
        args = {
                header = {
                order = 0,
                type = "header",
                name = " AddOnSkins Embed Tweaks",
            },
                description = {
                order = 1,
                type = "description",
                name = "|cffff0000NOTE: Requires AddOnSkins to be installed and an addon set to be embedded in the Embed Settings panel.|r\n\nThis module allows you to make embedded addons show and hide based on your combat status.\n",
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
            showOnCombat = {
                order = 5, type = "toggle",
                name = "Show in Combat",
                desc = "Automatically show DPS Meter when you enter combat.",
                get = function() return db.showOnCombat end,
                set = function(_, v) db.showOnCombat = v end,
            },
            hideOnLeave = {
                order = 6, type = "toggle",
                name = "Hide out of combat",
                desc = "Automatically hide DPS Meter when you leave combat.",
                get = function() return db.hideOnLeave end,
                set = function(_, v) db.hideOnLeave = v end,
            },
            hideDelay = {
                order = 7, type = "range",
                name = "Hide Delay (seconds)",
                min = 0, max = 60, step = 1,
                get = function() return db.hideDelay end,
                set = function(_, v) db.hideDelay = v end,
            },
            hideOnLogin = {
                order = 8,
                type = "toggle",
                name = "Hide on Login",
                desc = "Automatically hide DPS Meter 10 seconds after login/reload.",
                get = function() return db.hideOnLogin end,
                set = function(_, v) db.hideOnLogin = v end,
            },
                spacer2 = {
                order = 9,
                type = "description",
                name = " ",
                width = "full",
            },
            debug = {
                order = 10,
                type = "toggle",
                name = "Debug",
                get = function() return db.debug end,
                set = function(_, v) db.debug = v end,
            },
        }
    }
end

-- Register submodule with parent MiscTweaks
MOD:RegisterSubmodule("EmbedTweaks", SUB)