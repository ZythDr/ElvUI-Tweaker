local core = EWTweaker and EWTweaker.GetCore and EWTweaker.GetCore()
if not core then return end

local MOD = core.modules and core.modules.MiscTweaks
if not MOD then return end

local SUB = { name = "Microbar Tweaks" }

SUB.defaults = {
    enabled = true,
    selection_gap = true,
    selection_custom = true,
    hideTarget = "LFDMicroButton",
    replaceTarget = "LFDMicroButton", -- "NONE" for extra
    customType = "LFG",
    visibility = {
        CharacterMicroButton = true,
        SpellbookMicroButton = true,
        TalentMicroButton = true,
        AchievementMicroButton = true,
        QuestLogMicroButton = true,
        SocialsMicroButton = true,
        PVPMicroButton = true,
        LFDMicroButton = true,
        MainMenuMicroButton = true,
        HelpMicroButton = true,
    }
}

local E, L, V, P, G = unpack(_G.ElvUI)
local AB = E:GetModule("ActionBars")

local MICRO_BUTTONS = {
    "CharacterMicroButton",
    "SpellbookMicroButton",
    "TalentMicroButton",
    "AchievementMicroButton",
    "QuestLogMicroButton",
    "SocialsMicroButton",
    "PVPMicroButton",
    "LFDMicroButton",
    "MainMenuMicroButton",
    "HelpMicroButton",
}

-- Coordinate Presets
local COORDS = {
    LFG = {
        normal = { 0.17, 0.83, 0.05, 1.0 },
        pushed = { 0.20, 0.86, 0.02, 0.97 },
    },
    MOUNT = {
        normal = { 0.19, 0.91, 0.05, 1.0 },
        pushed = { 0.22, 0.94, 0.02, 0.97 },
    }
}

local function ApplyTexCoords(texture, mode, isPushed)
    local cfg = COORDS[mode] or COORDS.LFG
    local coords = isPushed and cfg.pushed or cfg.normal
    texture:SetTexCoord(unpack(coords))
end

local customButton
local lastTexture
local LFG_Internal

-- Helper to safely get the database
local function GetDB()
    if SUB.db then return SUB.db end
    if core.db and core.db.profile and core.db.profile.MiscTweaks and core.db.profile.MiscTweaks.MicrobarTweaks then
        return core.db.profile.MiscTweaks.MicrobarTweaks
    end
    return SUB.defaults
end

