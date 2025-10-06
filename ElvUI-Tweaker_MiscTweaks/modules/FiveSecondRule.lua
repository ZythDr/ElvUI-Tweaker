-- Five Second Rule & Mana Tick Spark for WotLK/3.3.5 (Hybrid: FSR + precise tick sync window + FSR end grace window + user update frequency option)

local core = EWTweaker and EWTweaker.GetCore and EWTweaker.GetCore()
if not core then return end
local MOD = core.modules and core.modules.MiscTweaks
if not MOD then return end

local SUB = { name = "Five Second Rule" }
SUB.defaults = {
    enabled = true,
    showManaTick = false,
    color = {1, 1, 1, 1},
    sizeX = 8,
    sizeY = nil,
    offsetY = 0.0,
    updateFrequency = 60, -- Default to 60 FPS
}

local _G = _G
local CreateFrame = CreateFrame
local GetTime = GetTime
local UnitPower = UnitPower
local UnitPowerType = UnitPowerType
local UnitMana = UnitMana
local UnitManaMax = UnitManaMax
local unpack = unpack
local math_max = math.max
local math_min = math.min
local math_abs = math.abs
local UIParent = UIParent
local C_Timer = C_Timer

local spark, tickSpark
local fiveSecondStart, fiveSecondActive, fiveSecondTotalDuration = 0, false, 5
local tickActive, tickStart, lastTickTime, expectedNextTick, waitingForTick = false, 0, 0, 0, false
local lastMana, db_local = nil, nil
local lastBarWidth, lastOverlayAlpha, lastSparkPos, lastTickPos = nil, nil, nil, nil

local fiveSecondDuration, manaTickDuration = 5, 2
local tickSyncWindow = 0.1 -- seconds
local fsrGraceWindow = 0.1 -- seconds

local fsrGraceActive = false
local fsrGraceEndTime = 0

-- Driver frames for throttled updates
local fsrDriver, fsrElapsed = nil, 0
local tickDriver, tickElapsed = nil, 0

local function GetPowerBar()
    local f = _G.ElvUF_Player
    return f and f.Power or nil
end

local function GetPlayerMana()
    if UnitPower then
        local powerType = UnitPowerType and UnitPowerType("player")
        if powerType == nil or powerType == 0 then
            return UnitPower("player", 0) or 0
        end
        return UnitPower("player", 0) or 0
    elseif UnitMana then
        return UnitMana("player") or 0
    end
    return 0
end

local function GetPlayerMaxMana()
    if UnitPower and UnitPowerType and UnitPowerMax then
        local powerType = UnitPowerType("player")
        if powerType == nil or powerType == 0 then
            return UnitPowerMax("player", 0) or 0
        end
        return UnitPowerMax("player", 0) or 0
    elseif UnitManaMax then
        return UnitManaMax("player") or 0
    end
    return 0
end

local function GetTickInterval()
    local freq = (db_local and db_local.updateFrequency) or 60
    if freq == 0 then
        return 0 -- every frame
    else
        return 1 / freq
    end
end

local function CreateOverlayFramesIfNeeded(bar)
    if not bar then return nil end
    if bar.__FiveSR_overlayParent and bar.__FiveSR_overlayParent:IsObjectType("Frame") then
        return bar.__FiveSR_overlayParent
    end
    local parent = bar:GetParent() or UIParent
    local overlayFrame = CreateFrame("Frame", nil, parent)
    overlayFrame:SetAllPoints(bar)
    overlayFrame:SetFrameLevel(math_max(bar:GetFrameLevel(), parent:GetFrameLevel()) + 30)
    overlayFrame:SetFrameStrata("TOOLTIP")
    bar.__FiveSR_overlayParent = overlayFrame
    return overlayFrame
end

local function ApplySettings()
    if not db_local then return end
    local col = db_local.color or {1, 1, 1, 1}
    local r,g,b,a = col[1], col[2], col[3], col[4] or 1
    if spark then
        spark:SetVertexColor(r, g, b)
        spark:SetWidth(db_local.sizeX or SUB.defaults.sizeX)
        spark:SetHeight(db_local.sizeY or (14 * 4))
        spark:SetAlpha(a)
    end
    if tickSpark then
        tickSpark:SetVertexColor(r, g, b)
        tickSpark:SetWidth(db_local.sizeX or SUB.defaults.sizeX)
        tickSpark:SetHeight(db_local.sizeY or (14 * 4))
        tickSpark:SetAlpha(a)
    end
end

