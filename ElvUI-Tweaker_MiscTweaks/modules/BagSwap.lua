local core = EWTweaker and EWTweaker.GetCore and EWTweaker.GetCore()
if not core then return end

local MOD = core.modules and core.modules.MiscTweaks
if not MOD then return end

local L = LibStub("AceLocale-3.0-ElvUI"):GetLocale("ElvUI", true)
if not L then L = setmetatable({}, { __index = function(t, k) return k end }) end

local SUB = { name = "Bag Swap" }

SUB.defaults = {
    enabled = true,
    debug = false,
}

local E, EL, V, P, G = unpack(_G.ElvUI)
local B = E:GetModule("Bags")

local function Print(msg, isDebug)
    if isDebug and not SUB.db.debug then return end
    E:Print("|cff00ff00[BagSwap]|r " .. msg)
end

local function GetItemCount(bagID)
    local count = 0
    for slot = 1, GetContainerNumSlots(bagID) do
        if GetContainerItemInfo(bagID, slot) then
            count = count + 1
        end
    end
    return count
end

local function GetAvailableSlots(excludeBagID, isBank, stashBag, stashSlot)
    local slots = {}
    local bags = isBank and {-1, 5, 6, 7, 8, 9, 10, 11} or {0, 1, 2, 3, 4}
    
    for _, bagID in ipairs(bags) do
        if bagID ~= excludeBagID then
            local free, bagType = GetContainerNumFreeSlots(bagID)
            if free > 0 then
                for slot = 1, GetContainerNumSlots(bagID) do
                    if (bagID ~= stashBag or slot ~= stashSlot) and not GetContainerItemInfo(bagID, slot) then
                        table.insert(slots, { bag = bagID, slot = slot, type = bagType })
                    end
                end
            end
        end
    end
    return slots
end

-- Check if an item can fit in a bag type
local function CanItemFitInBag(bagID, itemLink)
    local bagType = select(2, GetContainerNumFreeSlots(bagID))
    if bagType == 0 then return true end -- Normal bag
    
    local itemFamily = GetItemFamily(itemLink)
    return bit.band(itemFamily, bagType) > 0
end