local function UpdateLayout()
    local subdb = GetDB()
    if not subdb.enabled then return end

    if customButton then customButton:Hide() end

    local isCustom = subdb.selection_custom
    local customType = subdb.customType or "LFG"
    local replaceTarget = subdb.replaceTarget or "LFDMicroButton"

    local isLFG = isCustom and customType == "LFG"
    local isMount = isCustom and customType == "MOUNT"

    local db = AB.db.microbar
    -- If ElvUI microbar is disabled, stop
    if not db.enabled then return end

    local offset = E:Scale(E.PixelMode and 1 or 3)
    local spacing = E:Scale(offset + db.buttonSpacing)
    local buttonsPerRow = db.buttonsPerRow
    -- If we are adding an extra button and the row is at the native max (10),
    -- bump it to 11 internally to prevent the extra button from wrapping to a new row.
    if isCustom and replaceTarget == "NONE" and buttonsPerRow >= 10 then
        buttonsPerRow = buttonsPerRow + 1
    end

    -- Pre-create custom button if needed
    if isCustom and not customButton and ElvUI_MicroBar then
        customButton = CreateFrame("Button", "EWT_MicrobarCustomButton", ElvUI_MicroBar)
        customButton:SetHighlightTexture("")
        customButton:SetPushedTexture("")
        customButton:SetNormalTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        AB:HandleMicroButton(customButton)
        customButton:Hide()
    end

    -- Setup custom button properties if it exists
    if isCustom and customButton then
        customButton:Size(db.buttonSize, db.buttonSize * 1.4)
        local icon = isLFG and "Interface\\Addons\\LFG\\images\\eye\\battlenetworking0" or
            (isMount and "Interface\\AddOns\\ElvUI-Tweaker_MiscTweaks\\media\\MountJournalPortrait" or "Interface\\Icons\\INV_Misc_QuestionMark")
        local m = isMount and "MOUNT" or "LFG"

        local normal = customButton:GetNormalTexture()
        if normal then
            normal:SetTexture(icon)
            ApplyTexCoords(normal, m, false)
        end
        local pushed = customButton:GetPushedTexture()
        if pushed then
            pushed:SetTexture(icon)
            ApplyTexCoords(pushed, m, true)
            pushed:SetVertexColor(0.5, 0.5, 0.5)
            pushed:SetAllPoints()
        end

        customButton:SetScript("OnClick", function()
            if isLFG then
                if _G.LFG_Toggle then
                    _G.LFG_Toggle()
                elseif _G.LFGParentFrame then
                    if _G.LFGParentFrame:IsShown() then
                        HideUIPanel(_G.LFGParentFrame)
                    else
                        ShowUIPanel(_G
                            .LFGParentFrame)
                    end
                end
            elseif isMount then
                ToggleCharacter("PetPaperDollFrame")
                if PetPaperDollFrame_SetTab then PetPaperDollFrame_SetTab(3) end
            end
        end)

        customButton:SetScript("OnEnter", function(self)
            if self.backdrop then self.backdrop:SetBackdropBorderColor(unpack(E.media.rgbvaluecolor)) end
            if isLFG then
                if LFG_ShowMinimap then
                    local oldThis = _G.this; _G.this = self; LFG_ShowMinimap(); _G.this = oldThis
                end
                -- Precision Anchor: Bottom-Right of tooltip to Top-Right of button
                GameTooltip:SetOwner(self, "ANCHOR_NONE")
                GameTooltip:ClearAllPoints()
                GameTooltip:SetPoint("BOTTOMLEFT", self, "TOPRIGHT", 0, 0)
                GameTooltip:AddLine("LFG - Dungeon Group Finder", 1, 1, 1)
                GameTooltip:Show()

                if LFGGroupStatus and LFGGroupStatus:IsShown() then
                    LFGGroupStatus:ClearAllPoints()
                    LFGGroupStatus:Point("BOTTOMLEFT", self, "TOPRIGHT", 0, 10)
                end
            elseif isMount then
                -- Match anchor for consistency
                GameTooltip:SetOwner(self, "ANCHOR_NONE")
                GameTooltip:ClearAllPoints()
                GameTooltip:SetPoint("BOTTOMLEFT", self, "TOPRIGHT", 0, 0)
                GameTooltip:AddLine("Mount Journal", 1, 1, 1)
                GameTooltip:Show()
            end
        end)
        customButton:SetScript("OnLeave", function(self)
            if self.backdrop then self.backdrop:SetBackdropBorderColor(unpack(E.media.bordercolor)) end
            if isLFG and LFG_HideMinimap then LFG_HideMinimap() end
            GameTooltip:Hide()
        end)

        if isLFG then
            customButton:SetScript("OnUpdate", function(self, elapsed)
                if not LFG_Internal and _G.findGroup and debug and debug.getupvalue then
                    local i = 1; while true do
                        local n, v = debug.getupvalue(_G.findGroup, i); if not n then break end
                        if n == "LFG" then
                            LFG_Internal = v
                            break
                        end
                        i = i + 1
                    end
                end

                local isQueued = LFG_Internal and (LFG_Internal.findingGroup or LFG_Internal.findingMore)
                if not isQueued and _G.LFG_MinimapEye then
                    local tex = _G.LFG_MinimapEye:GetTexture()
                    if tex and not strfind(tex, "battlenetworking0") then isQueued = true end
                end

                local isTesting = IsShiftKeyDown() and self:IsMouseOver()
                local frame = 0

                if _G.LFG_MinimapEye and isQueued and not isTesting then
                    local tex = _G.LFG_MinimapEye:GetTexture()
                    if tex then frame = tonumber(strmatch(tex, "battlenetworking(%d+)")) or 0 end
                elseif isQueued or isTesting then
                    self.animElapsed = (self.animElapsed or 0) + elapsed
                    if self.animElapsed > 0.1 then
                        self.animElapsed = 0
                        self.frameIndex = (self.frameIndex or 0) + 1
                        if self.frameIndex > 28 then self.frameIndex = 0 end
                    end
                    frame = self.frameIndex or 0
                end

                local texture = 'Interface\\Addons\\LFG\\images\\eye\\battlenetworking' .. frame
                if texture == lastTexture then return end
                lastTexture = texture

                local normal = self:GetNormalTexture()
                if normal then
                    normal:SetTexture(texture)
                    ApplyTexCoords(normal, "LFG", false)
                end
                local pushed = self:GetPushedTexture()
                if pushed then
                    pushed:SetTexture(texture)
                    ApplyTexCoords(pushed, "LFG", true)
                    pushed:SetVertexColor(0.5, 0.5, 0.5)
                    pushed:SetAllPoints()
                end
            end)
        else
            customButton:SetScript("OnUpdate", nil)
            lastTexture = nil
        end
    end

    local visibleButtons = {}

    -- 1. Assemble list of buttons to display
    for _, name in ipairs(MICRO_BUTTONS) do
        local btn = _G[name]
        if btn then btn:Hide() end

        -- Check visibility override
        local isVisible = subdb.visibility and subdb.visibility[name]
        if isVisible == nil then isVisible = true end -- Default to true if missing

        if isCustom and name == replaceTarget then
            if customButton then
                table.insert(visibleButtons, customButton)
                customButton:Show()
            end
            if btn then btn:Hide() end
        else
            if isVisible and btn then
                table.insert(visibleButtons, btn)
                btn:Show()
            end
        end
    end

    -- Handle Extra Button (Add at end)
    if isCustom and replaceTarget == "NONE" and customButton then
        table.insert(visibleButtons, customButton)
        customButton:Show()
    end

    -- 2. Position the buttons
    local prevButton = ElvUI_MicroBar
    local numRows = 1
    for i, btn in ipairs(visibleButtons) do
        btn:Size(db.buttonSize, db.buttonSize * 1.4)
        btn:ClearAllPoints()

        local col = (i - 1) % buttonsPerRow
        local row = math.floor((i - 1) / buttonsPerRow) + 1

        if row > numRows then numRows = row end

        if col == 0 then
            if row == 1 then
                btn:Point("TOPLEFT", ElvUI_MicroBar, "TOPLEFT", offset, -offset)
            else
                -- Align with the button at the start of the previous row
                local prevRowStart = visibleButtons[i - buttonsPerRow]
                if prevRowStart then
                    btn:Point("TOP", prevRowStart, "BOTTOM", 0, -spacing)
                else
                    -- Fallback if something is weird
                    btn:Point("TOPLEFT", ElvUI_MicroBar, "TOPLEFT", offset,
                        -(offset + (row - 1) * (db.buttonSize * 1.4 + spacing)))
                end
            end
        else
            btn:Point("LEFT", prevButton, "RIGHT", spacing, 0)
        end

        prevButton = btn
    end

    -- 3. Resize Bar
    local actualCols = math.min(#visibleButtons, buttonsPerRow)
    local microWidth = (((db.buttonSize + spacing) * actualCols) - spacing) + (offset * 2)
    local microHeight = (((db.buttonSize * 1.4 + spacing) * numRows) - spacing) + (offset * 2)

    if #visibleButtons > 0 then
        ElvUI_MicroBar:Size(microWidth, microHeight)
    end
end

function SUB:ApplyEnabled(db)
    SUB.db = db
    if db.enabled then
        if not SUB.isHooked then
            hooksecurefunc(AB, "UpdateMicroPositionDimensions", UpdateLayout)
            hooksecurefunc(AB, "UpdateMicroButtonsParent", UpdateLayout)
            SUB.isHooked = true
        end
        -- Unlock ElvUI buttons per row max to 11 to support "Extra Button" mode
        if E.Options and E.Options.args and E.Options.args.actionbar and E.Options.args.actionbar.args and E.Options.args.actionbar.args.microbar and E.Options.args.actionbar.args.microbar.args and E.Options.args.actionbar.args.microbar.args.buttonsPerRow then
            E.Options.args.actionbar.args.microbar.args.buttonsPerRow.max = 11
        end
        UpdateLayout()
    else
        -- If disabled, try to restore original state
        if customButton then customButton:Hide() end
        if LFDMicroButton then LFDMicroButton:Show() end
        if AB.UpdateMicroPositionDimensions then
            AB:UpdateMicroPositionDimensions()
        end
    end
end

function SUB:GetOptions(db)
    return {
        type = "group",
        name = SUB.name,
        args = {
            header = {
                order = 0,
                type = "header",
                name = "Microbar Tweaks",
            },
            description = {
                order = 1,
                type = "description",
                name =
                "Advanced tweaks for the ElvUI microbar. Use the checklist below to hide any unwanted buttons, or replace a button with a custom LFG/Mount shortcut.\n",
            },
            enabled = {
                order = 2,
                type = "toggle",
                name = function() return db.enabled and "|cff00ff00Enabled|r" or "|cffff0000Disabled|r" end,
                desc = "Toggle the Microbar Tweaks module.",
                width = "full",
                get = function() return db.enabled end,
                set = function(_, value)
                    db.enabled = value
                    SUB:ApplyEnabled(db)
                end,
            },
            visibilityGroup = {
                order = 3,
                type = "group",
                name = "Button Visibility",
                guiInline = true,
                disabled = function() return not db.enabled end,
                args = {
                    CharacterMicroButton = { order = 1, type = "toggle", name = "Character" },
                    SpellbookMicroButton = { order = 2, type = "toggle", name = "Spellbook" },
                    TalentMicroButton = { order = 3, type = "toggle", name = "Talents" },
                    AchievementMicroButton = { order = 4, type = "toggle", name = "Achievements" },
                    QuestLogMicroButton = { order = 5, type = "toggle", name = "Quest Log" },
                    SocialsMicroButton = { order = 6, type = "toggle", name = "Social" },
                    PVPMicroButton = { order = 7, type = "toggle", name = "PVP" },
                    LFDMicroButton = { order = 8, type = "toggle", name = "LFD (Dungeons)" },
                    MainMenuMicroButton = { order = 9, type = "toggle", name = "Main Menu" },
                    HelpMicroButton = { order = 10, type = "toggle", name = "Help" },
                },
                get = function(info)
                    if not db.visibility then db.visibility = {} end
                    local val = db.visibility[info[#info]]
                    return val == nil and true or val
                end,
                set = function(info, value)
                    if not db.visibility then db.visibility = {} end
                    db.visibility[info[#info]] = value
                    UpdateLayout()
                end,
            },
            spacer = {
                order = 4,
                type = "description",
                name = "\n",
            },
            selection_custom = {
                order = 5,
                type = "toggle",
                name = "Custom Button",
                desc = "Enable the custom shortcut button.",
                get = function() return db.selection_custom end,
                set = function(_, value)
                    db.selection_custom = value
                    UpdateLayout()
                end,
                disabled = function() return not db.enabled end,
            },
            replaceTarget = {
                order = 6,
                type = "select",
                name = "Placement / Replacement",
                desc = "Select which button to replace, or add as extra.",
                values = {
                    ["NONE"] = "|cff00ff00Add as Extra (No Replacement)|r",
                    ["CharacterMicroButton"] = "Replace Character",
                    ["SpellbookMicroButton"] = "Replace Spellbook",
                    ["TalentMicroButton"] = "Replace Talents",
                    ["AchievementMicroButton"] = "Replace Achievements",
                    ["QuestLogMicroButton"] = "Replace Quest Log",
                    ["SocialsMicroButton"] = "Replace Social",
                    ["PVPMicroButton"] = "Replace PVP",
                    ["LFDMicroButton"] = "Replace LFD",
                    ["MainMenuMicroButton"] = "Replace Main Menu",
                    ["HelpMicroButton"] = "Replace Help",
                },
                get = function() return db.replaceTarget or "LFDMicroButton" end,
                set = function(_, value)
                    db.replaceTarget = value
                    UpdateLayout()
                end,
                disabled = function() return not db.enabled or not db.selection_custom end,
            },
            customType = {
                order = 7,
                type = "select",
                width = "double",
                name = "Button Type",
                desc = "Choose which custom button to display.",
                values = {
                    ["LFG"] = "LFG Addon Integration",
                    ["MOUNT"] = "Mount Journal Shortcut",
                },
                get = function() return db.customType or "LFG" end,
                set = function(_, value)
                    db.customType = value
                    UpdateLayout()
                end,
                disabled = function() return not db.enabled or not db.selection_custom end,
            },
        },
    }
end

MOD:RegisterSubmodule("MicrobarTweaks", SUB)

-- Unlock ElvUI buttons per row max to 11 (Late Injection)
local function UnlockSlider()
    if E.Options and E.Options.args and E.Options.args.actionbar and E.Options.args.actionbar.args and E.Options.args.actionbar.args.microbar and E.Options.args.actionbar.args.microbar.args and E.Options.args.actionbar.args.microbar.args.buttonsPerRow then
        E.Options.args.actionbar.args.microbar.args.buttonsPerRow.max = 11
        return true
    end
end

-- Login/Reload Sanity Watcher
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:SetScript("OnEvent", function(self)
    -- Initial wake-up
    local db = GetDB()
    if db and db.enabled then
        SUB:ApplyEnabled(db)
    end

    local elapsed = 0
    local sliderUnlocked = false
    self:SetScript("OnUpdate", function(s, e)
        elapsed = elapsed + e

        -- Try to unlock the slider until it works (options might load late)
        if not sliderUnlocked then
            sliderUnlocked = UnlockSlider()
        end

        -- Run layout update every second for 5 seconds to ensure stability
        if elapsed > 1 then
            UpdateLayout()
            if elapsed > 5 and sliderUnlocked then
                s:SetScript("OnUpdate", nil)
            end
        end
    end)
end)
