local core = EWTweaker and EWTweaker.GetCore and EWTweaker.GetCore()
if not core then return end
print("|cff00ff00[MiscTweaks]|r MiscTweaks.lua running")

local L = LibStub("AceLocale-3.0-ElvUI"):GetLocale("ElvUI", true)
if not L then L = setmetatable({}, { __index = function(t, k) return k end }) end

local MOD = {}
MOD.name = L["MiscTweaks"]
-- Ensure all submodules have empty tables in defaults for proper DB handoff
MOD.defaults = {
    LevelCap = {},
    TooltipAnchor = {},
    PortraitFix = {},
    PortraitDiag = {},
    ThreatColors = {},
    GameTimeDisplay = {} -- ADD THIS LINE for proper DB persistence!
}
MOD.submodules = {}

function MOD:RegisterSubmodule(name, tbl)
    MOD.submodules[name] = tbl
end

function MOD:GetOptions(db)
    db = db or (core and core.GetDB and core:GetDB().MiscTweaks) or {}
    local opts = {
        type = "group",
        name = self.name,
        childGroups = "tab",
        args = {},
    }
    local order = 1
    for key, sub in pairs(self.submodules) do
        if sub.GetOptions then
            if not db[key] then db[key] = {} end
            opts.args[key] = sub:GetOptions(db[key])
            opts.args[key].order = order
            opts.args[key].name = sub.name or key
        end
        order = order + 1
    end
    return opts
end

function MOD:ApplyEnabledModules()
    local db = (core and core.GetDB and core:GetDB().MiscTweaks) or {}
    for key, sub in pairs(self.submodules) do
        local subdb = db[key]
        if subdb and subdb.enabled then
            if sub.ApplyEnabled then
                sub:ApplyEnabled(subdb)
            elseif sub.OnEnable then
                sub:OnEnable(subdb)
            end
        elseif sub and sub.DisableAnchor then
            sub:DisableAnchor() -- For TooltipAnchor-style disables
        end
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent", function()
    MOD:ApplyEnabledModules()
end)

core:RegisterModule("MiscTweaks", MOD, MOD.defaults)

_G.EWTweaker_MiscTweaks = MOD