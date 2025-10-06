-- TooltipAnchor.lua
-- ElvUI MiscTweaks submodule: Tooltip Anchor
local MOD = _G.EWTweaker_MiscTweaks
if not MOD then return end

local bagFrames = {
    ["AdiBags"]     = { display = "AdiBags",     frame = "AdiBagsContainer1" },
    ["Bagnon"]      = { display = "Bagnon",      frame = "BagnonFrame" },
    ["Combuctor"]   = { display = "Combuctor",   frame = "CombuctorFrame" },
    ["ArkInventory"]= { display = "ArkInventory", frame = "ARKINV_Frame1" },
    ["Custom"]      = { display = "Custom",      frame = "" },
}

local anchorPoints = {
    ["TOPLEFT"] = "Top Left",
    ["TOPRIGHT"] = "Top Right",
    ["BOTTOMLEFT"] = "Bottom Left",
    ["BOTTOMRIGHT"] = "Bottom Right",
    ["CENTER"] = "Center",
    ["LEFT"] = "Left",
    ["RIGHT"] = "Right",
    ["TOP"] = "Top",
    ["BOTTOM"] = "Bottom",
}

local SUB = {}
SUB.name = "Tooltip Anchor"
SUB.defaults = {
    enabled = false,
    debug = false,
    selectedFrame = "AdiBags",
    customFrameName = bagFrames["AdiBags"].frame,
    tooltipAnchorPoint = "BOTTOMRIGHT",
    frameAnchorPoint = "TOPRIGHT",
    autoOffset = true,
    x = 0,
    y = 18
}

local function IsWotLK()
    local version = GetBuildInfo and GetBuildInfo() or ""
    return version:find("^3%.3%.5")
end

function SUB:GetOptions(db)
    local dropdownValues = {}
    for key, val in pairs(bagFrames) do
        dropdownValues[key] = val.display
    end

    return {
        type = "group",
        name = SUB.name,
        args = {
            header = {
                order = 0,
                type = "header",
                name = "Tooltip Anchor",
            },
            description = {
                order = 1,
                type = "description",
                name = "This module allows you to customize the anchor point of tooltips for various bag frames.\n",
            },
            enabled = {
                order = 2, type = "toggle", 
                name = function() return db.enabled and "|cff00ff00Enabled|r" or "|cffff0000Disabled|r" end,
                get = function() return db.enabled end,
                set = function(_, value)
                    db.enabled = value
                    if value then SUB:ApplyEnabled(db) else SUB:DisableAnchor() end
                end,
            },
                spacer1 = {
                order = 3,
                type = "description",
                name = " ",
                width = "full",
            },
            selectedFrame = {
                order = 4, type = "select", name = "Bag Addon/Frame",
                values = dropdownValues,
                get = function() return db.selectedFrame end,
                set = function(_, value)
                    db.selectedFrame = value
                    if value ~= "Custom" then db.customFrameName = bagFrames[value] and bagFrames[value].frame or "" end
                end,
                disabled = function() return not db.enabled end,
            },
            customFrameName = {
                order = 5, type = "input", name = "Custom Frame Name",
                desc = "Enter the global frame name to anchor to.",
                get = function()
                    local selected = db.selectedFrame
                    if selected and bagFrames[selected] and selected ~= "Custom" then
                        return bagFrames[selected].frame
                    end
                    return db.customFrameName
                end,
                set = function(_, value) db.customFrameName = value end,
                disabled = function() return not db.enabled or db.selectedFrame ~= "Custom" end,
            },
                spacer2 = {
                order = 6,
                type = "description",
                name = " ",
                width = "full",
            },
            tooltipAnchorPoint = {
                order = 7, type = "select", name = "Tooltip Anchor Point",
                desc = "Which anchor point of the tooltip should be attached.",
                values = anchorPoints,
                get = function() return db.tooltipAnchorPoint end,
                set = function(_, value) db.tooltipAnchorPoint = value end,
                disabled = function() return not db.enabled end,
            },
            frameAnchorPoint = {
                order = 8, type = "select", name = "Bag Frame Anchor Point",
                desc = "Which anchor point of the bag frame should be used.",
                values = anchorPoints,
                get = function() return db.frameAnchorPoint end,
                set = function(_, value) db.frameAnchorPoint = value end,
                disabled = function() return not db.enabled end,
            },
                spacer3 = {
                order = 9,
                type = "description",
                name = " ",
                width = "full",
            },
            autoOffset = {
                order = 10, type = "toggle", name = "Auto Offset",
                desc = "If checked, Y offset is automatically set to avoid overlapping (healthbar height + 4px).",
                get = function() return db.autoOffset end,
                set = function(_, value) db.autoOffset = value end,
                disabled = function() return not db.enabled end,
            },
            x = {
                order = 11, type = "range", name = "X Offset",
                min = -100, max = 100, step = 1,
                get = function() return db.x or 0 end,
                set = function(_, val) db.x = val end,
                disabled = function() return not db.enabled or db.autoOffset end,
            },
            y = {
                order = 12, type = "range", name = "Y Offset",
                min = -100, max = 100, step = 1,
                get = function() return db.y or 0 end,
                set = function(_, val) db.y = val end,
                disabled = function() return not db.enabled or db.autoOffset end,
            },
                spacer4 = {
                order = 20,
                type = "description",
                name = " ",
                width = "full",
            },
            debug = {
                order = 21, type = "toggle", name = "Debug",
                desc = "Print diagnostic info in chat for troubleshooting.",
                get = function() return db.debug end,
                set = function(_, value) db.debug = value end,
            },
        }
    }
