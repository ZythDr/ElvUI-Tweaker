local core = EWTweaker and EWTweaker.GetCore and EWTweaker.GetCore()
local MOD = core and core.modules and core.modules.MiscTweaks
if not MOD then return end

local L = LibStub("AceLocale-3.0-ElvUI"):GetLocale("ElvUI", true)
if not L then L = setmetatable({}, { __index = function(_, k) return k end }) end

local SUB = { name = "Roll Save" }

SUB.defaults = {
    enabled = false,
    trigger = "RIGHT",
    toggleSame = true,
    rollOnSave = true,
    autoConfirmBind = true,
    announceSaves = true,
    announceRolls = true,
    characters = {},
}

local ROLL_LABELS = {
    [0] = "Pass",
    [1] = "Need",
    [2] = "Greed",
    [3] = "Disenchant",
}

local ROLL_VALUES = {
    [0] = "Pass",
    [1] = "Need",
    [2] = "Greed",
    [3] = "Disenchant",
}

local TRIGGER_VALUES = {
    RIGHT = "Right click",
    SHIFT_RIGHT = "Shift + right click",
    CTRL_RIGHT = "Ctrl + right click",
    ALT_RIGHT = "Alt + right click",
}

local db_local
local eventFrame = CreateFrame("Frame")
local hookScanFrame = CreateFrame("Frame")
local hookedButtons = setmetatable({}, { __mode = "k" })
local pendingConfirmRolls = {}

local function Print(msg)
    print("|cff00ff00[Roll Save]|r " .. tostring(msg))
end

local function ApplyDefaults(db)
    db = db or {}
    for key, value in pairs(SUB.defaults) do
        if db[key] == nil then
            if type(value) == "table" then
                db[key] = {}
            else
                db[key] = value
            end
        end
    end
    db.characters = db.characters or {}
    return db
end

local function GetCharacterKey()
    local name = UnitName and UnitName("player") or "Unknown"
    local realm = GetRealmName and GetRealmName() or "Unknown"
    return tostring(name or "Unknown") .. "-" .. tostring(realm or "Unknown")
end

local function GetCharacterStore(db)
    db = ApplyDefaults(db or db_local)
    local key = GetCharacterKey()
    db.characters[key] = db.characters[key] or { items = {} }
    db.characters[key].items = db.characters[key].items or {}
    return db.characters[key], key
end

local function RefreshOptions()
    local ACR = LibStub and LibStub("AceConfigRegistry-3.0", true)
    if ACR then
        ACR:NotifyChange("ElvUI")
    end
end

local function GetItemIDFromLink(link)
    return link and tonumber(link:match("item:(%d+)"))
end

local function ParseItemID(input)
    input = tostring(input or ""):gsub("^%s*(.-)%s*$", "%1")
    if input == "" then return nil end

    local fromLink = GetItemIDFromLink(input)
    if fromLink then return fromLink end

    if input:match("^%d+$") then
        return tonumber(input)
    end
end

local function GetItemInfoForID(itemID)
    local name, link, quality, _, _, _, _, _, _, texture = GetItemInfo(itemID)
    return name or ("Item ID " .. tostring(itemID)), link, quality, texture
end

local function MakeItemLabel(itemID, entry)
    entry = entry or {}
    local name = entry.name
    local link = entry.link
    local texture = entry.texture

    if not name or name == "" or name == ("Item ID " .. tostring(itemID)) then
        local infoName, infoLink, _, infoTexture = GetItemInfoForID(itemID)
        name = infoName
        link = link or infoLink
        texture = texture or infoTexture
    end

    local roll = ROLL_LABELS[entry.rollType] or "Unknown"
    local prefix = texture and ("|T" .. texture .. ":18:18:0:0:64:64:4:60:4:60|t ") or ""
    return prefix .. tostring(name or ("Item ID " .. tostring(itemID))) .. " - " .. roll .. " (" .. tostring(itemID) .. ")"
end

local function SaveItemRoll(itemID, rollType, name, link, texture, allowToggle)
    itemID = tonumber(itemID)
    rollType = tonumber(rollType)
    if not itemID or not ROLL_LABELS[rollType] then return false end

    local store = GetCharacterStore(db_local)
    local current = store.items[itemID]

    if allowToggle and db_local.toggleSame and current and tonumber(current.rollType) == rollType then
        store.items[itemID] = nil
        RefreshOptions()
        if db_local.announceSaves then
            Print("Removed saved roll for " .. tostring(current.name or name or ("item " .. itemID)) .. ".")
        end
        return true, "removed"
    end

    local infoName, infoLink, _, infoTexture = GetItemInfoForID(itemID)
    store.items[itemID] = {
        rollType = rollType,
        name = name or infoName,
        link = link or infoLink,
        texture = texture or infoTexture,
        savedAt = time and time() or nil,
    }

    RefreshOptions()
    if db_local.announceSaves then
        Print("Saved " .. ROLL_LABELS[rollType] .. " for " .. tostring(name or infoName or ("item " .. itemID)) .. ".")
    end

    return true, "saved"
