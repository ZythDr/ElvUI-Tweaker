-- GoldScaleFix.lua
-- DataTexts submodule: Allows adjusting scale and offset of Gold/Silver/Copper icons in gold datatext

local core = EWTweaker and EWTweaker.GetCore and EWTweaker.GetCore()
if not core then return end
local MOD = core.modules and core.modules.DataTexts
if not MOD then return end

local E, L = unpack(ElvUI)

local SUB = { name = "GoldScaleFix" }
SUB.defaults = {
    enabled = true,
    iconScale = 1.0,
    iconXOffset = 0,
    iconYOffset = 0,
}

local db_local
local OriginalFormatMoney = E.FormatMoney

-- Utility for icons
local function getIcon(tag, scale, xOffset, yOffset)
    scale = scale or 1
    xOffset = xOffset or 0
    yOffset = yOffset or 0
    local size = math.floor(14 * scale)
    -- The 4th argument to |T texture tag is y-offset
    return ("|T%s:%d:%d:%d:%d:64:64:4:60:4:60|t"):format(tag, size, size, xOffset, yOffset)
end

local function CustomFormatMoney(amount, style, textonly, ...)
    if type(amount) == "table" and type(style) == "number" then
        amount, style, textonly = style, textonly, ...
    end
    amount = tonumber(amount) or 0

    local scale = (db_local and db_local.iconScale) or 1
    local xOffset = (db_local and db_local.iconXOffset) or 0
    local yOffset = (db_local and db_local.iconYOffset) or 0

    local ICON_GOLD   = getIcon("Interface\\MoneyFrame\\UI-GoldIcon", scale, xOffset, yOffset)
    local ICON_SILVER = getIcon("Interface\\MoneyFrame\\UI-SilverIcon", scale, xOffset, yOffset)
    local ICON_COPPER = getIcon("Interface\\MoneyFrame\\UI-CopperIcon", scale, xOffset, yOffset)

    local coppername = textonly and L["copperabbrev"] or ICON_COPPER
    local silvername = textonly and L["silverabbrev"] or ICON_SILVER
    local goldname   = textonly and L["goldabbrev"]   or ICON_GOLD

    local value = math.abs(amount)
    local gold   = math.floor(value / 10000)
    local silver = math.floor(math.fmod(value / 100, 100))
    local copper = math.floor(math.fmod(value, 100))

    if not style or style == "SMART" then
        local str = ""
        if gold > 0 then str = string.format("%d%s%s", gold, goldname, (silver > 0 or copper > 0) and " " or "") end
        if silver > 0 then str = string.format("%s%d%s%s", str, silver, silvername, copper > 0 and " " or "") end
        if copper > 0 or value == 0 then str = string.format("%s%d%s", str, copper, coppername) end
        return str
    elseif style == "FULL" then
        if gold > 0 then
            return string.format("%d%s %d%s %d%s", gold, goldname, silver, silvername, copper, coppername)
        elseif silver > 0 then
            return string.format("%d%s %d%s", silver, silvername, copper, coppername)
        else
            return string.format("%d%s", copper, coppername)
        end
    elseif style == "SHORT" then
        if gold > 0 then
            return string.format("%.1f%s", amount / 10000, goldname)
        elseif silver > 0 then
            return string.format("%.1f%s", amount / 100, silvername)
        else
            return string.format("%d%s", amount, coppername)
        end
    elseif style == "SHORTINT" then
        if gold > 0 then
            return string.format("%d%s", gold, goldname)
        elseif silver > 0 then
            return string.format("%d%s", silver, silvername)
        else
            return string.format("%d%s", copper, coppername)
        end
    elseif style == "CONDENSED" then
        if gold > 0 then
            return string.format("%d%s.%02d%s.%02d%s", gold, goldname, silver, silvername, copper, coppername)
        elseif silver > 0 then
            return string.format("%d%s.%02d%s", silver, silvername, copper, coppername)
        else
            return string.format("%d%s", copper, coppername)
        end
    elseif style == "BLIZZARD" then
        if gold > 0 then
            return string.format("%s%s %d%s %d%s", gold, goldname, silver, silvername, copper, coppername)
        elseif silver > 0 then
            return string.format("%d%s %d%s", silver, silvername, copper, coppername)
        else
            return string.format("%d%s", copper, coppername)
        end
    end