end

local orig_Anchor
local hooked = false

function SUB:GetTargetFrame(db)
    local selected = db.selectedFrame
    if selected == "Custom" then
        return _G[db.customFrameName or ""]
    elseif selected and bagFrames[selected] then
        return _G[bagFrames[selected].frame]
    end
    return nil
end

local function GetAutoYOffset()
    local h
    if ElvUI and ElvUI[1] and ElvUI[1].db and ElvUI[1].db.tooltip and ElvUI[1].db.tooltip.healthBar then
        h = ElvUI[1].db.tooltip.healthBar.height or 10
    elseif ElvUI and ElvUI.db and ElvUI.db.tooltip and ElvUI.db.tooltip.healthBar then
        h = ElvUI.db.tooltip.healthBar.height or 10
    end
    return (h or 10) + 4
end

local function ReanchorIfShown(db)
    local tt = GameTooltip
    local frame = SUB:GetTargetFrame(db)
    if db.enabled and tt:IsShown() and frame and frame:IsShown() then
        local x = db.x or 0
        local y = db.y or 0
        if db.autoOffset then
            y = GetAutoYOffset()
            if db.debug then print("TooltipAnchor: AutoOffset enabled, y =", y) end
        end
        if db.debug then
            print("TooltipAnchor: Reanchoring tooltip to", frame:GetName())
            print("  Tooltip Anchor Point:", db.tooltipAnchorPoint, "Frame Anchor Point:", db.frameAnchorPoint)
            print("  X/Y:", x, y)
        end
        tt:ClearAllPoints()
        tt:SetOwner(frame, "ANCHOR_NONE")
        tt:SetPoint(db.tooltipAnchorPoint, frame, db.frameAnchorPoint, x, y)
    end
end

