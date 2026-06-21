-- VendorTweaks.lua
-- MiscTweaks submodule: "Vendor Tweaks" (Inspired by GnomishVendorShrinker by Tekkub)
-- Adds a scrollable, compact list view to the Merchant frame perfectly skinned for ElvUI.

local core = EWTweaker and EWTweaker.GetCore and EWTweaker.GetCore()
if not core then return end

local MOD = core.modules and core.modules.MiscTweaks
if not MOD then return end

local SUB = { name = "Vendor Tweaks" }

SUB.defaults = {
    enabled = true,
    numRows = 12,
    alternateRows = true,
    showCurrencies = true,
    currencyScale = 1.0,
    -- Item coloring
    colorUnusable = true,
    colorUnusableColor = { 0.8, 0, 0 },
    colorAlreadyKnown = true,
    colorAlreadyKnownColor = { 0, 0.75, 0 },
    colorNotYetKnown = false,
    colorNotYetKnownColor = { 0.8, 0.8, 0 },
    colorIcons = true,
    -- Owned item coloring
    colorOwned = false,
    colorOwnedColor = { 0.3, 0.7, 1 },
}

local E, L, V, P, G = unpack(_G.ElvUI)
local S = E:GetModule("Skins")

local NUMROWS = 14
local ICONSIZE = 17
local GAP = 4
local SCROLLSTEP = 5

local offset = 0
local searchstring = nil
local knownCache = {}   -- per-session cache: [merchantIndex] = true/false
local scanTip           -- hidden tooltip for "Already known" detection

