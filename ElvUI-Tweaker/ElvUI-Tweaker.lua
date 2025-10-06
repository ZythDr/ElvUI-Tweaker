local EWTweaker = {}
_G["EWTweaker"] = EWTweaker

-- Registry for modules (actual loaded modules)
EWTweaker.modules = {}
EWTweaker.defaultDB = {}

-- Manifest of supported modules (add more here as you expand)
EWTweaker.MODULES = {
    DataTexts = { title = "DataTexts", addon = "ElvUI-Tweaker_DataTexts" },
    MiscTweaks = { title = "MiscTweaks", addon = "ElvUI-Tweaker_MiscTweaks" },
    -- Example: AnotherModule = { title = "AnotherModule", addon = "ElvUI-Tweaker_AnotherModule" },
}

EWTweaker.db = nil

-- Register modules and their defaults
function EWTweaker:RegisterModule(name, module, defaults)
    EWTweaker.modules[name] = module
    EWTweaker.defaultDB[name] = defaults
end

-- Helper: Deep copy for defaults
local function CopyTable(orig)
    local copy = {}
    for k, v in pairs(orig) do
        if type(v) == "table" then
            copy[k] = CopyTable(v)
        else
            copy[k] = v
        end
    end
    return copy
end

-- Handle SavedVariables switching
function EWTweaker:RefreshDB()
    if ElvUI_WotLK_TweakerDBPC and ElvUI_WotLK_TweakerDBPC.usePerCharacter then
        if not ElvUI_WotLK_TweakerDBPC.profile then ElvUI_WotLK_TweakerDBPC.profile = {} end
        EWTweaker.db = ElvUI_WotLK_TweakerDBPC.profile
    else
        if not ElvUI_WotLK_TweakerDB then ElvUI_WotLK_TweakerDB = {} end
        EWTweaker.db = ElvUI_WotLK_TweakerDB
    end
    -- Ensure defaults exist for all modules (even not loaded)
    for mod, def in pairs(EWTweaker.defaultDB) do
        if not EWTweaker.db[mod] then EWTweaker.db[mod] = CopyTable(def) end
    end
end

-- Inject EWTweaker config panel into ElvUI
local function InjectConfig()
    if not ElvUI or not ElvUI[1] or not ElvUI[1].Options then return end
    local E = ElvUI[1]
    local config = {
        type = "group",
        name = "|cff00FF96ElvUI Tweaker|r",
        order = 100,
        childGroups = "tab",
        args = {
            perCharacter = {
                type = "toggle",
                name = "Apply only for this character",
                desc = "Settings will only apply to this character when enabled.",
                order = 1,
                get = function() return ElvUI_WotLK_TweakerDBPC and ElvUI_WotLK_TweakerDBPC.usePerCharacter end,
                set = function(_, val)
                    if not ElvUI_WotLK_TweakerDBPC then ElvUI_WotLK_TweakerDBPC = {} end
                    ElvUI_WotLK_TweakerDBPC.usePerCharacter = val
                    EWTweaker:RefreshDB()
                end,
            },
        }
    }
    local baseOrder = 10
    for modName, modInfo in pairs(EWTweaker.MODULES) do
        -- Ensure LoD modules are loaded
        if modInfo.addon and not IsAddOnLoaded(modInfo.addon) then
            LoadAddOn(modInfo.addon)
        end
        local modObj = EWTweaker.modules[modName]
        config.args[modName] = {
            type = "group",
            name = modInfo.title,
            order = baseOrder,
            args = {},
        }
        if modObj and modObj.GetOptions then
            config.args[modName] = modObj:GetOptions()
            config.args[modName].order = baseOrder
        else
            config.args[modName].args = {
                info = {
                    order = 1,
                    type = "description",
                    name = "|cff888888This module is not loaded or enabled.\nPlease install or enable '" .. modInfo.addon .. "' in your AddOns list.|r",
                }
            }
        end
        baseOrder = baseOrder + 1
    end
    E.Options.args["Tweaker"] = config
end

-- Use LibElvUIPlugin-1.0 to inject config at the right time (when ElvUI_Options loads)
local EP = LibStub("LibElvUIPlugin-1.0")
EP:RegisterPlugin("EWTweaker", InjectConfig)

-- Setup DB and auto-enable modules on login
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    EWTweaker:RefreshDB()
    -- Auto-enable modules that are enabled in the DB
    for modName, modObj in pairs(EWTweaker.modules) do
        local modDB = EWTweaker.db[modName]
        if modObj and modObj.OnEnable and modDB and modDB.enabled then
            modObj:OnEnable(modDB)
        end
    end
end)

EWTweaker.GetCore = function() return EWTweaker end
EWTweaker.GetDB = function() return EWTweaker.db end