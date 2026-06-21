local core = EWTweaker and EWTweaker.GetCore and EWTweaker.GetCore()
if not core then return end

local MOD = (core.modules and core.modules.OptionsTweaks) or _G.EWTweaker_OptionsTweaks
if not MOD then return end

local L = LibStub("AceLocale-3.0-ElvUI"):GetLocale("ElvUI", true)
if not L then L = setmetatable({}, { __index = function(_, k) return k end }) end

local E = ElvUI and ElvUI[1]

local SUB = { name = L["Tabs Fix"] }

local function EnsureDefaults(db)
    if db.enabled == nil then db.enabled = false end
end

local saved = {}
local widths = {}
local rowwidths = {}
local rowends = {}
local InstallPatch

local function GetTabFontString(tab)
    return (tab.GetFontString and tab:GetFontString()) or tab.Text or tab.text or _G[tab:GetName() .. "Text"]
end

local function GetTabTextWidth(tab)
    local fontString = GetTabFontString(tab)
    if fontString and fontString.GetStringWidth then
        return fontString:GetStringWidth()
    end

    if tab.GetTextWidth then
        return tab:GetTextWidth()
    end

    return 0
end

local function ResizeTab(tab, padding, absoluteSize, minWidth, maxWidth, absoluteTextSize)
    local tabName = tab:GetName()
    local middle = tab.Middle or tab.middleTexture or _G[tabName .. "Middle"]
    local middleDisabled = tab.MiddleDisabled or _G[tabName .. "MiddleDisabled"]
    local left = tab.Left or tab.leftTexture or _G[tabName .. "Left"]
    local highlight = tab.HighlightTexture or _G[tabName .. "HighlightTexture"]
    local text = GetTabFontString(tab)

    if not left or not text then return end

    local sideWidths = 2 * left:GetWidth()
    local textWidth

    if absoluteTextSize then
        textWidth = absoluteTextSize
    else
        text:SetWidth(0)
        textWidth = text:GetWidth()
    end

    local width
    local tabWidth

    if absoluteSize then
        if absoluteSize < sideWidths then
            width = 1
            tabWidth = sideWidths
        else
            width = absoluteSize - sideWidths
            tabWidth = absoluteSize
        end
        text:SetWidth(width)
    else
        width = textWidth + (padding or 24)

        if maxWidth and width > maxWidth then
            width = maxWidth + (padding or 24)
            text:SetWidth(width)
        else
            text:SetWidth(0)
        end

        if minWidth and width < minWidth then
            width = minWidth
        end

        tabWidth = width + sideWidths
    end

    if middle then middle:SetWidth(width) end
    if middleDisabled then middleDisabled:SetWidth(width) end
    tab:SetWidth(tabWidth)
    if highlight then highlight:SetWidth(tabWidth) end
end

local function SetTabText(tab, text)
    if tab._SetText then
        tab:_SetText(text)
    else
        tab:SetText(text)
    end
end

local function GetWidgetUserData(widget)
    if widget and widget.GetUserDataTable then
        return widget:GetUserDataTable()
    end

    return widget and widget.userdata
end

local function IsElvUIOptionsTabGroup(widget)
    if not widget or widget.type ~= "TabGroup" then return false end

    local user = GetWidgetUserData(widget)
    return user and user.appName == "ElvUI"
end

