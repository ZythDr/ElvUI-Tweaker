-- init.lua
-- Runs after MiscTweaks.lua (ensure TOC order: MiscTweaks.lua then init.lua then modules/Load_Modules.xml).
-- Exposes lightweight helpers for modules and (optionally) runs any pending registrations.

print("|cff00ff00[MiscTweaks:init]|r init.lua running")

local core = EWTweaker and EWTweaker.GetCore and EWTweaker.GetCore()
if not core then
    print("|cff00ff00[MiscTweaks:init]|r EWTweaker core NOT present")
    return
end

print("|cff00ff00[MiscTweaks:init]|r EWTweaker core present")

-- small helpers table modules can access via: local helpers = EWTweaker.modules_helpers
core.modules_helpers = core.modules_helpers or {}

-- safe pcall helper for fragile calls inside modules
core.modules_helpers.safe = function(fn, name)
    local ok, err = pcall(fn)
    if not ok then
        print("|cff00ff00[ElvUI Tweaker]|r Module error in " .. (name or "<unknown>") .. ": " .. tostring(err))
    end
end

-- Optional: if you implemented the pending registration queue in core.lua, run it now.
-- This makes modules resilient to accidental load-order differences.
if EWTweaker and EWTweaker.RunPendingSubmoduleRegistrations then
    pcall(EWTweaker.RunPendingSubmoduleRegistrations)
end