-- Item classes that can contain learnable items
-- Built from localized class names so it works on any locale
local LEARNABLE_ITEM_CLASSES
local function BuildLearnableClasses()
    LEARNABLE_ITEM_CLASSES = {}
    local classNames = { GetAuctionItemClasses() }
    
    local isEpoch = false
    if SUB.db and SUB.db.projectEpochCompat ~= nil then
        isEpoch = SUB.db.projectEpochCompat
    else
        isEpoch = (#classNames >= 12)
    end

    if isEpoch then
        -- Ascension/Epoch indices: 9 = Recipe, 11 = Miscellaneous
        if classNames[9] then LEARNABLE_ITEM_CLASSES[classNames[9]] = "recipe" end
        if classNames[11] then LEARNABLE_ITEM_CLASSES[classNames[11]] = "misc" end
    else
        -- Standard 3.3.5 indices: 7 = Recipe, 9 = Miscellaneous
        if classNames[7] then LEARNABLE_ITEM_CLASSES[classNames[7]] = "recipe" end
        if classNames[9] then LEARNABLE_ITEM_CLASSES[classNames[9]] = "misc" end
    end
end
local currencyCache = {}
local tokenFrames = {}
local currencyBar
local currencyBarHolder

local f -- our main frame
local rows = {}
local isHooked = false

-- Utility Functions
local HONOR_POINTS_ID = 43308
local ARENA_POINTS_ID = 43307
local HONOR_POINTS = "|cffffffff|Hitem:43308:0:0:0:0:0:0:0:0|h[Honor Points]|h|r"
local ARENA_POINTS = "|cffffffff|Hitem:43307:0:0:0:0:0:0:0:0|h[Arena Points]|h|r"

local function Purchase(id, quantity)
    local _, _, _, vendorStackSize, numAvailable = GetMerchantItemInfo(id)
    local maxPurchase = GetMerchantItemMaxStack(id)
    quantity = quantity / vendorStackSize

    if numAvailable > 0 and numAvailable < quantity then quantity = numAvailable end
    local purchased = 0
    while purchased < quantity do
        local buyamount = math.min(maxPurchase, quantity - purchased)
        purchased = purchased + buyamount
        BuyMerchantItem(id, buyamount)
    end
end

local function BuyItem(self, fullstack)
    local id = self:GetID()
    local link = GetMerchantItemLink(id)
    if not link then return end
    local _, _, _, _, _, _, _, stack = GetItemInfo(link)
    Purchase(id, fullstack and stack or 1)
end

local function OnClick(self, button)
    if IsAltKeyDown() and not self.altcurrency then
        self:BuyItem(true)
    elseif IsModifiedClick() then
        HandleModifiedItemClick(GetMerchantItemLink(self:GetID()))
    elseif self.altcurrency then
        local id = self:GetID()
        local link = GetMerchantItemLink(id)
        self.link, self.texture = GetMerchantItemLink(id), self.icon:GetTexture()
        MerchantFrame_ConfirmExtendedItemCost(self)
    else
        self:BuyItem()
    end
end

local function PopoutOnClick(self, button)
    local id = self:GetParent():GetID()
    local link = GetMerchantItemLink(id)
    if not link then return end

    local _, _, _, vendorStackSize, numAvailable = GetMerchantItemInfo(id)
    local maxPurchase = GetMerchantItemMaxStack(id)
    local _, _, _, _, _, _, _, itemStackSize = GetItemInfo(link)

    local size = numAvailable > 0 and numAvailable or itemStackSize
    OpenStackSplitFrame(250, self, "LEFT", "RIGHT")
end

local function PopoutSplitStack(self, qty)
    Purchase(self:GetParent():GetID(), qty)
end

local function OnEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if self.link then
        GameTooltip:SetHyperlink(self.link)
    else
        GameTooltip:SetMerchantCostItem(self.index, self
            .itemIndex)
    end
end

local function OnLeave()
    GameTooltip:Hide()
    ResetCursor()
end

local function GSC(cash)
    if not cash then return end
    local g, s, c = math.floor(cash / 10000), math.floor((cash / 100) % 100), cash % 100
    if g > 0 and s == 0 and c == 0 then
        return string.format(" |cffffd700%d", g)
    elseif g > 0 and c == 0 then
        return string.format(" |cffffd700%d.|cffc7c7cf%02d", g, s)
    elseif g > 0 then
        return string.format(" |cffffd700%d.|cffc7c7cf%02d.|cffeda55f%02d", g, s, c)
    elseif s > 0 and c == 0 then
        return string.format(" |cffc7c7cf%d", s)
    elseif s > 0 then
        return string.format(" |cffc7c7cf%d.|cffeda55f%02d", s, c)
    else
        return string.format(" |cffeda55f%02d", c)
    end
end

local function SetValue(self, text, icon, link)
    self.text:SetText(text)
    self.icon:SetTexture(icon)
    self.link, self.index, self.itemIndex = link
    if link == HONOR_POINTS then
        self.icon:SetPoint("RIGHT", -2, 0)
        self.text:SetPoint("RIGHT", self.icon, "LEFT", -GAP / 2 + 2, 0)
    else
        self.icon:SetPoint("RIGHT")
        self.text:SetPoint("RIGHT", self.icon, "LEFT", -GAP / 2, 0)
    end
    self:Show()
end

local function GetAltCurrencyFrame(frame)
    for i, v in ipairs(frame.altframes) do if not v:IsShown() then return v end end

    local anchor = #frame.altframes > 0 and frame.altframes[#frame.altframes].text
    local child = CreateFrame('Frame', nil, frame)
    child:SetWidth(ICONSIZE)
    child:SetHeight(ICONSIZE)
    child:SetPoint("RIGHT", anchor or frame.ItemPrice, "LEFT")

    child.icon = child:CreateTexture()
    child.icon:SetWidth(ICONSIZE)
    child.icon:SetHeight(ICONSIZE)
    child.icon:SetTexCoord(unpack(E.TexCoords))

    child.text = child:CreateFontString(nil, nil, "NumberFontNormalSmall")

    child.SetValue = SetValue

    child:EnableMouse(true)
    child:SetScript("OnEnter", OnEnter)
    child:SetScript("OnLeave", OnLeave)

    table.insert(frame.altframes, child)
    return child
end

-- Returns how many of a given cost currency the player currently has
local function GetPlayerCurrencyCount(texture, link)
    if not link and not texture then return 0 end
    if link then
        local bagCount = GetItemCount(link) or 0
        if bagCount > 0 then return bagCount end
        local name = GetItemInfo(link)
        if name and currencyCache[name:lower()] then
            return currencyCache[name:lower()].count or 0
        end
    end
    if texture then
        for _, info in pairs(currencyCache) do
            if info.icon == texture then return info.count or 0 end
        end
    end
    return 0
end

local function AddAltCurrency(frame, i)
    local lastframe = frame.ItemPrice
    local honorPoints, arenaPoints, itemCount = GetMerchantItemCostInfo(i)
    for j = itemCount, 1, -1 do
        local child = frame:GetAltCurrencyFrame()
        local texture, price, costLink = GetMerchantItemCostItem(i, j)
        child:SetValue(price, texture)
        child.index, child.itemIndex, child.link = i, j
        -- Color cost text red if player cannot afford it
        local have = GetPlayerCurrencyCount(texture, costLink)
        child.text:SetTextColor(have >= price and 1 or 1, have >= price and 1 or 0.1, have >= price and 1 or 0.1)
        lastframe = child.text
    end
    if arenaPoints > 0 then
        local child = frame:GetAltCurrencyFrame()
        child:SetValue(arenaPoints, "Interface\\PVPFrame\\PVP-ArenaPoints-Icon", ARENA_POINTS)
        local have = GetArenaCurrency() or 0
        child.text:SetTextColor(have >= arenaPoints and 1 or 1, have >= arenaPoints and 1 or 0.1, have >= arenaPoints and 1 or 0.1)
        lastframe = child.text
    end
    if honorPoints > 0 then
        local child = frame:GetAltCurrencyFrame()
        child:SetValue(honorPoints, "Interface\\PVPFrame\\PVP-Currency-" .. UnitFactionGroup("player"), HONOR_POINTS)
        local have = GetHonorCurrency() or 0
        child.text:SetTextColor(have >= honorPoints and 1 or 1, have >= honorPoints and 1 or 0.1, have >= honorPoints and 1 or 0.1)
        lastframe = child.text
    end
    frame.ItemName:SetPoint("RIGHT", lastframe, "LEFT", -GAP, 0)
end

local quality_colors = setmetatable({}, { __index = function() return "|cffffffff" end })
for i = 1, 7 do quality_colors[i] = select(4, GetItemQualityColor(i)) end

local function MakeGradient(r, g, b)
    return r, g, b, 0.75, r, g, b, 0
end

-- Tooltip-scan based "already known" detection.
-- Uses the game's own 'Already known' text (ITEM_SPELL_KNOWN) for reliability.
local function GetScanTip()
    if not scanTip then
        scanTip = CreateFrame("GameTooltip", "EWT_VendorScanTip", nil, "GameTooltipTemplate")
        scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
    end
    return scanTip
end

local function IsAlreadyKnown(merchantIndex)
    if knownCache[merchantIndex] ~= nil then
        return knownCache[merchantIndex]
    end
    local tip = GetScanTip()
    tip:ClearLines()
    tip:SetMerchantItem(merchantIndex)
    local result = false
    for i = 1, tip:NumLines() do
        local line = _G["EWT_VendorScanTipTextLeft" .. i]
        if line then
            local text = line:GetText()
            if text and text == ITEM_SPELL_KNOWN then
                result = true
                break
            end
        end
    end
    knownCache[merchantIndex] = result
    return result
end

local function GetMerchantCostCurrencyName(merchantIndex, costIndex)
    local tip = GetScanTip()
    tip:ClearLines()
    if not tip.SetMerchantCostItem then return nil end
    tip:SetMerchantCostItem(merchantIndex, costIndex)

    local line = _G["EWT_VendorScanTipTextLeft1"]
    local text = line and line:GetText()
    return text and text ~= "" and text or nil
end

local function NormalizeCurrencyName(name)
    if not name or name == "" then return nil end

    name = name:gsub("|c%x%x%x%x%x%x%x%x", "")
    name = name:gsub("|r", "")
    name = name:gsub("|H.-|h%[(.-)%]|h", "%1")
    name = name:gsub("^%s+", ""):gsub("%s+$", "")

    return name ~= "" and name:lower() or nil
end

local function NormalizeTexture(texture)
    if not texture or texture == "" then return nil end
    return tostring(texture):lower():gsub("/", "\\")
end

local function ExtractItemID(link)
    if not link then return nil end
    local id = tostring(link):match("item:(%d+)")
    return id and tonumber(id) or nil
end

local function FindCurrencyByIcon(texture)
    local key = NormalizeTexture(texture)
    if not key then return nil end

    for _, info in pairs(currencyCache) do
        if NormalizeTexture(info.icon) == key then
            return info
        end
    end
end

local function FindCurrencyByID(id)
    if not id then return nil end

    for _, info in pairs(currencyCache) do
        if info.currencyID and tonumber(info.currencyID) == tonumber(id) then
            return info
        end
    end
end

local function FindCurrencyByItemName(itemName)
    local key = NormalizeCurrencyName(itemName)
    if not key then return nil end

    if currencyCache[key] then return currencyCache[key] end

    for lowerName, info in pairs(currencyCache) do
        if key:find(lowerName, 1, true) or lowerName:find(key, 1, true) then
            return info
        end
    end
end

local function IsLikelyCurrencyItemID(value)
    return type(value) == "number" and value >= 1000
end

local function ScanMerchantItemTooltipForCurrencies(merchantIndex, found)
    local tip = GetScanTip()
    tip:ClearLines()
    tip:SetMerchantItem(merchantIndex)

    for i = 1, tip:NumLines() do
        local line = _G["EWT_VendorScanTipTextLeft" .. i]
        local text = line and line:GetText()
        local key = NormalizeCurrencyName(text)
        if key then
            for lowerName in pairs(currencyCache) do
                if key:find(lowerName, 1, true) then
                    found[lowerName] = true
                end
            end
        end
    end
end

local function MarkCurrency(found, info, fallbackName)
    local key = info and NormalizeCurrencyName(info.name) or NormalizeCurrencyName(fallbackName)
    if key then found[key] = true end
end

local function MarkCurrencyWithIcon(found, info, fallbackName, texture)
    local key = info and NormalizeCurrencyName(info.name) or NormalizeCurrencyName(fallbackName)
    if not key then return end

    found[key] = true
    if info and texture and texture ~= "" then
        info.vendorIcon = texture
    end
end

local function MarkBuiltinCurrency(found, currencyID, fallbackName)
    local info = FindCurrencyByID(currencyID) or FindCurrencyByItemName(GetItemInfo(currencyID))
    MarkCurrency(found, info, fallbackName)
end

local function LoadAllCurrencies()
    wipe(currencyCache)
    local n = GetCurrencyListSize() or 0
    for i = 1, n do
        local name, isHeader, _, _, _, count, extra1, extra2, itemID = GetCurrencyListInfo(i)
        local key = NormalizeCurrencyName(name)
        if key and not isHeader then
            local icon
            local currencyID = IsLikelyCurrencyItemID(itemID) and itemID or nil
            if type(extra1) == "string" and extra1:find("^Interface\\") then
                icon = extra1
            elseif IsLikelyCurrencyItemID(extra1) then
                currencyID = extra1
            elseif type(extra1) == "string" and extra1 ~= "" then
                icon = extra1
            elseif type(extra2) == "string" and extra2:find("^Interface\\") then
                icon = extra2
            elseif IsLikelyCurrencyItemID(extra2) then
                currencyID = currencyID or extra2
            elseif type(extra2) == "string" and extra2 ~= "" then
                icon = icon or extra2
            end
            currencyCache[key] = {
                name = name,
                icon = icon or "Interface\\Icons\\INV_Misc_Coin_01",
                currencyID = currencyID,
                index = i,
                count =
                    count or 0
            }
        end
    end
end

local function GetCurrencyDisplayIcon(info)
    local name = info and NormalizeCurrencyName(info.name)
    if info and (info.currencyID == HONOR_POINTS_ID or name == "honor points") then
        local faction = E and E.myfaction or UnitFactionGroup("player") or "Alliance"
        return "Interface\\PVPFrame\\PVP-Currency-" .. faction
    end

    if info and (info.currencyID == ARENA_POINTS_ID or name == "arena points" or name == "conquest points") then
        return "Interface\\PVPFrame\\PVP-ArenaPoints-Icon"
    end

    if info and info.vendorIcon then
        return info.vendorIcon
    end

    return info and info.icon
end

local function ScanVendorForCurrencies()
    local found = {}
    local numItems = GetMerchantNumItems() or 0
    if numItems == 0 then return found end

    for i = 1, numItems do
        local honor, arena, count = GetMerchantItemCostInfo(i)
        if honor > 0 then MarkBuiltinCurrency(found, HONOR_POINTS_ID, "honor points") end
        if arena > 0 then MarkBuiltinCurrency(found, ARENA_POINTS_ID, "arena points") end
        if count > 0 then
            for j = 1, count do
                local texture, price, link = GetMerchantItemCostItem(i, j)
                local matched
                if link then
                    local name = GetItemInfo(link)
                    local info = FindCurrencyByItemName(name) or FindCurrencyByID(ExtractItemID(link))
                    if info then
                        MarkCurrencyWithIcon(found, info, nil, texture)
                        matched = true
                    end
                end

                if not matched then
                    local name = GetMerchantCostCurrencyName(i, j)
                    local info = FindCurrencyByItemName(name)
                    if info then
                        MarkCurrencyWithIcon(found, info, nil, texture)
                        matched = true
                    end
                end

                if not matched and texture then
                    local info = FindCurrencyByIcon(texture) or FindCurrencyByID(texture)
                    if info then
                        MarkCurrencyWithIcon(found, info, nil, texture)
                        matched = true
                    end
                end

                if not matched then
                    ScanMerchantItemTooltipForCurrencies(i, found)
                end
            end
        end
    end
    return found
end

local function UpdateCurrencyBar()
    if not SUB.db.enabled or not SUB.db.showCurrencies or not MerchantFrame:IsVisible() then
        if currencyBar then currencyBar:Hide() end
        if currencyBarHolder then currencyBarHolder:Hide() end
        return
    end

    if not currencyBarHolder then
        currencyBarHolder = CreateFrame("Frame", nil, MerchantFrame)
        currencyBarHolder:SetSize(1, 1)
        currencyBarHolder:SetPoint("BOTTOMLEFT", MerchantFrame, "TOPLEFT", 12, -12)
    end

    if not currencyBar then
        currencyBar = CreateFrame("Frame", "EWT_VendorTweaksCurrencyBar", currencyBarHolder)
        currencyBar:SetPoint("BOTTOMLEFT", currencyBarHolder, "BOTTOMLEFT", 0, 0)
        currencyBar:SetHeight(28)
        currencyBar:CreateBackdrop("Transparent")
    end

    currencyBar:SetScale(SUB.db.currencyScale or 1.0)
    currencyBarHolder:Show() -- Ensure holder is visible


    LoadAllCurrencies()
    local found = ScanVendorForCurrencies()
    local sorted = {}
    for name in pairs(found) do
        if currencyCache[name] then table.insert(sorted, currencyCache[name]) end
    end
    table.sort(sorted, function(a, b) return a.name < b.name end)

    for _, frame in ipairs(tokenFrames) do frame:Hide() end

    local xOffset = 6 -- Initial padding
    for i, info in ipairs(sorted) do
        local frame = tokenFrames[i]
        if not frame then
            frame = CreateFrame("Button", nil, currencyBar)
            frame:SetHeight(20)

            frame.icon = frame:CreateTexture(nil, "ARTWORK")
            frame.icon:SetPoint("LEFT", 0, 0)
            frame.icon:SetSize(16, 16)
            S:HandleIcon(frame.icon)

            frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            frame.text:SetPoint("LEFT", frame.icon, "RIGHT", 5, 0)
            frame.text:SetJustifyH("LEFT")

            frame:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:ClearLines()
                GameTooltip:AddLine(self.info.name, 1, 1, 1)
                GameTooltip:AddLine("You have: |cffffffff" .. self.info.count .. "|r", 1, 1, 1)
                GameTooltip:Show()
            end)
            frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
            tokenFrames[i] = frame
        end

        frame.info = info
        frame.index = info.index
        frame.icon:SetTexture(GetCurrencyDisplayIcon(info))
        local count = info.count
        if count > 99999 then count = math.floor(count / 1000) .. "k" end
        frame.text:SetText(count)

        local textWidth = frame.text:GetStringWidth()
        frame:SetWidth(16 + 5 + textWidth)

        frame:SetPoint("LEFT", currencyBar, "LEFT", xOffset, 0)
        xOffset = xOffset + frame:GetWidth() + 10
        frame:Show()
    end

    if xOffset > 6 then
        currencyBar:SetWidth(xOffset - 4) -- -4 to trim the last spacing
        currencyBar:Show()
    else
        currencyBar:Hide()
    end