function SUB:EnableAnchor(db)
    if hooked then return true end

    local E = (IsWotLK() and ElvUI and ElvUI[1]) or ElvUI
    local TT = E and E.GetModule and E:GetModule("Tooltip")
    if not TT then
        if db.debug then print("TooltipAnchor: ElvUI Tooltip module not found! (TT is nil)") end
        return false
    end
    if db.debug then print("TooltipAnchor: TT found, type:", type(TT))
        print("TooltipAnchor: GameTooltip_SetDefaultAnchor type:", type(TT.GameTooltip_SetDefaultAnchor))
    end
    if not TT.GameTooltip_SetDefaultAnchor or type(TT.GameTooltip_SetDefaultAnchor) ~= "function" then
        if db.debug then print("TooltipAnchor: GameTooltip_SetDefaultAnchor missing or not a function!") end
        return false
    end

    orig_Anchor = TT.GameTooltip_SetDefaultAnchor

    TT.GameTooltip_SetDefaultAnchor = function(self, tt, parent)
        if db.debug then
            print("TooltipAnchor: Called!")
            print("  Tooltip:", tt and tt:GetName() or "nil")
            print("  Parent:", parent and parent:GetName() or "nil")
        end

        if tt.GetAnchorType and tt:GetAnchorType() ~= "ANCHOR_NONE" then
            if db.debug then print("  Skipping: Tooltip anchor type is not ANCHOR_NONE") end
            return
        end

        if parent then
            if self.db and self.db.cursorAnchor then
                if db.debug then print("  Skipping: Cursor anchor is enabled in ElvUI config") end
                tt:SetOwner(parent, self.db.cursorAnchorType, self.db.cursorAnchorX, self.db.cursorAnchorY)
                return
            else
                tt:SetOwner(parent, "ANCHOR_NONE")
            end
        end

        local customFrame = SUB:GetTargetFrame(db)
        local x = db.x or 0
        local y = db.y or 0
        if db.autoOffset then
            y = GetAutoYOffset()
            if db.debug then print("TooltipAnchor: AutoOffset enabled, y =", y) end
        end
        if db.debug then
            print("  Chosen anchor frame:", customFrame and customFrame:GetName() or "nil")
            print("  Is frame shown:", customFrame and customFrame:IsShown() or false)
            print("  Config enabled:", db.enabled)
            print("  Tooltip Anchor Point:", db.tooltipAnchorPoint, "Frame Anchor Point:", db.frameAnchorPoint)
            print("  X/Y:", x, y)
        end

        if db.enabled and customFrame and customFrame:IsShown() then
            if db.debug then print("  Applying custom anchor! Frame:", customFrame:GetName()) end
            tt:ClearAllPoints()
            tt:SetPoint(db.tooltipAnchorPoint, customFrame, db.frameAnchorPoint, x, y)
            return
        else
            if db.debug then print("  NOT applying custom anchor. Falling back to ElvUI logic.") end
        end

        if orig_Anchor then
            orig_Anchor(self, tt, parent)
        else
            if db.debug then print("TooltipAnchor: orig_Anchor is nil, cannot fallback.") end
        end
    end
    if db.debug then print("TooltipAnchor: Hooked ElvUI anchor function") end
    hooked = true

    local frame = SUB:GetTargetFrame(db)
    if frame then
        if not frame.__TooltipAnchorHooked then
            frame:HookScript("OnShow", function() ReanchorIfShown(db) end)
            frame:HookScript("OnHide", function() ReanchorIfShown(db) end)
            frame.__TooltipAnchorHooked = true
            if db.debug then print("TooltipAnchor: Hooked OnShow/OnHide for", frame:GetName()) end
        end
    end

    -- Reanchor immediately if shown
    if frame and frame:IsShown() then
        ReanchorIfShown(db)
    end

    return true
end

function SUB:ApplyEnabled(db)
    local tries = 0
    local function TryEnable()
        if not db.enabled then return end
        tries = tries + 1
        local success = SUB:EnableAnchor(db)
        if not success and tries < 10 then
            C_Timer.After(1, TryEnable)
        elseif not success and db.debug then
            print("TooltipAnchor: Unable to hook after 10 tries")
        end
    end
    TryEnable()
end

function SUB:DisableAnchor()
    local E = (IsWotLK() and ElvUI and ElvUI[1]) or ElvUI
    local TT = E and E.GetModule and E:GetModule("Tooltip")
    if hooked and TT and orig_Anchor then
        TT.GameTooltip_SetDefaultAnchor = orig_Anchor
        if db and db.debug then print("TooltipAnchor: Unhooked ElvUI anchor function") end
        hooked = false
    end
end

MOD:RegisterSubmodule("TooltipAnchor", SUB)