local function PatchBuildTabs(self)
    local tablist = self and self.tablist
    local tabs = self and self.tabs
    local frame = self and self.frame

    if not tablist or not tabs or not frame then return end

    local title = self.titletext and self.titletext.GetText and self.titletext:GetText()
    local hastitle = title and title ~= ""
    local width = frame.width or (frame.GetWidth and frame:GetWidth()) or 0

    if width <= 0 then return end

    wipe(widths)
    wipe(rowwidths)
    wipe(rowends)

    for i, v in ipairs(tablist) do
        local tab = tabs[i]
        if not tab and self.CreateTab then
            tab = self:CreateTab(i)
            tabs[i] = tab
        end

        if tab then
            tab:Show()
            SetTabText(tab, v.text)
            ResizeTab(tab, 0, nil, nil, width, GetTabTextWidth(tab))
            tab:SetDisabled(v.disabled)
            tab.value = v.value

            widths[i] = (tab:GetWidth() or 0) - 6
        end
    end

    for i = #tablist + 1, #tabs do
        tabs[i]:Hide()
    end

    local numtabs = #tablist
    if numtabs == 0 then return end

    local numrows = 1
    local usedwidth = 0

    for i = 1, numtabs do
        if usedwidth ~= 0 and (width - usedwidth - widths[i]) < 0 then
            rowwidths[numrows] = usedwidth + 10
            rowends[numrows] = i - 1
            numrows = numrows + 1
            usedwidth = 0
        end
        usedwidth = usedwidth + widths[i]
    end

    rowwidths[numrows] = usedwidth + 10
    rowends[numrows] = numtabs

    if numrows > 1 and rowends[numrows - 1] == numtabs - 1 then
        if (numrows == 2 and rowends[numrows - 1] > 2) or (rowends[numrows] - rowends[numrows - 1] > 2) then
            if (rowwidths[numrows] + widths[numtabs - 1]) <= width then
                rowends[numrows - 1] = rowends[numrows - 1] - 1
                rowwidths[numrows] = rowwidths[numrows] + widths[numtabs - 1]
                rowwidths[numrows - 1] = rowwidths[numrows - 1] - widths[numtabs - 1]
            end
        end
    end

    local starttab = 1
    for row, endtab in ipairs(rowends) do
        local first = true

        for tabno = starttab, endtab do
            local tab = tabs[tabno]
            tab:ClearAllPoints()

            if first then
                tab:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -(hastitle and 14 or 7) - (row - 1) * 20)
                first = false
            else
                tab:SetPoint("LEFT", tabs[tabno - 1], "RIGHT", -10, 0)
            end
        end

        local padding = 0
        if not (numrows == 1 and rowwidths[1] < width * 0.75 - 18) then
            padding = (width - rowwidths[row]) / (endtab - starttab + 1)
        end

        for i = starttab, endtab do
            ResizeTab(tabs[i], padding + 4, nil, nil, width, GetTabTextWidth(tabs[i]))
        end

        starttab = endtab + 1
    end

    self.borderoffset = (hastitle and 17 or 10) + (numrows * 20)
    if self.border then
        self.border:SetPoint("TOPLEFT", 1, -self.borderoffset)
    end
end

local function PatchWidgetBuildTabs(widget)
    if not widget or widget.type ~= "TabGroup" or widget._ewt_tabsPatched then return end
    local orig = widget.BuildTabs
    widget._ewt_originalBuildTabs = orig
    widget.BuildTabs = function(self)
        if IsElvUIOptionsTabGroup(self) then
            return PatchBuildTabs(self)
        elseif orig then
            return orig(self)
        end
    end
    widget._ewt_tabsPatched = true

    if widget.tablist and IsElvUIOptionsTabGroup(widget) then
        widget:BuildTabs()
    end
end

local function PatchFrameTree(frame, seen)
    if not frame or seen[frame] then return end
    seen[frame] = true

    local obj = frame.obj
    if obj and type(obj) == "table" and IsElvUIOptionsTabGroup(obj) then
        PatchWidgetBuildTabs(obj)
    end

    if frame.GetNumChildren and frame.GetChildren then
        local numChildren = frame:GetNumChildren()
        for i = 1, numChildren do
            local child = select(i, frame:GetChildren())
            PatchFrameTree(child, seen)
        end
    end
end

local function PatchExistingTabGroups()
    for k, v in pairs(_G) do
        if type(k) == "string" and k:match("^AceGUITabGroup%d+Tab%d+$") and type(v) == "table" then
            local obj = v.obj
            if obj and type(obj) == "table" and IsElvUIOptionsTabGroup(obj) then
                PatchWidgetBuildTabs(obj)
            end
        end
    end

    if UIParent then
        PatchFrameTree(UIParent, {})
    end
end

local function RestoreWidget(widget)
    if widget and widget._ewt_tabsPatched and widget._ewt_originalBuildTabs then
        widget.BuildTabs = widget._ewt_originalBuildTabs
        widget._ewt_originalBuildTabs = nil
        widget._ewt_tabsPatched = nil
    end
end

local function RestoreFrameTree(frame, seen)
    if not frame or seen[frame] then return end
    seen[frame] = true

    RestoreWidget(frame.obj)

    if frame.GetNumChildren and frame.GetChildren then
        local numChildren = frame:GetNumChildren()
        for i = 1, numChildren do
            local child = select(i, frame:GetChildren())
            RestoreFrameTree(child, seen)
        end
    end
end

local function SchedulePatchScan()
    if not SUB.enabled then return end

    SUB.patchScanFrame = SUB.patchScanFrame or CreateFrame("Frame")
    if SUB.patchScanPending then return end

    SUB.patchScanPending = true
    SUB.patchScanFrame:SetScript("OnUpdate", function(frame)
        frame:SetScript("OnUpdate", nil)
        SUB.patchScanPending = nil
        InstallPatch()
    end)
end

