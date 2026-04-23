-- ChatEditboxMover.lua
-- ElvUI MiscTweaks submodule: Chat Editbox Mover
local MOD = _G.EWTweaker_MiscTweaks
if not MOD then return end

local SUB = {}
SUB.name = "Chat Editbox Mover"
local STRATA_LEVELS = {
    [1] = "BACKGROUND",
    [2] = "LOW",
    [3] = "MEDIUM",
    [4] = "HIGH",
    [5] = "DIALOG",
    [6] = "FULLSCREEN",
    [7] = "FULLSCREEN_DIALOG",
    [8] = "TOOLTIP",
}

SUB.defaults = {
    enabled = false,
    strataLevel = 5,
    width = 320,
    height = 32,
    scale = 1.0,
}

local editbox = _G.ChatFrame1EditBox
local holder = nil
local E = nil
local isHooked = false

-- Ensure the holder frame and mover are created
local function EnsureHolder(db)
    if not E then
        if ElvUI and ElvUI[1] then E = ElvUI[1] end
        if not E or not E.CreateMover then return end
    end
    if not holder then
        holder = CreateFrame("Frame", "EWTweaker_ChatEditboxMoverHolder", E.UIParent or UIParent)
        holder:SetSize((db and db.width) or 320, (db and db.height) or 32)
        holder:SetScale((db and db.scale) or 1.0)
        holder:SetPoint("BOTTOM", E.UIParent or UIParent, "BOTTOM", 0, 300) -- Default position

        if not holder.mover then
            E:CreateMover(holder, "EWTweaker_ChatEditboxMover", "Chat Editbox", nil, nil, nil, "ALL,GENERAL", nil, "Tweaker,MiscTweaks,ChatEditboxMover")
        end
    end
    return holder
end

function SUB:GetOptions(db)
    return {
        type = "group",
        name = SUB.name,
        args = {
            header = {
                order = 0,
                type = "header",
                name = "Chat Editbox Mover",
            },
            description = {
                order = 1,
                type = "description",
                name = "Allows you to move ChatFrame1EditBox anywhere on your screen, just like other ElvUI movers.",
            },
            enabled = {
                order = 2,
                type = "toggle",
                width = "full",
                name = function() return db.enabled and "|cff00ff00Enabled|r" or "|cffff0000Disabled|r" end,
                get = function() return db.enabled end,
                set = function(_, value)
                    db.enabled = value
                    if value then SUB:ApplyEnabled(db) else SUB:DisableMover() end
                end,
            },
            width = {
                order = 3,
                type = "range",
                name = "Width",
                min = 100, max = 1000, step = 1,
                get = function() return db.width or 320 end,
                set = function(_, val)
                    db.width = val
                    SUB:UpdateSize(db)
                end,
                disabled = function() return not db.enabled end,
            },
            height = {
                order = 4,
                type = "range",
                name = "Height",
                min = 20, max = 100, step = 1,
                get = function() return db.height or 32 end,
                set = function(_, val)
                    db.height = val
                    SUB:UpdateSize(db)
                end,
                disabled = function() return not db.enabled end,
            },
            scale = {
                order = 5,
                type = "range",
                name = "Scale",
                desc = "Set the scale of the chat editbox.",
                min = 0.5, max = 2.0, step = 0.05,
                get = function() return db.scale or 1.0 end,
                set = function(_, val)
                    db.scale = val
                    SUB:UpdateSize(db)
                end,
                disabled = function() return not db.enabled end,
            },
            spacer = {
                order = 5.5,
                type = "description",
                name = " ",
                width = "full",
            },
            strataLevel = {
                order = 6,
                type = "select",
                name = "Frame Strata",
                desc = "Set the frame strata level of the chat editbox to control whether it appears above or below other UI elements (like ElvUI options).",
                values = STRATA_LEVELS,
                get = function() return db.strataLevel or 5 end,
                set = function(_, val)
                    db.strataLevel = val
                    local strata = STRATA_LEVELS[val] or "DIALOG"
                    if editbox then 
                        editbox:SetFrameStrata(strata)
                        editbox:SetFrameLevel(205)
                    end
                end,
                disabled = function() return not db.enabled end,
            },
        }
    }
end

function SUB:EnforcePosition(db)
    local h = EnsureHolder(db)
    if not h or not editbox then return end

    if db.enabled then
        h:SetSize((db and db.width) or 320, (db and db.height) or 32)
        editbox:SetParent(h)
        editbox:ClearAllPoints()
        editbox:SetAllPoints(h)
        h:SetScale((db and db.scale) or 1.0)
        
        local strata = STRATA_LEVELS[db and db.strataLevel or 5] or "DIALOG"
        editbox:SetFrameStrata(strata)
        editbox:SetFrameLevel(205)
    end
end

function SUB:ApplyEnabled(db)
    if not editbox then return end
    local h = EnsureHolder(db)
    if not h then return end
    
    if E and E:GetModule('Chat') and not isHooked then
        local CH = E:GetModule('Chat')
        hooksecurefunc(CH, "UpdateAnchors", function()
            if db.enabled then
                SUB:EnforcePosition(db)
            end
        end)
        hooksecurefunc("ChatEdit_UpdateHeader", function(eb)
            if db.enabled and eb == editbox then
                local strata = STRATA_LEVELS[db and db.strataLevel or 5] or "DIALOG"
                eb:SetFrameStrata(strata)
                eb:SetFrameLevel(205)
            end
        end)
        isHooked = true
    end

    SUB:EnforcePosition(db)
    if db and db.debug then print("[ChatEditboxMover] Enabled and mover registered") end
end

function SUB:UpdateSize(db)
    local h = EnsureHolder(db)
    if h then
        h:SetSize((db and db.width) or 320, (db and db.height) or 32)
        h:SetScale((db and db.scale) or 1.0)
    end
    SUB:EnforcePosition(db)
end

function SUB:DisableMover()
    if not E then return end
    local CH = E:GetModule('Chat')
    -- Re-run ElvUI's chat anchors update to restore standard position
    if CH and CH.UpdateAnchors then
        -- Temporarily clear our enabled flag so the hook doesn't override it immediately
        local originalHook = isHooked
        isHooked = false -- to prevent our hook from forcing it back if we call UpdateAnchors
        -- wait, our hook checks db.enabled. Since we just set it to false, our hook does nothing.
        isHooked = originalHook
        CH:UpdateAnchors()
    end
    if editbox then
        editbox:SetParent(UIParent)
        editbox:ClearAllPoints()
        editbox:SetPoint("BOTTOMLEFT", ChatFrame1, "TOPLEFT", 0, 0)
    end
end

-- Initialize the holder silently if it's supposed to be registered, but do it safely
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function()
    -- Create the mover so it's always available in the ElvUI movers list if needed
    local db = MOD.defaults.ChatEditboxMover or {}
    EnsureHolder(db)
end)

MOD:RegisterSubmodule("ChatEditboxMover", SUB)

