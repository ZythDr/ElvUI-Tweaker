-- init.lua
-- Runs after OptionsTweaks.lua (ensure TOC order: OptionsTweaks.lua then init.lua then modules/Load_Modules.xml).
-- Exposes lightweight helpers for modules and (optionally) runs any pending registrations.

print("|cff00ff00[OptionsTweaks:init]|r init.lua running")

local core = EWTweaker and EWTweaker.GetCore and EWTweaker.GetCore()
if not core then
    print("|cff00ff00[OptionsTweaks:init]|r EWTweaker core NOT present")
    return
end

print("|cff00ff00[OptionsTweaks:init]|r EWTweaker core present")

core.modules_helpers = core.modules_helpers or {}

core.modules_helpers.safe = function(fn, name)
    local ok, err = pcall(fn)
    if not ok then
        print("|cff00ff00[ElvUI Tweaker]|r Module error in " .. (name or "<unknown>") .. ": " .. tostring(err))
    end
end

if EWTweaker and EWTweaker.RunPendingSubmoduleRegistrations then
    pcall(EWTweaker.RunPendingSubmoduleRegistrations)
end