local function EnsureSpark()
    local bar = GetPowerBar()
    if not bar or not bar:IsVisible() or bar:GetWidth() == 0 then return end
    if not spark then
        local overlayParent = CreateOverlayFramesIfNeeded(bar)
        if not overlayParent then return end
        spark = overlayParent:CreateTexture(nil, "ARTWORK", nil, 10)
        spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
        if spark.SetBlendMode then spark:SetBlendMode("ADD") end
        spark:SetWidth(db_local and db_local.sizeX or SUB.defaults.sizeX)
        local fallbackY = (bar:GetHeight() or 14) * 2.5
        spark:SetHeight(db_local and db_local.sizeY or fallbackY)
        local col = (db_local and db_local.color) or SUB.defaults.color
        spark:SetVertexColor(col[1], col[2], col[3])
        spark:SetAlpha(col[4] or 1)
        spark:Hide()
        spark.__overlayParent = overlayParent
    else
        ApplySettings()
    end
end

local function EnsureTickSpark()
    local bar = GetPowerBar()
    if not bar or not bar:IsVisible() or bar:GetWidth() == 0 then return end
    if not tickSpark then
        local overlayParent = CreateOverlayFramesIfNeeded(bar)
        if not overlayParent then return end
        tickSpark = overlayParent:CreateTexture(nil, "ARTWORK", nil, 11)
        tickSpark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
        if tickSpark.SetBlendMode then tickSpark:SetBlendMode("ADD") end
        tickSpark:SetWidth(db_local and db_local.sizeX or SUB.defaults.sizeX)
        local fallbackY = (bar:GetHeight() or 14) * 2.5
        tickSpark:SetHeight(db_local and db_local.sizeY or fallbackY)
        local col = (db_local and db_local.color) or SUB.defaults.color
        tickSpark:SetVertexColor(col[1], col[2], col[3])
        tickSpark:SetAlpha(col[4] or 1)
        tickSpark:Hide()
        tickSpark.__overlayParent = overlayParent
    else
        ApplySettings()
    end
end

local function SetOverlayAlphaIfChanged(overlay, alpha)
    if not overlay then return end
    if not lastOverlayAlpha or math_abs(lastOverlayAlpha - alpha) > 0.001 then
        overlay:SetAlpha(alpha)
        lastOverlayAlpha = alpha
    end
end

local function PlaceTextureIfChanged(tex, bar, pos, yOff, widthCache)
    if not tex or not bar then return end
    local changed = false
    if widthCache ~= lastBarWidth then
        changed = true
    else
        local lastPos = (tex == spark) and lastSparkPos or lastTickPos
        if not lastPos or math_abs(lastPos - pos) >= 0.5 then
            changed = true
        end
    end
    if changed then
        tex:ClearAllPoints()
        tex:SetPoint("CENTER", bar, "LEFT", pos, yOff)
        if tex == spark then lastSparkPos = pos else lastTickPos = pos end
    end
end

local function StopFSR()
    if spark then spark:Hide() end
    fiveSecondActive = false
    fiveSecondStart = 0
    fiveSecondTotalDuration = fiveSecondDuration
    lastSparkPos = nil
    waitingForTick = false
    fsrGraceActive = false
    fsrGraceEndTime = 0
    -- Stop driver
    if fsrDriver then fsrDriver:SetScript("OnUpdate", nil); fsrDriver:Hide(); fsrElapsed = 0 end
end

local function StopTick()
    if tickSpark then tickSpark:Hide() end
    tickActive = false
    tickStart = 0
    lastTickPos = nil
    lastTickTime = 0
    expectedNextTick = 0
    -- Stop driver
    if tickDriver then tickDriver:SetScript("OnUpdate", nil); tickDriver:Hide(); tickElapsed = 0 end
end

local function DriverStepFSR()
    local now = GetTime()
    local bar = GetPowerBar()
    if bar and bar:IsVisible() and bar:GetWidth() > 0 and fiveSecondActive and spark then
        local barAlpha = (bar.GetAlpha and bar:GetAlpha()) or 1
        local yOff = (db_local and db_local.offsetY) and db_local.offsetY or 0
        local width = bar:GetWidth()
        local elapsed = now - fiveSecondStart
        if elapsed >= fiveSecondTotalDuration then
            StopFSR()
            -- Start the grace window for UNIT_MANA detection
            fsrGraceActive = true
            fsrGraceEndTime = now + fsrGraceWindow
            waitingForTick = true
        else
            local pos = width * (elapsed / fiveSecondTotalDuration)
            PlaceTextureIfChanged(spark, bar, pos, yOff, width)
            SetOverlayAlphaIfChanged(spark.__overlayParent, barAlpha)
            spark:Show()
        end
        lastBarWidth = width
    else
        if spark then spark:Hide() end
        lastBarWidth = nil
        lastOverlayAlpha = nil
        lastSparkPos = nil
    end
end