end

local function Refresh()
    if not f or not f:IsShown() then return end
    LoadAllCurrencies() -- Ensure cache is fresh before any affordability checks
    local n = GetMerchantNumItems()
    local numRows = SUB.db.numRows or 12
    local altRows = SUB.db.alternateRows
    for i, row in pairs(rows) do
        local j = i + offset
        if i > numRows or j > n then
            row:Hide()
        else
            row.backdrop:Hide()
            if altRows and (i % 2 == 0) then
                row.altbg:Show()
            else
                row.altbg:Hide()
            end

            local name, itemTexture, itemPrice, itemStackCount, numAvailable, isUsable, extendedCost =
                GetMerchantItemInfo(j)
            local link = GetMerchantItemLink(j)
            local color = quality_colors.default
            local isLearnable, isAlreadyKnown = false, false

            if link then
                local _, _, quality, _, _, itemClass = GetItemInfo(link)
                if quality then color = quality_colors[quality] end

                -- Only check learnable status for Recipe/Miscellaneous class items
                if itemClass and LEARNABLE_ITEM_CLASSES and LEARNABLE_ITEM_CLASSES[itemClass] then
                    -- Private servers often return nil for GetItemSpell on custom recipes.
                    -- If it's a Recipe, it's always learnable. For Misc, fallback to GetItemSpell.
                    if LEARNABLE_ITEM_CLASSES[itemClass] == "recipe" then
                        isLearnable = true
                    else
                        local spellName = GetItemSpell(link)
                        if spellName and spellName ~= "" then
                            isLearnable = true
                        end
                    end
                    -- Always scan the tooltip for "Already known" if it's in these categories
                    isAlreadyKnown = IsAlreadyKnown(j)
                end
            end

            local db = SUB.db
            local isOwned = link and db.colorOwned and (GetItemCount(link) or 0) > 0

            -- Apply backdrop: unusable > already known > not yet known > owned
            row.backdrop:Hide()
            if not isUsable and db.colorUnusable then
                local c = db.colorUnusableColor or { 0.8, 0, 0 }
                row.backdrop:SetGradientAlpha("HORIZONTAL", MakeGradient(c[1], c[2], c[3]))
                row.backdrop:Show()
            elseif isAlreadyKnown and db.colorAlreadyKnown then
                local c = db.colorAlreadyKnownColor or { 0, 0.75, 0 }
                row.backdrop:SetGradientAlpha("HORIZONTAL", MakeGradient(c[1], c[2], c[3]))
                row.backdrop:Show()
            elseif isLearnable and not isAlreadyKnown and db.colorNotYetKnown then
                local c = db.colorNotYetKnownColor or { 0.8, 0.8, 0 }
                row.backdrop:SetGradientAlpha("HORIZONTAL", MakeGradient(c[1], c[2], c[3]))
                row.backdrop:Show()
            elseif isOwned then
                local c = db.colorOwnedColor or { 0.3, 0.7, 1 }
                row.backdrop:SetGradientAlpha("HORIZONTAL", MakeGradient(c[1], c[2], c[3]))
                row.backdrop:Show()
            end

            row:SetAlpha(searchstring and name and not name:lower():match(searchstring) and 0.5 or 1)

            row.icon:SetTexture(itemTexture)
            row.ItemName:SetText((numAvailable > -1 and ("[" .. numAvailable .. "] ") or "") ..
                color .. (name or "<Loading item data>") .. (itemStackCount > 1 and ("|r x" .. itemStackCount) or ""))

            for _, v in pairs(row.altframes) do v:Hide() end
            row.altcurrency = extendedCost
            if extendedCost then
                row:AddAltCurrency(j)
                row.link, row.texture, row.extendedCost = link, itemTexture, true
            end
            if itemPrice > 0 then
                row.ItemPrice:SetText(GSC(itemPrice))
                row.Price = itemPrice
            end
            if extendedCost and (itemPrice <= 0) then
                row.ItemPrice:SetText()
                row.Price = 0
            elseif extendedCost and (itemPrice > 0) then
                row.ItemPrice:SetText(GSC(itemPrice))
            else
                row.ItemName:SetPoint("RIGHT", row.ItemPrice, "LEFT", -GAP, 0)
                row.extendedCost = nil
            end

            if db.colorIcons then
                if not isUsable and db.colorUnusable then
                    local c = db.colorUnusableColor or { 0.8, 0, 0 }
                    row.icon:SetVertexColor(c[1], c[2], c[3])
                elseif isAlreadyKnown and db.colorAlreadyKnown then
                    local c = db.colorAlreadyKnownColor or { 0, 0.75, 0 }
                    row.icon:SetVertexColor(c[1], c[2], c[3])
                elseif isLearnable and not isAlreadyKnown and db.colorNotYetKnown then
                    local c = db.colorNotYetKnownColor or { 0.8, 0.8, 0 }
                    row.icon:SetVertexColor(c[1], c[2], c[3])
                elseif isOwned then
                    local c = db.colorOwnedColor or { 0.3, 0.7, 1 }
                    row.icon:SetVertexColor(c[1], c[2], c[3])
                else
                    row.icon:SetVertexColor(1, 1, 1)
                end
            else
                row.icon:SetVertexColor(1, 1, 1)
            end
            row:SetID(j)
            row:Show()
        end
    end
    UpdateCurrencyBar()
