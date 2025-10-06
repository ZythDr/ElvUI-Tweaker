-- MovementSpeed.lua
-- ElvUI DataTexts submodule: Movement Speed DataText
-- Simple, robust: always displays accurate movement speed as an integer percent, with a single enable toggle.
-- Tooltip is hidden on mouse leave but polling continues while the module is enabled.

local core = EWTweaker and EWTweaker.GetCore and EWTweaker.GetCore()
if not core then return end
local MOD = core.modules and core.modules.DataTexts
if not MOD then return end

local SUB = { name = "Movement Speed" }
SUB.defaults = {
    enabled = true,
}
local db_local

local E, L, V, P, G = unpack(ElvUI)
local DT = E:GetModule("DataTexts")
local displayName = "|cff00FF96Movement Speed|r"

local valueColor = E.media.hexvaluecolor or "|cffffffff"
local lastSpeed = -1
local activePanel = nil

-- Value color sync
local function ValueColorUpdate(hex)
    valueColor = hex or "|cffffffff"
end
E.valueColorUpdateFuncs[ValueColorUpdate] = true

local function GetConfig()
    return MOD.db and MOD.db.MovementSpeed or SUB.defaults
end

local function GetSpeed()
    local speed = GetUnitSpeed("player") or 0
    local percent = (speed / 7) * 100
    -- Round to nearest integer for display
    return math.floor(percent + 0.5)
end

local function UpdateDisplay(panel, percent)
    if panel and panel.text then
        panel.text:SetFormattedText("Speed: %s%d%%|r", valueColor, percent)
    end
end

-- Fixed update interval (0.5s)
local elapsedSinceLast = 0
local pollInterval = 0.5
local speedFrame = CreateFrame("Frame")
speedFrame:Hide()
speedFrame:SetScript("OnUpdate", function(self, elapsed)
    elapsedSinceLast = elapsedSinceLast + elapsed
    if elapsedSinceLast < pollInterval then return end
    elapsedSinceLast = 0
    if activePanel then
        local percent = GetSpeed()
        if percent ~= lastSpeed then
            lastSpeed = percent
            UpdateDisplay(activePanel, percent)
        end
    end
end)

local function OnEvent(self)
    -- Set the active panel to ensure the displayed text updates continuously even when not hovered.
    activePanel = self
    lastSpeed = GetSpeed()
    UpdateDisplay(self, lastSpeed)
    -- Ensure the poller is running while module is enabled
    speedFrame:Show()
end

local function OnEnter(self)
    activePanel = self
    DT:SetupTooltip(self)
    if DT.tooltip then
        DT.tooltip:AddLine("Movement Speed")
        DT.tooltip:AddLine(("Current: |cffffffff%d%%|r"):format(lastSpeed))
        DT.tooltip:Show()
    end
    -- Keep the poller running while hovered
    speedFrame:Show()
end

local function OnLeave(self)
    -- Only hide the tooltip. Keep updating the datatext value while the module is enabled.
    if DT and DT.tooltip and DT.tooltip:IsShown() then
        DT.tooltip:Hide()
    end
    -- Do NOT clear activePanel or hide the speedFrame here; updates should continue as long as the module is enabled.
end

local function ForceDataTextUpdate()
    for panelName, panel in pairs(DT.StatusPanels or {}) do
        for dataPanelName, dataPanel in pairs(panel.dataPanels or {}) do
            if dataPanel.name == "Movement Speed" or dataPanel.name == displayName then
                if dataPanel.text then
                    OnEvent(dataPanel)
                end
            end
        end
    end
    if DT.RegisteredDataTexts and DT.RegisteredDataTexts[displayName] and DT.RegisteredDataTexts[displayName].frame then
        OnEvent(DT.RegisteredDataTexts[displayName].frame)
    end
end

DT:RegisterDatatext("Movement Speed",
    {"PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "PLAYER_MOUNT_DISPLAY_CHANGED", "UNIT_AURA", "PLAYER_AURAS_CHANGED", "UPDATE_SHAPESHIFT_FORM"},
    OnEvent, nil, nil, OnEnter, OnLeave, displayName)

function SUB:OnEnable()
    speedFrame:Show()
    if C_Timer and C_Timer.After then
        C_Timer.After(1, ForceDataTextUpdate)
    else
        ForceDataTextUpdate()
    end
end

function SUB:OnDisable()
    speedFrame:Hide()
    activePanel = nil
end

function SUB:GetOptions(db)
    db = db or (MOD.db and MOD.db.MovementSpeed or SUB.defaults)
    return {
        type = "group",
        name = SUB.name,
        args = {
            header = {
                order = 0,
                type = "header",
                name = "Movement Speed",
            },
            desc = {
                order = 1,
                type = "description",
                name = "Displays your current movement speed as a percentage.\nStanding still = 0%\nBaseline run speed = 100%\n\nExample: A Hunter with 2/2 Pathfinding runs at 138% with Aspect of the Cheetah active.\n(Baseline 100% + Aspect 30% + Pathfinding 8%)\n",
            },
            desc = {
                order = 2,
                type = "description",
                name = "Disabling this module only prevents the DataText from updating.\n",
            },
            enabled = {
                order = 3,
                type = "toggle",
                name = function() return db.enabled and "|cff00ff00Enabled|r" or "|cffff0000Disabled|r" end,
                get = function() return db.enabled end,
                set = function(_, v)
                    db.enabled = v
                    if v then SUB:OnEnable() else SUB:OnDisable() end
                end,
            },
        },
    }
end

MOD:RegisterSubmodule("MovementSpeed", SUB)
