local core = EWTweaker and EWTweaker.GetCore and EWTweaker.GetCore()
if not core then return end

local MOD = core.modules and core.modules.MiscTweaks
if not MOD then return end

local SUB = { name = "Microbar Tweaks" }

SUB.defaults = {
    enabled = true,
    fixGap = true,
    addMounts = true,
    lfgAddon = true,
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
    "HelpMicroButton"
}

local mountButton

local function OnEnter(self)
    if AB.db.microbar.mouseover then
        E:UIFrameFadeIn(ElvUI_MicroBar, 0.2, ElvUI_MicroBar:GetAlpha(), AB.db.microbar.alpha)
    end
    if self.backdrop then
        self.backdrop:SetBackdropBorderColor(unpack(E.media.rgbvaluecolor))
    end
    
    if self == mountButton then
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Mounts & Pets")
        GameTooltip:Show()
    elseif self == _G.LFDMicroButton and SUB.db.lfgAddon then
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Looking For Group (Addon)")
        GameTooltip:Show()
    end
end

local function OnLeave(self)
    if AB.db.microbar.mouseover then
        E:UIFrameFadeOut(ElvUI_MicroBar, 0.2, ElvUI_MicroBar:GetAlpha(), 0)
    end
    if self.backdrop then
        self.backdrop:SetBackdropBorderColor(unpack(E.media.bordercolor))
    end
    GameTooltip:Hide()
end

local function CreateMountButton()
    if mountButton then return end
    
    mountButton = CreateFrame("Button", "EWT_MountMicroButton", _G.ElvUI_MicroBar)
    mountButton:Size(AB.db.microbar.buttonSize, AB.db.microbar.buttonSize * 1.4)
    
    mountButton:SetScript("OnClick", function()
        ToggleCharacter("PetPaperDollFrame")
    end)
    
    local normal = mountButton:CreateTexture(nil, "ARTWORK")
    normal:SetTexture("Interface\\Icons\\Ability_Mount_RidingHorse")
    normal:SetInside()
    mountButton.normal = normal
    
    local pushed = mountButton:CreateTexture(nil, "ARTWORK")
    pushed:SetTexture("Interface\\Icons\\Ability_Mount_RidingHorse")
    pushed:SetInside()
    pushed:SetVertexColor(0.5, 0.5, 0.5)
    mountButton:SetPushedTexture(pushed)
    
    AB:HandleMicroButton(mountButton)
    
    -- Override the crop that ElvUI applies in HandleMicroButton
    mountButton:GetNormalTexture():SetTexCoord(0.08, 0.92, 0.08, 0.92)
    mountButton:GetPushedTexture():SetTexCoord(0.08, 0.92, 0.08, 0.92)
    
    mountButton:SetScript("OnEnter", OnEnter)
    mountButton:SetScript("OnLeave", OnLeave)
end

local function UpdateLayout()
    if not ElvUI_MicroBar or not SUB.db.enabled then return end
    local db = AB.db.microbar
    
    local offset = E:Scale(E.PixelMode and 1 or 3)
    local spacing = E:Scale(offset + db.buttonSpacing)
    local buttonsPerRow = db.buttonsPerRow
    
    local prevButton = ElvUI_MicroBar
    local numRows = 1
    local visibleCount = 0
    
    local buttons = {}
    for _, name in ipairs(MICRO_BUTTONS) do
        local btn = _G[name]
        
        -- Custom Mounts button insertion (before LFD/MainMenu)
        if name == "LFDMicroButton" and SUB.db.addMounts then
            if not mountButton then CreateMountButton() end
            table.insert(buttons, mountButton)
        end
        
        if btn then
            if name == "LFDMicroButton" then
                if SUB.db.lfgAddon then
                    btn:Show()
                    if not btn.isHookedEWT then
                        btn:SetScript("OnClick", function()
                            if _G.LFG_Toggle then _G.LFG_Toggle()
                            elseif _G.SlashCmdList["LFG"] then _G.SlashCmdList["LFG"]("") end
                        end)
                        btn:HookScript("OnEnter", OnEnter)
                        btn:HookScript("OnLeave", OnLeave)
                        btn.isHookedEWT = true
                    end
                end
            end
            table.insert(buttons, btn)
        end
    end
    
    local rowButtons = {}
    
    for _, button in ipairs(buttons) do
        -- If fixGap is on, we skip hidden buttons for positioning
        if button and (not SUB.db.fixGap or button:IsShown()) then
            visibleCount = visibleCount + 1
            button:Size(db.buttonSize, db.buttonSize * 1.4)
            button:ClearAllPoints()
            
            local col = (visibleCount - 1) % buttonsPerRow
            local row = math.floor((visibleCount - 1) / buttonsPerRow) + 1
            
            if row > numRows then numRows = row end
            
            if col == 0 then
                if row == 1 then
                    button:Point("TOPLEFT", ElvUI_MicroBar, "TOPLEFT", offset, -offset)
                else
                    button:Point("TOP", rowButtons[row-1], "BOTTOM", 0, -spacing)
                end
                rowButtons[row] = button
            else
                button:Point("LEFT", prevButton, "RIGHT", spacing, 0)
            end
            
            prevButton = button
        end
    end
    
    -- Update MicroBar size
    local microWidth = (((db.buttonSize + spacing) * buttonsPerRow) - spacing) + (offset * 2)
    local microHeight = (((db.buttonSize * 1.4 + spacing) * numRows) - spacing) + (offset * 2)
    ElvUI_MicroBar:Size(microWidth, microHeight)
end

function SUB:ApplyEnabled(db)
    SUB.db = db
    if not SUB.isHooked then
        hooksecurefunc(AB, "UpdateMicroPositionDimensions", UpdateLayout)
        SUB.isHooked = true
    end
    
    if SUB.db.addMounts then
        if not mountButton then CreateMountButton() end
        mountButton:Show()
    elseif mountButton then
        mountButton:Hide()
    end
    
    AB:UpdateMicroPositionDimensions()
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
            fixGap = {
                order = 1,
                type = "toggle",
                name = "Fix Microbar Gap",
                desc = "Automatically shift buttons to close gaps left by hidden menu items.",
                get = function() return db.fixGap end,
                set = function(_, value) db.fixGap = value; SUB:ApplyEnabled(db) end,
            },
            addMounts = {
                order = 2,
                type = "toggle",
                name = "Add Mounts Button",
                desc = "Add a custom Mounts & Pets micro button to the bar.",
                get = function() return db.addMounts end,
                set = function(_, value) db.addMounts = value; SUB:ApplyEnabled(db) end,
            },
            lfgAddon = {
                order = 3,
                type = "toggle",
                name = "LFG Addon Integration",
                desc = "Restore the Dungeon Finder button but make it open the custom LFG Addon GUI.",
                get = function() return db.lfgAddon end,
                set = function(_, value) db.lfgAddon = value; SUB:ApplyEnabled(db) end,
            },
        },
    }
end

MOD:RegisterSubmodule("MicrobarTweaks", SUB)