local function EmptyBag(bagID, isBank, stashBag, stashSlot)
    local itemCount = GetItemCount(bagID)
    if itemCount == 0 then return true end

    local freeSlots = GetAvailableSlots(bagID, isBank, stashBag, stashSlot)
    if #freeSlots < itemCount then
        return false, string.format("Not enough free space to empty the bag. Need %d slots, have %d.", itemCount, #freeSlots)
    end

    for slot = 1, GetContainerNumSlots(bagID) do
        if GetContainerItemInfo(bagID, slot) then
            local itemLink = GetContainerItemLink(bagID, slot)
            local found = false
            for i, target in ipairs(freeSlots) do
                if CanItemFitInBag(target.bag, itemLink) then
                    PickupContainerItem(bagID, slot)
                    PickupContainerItem(target.bag, target.slot)
                    table.remove(freeSlots, i)
                    found = true
                    break
                end
            end
            if not found then
                return false, "Could not find a suitable slot for all items (Specialty bag mismatch?)"
            end
        end
    end
    return true
end

-- State machine for the "handshake"
local activeSwap = nil
local monitorFrame = CreateFrame("Frame")
monitorFrame:Hide()

monitorFrame:SetScript("OnUpdate", function(self, elapsed)
    if not activeSwap then 
        self:Hide()
        return 
    end
    
    activeSwap.timer = (activeSwap.timer or 0) + elapsed
    if activeSwap.timer > 5 then -- 5 second timeout
        E:Print("|cffff0000[BagSwap]|r Error: Handshake timed out. The bag might not have emptied correctly.")
        activeSwap = nil
        self:Hide()
        return
    end

    if activeSwap.state == "WAITING_FOR_EMPTY" then
        if GetItemCount(activeSwap.targetBagID) == 0 then
            Print("Bag cleared. Picking up new bag from stash...", true)
            PickupContainerItem(activeSwap.stashBag, activeSwap.stashSlot)
            activeSwap.state = "WAITING_FOR_CURSOR"
        end
    elseif activeSwap.state == "WAITING_FOR_CURSOR" then
        if CursorHasItem() then
            Print(string.format("Equipping to Slot %d...", activeSwap.invSlot), true)
            PutItemInBag(activeSwap.invSlot)
            Print("Done!")
            activeSwap = nil
            self:Hide()
        end
    end
end)

local function OnBagClick(self)
    if not SUB.db.enabled then return false end
    if not CursorHasItem() then return false end
    if activeSwap then return true end -- Busy

    local type, itemID, itemLink = GetCursorInfo()
    if type ~= "item" then return false end

    local itemName, _, _, _, _, itemType = GetItemInfo(itemLink or itemID)
    if not itemName then return false end

    local targetBagID = self.id
    if not targetBagID then return false end
    
    local isBank = targetBagID >= 5 or targetBagID == -1
    local invSlot = self.GetInventorySlot and self:GetInventorySlot() or ContainerIDToInventoryID(targetBagID)

    local currentItemLink = GetInventoryItemLink("player", invSlot)
    if not currentItemLink then return false end

    local itemCount = GetItemCount(targetBagID)
    if itemCount == 0 then return false end

    -- Check space
    local freeSlots = GetAvailableSlots(targetBagID, isBank)
    if #freeSlots < itemCount + 1 then
        E:Print(string.format("|cffff0000[BagSwap]|r Not enough space. Need %d free slots.", itemCount + 1))
        return true
    end

    -- 1. STASH
    local stashBag, stashSlot
    for slot = 1, GetContainerNumSlots(0) do
        if not GetContainerItemInfo(0, slot) then
            stashBag, stashSlot = 0, slot
            break
        end
    end
    if not stashBag then
        local s = freeSlots[1]
        stashBag, stashSlot = s.bag, s.slot
    end

    Print(string.format("Stashing %s...", itemLink), true)
    PickupContainerItem(stashBag, stashSlot)
    
    if CursorHasItem() then
        E:Print("|cffff0000[BagSwap]|r Failed to stash the new bag! Aborting.")
        return true
    end

    -- 2. EMPTY
    Print(string.format("Emptying Bag %d...", targetBagID))
    local success, err = EmptyBag(targetBagID, isBank, stashBag, stashSlot)
    if not success then
        E:Print("|cffff0000[BagSwap]|r " .. err)
        PickupContainerItem(stashBag, stashSlot)
        return true
    end

    -- 3. START HANDSHAKE
    activeSwap = {
        state = "WAITING_FOR_EMPTY",
        targetBagID = targetBagID,
        invSlot = invSlot,
        stashBag = stashBag,
        stashSlot = stashSlot,
        timer = 0
    }
    monitorFrame:Show()
    
    return true
end

function SUB:ApplyEnabled(db)
    SUB.db = db
    if not SUB.isHooked then
        hooksecurefunc(B, "Layout", function(self, isBank)
            local f = B:GetContainerFrame(isBank)
            if f and f.ContainerHolder then
                for i = 1, (f.BagIDs and #f.BagIDs or 0) do
                    local holder = f.ContainerHolder[i]
                    if holder and holder.id and holder.id ~= 0 and holder.id ~= -1 then
                        if not holder.isHookedEWT then
                            local originalOnClick = holder:GetScript("OnClick")
                            holder:SetScript("OnClick", function(s, button)
                                if SUB.db.enabled and CursorHasItem() and button == "LeftButton" then
                                    if OnBagClick(s) then
                                        return
                                    end
                                end
                                if originalOnClick then originalOnClick(s, button) end
                            end)

                            local originalOnReceiveDrag = holder:GetScript("OnReceiveDrag")
                            holder:SetScript("OnReceiveDrag", function(s)
                                if SUB.db.enabled and CursorHasItem() then
                                    if OnBagClick(s) then
                                        return
                                    end
                                end
                                if originalOnReceiveDrag then originalOnReceiveDrag(s) end
                            end)

                            holder.isHookedEWT = true
                        end
                    end
                end
            end
        end)
        SUB.isHooked = true
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
                name = "Bag Swap Automation",
            },
            description = {
                order = 1,
                type = "description",
                name = "Automatically empties a bag into your other bags when you try to replace it with a new one. No more 'You can't replace a bag that is not empty' errors!",
            },
            enabled = {
                order = 2,
                type = "toggle",
                name = function() return db.enabled and "|cff00ff00Enabled|r" or "|cffff0000Disabled|r" end,
                get = function() return db.enabled end,
                set = function(_, value)
                    db.enabled = value
                    SUB:ApplyEnabled(db)
                end,
            },
            debug = {
                order = 3,
                type = "toggle",
                name = "Debug Logs",
                desc = "Show detailed step-by-step logs in chat during the swap process.",
                get = function() return db.debug end,
                set = function(_, value) db.debug = value end,
            },
        },
    }
end

MOD:RegisterSubmodule("BagSwap", SUB)