end

local MAX_ROWS = 30

local function UpdateRowLayout()
    if not f then return end
    local numRows = SUB.db.numRows or 12
    local ROWHEIGHT = 290 / numRows
    local ICONSIZE = ROWHEIGHT - 4
    if ICONSIZE > 24 then ICONSIZE = 24 end

    for i = 1, MAX_ROWS do
        local row = rows[i]
        if row then
            row:SetHeight(ROWHEIGHT)
            row.iconFrame:SetSize(ICONSIZE, ICONSIZE)
            row.popout:SetSize(ROWHEIGHT / 2, ROWHEIGHT)
        end
    end

    if MerchantFrame:IsVisible() then
        local maxOffset = math.max(0, GetMerchantNumItems() - numRows)
        f.scrollbar:SetMinMaxValues(0, maxOffset)
        local val = f.scrollbar:GetValue()
        if val > maxOffset then f.scrollbar:SetValue(maxOffset) end
        if f.UpdateScrollArrows then f.UpdateScrollArrows() end
        Refresh()
    end
end

local function BuildUI()
    if f then return end
    f = CreateFrame("Frame", "EWT_VendorTweaksFrame", MerchantFrame)
    f:SetWidth(325)
    f:SetHeight(294)
    f:SetPoint("TOPLEFT", 19, -54)
    f:SetTemplate("Transparent")
    f:Hide()

    local scrollbar = CreateFrame("Slider", "EWT_VendorTweaksScroll", f, "UIPanelScrollBarTemplate")
    scrollbar:SetScript("OnValueChanged", nil)
    scrollbar:SetWidth(18)
    scrollbar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -3, -19)
    scrollbar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -3, 19)
    S:HandleScrollBar(scrollbar)
    scrollbar:SetMinMaxValues(0, 0)
    scrollbar:SetValueStep(1)
    scrollbar:SetValue(0)

    local function UpdateScrollArrows()
        local min, max = scrollbar:GetMinMaxValues()
        local val = scrollbar:GetValue()
        local upBtn = _G["EWT_VendorTweaksScrollScrollUpButton"]
        local downBtn = _G["EWT_VendorTweaksScrollScrollDownButton"]
        if upBtn then
            if val <= min then upBtn:Disable() else upBtn:Enable() end
        end
        if downBtn then
            if val >= max or max == 0 then downBtn:Disable() else downBtn:Enable() end
        end
    end

    scrollbar:SetScript("OnValueChanged", function(self, value)
        offset = math.floor(value)
        Refresh()
        UpdateScrollArrows()
    end)
    f.scrollbar = scrollbar
    f.UpdateScrollArrows = UpdateScrollArrows

    for i = 1, MAX_ROWS do
        local row = CreateFrame('Button', nil, f)
        row:SetPoint("TOP", i == 1 and f or rows[i - 1], i == 1 and "TOP" or "BOTTOM", 0, i == 1 and -2 or 0)
        row:SetPoint("LEFT", 2, 0)
        row:SetPoint("RIGHT", -24, 0)

        row.BuyItem = BuyItem
        row:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2")
        S:HandleButtonHighlight(row)
        row:RegisterForClicks("AnyUp")
        row:SetScript('OnClick', OnClick)
        row:SetScript('OnDragStart', function(self, button)
            MerchantFrame.extendedCost = nil
            PickupMerchantItem(self:GetID())
            if self.extendedCost then MerchantFrame.extendedCost = self end
        end)

        local backdrop = row:CreateTexture(nil, "BACKGROUND")
        backdrop:SetAllPoints()
        backdrop:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
        row.backdrop = backdrop

        local altbg = row:CreateTexture(nil, "BACKGROUND")
        altbg:SetAllPoints()
        altbg:SetTexture(1, 1, 1, 0.05)
        altbg:Hide()
        row.altbg = altbg

        local iconFrame = CreateFrame('Frame', nil, row)
        iconFrame:SetPoint('LEFT', 2, 0)
        row.iconFrame = iconFrame

        row.icon = iconFrame:CreateTexture(nil, "BORDER")
        row.icon:SetAllPoints()
        row.icon:SetTexCoord(unpack(E.TexCoords))

        local ItemName = row:CreateFontString(nil, nil, "GameFontNormalSmall")
        ItemName:SetPoint('LEFT', iconFrame, "RIGHT", GAP, 0)
        ItemName:SetJustifyH('LEFT')
        row.ItemName = ItemName

        local popout = CreateFrame("Button", nil, row)
        popout:SetPoint("RIGHT", -3, 0)
        popout.icon = popout:CreateTexture(nil, "ARTWORK")
        popout.icon:SetSize(21, 21)
        popout.icon:SetPoint("CENTER")
        popout.icon:SetTexture(E.Media.Textures.ArrowUp)
        popout.icon:SetRotation(S.ArrowRotation.right)

        popout:SetScript("OnClick", PopoutOnClick)
        popout:HookScript("OnEnter", function(self) self.icon:SetVertexColor(unpack(E.media.rgbvaluecolor)) end)
        popout:HookScript("OnLeave", function(self) self.icon:SetVertexColor(1, 1, 1) end)
        popout.SplitStack = PopoutSplitStack
        row.popout = popout

        local ItemPrice = row:CreateFontString(nil, nil, "NumberFontNormalSmall")
        ItemPrice:SetPoint('RIGHT', popout, "LEFT", -2, 0)
        row.ItemPrice = ItemPrice

        row.altframes = {}
        row.AddAltCurrency, row.GetAltCurrencyFrame = AddAltCurrency, GetAltCurrencyFrame

        row:SetScript('OnEnter', function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetMerchantItem(self:GetID())
            GameTooltip_ShowCompareItem()
            MerchantFrame.itemHover = self:GetID()
            if IsModifiedClick("DRESSUP") then ShowInspectCursor() else ResetCursor() end
        end)
        row:SetScript('OnLeave', function()
            GameTooltip:Hide()
            ResetCursor()
            MerchantFrame.itemHover = nil
        end)

        rows[i] = row
    end

    local editbox = CreateFrame('EditBox', nil, f)
    editbox:SetAutoFocus(false)
    editbox:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 1, -61)
    editbox:SetSize(135, 18)
    editbox:SetFontObject('GameFontHighlightSmall')
    S:HandleEditBox(editbox)

    editbox:SetScript("OnEscapePressed", editbox.ClearFocus)
    editbox:SetScript("OnEnterPressed", editbox.ClearFocus)
    editbox:SetScript("OnEditFocusGained", function(self)
        if not searchstring then
            self:SetText("")
            self:SetTextColor(1, 1, 1, 1)
        end
    end)
    editbox:SetScript("OnEditFocusLost", function(self)
        if self:GetText() == "" then
            self:SetText("Search...")
            self:SetTextColor(0.75, 0.75, 0.75, 1)
        end
    end)
    editbox:SetScript("OnTextChanged", function(self)
        local t = self:GetText()
        searchstring = t ~= "" and t ~= "Search..." and t:lower() or nil
        offset = 0
        scrollbar:SetValue(0)
        Refresh()
    end)
    editbox:SetScript("OnShow", function(self)
        self:SetText("Search...")
        self:SetTextColor(0.75, 0.75, 0.75, 1)
        searchstring = nil
    end)

    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(self, delta)
        local val = scrollbar:GetValue() - (delta * SCROLLSTEP)
        local min, max = scrollbar:GetMinMaxValues()
        if val < min then val = min end
        if val > max then val = max end
        scrollbar:SetValue(val)
    end)

    f:SetScript("OnShow", function(self)
        wipe(knownCache) -- fresh detection each time the vendor opens
        local numRows = SUB.db.numRows or 12
        local max = math.max(0, GetMerchantNumItems() - numRows)
        scrollbar:SetMinMaxValues(0, max)
        offset = 0
        scrollbar:SetValue(0)
        Refresh()
        if f.UpdateScrollArrows then f.UpdateScrollArrows() end
    end)

    f:RegisterEvent("CURRENCY_DISPLAY_UPDATE")
    f:HookScript("OnEvent", function(self, event)
        if event == "CURRENCY_DISPLAY_UPDATE" then
            UpdateCurrencyBar()
        end
    end)

    f:SetScript("OnHide", function()
        if StackSplitFrame:IsVisible() then StackSplitFrame:Hide() end
        if currencyBar then currencyBar:Hide() end
    end)

    UpdateRowLayout()