end

local function DeleteSavedItem(itemID)
    itemID = tonumber(itemID)
    if not itemID then return false end

    local store = GetCharacterStore(db_local)
    if store.items[itemID] then
        store.items[itemID] = nil
        RefreshOptions()
        return true
    end
    return false
end

local function GetNow()
    return (GetTime and GetTime()) or (time and time()) or 0
end

local function MarkPendingConfirm(rollID, rollType)
    if not db_local or not db_local.autoConfirmBind then return end
    if not rollID or rollType == nil then return end

    pendingConfirmRolls[rollID] = {
        rollType = tonumber(rollType),
        expires = GetNow() + 5,
    }
end

local function ClearPendingConfirm(rollID)
    if rollID then
        pendingConfirmRolls[rollID] = nil
    end
end

local function ShouldAutoConfirm(rollID, rollType)
    if not db_local or not db_local.enabled or not db_local.autoConfirmBind then return false end

    local pending = rollID and pendingConfirmRolls[rollID]
    if not pending then return false end

    if pending.expires and pending.expires < GetNow() then
        ClearPendingConfirm(rollID)
        return false
    end

    local eventRollType = tonumber(rollType)
    if eventRollType and pending.rollType ~= nil and eventRollType ~= pending.rollType then
        return false
    end

    return true
end

local function HideLootRollConfirm(rollID)
    if StaticPopup_Hide then
        StaticPopup_Hide("CONFIRM_LOOT_ROLL", rollID)
    end
end

local function AutoConfirmLootRoll(rollID, rollType)
    if not ShouldAutoConfirm(rollID, rollType) then return false end

    rollType = tonumber(rollType) or tonumber(pendingConfirmRolls[rollID] and pendingConfirmRolls[rollID].rollType)
    if ConfirmLootRoll and rollID and rollType then
        ConfirmLootRoll(rollID, rollType)
        HideLootRollConfirm(rollID)
        ClearPendingConfirm(rollID)
        return true
    end

    return false
end

local function IsRollAllowed(rollType, canNeed, canGreed, canDisenchant)
    local function IsAvailable(value)
        return value ~= nil and value ~= false and value ~= 0
    end

    rollType = tonumber(rollType)
    if rollType == 0 then return true end
    if rollType == 1 then return IsAvailable(canNeed) end
    if rollType == 2 then return IsAvailable(canGreed) end
    if rollType == 3 then return IsAvailable(canDisenchant) end
    return false
end

local function RollSavedChoice(rollID, rollType)
    MarkPendingConfirm(rollID, rollType)
    RollOnLoot(rollID, rollType)
end

local function TriggerMatches(button)
    if button ~= "RightButton" then return false end

    local trigger = db_local and db_local.trigger or "RIGHT"
    if trigger == "RIGHT" then
        return not IsShiftKeyDown() and not IsControlKeyDown() and not IsAltKeyDown()
    elseif trigger == "SHIFT_RIGHT" then
        return IsShiftKeyDown() and not IsControlKeyDown() and not IsAltKeyDown()
    elseif trigger == "CTRL_RIGHT" then
        return IsControlKeyDown() and not IsShiftKeyDown() and not IsAltKeyDown()
    elseif trigger == "ALT_RIGHT" then
        return IsAltKeyDown() and not IsShiftKeyDown() and not IsControlKeyDown()
    end

    return false
end

local function GetRollInfo(rollID)
    if not rollID then return end

    local texture, name, _, _, _, canNeed, canGreed, canDisenchant = GetLootRollItemInfo(rollID)
    local link = GetLootRollItemLink(rollID)
    local itemID = GetItemIDFromLink(link)
    return itemID, name, link, texture, canNeed, canGreed, canDisenchant
end

local function GetButtonRollID(button)
    if not button then return end
    if button.rollID then return button.rollID end
    if button.parent and button.parent.rollID then return button.parent.rollID end

    local parent = button.GetParent and button:GetParent()
    return parent and parent.rollID
end

