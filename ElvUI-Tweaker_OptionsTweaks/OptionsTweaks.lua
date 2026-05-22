local core = EWTweaker and EWTweaker.GetCore and EWTweaker.GetCore()
local L = LibStub("AceLocale-3.0-ElvUI"):GetLocale("ElvUI", true)
if not L then L = setmetatable({}, { __index = function(_, k) return k end }) end

local MOD = {}
_G.EWTweaker_OptionsTweaks = MOD

if not core then return end
print("|cff00ff00[OptionsTweaks]|r OptionsTweaks.lua running")

MOD.name = L["Options Tweaks"]
MOD.defaults = {
    Search = {
        enabled = true,
        includeDescriptions = true,
        includeKeys = true,
        gridResults = true,
        maxResults = 40,
    },
}
MOD.submodules = {}

function MOD:RegisterSubmodule(name, tbl)
    MOD.submodules[name] = tbl
end

function MOD:GetOptions(db)
    db = db or (core and core.GetDB and core:GetDB().OptionsTweaks) or {}
    self.db = db

    local opts = {
        type = "group",
        name = self.name,
        args = {
            header = {
                order = 1,
                type = "header",
                name = self.name,
            },
        },
    }

    local order = 10
    for key, sub in pairs(self.submodules) do
        if sub.GetOptions then
            if not db[key] then db[key] = {} end
            opts.args[key] = sub:GetOptions(db[key])
            opts.args[key].order = order
            opts.args[key].name = sub.name or key
            opts.args[key].guiInline = true
        end
        order = order + 1
    end

    return opts
end

function MOD:ApplyEnabledModules()
    local db = (core and core.GetDB and core:GetDB().OptionsTweaks) or {}
    self.db = db

    for key, sub in pairs(self.submodules) do
        local subDB = db[key]
        if subDB and subDB.enabled then
            if sub.OnEnable then
                sub:OnEnable(subDB)
            end
        elseif sub.OnDisable then
            sub:OnDisable(subDB)
        end
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent", function()
    MOD:ApplyEnabledModules()
end)

core:RegisterModule("OptionsTweaks", MOD, MOD.defaults)