end

local function UpdateVisibility()
    if not SUB.db.enabled then
        if f then f:Hide() end
        for i = 1, 12 do
            local item = _G["MerchantItem" .. i]
            if item then item:Show() end
        end
        if _G.MerchantNextPageButton then _G.MerchantNextPageButton:Show() end
        if _G.MerchantPrevPageButton then _G.MerchantPrevPageButton:Show() end
        if _G.MerchantPageText then _G.MerchantPageText:Show() end
        return
    end

    if MerchantFrame:IsVisible() and MerchantFrame.selectedTab == 1 then
        for i = 1, 12 do
            local item = _G["MerchantItem" .. i]
            if item then item:Hide() end
        end
        if _G.MerchantNextPageButton then _G.MerchantNextPageButton:Hide() end
        if _G.MerchantPrevPageButton then _G.MerchantPrevPageButton:Hide() end
        if _G.MerchantPageText then _G.MerchantPageText:Hide() end

        MerchantBuyBackItem:ClearAllPoints()
        MerchantBuyBackItem:SetPoint("BOTTOMLEFT", 187, 118)

        if f then f:Show() end
        Refresh()
    else
        if f then f:Hide() end
        for i = 1, 12 do
            local item = _G["MerchantItem" .. i]
            if item then item:Show() end
        end
        if currencyBar then currencyBar:Hide() end
    end