local function OnRollButtonMouseUp(button, mouseButton)
    if not db_local or not db_local.enabled or not TriggerMatches(mouseButton) then return end

    local rollType = button.rollType or button._ewtRollSaveRollType
    local rollID = GetButtonRollID(button)
    if not rollID or not ROLL_LABELS[rollType] then return end

    local itemID, name, link, texture, canNeed, canGreed, canDisenchant = GetRollInfo(rollID)
    if not itemID then
        Print("Could not read the item ID for this roll.")
        return
    end

    if not IsRollAllowed(rollType, canNeed, canGreed, canDisenchant) then
        Print("Cannot save " .. ROLL_LABELS[rollType] .. " for " .. tostring(name or "this item") .. " because that roll is not currently available.")
        return
    end

    local ok, action = SaveItemRoll(itemID, rollType, name, link, texture, true)
    if ok and action == "saved" and db_local.rollOnSave then
        RollSavedChoice(rollID, rollType)
    end
end

local function HookRollButton(button, rollType)
    if not button then return end

    button._ewtRollSaveRollType = rollType or button.rollType or button._ewtRollSaveRollType
    if hookedButtons[button] then return end

    button:HookScript("OnMouseUp", OnRollButtonMouseUp)
    hookedButtons[button] = true
end

local function HookBlizzardRollFrames()
    local count = NUM_GROUP_LOOT_FRAMES or 4
    for i = 1, count do
        HookRollButton(_G["GroupLootFrame" .. i .. "PassButton"], 0)
        HookRollButton(_G["GroupLootFrame" .. i .. "NeedButton"], 1)
        HookRollButton(_G["GroupLootFrame" .. i .. "GreedButton"], 2)
        HookRollButton(_G["GroupLootFrame" .. i .. "DisenchantButton"], 3)
    end
end

local function HookElvUIRollFrames()
    for i = 1, 10 do
        local frame = _G["ElvUI_GroupLootFrame" .. i]
        if frame then
            HookRollButton(frame.passButton, 0)
            HookRollButton(frame.needButton, 1)
            HookRollButton(frame.greedButton, 2)
            HookRollButton(frame.disenchantButton, 3)
        end
    end
end

local function HookRollFrames()
    HookBlizzardRollFrames()
    HookElvUIRollFrames()
end

local function ScheduleHookScan()
    hookScanFrame.scansLeft = 5
    hookScanFrame:SetScript("OnUpdate", function(frame)
        HookRollFrames()
        frame.scansLeft = (frame.scansLeft or 0) - 1
        if frame.scansLeft <= 0 then
            frame:SetScript("OnUpdate", nil)
        end
    end)
end

local function AutoRoll(rollID)
    local itemID, name, link, texture, canNeed, canGreed, canDisenchant = GetRollInfo(rollID)
    if not itemID then return end

    local store = GetCharacterStore(db_local)
    local entry = store.items[itemID]
    if not entry then return end

    local rollType = tonumber(entry.rollType)
    if not IsRollAllowed(rollType, canNeed, canGreed, canDisenchant) then
        if db_local.announceRolls then
            Print("Saved roll for " .. tostring(name or entry.name or ("item " .. itemID)) .. " is " .. tostring(ROLL_LABELS[rollType]) .. ", but that option is not available.")
        end
        return
    end

    entry.name = entry.name or name
    entry.link = entry.link or link
    entry.texture = entry.texture or texture

    RollSavedChoice(rollID, rollType)
    if db_local.announceRolls then
        Print("Auto rolled " .. ROLL_LABELS[rollType] .. " on " .. tostring(name or entry.name or ("item " .. itemID)) .. ".")
    end
end

eventFrame:SetScript("OnEvent", function(_, event, rollID, rollType)
    if event == "START_LOOT_ROLL" then
        HookRollFrames()
        ScheduleHookScan()
        if db_local and db_local.enabled then
            AutoRoll(rollID)
        end
    elseif event == "CONFIRM_LOOT_ROLL" then
        AutoConfirmLootRoll(rollID, rollType)
    end
end)

local function BuildSavedValues(db)
    local values = {}
    local store = GetCharacterStore(db)
    for itemID, entry in pairs(store.items) do
        values[itemID] = MakeItemLabel(itemID, entry)
    end
    return values
end