local function HookAceConfigDialog(name)
    local ACD = LibStub and LibStub(name, true)
    if not ACD or saved.hookedAceConfigDialogs[name] then return end

    if ACD.SelectGroup then
        hooksecurefunc(ACD, "SelectGroup", SchedulePatchScan)
    end

    if ACD.Open then
        hooksecurefunc(ACD, "Open", SchedulePatchScan)
    end

    saved.hookedAceConfigDialogs[name] = true
end

function InstallPatch()
    if not SUB.enabled then return end

    local AceGUI = LibStub and LibStub("AceGUI-3.0", true)
    if not AceGUI then return end

    if AceGUI.RegisterAsContainer ~= saved.registerAsContainerWrapper then
        saved.originalRegisterAsContainer = AceGUI.RegisterAsContainer
        saved.registerAsContainerWrapper = function(self, widget)
            widget = saved.originalRegisterAsContainer(self, widget)
            if widget and widget.type == "TabGroup" then
                PatchWidgetBuildTabs(widget)
            end
            SchedulePatchScan()
            return widget
        end
        AceGUI.RegisterAsContainer = saved.registerAsContainerWrapper
    end

    saved.hookedAceConfigDialogs = saved.hookedAceConfigDialogs or {}
    HookAceConfigDialog("AceConfigDialog-3.0")
    HookAceConfigDialog("AceConfigDialog-3.0-ElvUI")

    PatchExistingTabGroups()
end

local function IsOptionsAddonLoaded()
    return IsAddOnLoaded and (IsAddOnLoaded("ElvUI_OptionsUI") or IsAddOnLoaded("ElvUI_Options"))
end

local function StartControlWatcher()
    if SUB.controlWatcherActive then return end

    SUB.controlWatcher = SUB.controlWatcher or CreateFrame("Frame")
    SUB.controlWatcher:SetScript("OnEvent", function(_, _, addon)
        if addon == "ElvUI_OptionsUI" or addon == "ElvUI_Options" then
            InstallPatch()
        end
    end)
    SUB.controlWatcher:RegisterEvent("ADDON_LOADED")
    SUB.controlWatcherActive = true

    if E and not SUB.toggleHooked then
        hooksecurefunc(E, "ToggleOptionsUI", InstallPatch)
        SUB.toggleHooked = true
    end
end

local function StopControlWatcher()
    if SUB.controlWatcher then
        SUB.controlWatcher:UnregisterEvent("ADDON_LOADED")
    end
    SUB.controlWatcherActive = nil
end

local function RemovePatch()
    local AceGUI = LibStub and LibStub("AceGUI-3.0", true)
    if not AceGUI then return end
    if saved.originalRegisterAsContainer then
        if AceGUI.RegisterAsContainer == saved.registerAsContainerWrapper then
            AceGUI.RegisterAsContainer = saved.originalRegisterAsContainer
        end
        saved.originalRegisterAsContainer = nil
        saved.registerAsContainerWrapper = nil
    end

    for k, v in pairs(_G) do
        if type(k) == "string" and k:match("^AceGUITabGroup%d+Tab%d+$") and type(v) == "table" then
            RestoreWidget(v.obj)
        end
    end

    if UIParent then
        RestoreFrameTree(UIParent, {})
    end
end

function SUB:OnEnable(db)
    SUB.db = db
    SUB.enabled = true
    EnsureDefaults(db)
    StartControlWatcher()

    -- If options UI is already loaded, apply immediately
    if IsOptionsAddonLoaded() then
        InstallPatch()
    else
        -- also apply if AceGUI and ElvUI options are already present
        local AceGUI = LibStub and LibStub("AceGUI-3.0", true)
        if AceGUI and ElvUI and ElvUI[1] and ElvUI[1].Options then
            InstallPatch()
        end
    end
end

function SUB:OnDisable(db)
    SUB.db = db or SUB.db
    SUB.enabled = false
    RemovePatch()
    StopControlWatcher()
end

function SUB:GetOptions(db)
    EnsureDefaults(db)
    return {
        type = "group",
        name = SUB.name,
        args = {
            enabled = {
                order = 1,
                type = "toggle",
                name = function()
                    return db.enabled and "|cff00ff00Enabled|r" or "|cffff0000Disabled|r"
                end,
                get = function() return db.enabled end,
                set = function(_, value)
                    db.enabled = value
                    if value then
                        SUB:OnEnable(db)
                    else
                        SUB:OnDisable(db)
                    end
                end,
            },
            description = {
                order = 2,
                type = "description",
                name = L["Attempt to force ElvUI options TabGroup widgets to layout horizontally instead of stacking into vertical lists on some WotLK forks."],
            },
        },
    }
end

MOD:RegisterSubmodule("TabsFix", SUB)
