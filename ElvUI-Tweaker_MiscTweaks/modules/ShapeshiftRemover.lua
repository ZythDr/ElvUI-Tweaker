-- ShapeshiftRemover.lua
-- MiscTweaks submodule: "Shapeshift Remover"
-- ElvUI-safe: does NOT attempt to programmatically show ElvUI/Blizzard reload popups.
-- When custom buffs are added/removed we mark db._needsReload = true and instruct the user to reload the UI.

local core = EWTweaker and EWTweaker.GetCore and EWTweaker.GetCore()
if not core then return end
local MOD = core.modules and core.modules.MiscTweaks
if not MOD then return end

local SUB = { name = "Shapeshift Remover" }

local PREDEFINED_SHAPESHIFTS = {
    { name = "Furbolg Form", id = 6405 },
    { name = "Noggenfogger Elixir (Skeleton)", id = 16591 },
}

SUB.defaults = {
    enabled = false,
    debug = false,
    debugLevel = 2, -- 1 = removals-only, 2 = verbose
    _tmpBuffToAdd = "",
    whitelist = {},           -- array of {name="BuffName", id=12345} tables
    customEnabled = {},       -- map id -> true/false for custom checkboxes
    selectedWhitelist = nil,
    predefs = {},             -- map id -> true/false for predefined toggles
    removeOnTaxiOpen = true,
    _needsReload = false,     -- true if changes require a UI reload to show in open options
}

local db_local -- will be set in OnEnable(db)
local driver

local function trim(s) return (s or ""):gsub("^%s*(.-)%s*$", "%1") end

-- Helper: Try to find spell ID by scanning player buffs for matching name
local function FindSpellIDByName(buffName)
    if not buffName or buffName == "" then return nil end
    buffName = buffName:lower()
    
    for i = 1, 40 do
        local name, rank, icon, count, debuffType, duration, expirationTime, unitCaster, isStealable, shouldConsolidate, spellId = UnitBuff("player", i)
        if name and spellId and name:lower() == buffName then
            return spellId, name
        end
    end
    return nil
end