end

local function ApplyHooks()
    if db_local and db_local.enabled then
        E.FormatMoney = CustomFormatMoney
    else
        E.FormatMoney = OriginalFormatMoney
    end
end

local function RefreshGoldDatatext()
    local DT = E:GetModule("DataTexts")
    if DT and DT.LoadDataTexts then
        DT:LoadDataTexts()
    end
end

function SUB:GetOptions(db)
    db = db or (MOD.db and MOD.db.GoldScaleFix or SUB.defaults)
    for k, v in pairs(SUB.defaults) do 
        if db[k] == nil then 
            db[k] = v 
        end 
    end
    
    return {
        type = "group",
        name = SUB.name,
        args = {
            header = { 
                order = 0, 
                type = "header", 
                name = L["GoldScaleFix"] 
            },
            description = {
                order = 1,
                type = "description",
                name = L["Adjust position and scale of currency icons in ElvUI's \"Gold\" DataText panel."] .. "\n",
            },
            enabled = {
                order = 2, 
                type = "toggle", 
                name = function() 
                    return db.enabled and "|cff00ff00Enabled|r" or "|cffff0000Disabled|r" 
                end,
                desc = L["Enable or disable GoldScaleFix tweaks."],
                get = function() return db.enabled end,
                set = function(_, value)
                    db.enabled = value
                    if db_local then db_local.enabled = value end
                    ApplyHooks()
                    RefreshGoldDatatext()
                end,
            },
            spacer = {
                order = 2.5,
                type = "description",
                name = " ",
                width = "full",
            },
            iconScale = {
                order = 3, 
                type = "range", 
                min = 0.5, 
                max = 2, 
                step = 0.01,
                name = L["Icon Scale"], 
                desc = L["Adjust the scale of gold/silver/copper icons."],
                get = function() return db.iconScale end,
                set = function(_, value)
                    db.iconScale = value
                    if db_local then db_local.iconScale = value end
                    ApplyHooks()
                    RefreshGoldDatatext()
                end,
                disabled = function() return not db.enabled end,
            },
            iconXOffset = {
                order = 4, 
                type = "range", 
                min = -20, 
                max = 20, 
                step = 1,
                name = L["Icon X-Offset"], 
                desc = L["Adjust the horizontal offset of gold/silver/copper icons."],
                get = function() return db.iconXOffset end,
                set = function(_, value)
                    db.iconXOffset = value
                    if db_local then db_local.iconXOffset = value end
                    ApplyHooks()
                    RefreshGoldDatatext()
                end,
                disabled = function() return not db.enabled end,
            },
            iconYOffset = {
                order = 5, 
                type = "range", 
                min = -20, 
                max = 20, 
                step = 1,
                name = L["Icon Y-Offset"], 
                desc = L["Adjust the vertical offset of gold/silver/copper icons."],
                get = function() return db.iconYOffset end,
                set = function(_, value)
                    db.iconYOffset = value
                    if db_local then db_local.iconYOffset = value end
                    ApplyHooks()
                    RefreshGoldDatatext()
                end,
                disabled = function() return not db.enabled end,
            },
        }
    }
end

function SUB:OnEnable(db)
    db_local = db or {}
    for k, v in pairs(SUB.defaults) do 
        if db_local[k] == nil then 
            db_local[k] = v 
        end 
    end
    
    ApplyHooks()
    RefreshGoldDatatext()
end

function SUB:OnDisable(db)
    E.FormatMoney = OriginalFormatMoney
    RefreshGoldDatatext()
end

MOD:RegisterSubmodule("GoldScaleFix", SUB)