local function DriverStepTick()
    local now = GetTime()
    local bar = GetPowerBar()
    if not bar or not bar:IsVisible() or bar:GetWidth() == 0 then
        if tickSpark then tickSpark:Hide() end
        lastBarWidth = nil
        lastOverlayAlpha = nil
        lastTickPos = nil
        return
    end
    if not tickActive then
        if tickSpark then tickSpark:Hide() end
        return
    end

    local barAlpha = (bar.GetAlpha and bar:GetAlpha()) or 1
    local yOff = (db_local and db_local.offsetY) and db_local.offsetY or 0
    local width = bar:GetWidth()
    local elapsed = now - tickStart
    local tickElapsed = elapsed % manaTickDuration
    local pos = width * (tickElapsed / manaTickDuration)
    PlaceTextureIfChanged(tickSpark, bar, pos, yOff, width)
    SetOverlayAlphaIfChanged(tickSpark.__overlayParent, barAlpha)
    tickSpark:Show()
    lastBarWidth = width
end

local function StartFSR()
    StopTick()
    EnsureSpark()
    if spark then spark:Show() end
    fiveSecondStart = GetTime()
    fiveSecondActive = true
    local latencySec = 0
    if GetNetStats then
        local ok, _, _, latencyHome, latencyWorld = pcall(GetNetStats)
        local ms = (ok and latencyHome) or latencyWorld or 0
        if type(ms) == "number" and ms > 0 and ms < 1000 then latencySec = ms / 1000 end
    end
    fiveSecondTotalDuration = fiveSecondDuration + math_min(latencySec, fiveSecondDuration)
    -- Start FSR animation driver (throttled)
    if not fsrDriver then fsrDriver = CreateFrame("Frame") end
    fsrElapsed = 0
    local updateInterval = GetTickInterval()
    fsrDriver:SetScript("OnUpdate", function(self, elapsed)
        if not fiveSecondActive then self:SetScript("OnUpdate", nil); self:Hide(); fsrElapsed = 0; return end
        if updateInterval == 0 then
            DriverStepFSR()
        else
            fsrElapsed = fsrElapsed + elapsed
            if fsrElapsed >= updateInterval then
                fsrElapsed = 0
                DriverStepFSR()
            end
        end
    end)
    fsrDriver:Show()
end

local function IsAtFullMana()
    local current, max = GetPlayerMana(), GetPlayerMaxMana()
    return (max > 0) and (current >= max)
end

local function StartTick()
    EnsureTickSpark()
    tickActive = true
    tickStart = GetTime()
    lastTickTime = tickStart
    expectedNextTick = lastTickTime + manaTickDuration
    -- Start tick animation driver (throttled)
    if not tickDriver then tickDriver = CreateFrame("Frame") end
    tickElapsed = 0
    local updateInterval = GetTickInterval()
    tickDriver:SetScript("OnUpdate", function(self, elapsed)
        if not tickActive then self:SetScript("OnUpdate", nil); self:Hide(); tickElapsed = 0; return end
        if updateInterval == 0 then
            DriverStepTick()
        else
            tickElapsed = tickElapsed + elapsed
            if tickElapsed >= updateInterval then
                tickElapsed = 0
                DriverStepTick()
            end
        end
    end)
    tickDriver:Show()
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("UNIT_MANA")
frame:RegisterEvent("UNIT_POWER_UPDATE")
frame:SetScript("OnEvent", function(self, event, ...)
    local db = db_local
    if not db or not db.enabled then return end

    if event == "PLAYER_ENTERING_WORLD" then
        lastMana = GetPlayerMana()
        StopFSR()
        StopTick()
        waitingForTick = false
        fsrGraceActive = false
        fsrGraceEndTime = 0
        return
    end

    if event == "UNIT_MANA" or event == "UNIT_POWER_UPDATE" then
        local unit = ...
        if unit ~= "player" then return end
        local currentMana = GetPlayerMana()
        local maxMana = GetPlayerMaxMana()
        if not lastMana then lastMana = currentMana return end
        local delta = currentMana - lastMana
        local now = GetTime()

        -- Mana spent: start FSR, stop waiting for tick
        if delta < 0 then
            StartFSR()
            waitingForTick = false
            fsrGraceActive = false
            fsrGraceEndTime = 0
            StopTick()
        -- After FSR ends: 
        elseif db.showManaTick and delta > 0 and currentMana < maxMana then
            if (waitingForTick and not fiveSecondActive) or
               (fsrGraceActive and now <= fsrGraceEndTime)
            then
                StartTick()
                waitingForTick = false
                fsrGraceActive = false
                fsrGraceEndTime = 0
            elseif tickActive then
                -- Only allow resets very close to expected tick
                if math_abs(now - expectedNextTick) <= tickSyncWindow then
                    tickStart = now
                    lastTickTime = now
                    expectedNextTick = now + manaTickDuration
                end
            end
        end

        -- If at full mana, stop tick animation, stop waiting for tick and grace
        if IsAtFullMana() then
            StopTick()
            waitingForTick = false
            fsrGraceActive = false
            fsrGraceEndTime = 0
        end
        lastMana = currentMana
    end
end)