function SUB:GetOptions(db)
    db = ApplyDefaults(db)
    db_local = db

    return {
        type = "group",
        name = SUB.name,
        childGroups = "tab",
        args = {
            header = {
                order = 0,
                type = "header",
                name = SUB.name,
            },
            description = {
                order = 1,
                type = "description",
                name = "Save loot roll choices per character and repeat them automatically when the same item drops again.",
            },
            enabled = {
                order = 2,
                type = "toggle",
                width = "full",
                name = function() return db.enabled and "|cff00ff00Enabled|r" or "|cffff0000Disabled|r" end,
                get = function() return db.enabled end,
                set = function(_, value)
                    db.enabled = value and true or false
                    if db.enabled then SUB:OnEnable(db) else SUB:OnDisable(db) end
                end,
            },
            behavior = {
                order = 10,
                type = "group",
                name = "Behavior",
                args = {
                    trigger = {
                        order = 1,
                        type = "select",
                        name = "Save Trigger",
                        desc = "Click pattern used on Need, Greed, Disenchant, or Pass to save that roll for this character.",
                        values = TRIGGER_VALUES,
                        get = function() return db.trigger or "RIGHT" end,
                        set = function(_, value) db.trigger = value end,
                    },
                    toggleSame = {
                        order = 2,
                        type = "toggle",
                        name = "Repeat trigger removes saved roll",
                        desc = "Using the save trigger on an item that already has the same saved roll removes it.",
                        get = function() return db.toggleSame ~= false end,
                        set = function(_, value) db.toggleSame = value and true or false end,
                    },
                    rollOnSave = {
                        order = 3,
                        type = "toggle",
                        name = "Roll immediately when saving",
                        desc = "When you save a roll from the loot roll buttons, also roll that choice for the current drop.",
                        get = function() return db.rollOnSave ~= false end,
                        set = function(_, value) db.rollOnSave = value and true or false end,
                    },
                    autoConfirmBind = {
                        order = 4,
                        type = "toggle",
                        name = "Auto-confirm bind popups",
                        desc = "Automatically accept the bind-on-pickup confirmation popup only for rolls started by Roll Save.",
                        get = function() return db.autoConfirmBind == true end,
                        set = function(_, value) db.autoConfirmBind = value and true or false end,
                    },
                    announceSaves = {
                        order = 5,
                        type = "toggle",
                        name = "Print save changes",
                        get = function() return db.announceSaves ~= false end,
                        set = function(_, value) db.announceSaves = value and true or false end,
                    },
                    announceRolls = {
                        order = 6,
                        type = "toggle",
                        name = "Print automatic rolls",
                        get = function() return db.announceRolls ~= false end,
                        set = function(_, value) db.announceRolls = value and true or false end,
                    },
                },
            },
            saved = {
                order = 20,
                type = "group",
                name = "Saved Items",
                args = {
                    addDesc = {
                        order = 0,
                        type = "description",
                        name = "Saved rolls are stored per character. You can save from roll buttons or add an item manually by item ID.",
                    },
                    itemID = {
                        order = 1,
                        type = "input",
                        name = "Item ID or Item Link",
                        get = function() return tostring(db._tmpItemID or "") end,
                        set = function(_, value) db._tmpItemID = tostring(value or "") end,
                    },
                    rollType = {
                        order = 2,
                        type = "select",
                        name = "Roll",
                        values = ROLL_VALUES,
                        get = function() return tonumber(db._tmpRollType) or 1 end,
                        set = function(_, value) db._tmpRollType = tonumber(value) or 1 end,
                    },
                    add = {
                        order = 3,
                        type = "execute",
                        name = "Add / Update",
                        func = function()
                            local itemID = ParseItemID(db._tmpItemID)
                            if not itemID then
                                Print("Enter a valid item ID or item link.")
                                return
                            end

                            local name, link, _, texture = GetItemInfoForID(itemID)
                            SaveItemRoll(itemID, tonumber(db._tmpRollType) or 1, name, link, texture, false)
                            db._tmpItemID = ""
                            db.selectedItem = itemID
                        end,
                    },
                    current = {
                        order = 4,
                        type = "select",
                        name = "Saved Items",
                        values = function() return BuildSavedValues(db) end,
                        get = function() return db.selectedItem and tonumber(db.selectedItem) or nil end,
                        set = function(_, value) db.selectedItem = tonumber(value) end,
                        width = "full",
                    },
                    delete = {
                        order = 5,
                        type = "execute",
                        name = "Delete Selected",
                        func = function()
                            if not db.selectedItem then
                                Print("No saved item selected.")
                                return
                            end

                            if DeleteSavedItem(db.selectedItem) then
                                Print("Removed saved roll for item ID " .. tostring(db.selectedItem) .. ".")
                                db.selectedItem = nil
                            end
                        end,
                    },
                },
            },
        },
    }
end

function SUB:OnEnable(db)
    db_local = ApplyDefaults(db or db_local)
    eventFrame:RegisterEvent("START_LOOT_ROLL")
    eventFrame:RegisterEvent("CONFIRM_LOOT_ROLL")
    HookRollFrames()
    ScheduleHookScan()
end

function SUB:OnDisable(db)
    db_local = ApplyDefaults(db or db_local)
    eventFrame:UnregisterEvent("START_LOOT_ROLL")
    eventFrame:UnregisterEvent("CONFIRM_LOOT_ROLL")
    wipe(pendingConfirmRolls)
end

MOD:RegisterSubmodule("RollSave", SUB)