-- dbg(...) behavior:
-- - If first arg is a number it is treated as debug level (1 or 2). Otherwise default level = 2.
-- - Only prints if db_local.debug is true and level <= db_local.debugLevel.
-- - Suppresses empty/whitespace-only messages.
local function dbg(...)
    if not (db_local and db_local.debug) then return end
    local nargs = select("#", ...)
    if nargs == 0 then return end

    local first = select(1, ...)
    local level = 2
    local startIdx = 1
    if type(first) == "number" then
        level = first
        startIdx = 2
    end

    local configuredLevel = tonumber(db_local.debugLevel) or 2
    if level > configuredLevel then return end

    local parts = {}
    for i = startIdx, nargs do
        local v = select(i, ...)
        parts[#parts+1] = tostring(v == nil and "<nil>" or v)
    end
    local msg = trim(table.concat(parts, " "))
    if msg == "" then return end

    print("|cff00ff00[ShapeshiftRemover][DEBUG]|r", "[" .. tostring(level) .. "]", msg)
end

local function GetAllBuffSpellIDs()
    local s = db_local or {}
    local out = {} -- map: spellID -> buffName
    
    -- Add predefined shapeshifts
    for _, v in ipairs(PREDEFINED_SHAPESHIFTS) do
        if s.predefs and s.predefs[v.id] then
            local buffName = GetSpellInfo and GetSpellInfo(v.id) or v.name
            if buffName then 
                out[v.id] = buffName
            end
        end
    end
    
    -- Add custom buffs
    for _, entry in ipairs(s.whitelist or {}) do
        if entry and entry.id then
            if s.customEnabled == nil or s.customEnabled[entry.id] == nil or s.customEnabled[entry.id] == true then
                local buffName = GetSpellInfo and GetSpellInfo(entry.id) or entry.name
                if buffName then
                    out[entry.id] = buffName
                end
            end
        end
    end
    
    return out
end

local function RemoveAllWhitelistedBuffs(source)
    local s = db_local or {}
    local all = GetAllBuffSpellIDs() -- map: spellID -> buffName

    -- Make a stable list of IDs to scan
    local ids = {}
    for id in pairs(all) do table.insert(ids, id) end
    local totalIDs = #ids

    dbg(2, "RemoveAllWhitelistedBuffs invoked. Source:", tostring(source or "<none>"))
    dbg(2, "Step: beginning scan of " .. tostring(totalIDs) .. " configured spell ID(s) across up to 40 buff slots.")

    local removed = {}
    local notfound = {}
    local scannedAny = false
    local removedDetails = {} -- spellID -> {name, slots}

    for _, spellID in ipairs(ids) do
        local buffName = all[spellID]
        local removedSlots = {}
        
        for i = 1, 40 do
            local name, rank, icon, count, debuffType, duration, expirationTime, unitCaster, isStealable, shouldConsolidate, spellId = UnitBuff("player", i)
            if spellId and spellId == spellID then
                CancelUnitBuff("player", i)
                scannedAny = true
                table.insert(removedSlots, tostring(i))
                dbg(2, "Removed buff at slot", i, "- Name:", name, "SpellID:", spellId)
            end
        end
        
        if #removedSlots > 0 then
            table.insert(removed, buffName .. " (" .. spellID .. ")")
            removedDetails[spellID] = {name = buffName, slots = removedSlots}
        else
            table.insert(notfound, buffName .. " (" .. spellID .. ")")
        end
    end

    -- USER-FACING: only print removal summary when debug is enabled (per request)
    if s and s.debug then
        if #removed > 0 then
            print("|cff00ff00[ShapeshiftRemover]|r Removed buffs: " .. table.concat(removed, ", ") .. (source and (" ["..source.."]") or ""))
        else
            dbg(1, "No configured buff instances were present to remove (source: " .. tostring(source or "<none>") .. ").")
        end
    end

    -- DEBUG specifics (level 1 & 2)
    if #removed > 0 then
        dbg(1, "Removed (summary): " .. table.concat(removed, ", "))
        for spellID, data in pairs(removedDetails) do
            dbg(2, "Detail: Removed '" .. tostring(data.name) .. "' (ID:" .. tostring(spellID) .. ") from slots: " .. table.concat(data.slots, ","))
        end
        dbg(2, "RemoveAllWhitelistedBuffs finished. Removed count:", tostring(#removed), "Not found count:", tostring(#notfound))
    else
        if scannedAny then
            dbg(2, "RemoveAllWhitelistedBuffs finished: scanned slots but no configured buffs were present.")
        else
            dbg(2, "RemoveAllWhitelistedBuffs finished: no configured buff IDs were enabled (nothing scanned).")
        end
    end

    return removed, notfound
end

local SHAPESHIFT_ERROR = _G.ERR_CANT_MOUNT_WHILE_SHAPESHIFTED or "You can't mount while shapeshifted."

local function OnUIError(self, event, errorText, ...)
    dbg(2, "EVENT: UI_ERROR_MESSAGE fired. Arg1:", tostring(errorText))
    if errorText == SHAPESHIFT_ERROR then
        dbg(2, "Detected shapeshift restriction error, calling removal routine.")
        RemoveAllWhitelistedBuffs("UI_ERROR_MESSAGE")
    else
        dbg(2, "UI_ERROR_MESSAGE not relevant to shapeshift/taxi, ignoring.")
    end
end

local function OnTaxiOpened()
    local s = db_local or {}
    dbg(2, "EVENT: TAXIMAP_OPENED fired. enabled:", tostring(s and s.enabled), "removeOnTaxiOpen:", tostring(s and s.removeOnTaxiOpen))
    if not s then
        dbg(2, "OnTaxiOpened: no db_local available, aborting.")
        return
    end
    if s.enabled then
        if s.removeOnTaxiOpen then
            dbg(2, "OnTaxiOpened: removeOnTaxiOpen is enabled, triggering removal.")
            RemoveAllWhitelistedBuffs("TAXIMAP_OPENED")
        else
            dbg(2, "OnTaxiOpened: removeOnTaxiOpen is disabled, skipping removal.")
        end
    else
        dbg(2, "OnTaxiOpened: module disabled, skipping.")
    end
end

local function OnTaxiClosed()
    dbg(2, "EVENT: TAXIMAP_CLOSED fired.")
end

local function EnsureDriver()
    if not driver then
        driver = CreateFrame("Frame")
        driver:SetScript("OnEvent", function(self, event, ...)
            dbg(2, "Driver event received:", event)
            if event == "TAXIMAP_OPENED" then OnTaxiOpened()
            elseif event == "TAXIMAP_CLOSED" then OnTaxiClosed()
            elseif event == "UI_ERROR_MESSAGE" then OnUIError(self, event, ...) end
        end)
        dbg(2, "Driver frame created and script set.")
    end
end

local function AddBuffSpellID(input)
    local s = db_local or {}
    if not input then
        dbg(2, "AddBuffSpellID called with nil; aborting.")
        return false, "invalid"
    end
    
    input = tostring(input):gsub("^%s*(.-)%s*$", "%1")
    if input == "" then
        dbg(2, "AddBuffSpellID: empty input; aborting.")
        return false, "invalid"
    end
    
    local spellID, displayName
    
    -- Smart detection: if input contains only digits, treat as spell ID
    if input:match("^%d+$") then
        spellID = tonumber(input)
        if not spellID or spellID <= 0 then
            dbg(2, "AddBuffSpellID: invalid spell ID:", input)
            return false, "invalid spell ID"
        end
        -- Try to get the real spell name from API
        displayName = GetSpellInfo and GetSpellInfo(spellID) or "Spell ID " .. spellID
        dbg(2, "AddBuffSpellID: detected spell ID input:", spellID, "name:", displayName)
    else
        -- Input contains letters - treat as buff name
        local foundID, foundName = FindSpellIDByName(input)
        if not foundID then
            dbg(2, "AddBuffSpellID: buff name not found on player:", input)
            return false, "buff not found - must be active on player"
        end
        spellID = foundID
        displayName = foundName
        dbg(2, "AddBuffSpellID: detected buff name input:", input, "resolved to ID:", spellID)
    end
    
    s.whitelist = s.whitelist or {}
    s.customEnabled = s.customEnabled or {}
    
    -- Check if spell ID already exists
    for _, entry in ipairs(s.whitelist) do
        if entry.id == spellID then
            dbg(2, "AddBuffSpellID: spell ID already present:", spellID)
            return false, "already present"
        end
    end
    
    table.insert(s.whitelist, {name = displayName, id = spellID})
    s.customEnabled[spellID] = true -- enable by default
    dbg(1, "AddBuffSpellID: added custom buff:", displayName, "with ID:", spellID)

    -- Mark that a reload is required
    s._needsReload = true
    print("|cff00ff00[ShapeshiftRemover]|r Reload UI is required for changes to appear in the options. Use ElvUI's Reload UI button at the bottom of options or type /reload.")
    return true, displayName, spellID
end

local function RemoveBuffSpellID(spellID)
    local s = db_local or {}
    if not spellID or spellID <= 0 then
        dbg(2, "RemoveBuffSpellID: invalid spell ID provided.")
        return false, "invalid"
    end
    
    spellID = tonumber(spellID)
    s.whitelist = s.whitelist or {}
    s.customEnabled = s.customEnabled or {}
    
    for i = #s.whitelist, 1, -1 do
        if s.whitelist[i].id == spellID then
            local name = s.whitelist[i].name
            table.remove(s.whitelist, i)
            s.customEnabled[spellID] = nil
            dbg(1, "RemoveBuffSpellID: removed custom buff:", name, "ID:", spellID)
            if s.selectedWhitelist == spellID then s.selectedWhitelist = nil end

            s._needsReload = true
            print("|cff00ff00[ShapeshiftRemover]|r Reload UI is required for changes to appear in the options. Use ElvUI's Reload UI button at the bottom of options or type /reload.")
            return true
        end
    end
    
    dbg(2, "RemoveBuffSpellID: spell ID not found in whitelist:", spellID)
    return false, "not found"
end

local function TestBuffDetection()
    local s = db_local or {}
    dbg(2, "TestBuffDetection START")
    local all = GetAllBuffSpellIDs()
    local found, notfound = {}, {}
    
    for spellID, buffName in pairs(all) do
        dbg(2, "Test: scanning for", buffName, "with ID", spellID)
        local removedOne = false
        
        for i = 1, 40 do
            local name, rank, icon, count, debuffType, duration, expirationTime, unitCaster, isStealable, shouldConsolidate, spellId = UnitBuff("player", i)
            dbg(2, "  Slot", i, "->", name or "<none>", "ID:", spellId or "<none>")
            
            if spellId and spellId == spellID then
                CancelUnitBuff("player", i)
                removedOne = true
                dbg(2, "  Test: removed", buffName, "(ID:", spellID, ") from slot", i)
            end
        end
        
        if removedOne then 
            table.insert(found, ("'%s' (ID:%d, removed)"):format(buffName, spellID))
        else 
            table.insert(notfound, ("'%s' (ID:%d)"):format(buffName, spellID))
        end
    end
    
    if s and s.debug then
        print("|cff00ff00[ShapeshiftRemover]|r Buff detection+removal test:")
        if #found > 0 then 
            print("  Found and removed: " .. table.concat(found, ", "))
        else 
            print("  None of the enabled shapeshift buffs were found on your player.")
        end
        if #notfound > 0 then 
            print("  Not found: " .. table.concat(notfound, ", "))
        end
    end
    
    dbg(2, "TestBuffDetection END. Found count:", #found, "Not found count:", #notfound)
end

SLASH_SHAPESHIFTREMOVER1 = "/removeshapeshift"
SlashCmdList["SHAPESHIFTREMOVER"] = function()
    local s = db_local or {}
    dbg(2, "Slash command /removeshapeshift invoked.")
    RemoveAllWhitelistedBuffs("slash")
    if s and s.debug then print("|cff00ff00[ShapeshiftRemover]|r Removed whitelisted buffs (manual command).") end
end

-- Extract spell tooltip text by scanning GameTooltip
local scannerTooltip = CreateFrame("GameTooltip", "ShapeshiftRemoverScanner", nil, "GameTooltipTemplate")
scannerTooltip:SetOwner(UIParent, "ANCHOR_NONE")

local function GetSpellTooltipText(spellID)
    if not spellID then return "" end
    
    scannerTooltip:ClearLines()
    scannerTooltip:SetSpellByID(spellID)
    
    local lines = {}
    -- Scan tooltip lines (skip line 1 which is the spell name)
    for i = 2, scannerTooltip:NumLines() do
        local leftText = _G["ShapeshiftRemoverScannerTextLeft" .. i]
        if leftText then
            local text = leftText:GetText()
            if text and text ~= "" then
                table.insert(lines, text)
            end
        end
    end
    
    return table.concat(lines, "\n")
end

function SUB:GetOptions(db)
    db = db or {}
    -- ensure defaults
    for k, v in pairs(SUB.defaults) do if db[k] == nil then db[k] = v end end
    db.predefs = db.predefs or {}
    if not db._initialized_predefs then
        for _, v in ipairs(PREDEFINED_SHAPESHIFTS) do db.predefs[v.id] = true end
        db._initialized_predefs = true
    end
    db.customEnabled = db.customEnabled or {}

    local predefinedToggles = {}
    for idx, v in ipairs(PREDEFINED_SHAPESHIFTS) do
        local key = "predef_"..idx
        local spellID = v.id
        predefinedToggles[key] = {
            order = idx,
            type = "toggle",
            name = function() 
                local spellName, _, icon = GetSpellInfo(spellID)
                spellName = spellName or v.name
                
                if icon then
                    -- Larger icon (26x26) with 5px crop from each edge
                    -- Format: |Ttexture:size:size:xoff:yoff:texWidth:texHeight:left:right:top:bottom|t
                    return "|T" .. icon .. ":26:26:0:0:64:64:5:59:5:59|t " .. spellName
                else
                    return spellName
                end
            end,
            desc = function()
                local tooltipText = GetSpellTooltipText(spellID)
                local desc = ""
                
                if tooltipText and tooltipText ~= "" then
                    desc = tooltipText .. "\n\n"
                end
                
                desc = desc .. "|cff808080Spell ID: " .. spellID .. "|r\n"
                desc = desc .. "Enable/disable automatic removal of this buff."
                
                return desc
            end,
            get = function() return db.predefs and db.predefs[spellID] end,
            set = function(_, val) db.predefs = db.predefs or {}; db.predefs[spellID] = val end,
        }
    end

    -- Dynamic toggles for custom whitelist entries
    local customToggles = {}
    do
        local orderBase = 100
        db.whitelist = db.whitelist or {}
        for idx, entry in ipairs(db.whitelist) do
            if entry and entry.id then
                local spellID = entry.id
                local key = "custom_" .. idx
                customToggles[key] = {
                    order = orderBase + idx,
                    type = "toggle",
                    name = function()
                        local spellName, _, icon = GetSpellInfo(spellID)
                        spellName = spellName or entry.name
                        
                        if icon then
                            -- Crop 3px from each edge: use normalized coords (3/64 = 0.046875, 61/64 = 0.953125)
                            return "|T" .. icon .. ":20:20:0:0:64:64:4:60:4:60|t " .. spellName
                        else
                            return spellName
                        end
                    end,
                    desc = function()
                        local tooltipText = GetSpellTooltipText(spellID)
                        local desc = ""
                        
                        if tooltipText and tooltipText ~= "" then
                            desc = tooltipText .. "\n\n"
                        end
                        
                        desc = desc .. "|cff808080Spell ID: " .. spellID .. "|r\n"
                        desc = desc .. "Enable/disable automatic removal of this custom buff."
                        
                        return desc
                    end,
                    get = function() db.customEnabled = db.customEnabled or {}; return db.customEnabled[spellID] ~= false end,
                    set = function(_, val) db.customEnabled = db.customEnabled or {}; db.customEnabled[spellID] = val and true or false end,
                }
            end
        end
    end

    local existingHeader = "Predefined and custom buff spell IDs. Use the checkboxes to enable/disable removal for each entry.\n"
    if db._needsReload then
        existingHeader = existingHeader .. "\n|cffff0000NOTE: Custom buffs require a UI reload to appear/disappear in the options.\n             Please type|r |cffffff00/rl|r |cffff0000for changes to appear in this panel.|r\n "
    end

    return {
        type = "group",
        name = SUB.name,
        childGroups = "tab",
        args = {
            header = {
                order = 0,
                type = "header",
                name = "Shapeshift Remover",
            },
            mainDescription = {
                order = 1, type = "description",
                name = "This module attempts to remove shapeshifting buffs automatically where shapeshifts prevent actions.\nYou can manually trigger this by using |cffffff00/removeshapeshift|r in macros (e.g. remove shapeshift before mount cast).\n",
            },
            enabled = {
                order = 2, type = "toggle", width = "full",
                name = function() return db.enabled and "|cff00ff00Enabled|r" or "|cffff0000Disabled|r" end,
                get = function() return db.enabled end,
                set = function(_, v) db.enabled = v if v then SUB:OnEnable(db) else SUB:OnDisable() end end,
            },
            existingBuffs = {
                order = 10, type = "group", name = "Existing Buffs",
                disabled = function() return not db.enabled end,
                args = (function()
                    local t = {
                        header = { order = 0, type = "description", name = existingHeader }
                    }
                    for k, v in pairs(predefinedToggles) do t[k] = v end
                    for k, v in pairs(customToggles) do t[k] = v end
                    return t
                end)(),
            },
            addBuffs = {
                order = 20, type = "group", name = "Add Buffs",
                disabled = function() return not db.enabled end,
                args = {
                    desc = {
                        order = 0, type = "description",
                        name = "Add custom buffs by entering either:\n" ..
                               "|cff00ff00• Spell ID|r (numbers only, e.g., '16591')\n" ..
                               "|cff00ff00• Buff Name|r (e.g., 'Noggenfogger Elixir') - |cffffaa00must be active on your character|r\n\n" ..
                               "The addon will automatically detect which type you entered and add it accordingly.\n",
                    },
                    addBox = {
                        order = 1,
                        type = "input",
                        name = "Spell ID or Buff Name",
                        desc = "Enter a spell ID (16591) or buff name (Noggenfogger Elixir).\nBuff names must be currently active on your character.",
                        get = function() return tostring(db._tmpBuffToAdd or "") end,
                        set = function(_, v) db._tmpBuffToAdd = tostring(v or "") end,
                        width = "full",
                    },
                    addButton = {
                        order = 2,
                        type = "execute",
                        name = "Add",
                        func = function()
                            local input = tostring(db._tmpBuffToAdd or ""):gsub("^%s*(.-)%s*$", "%1")
                            
                            if input == "" then 
                                print("|cff00ff00[ShapeshiftRemover]|r Please enter a spell ID or buff name.") 
                                return 
                            end
                            
                            local ok, name, spellID = AddBuffSpellID(input)
                            if ok then 
                                db._tmpBuffToAdd = ""
                                db.selectedWhitelist = spellID
                                print("|cff00ff00[ShapeshiftRemover]|r Added " .. tostring(name) .. " (ID: " .. tostring(spellID) .. "). A UI reload is required for the options list to update.") 
                            else 
                                local errMsg = name or "unknown error"
                                if errMsg == "buff not found - must be active on player" then
                                    print("|cff00ff00[ShapeshiftRemover]|r Buff '" .. input .. "' not found. Make sure the buff is currently active on your character.")
                                else
                                    print("|cff00ff00[ShapeshiftRemover]|r Add failed: " .. errMsg) 
                                end
                            end
                        end,
                        width = "half",
                    },
                    currentList = {
                        order = 4,
                        type = "select",
                        name = "Existing buffs",
                        values = function()
                            local out = {}
                            db.whitelist = db.whitelist or {}
                            for _, entry in ipairs(db.whitelist) do
                                if entry and entry.id then
                                    out[entry.id] = entry.name .. " (ID: " .. entry.id .. ")"
                                end
                            end
                            return out
                        end,
                        get = function() return db.selectedWhitelist and tonumber(db.selectedWhitelist) or nil end,
                        set = function(_, v) db.selectedWhitelist = tonumber(v) end,
                    },
                    deleteSelected = {
                        order = 5,
                        type = "execute",
                        name = "Delete selected",
                        func = function()
                            local sel = db.selectedWhitelist
                            if not sel then 
                                print("|cff00ff00[ShapeshiftRemover]|r No selection") 
                                return 
                            end
                            
                            local ok, err = RemoveBuffSpellID(sel)
                            if ok then 
                                db.selectedWhitelist = nil
                                print("|cff00ff00[ShapeshiftRemover]|r Removed spell ID " .. tostring(sel) .. ". A UI reload is required for the options list to update.") 
                            else 
                                print("|cff00ff00[ShapeshiftRemover]|r Remove failed: " .. tostring(err)) 
                            end
                        end,
                    },
                },
            },
            debug = {
                order = 30, type = "group", name = "Debug",
                disabled = function() return not db.enabled end,
                args = {
                    debug = {
                        order = 3, type = "toggle", name = "Debug",
                        desc = "Enable debug printing to chat.",
                        get = function() return db.debug end,
                        set = function(_, v) db.debug = v end,
                    },
                    debugLevel = {
                        order = 2, type = "select", name = "Debug Level",
                        desc = "Choose debug verbosity: 1 = removals only; 2 = verbose.",
                        values = { [1] = "1 - Removals only", [2] = "2 - Verbose (events+steps)" },
                        get = function() return db.debugLevel or 2 end,
                        set = function(_, v) db.debugLevel = v end,
                        disabled = function() return not db.debug end,
                    },
                    testBuffDetection = {
                        order = 1, type = "execute", name = "Test Buff Detection",
                        desc = "Test if the enabled shapeshift buffs are currently detected and REMOVE any found buffs.",
                        func = function() dbg(2, "Test Buff Detection invoked"); TestBuffDetection() end,
                    },
                },
            },
        },
    }
end

function SUB:OnEnable(db)
    db_local = db or {}
    for k, v in pairs(SUB.defaults) do if db_local[k] == nil then db_local[k] = v end end
    if not db_local._initialized_predefs then
        db_local.predefs = db_local.predefs or {}
        for _, v in ipairs(PREDEFINED_SHAPESHIFTS) do db_local.predefs[v.id] = true end
        db_local._initialized_predefs = true
    end
    db_local.customEnabled = db_local.customEnabled or {}
    db_local.debugLevel = tonumber(db_local.debugLevel) or SUB.defaults.debugLevel

    EnsureDriver()
    if driver then
        driver:RegisterEvent("TAXIMAP_OPENED")
        driver:RegisterEvent("TAXIMAP_CLOSED")
        driver:RegisterEvent("UI_ERROR_MESSAGE")
        dbg(2, "OnEnable: Driver events registered")
    end
    dbg(2, "ShapeshiftRemover enabled (OnEnable finished)")
end

function SUB:OnDisable()
    if driver then
        driver:UnregisterEvent("TAXIMAP_OPENED")
        driver:UnregisterEvent("TAXIMAP_CLOSED")
        driver:UnregisterEvent("UI_ERROR_MESSAGE")
        dbg(2, "OnDisable: Driver events unregistered")
    end
    db_local = nil
    dbg(2, "ShapeshiftRemover disabled (OnDisable finished)")
end

MOD:RegisterSubmodule("ShapeshiftRemover", SUB)