function SUB:OnEnable(db)
    for k, v in pairs(SUB.defaults) do if db[k] == nil then db[k] = v end end
    db_local = db

    local bar = GetPowerBar()
    if bar and (not db_local.sizeY) then
        db_local.sizeY = (bar:GetHeight() or 14) * 2.5
    end
    if not db_local.sizeX then db_local.sizeX = 8 end
    if not db_local.updateFrequency then db_local.updateFrequency = 60 end

    lastMana = GetPlayerMana()
    StopFSR()
    StopTick()
    waitingForTick = false
    fsrGraceActive = false
    fsrGraceEndTime = 0
    ApplySettings()
end

function SUB:OnDisable(db)
    db_local = nil
    StopFSR()
    StopTick()
    waitingForTick = false
    fsrGraceActive = false
    fsrGraceEndTime = 0
end

function SUB:GetOptions(db)
    for k, v in pairs(SUB.defaults) do if db[k] == nil then db[k] = v end end
    db_local = db

    return {
        type = "group", name = SUB.name,
        args = {
            header = {
                order = 0,
                type = "header",
                name = "Five Second Rule",
            },
            description = {
                order = 1,
                type = "description",
                name = "This module displays a \"Five Second Rule\" on your Mana/Power bar via a spark animation.  This allows for much easier tracking of mana regeneration ticks.\n",
            },
            enabled = {
                order = 2, 
                type = "toggle",
                name = function() 
                    return db.enabled and "|cff00ff00Enabled|r" or "|cffff0000Disabled|r" 
                end,
                get = function() return db.enabled end,
                set = function(_, v) 
                    db.enabled = v 
                    if v then 
                        SUB:OnEnable(db) 
                    else 
                        SUB:OnDisable() 
                    end 
                end,
            },
                spacer1 = {
                order = 3,
                type = "description",
                name = " ",
                width = "full",
            },
            showManaTick = {
                order = 4, type = "toggle", name = "Show Mana Tick Spark",
                desc = "Show an additional spark when mana ticks occur.",
                get = function() return db.showManaTick end,
                set = function(_, v)
                    db.showManaTick = v
                    if db.enabled then
                        if v then
                            if not fiveSecondActive and not IsAtFullMana() then
                                waitingForTick = true
                                fsrGraceActive = false
                                fsrGraceEndTime = 0
                            end
                        else
                            StopTick()
                        end
                    end
                end,
                disabled = function() return not db.enabled end,
            },
            color = {
                order = 5, type = "color", name = "Spark Color",
                hasAlpha = true,
                get = function() return unpack(db.color) end,
                set = function(_, r, g, b, a)
                    db.color = {r, g, b, a}
                    ApplySettings()
                end,
                disabled = function() return not db.enabled end,
            },
            spacer = {
                order = 6, type = "description", name = "", width = "full",
            },
            sizeX = {
                order = 10, type = "range", name = "Spark Width",
                min = 1, max = 256, step = 1,
                get = function() return db.sizeX end,
                set = function(_, v)
                    db.sizeX = v
                    ApplySettings()
                end,
                disabled = function() return not db.enabled end,
            },
            sizeY = {
                order = 11, type = "range", name = "Spark Height",
                min = 4, max = 512, step = 1,
                get = function() return db.sizeY end,
                set = function(_, v) db.sizeY = v; ApplySettings() end,
                disabled = function() return not db.enabled end,
            },
            offsetY = {
                order = 12, type = "range", name = "Spark Y-Offset",
                desc = "Move the spark up (positive) or down (negative) in pixels. Step is 0.1 for fine control.",
                min = -128, max = 128, step = 0.1,
                get = function() return db.offsetY end,
                set = function(_, v) db.offsetY = v; ApplySettings() end,
                isPercent = false,
                disabled = function() return not db.enabled end,
            },
            updateFrequency = {
                order = 20,
                type = "select",
                name = "Update Frequency",
                desc = "Spark animation FPS (reduce to increase performance).",
                values = {
                    [30] = "30 FPS",
                    [60] = "60 FPS",
                    [120] = "120 FPS",
                    [0] = "Every Frame",
                },
                get = function() return db.updateFrequency or 60 end,
                set = function(_, v)
                    db.updateFrequency = v
                end,
                disabled = function() return not db.enabled end,
            },
        },
    }
end

MOD:RegisterSubmodule("FiveSecondRule", SUB)