end

function SUB:ApplyEnabled(db)
    SUB.db = db
    if db.enabled then
        BuildLearnableClasses()
        BuildUI()
        UpdateRowLayout()

        if not isHooked then
            hooksecurefunc("MerchantFrame_UpdateMerchantInfo", UpdateVisibility)
            hooksecurefunc("MerchantFrame_UpdateBuybackInfo", UpdateVisibility)
            isHooked = true
        end

        if MerchantFrame:IsVisible() then UpdateVisibility() end
    else
        UpdateVisibility()
        if currencyBar then currencyBar:Hide() end
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
                name = "Vendor Tweaks",
            },
            description = {
                order = 1,
                type = "description",
                name =
                "Replaces the default 10-item grid merchant layout with a compact, scrollable list view.\n\n|cffaaaaaaHeavily inspired by the original GnomishVendorShrinker addon by Tekkub.|r",
            },
            enabled = {
                order = 2,
                type = "toggle",
                width = "double",
                name = function() return db.enabled and "|cff00ff00Enabled|r" or "|cffff0000Disabled|r" end,
                desc = "Toggle the Vendor Tweaks module.",
                get = function() return db.enabled end,
                set = function(_, value)
                    db.enabled = value
                    SUB:ApplyEnabled(db)
                    if not value then
                        E:StaticPopup_Show("GLOBAL_RL")
                    end
                end,
            },
            projectEpochCompat = {
                order = 2.1,
                type = "toggle",
                width = "double",
                name = "Project Epoch Compatibility",
                desc = "Adjusts item classification indices for Project Epoch/Ascension servers (where custom categories push default indices down). Automatically enables itself if your client has modified AH categories.",
                get = function() 
                    if db.projectEpochCompat == nil then
                        return (select("#", GetAuctionItemClasses()) >= 12)
                    end
                    return db.projectEpochCompat 
                end,
                set = function(_, value)
                    db.projectEpochCompat = value
                    BuildLearnableClasses()
                    if f and f:IsShown() then Refresh() end
                end,
                disabled = function() return not db.enabled end,
            },
            alternateRows = {
                order = 3,
                type = "toggle",
                width = "double",
                name = "Alternate Rows",
                desc =
                "Adds a subtle alternating transparent background to every other row to make scanning items easier.",
                get = function() return db.alternateRows end,
                set = function(_, value)
                    db.alternateRows = value
                    if f then
                        UpdateRowLayout()
                        Refresh()
                    end
                end,
                disabled = function() return not db.enabled end,
            },
            numRows = {
                order = 4,
                type = "range",
                width = "double",
                name = "Number of Rows",
                desc =
                "Adjust how many items are visible at once. A higher number squishes the rows together, while a lower number expands the row height.\n\nDefault is 12.",
                min = 8,
                max = 16,
                step = 1,
                get = function() return db.numRows or 12 end,
                set = function(_, value)
                    db.numRows = value
                    if f then
                        UpdateRowLayout()
                    end
                end,
                disabled = function() return not db.enabled end,
            },
            showCurrencies = {
                order = 5,
                type = "toggle",
                width = "double",
                name = "Currency Display",
                desc =
                "Displays a bar at the top of the vendor frame showing how many of the relevant currencies (used by this vendor) you currently possess.\n\n|cffaaaaaaPorted from my unreleased HMDIH addon.|r",
                get = function() return db.showCurrencies end,
                set = function(_, value)
                    db.showCurrencies = value
                    UpdateCurrencyBar()
                end,
                disabled = function() return not db.enabled end,
            },
            currencyScale = {
                order = 6,
                type = "range",
                width = "double",
                name = "Currency Scale",
                desc = "Adjust the scale of the currency display bar at the top of the vendor frame.",
                min = 0.5,
                max = 1.5,
                step = 0.05,
                get = function() return db.currencyScale or 1.0 end,
                set = function(_, value)
                    db.currencyScale = value
                    UpdateCurrencyBar()
                end,
                disabled = function() return not db.enabled or not db.showCurrencies end,
            },
            -- Item Coloring
            colorHeader = {
                order = 7,
                type = "header",
                name = "Item Coloring",
            },
            colorHeaderDesc = {
                order = 7.1,
                type = "description",
                name =
                "Color vendor rows based on item status. Learnable items include recipes, spells, mounts, and companions.\n",
            },
            colorUnusable = {
                order = 8,
                type = "toggle",
                width = "normal",
                name = "Color Unusable",
                desc =
                "Highlights items you cannot use (wrong level, class, or profession) with a colored row and icon tint.",
                get = function() return db.colorUnusable end,
                set = function(_, v)
                    db.colorUnusable = v
                    Refresh()
                end,
                disabled = function() return not db.enabled end,
            },
            colorUnusableColor = {
                order = 8.1,
                type = "color",
                width = "half",
                name = "Color",
                hasAlpha = false,
                get = function()
                    local c = db.colorUnusableColor or { 0.8, 0, 0 }
                    return c[1], c[2], c[3], 1, 0.8, 0, 0, 1
                end,
                set = function(_, r, g, b)
                    db.colorUnusableColor = { r, g, b }
                    Refresh()
                end,
                disabled = function() return not db.enabled or not db.colorUnusable end,
            },
            colorUnusableSpacer = { order = 8.2, type = "description", name = " ", width = "double" },
            colorAlreadyKnown = {
                order = 9,
                type = "toggle",
                width = "normal",
                name = "Color Already Known",
                desc = "Highlights learnable items (recipes, mounts, etc.) that you have already learned.",
                get = function() return db.colorAlreadyKnown end,
                set = function(_, v)
                    db.colorAlreadyKnown = v
                    Refresh()
                end,
                disabled = function() return not db.enabled end,
            },
            colorAlreadyKnownColor = {
                order = 9.1,
                type = "color",
                width = "half",
                name = "Color",
                hasAlpha = false,
                get = function()
                    local c = db.colorAlreadyKnownColor or { 0, 0.75, 0 }
                    return c[1], c[2], c[3], 1, 0, 0.75, 0, 1
                end,
                set = function(_, r, g, b)
                    db.colorAlreadyKnownColor = { r, g, b }
                    Refresh()
                end,
                disabled = function() return not db.enabled or not db.colorAlreadyKnown end,
            },
            colorAlreadyKnownSpacer = { order = 9.2, type = "description", name = " ", width = "double" },
            colorNotYetKnown = {
                order = 10,
                type = "toggle",
                width = "normal",
                name = "Color Not Yet Known",
                desc = "Highlights learnable items (recipes, mounts, etc.) that you can use but have not yet learned.",
                get = function() return db.colorNotYetKnown end,
                set = function(_, v)
                    db.colorNotYetKnown = v
                    Refresh()
                end,
                disabled = function() return not db.enabled end,
            },
            colorNotYetKnownColor = {
                order = 10.1,
                type = "color",
                width = "half",
                name = "Color",
                hasAlpha = false,
                get = function()
                    local c = db.colorNotYetKnownColor or { 0.8, 0.8, 0 }
                    return c[1], c[2], c[3], 1, 0.8, 0.8, 0, 1
                end,
                set = function(_, r, g, b)
                    db.colorNotYetKnownColor = { r, g, b }
                    Refresh()
                end,
                disabled = function() return not db.enabled or not db.colorNotYetKnown end,
            },
            colorIconsSpacer = { order = 10.2, type = "description", name = " ", width = "double" },
            colorOwned = {
                order = 11,
                type = "toggle",
                width = "normal",
                name = "Color Owned",
                desc = "Highlights items that you already have in your inventory, bank, or bags. Useful for preventing duplicate purchases at PvP vendors.",
                get = function() return db.colorOwned end,
                set = function(_, v)
                    db.colorOwned = v
                    Refresh()
                end,
                disabled = function() return not db.enabled end,
            },
            colorOwnedColor = {
                order = 11.1,
                type = "color",
                width = "half",
                name = "Color",
                hasAlpha = false,
                get = function()
                    local c = db.colorOwnedColor or { 0.3, 0.7, 1 }
                    return c[1], c[2], c[3], 1, 0.3, 0.7, 1, 1
                end,
                set = function(_, r, g, b)
                    db.colorOwnedColor = { r, g, b }
                    Refresh()
                end,
                disabled = function() return not db.enabled or not db.colorOwned end,
            },
            colorOwnedSpacer = { order = 11.2, type = "description", name = " ", width = "double" },
            colorIcons = {
                order = 12,
                type = "toggle",
                width = "double",
                name = "Tint Icons",
                desc =
                "When enabled, item icons are also tinted with the corresponding status color. Disable to keep icons at full brightness while still showing the row background coloring.",
                get = function() return db.colorIcons end,
                set = function(_, v)
                    db.colorIcons = v
                    Refresh()
                end,
                disabled = function() return not db.enabled end,
            },
        }
    }
end

MOD:RegisterSubmodule("VendorTweaks", SUB)
