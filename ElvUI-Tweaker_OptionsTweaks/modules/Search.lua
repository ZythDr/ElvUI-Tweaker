local core = EWTweaker and EWTweaker.GetCore and EWTweaker.GetCore()
if not core then return end

local MOD = core.modules and core.modules.OptionsTweaks
if not MOD then return end

local E = ElvUI and ElvUI[1]
local L = LibStub("AceLocale-3.0-ElvUI"):GetLocale("ElvUI", true)
if not L then L = setmetatable({}, { __index = function(_, k) return k end }) end

local concat = table.concat
local format = string.format
local gsub = string.gsub
local hooksecurefunc = hooksecurefunc
local lower = string.lower
local pairs = pairs
local sort = table.sort
local tostring = tostring
local type = type
local unpack = unpack

local RESULTS_GROUP_KEY = "EWTweakerOptionsSearch"
local SEARCH_GROUP_KEY = "Search"
local SEARCH_CONTROL_KEY = "EWTweakerOptionsSearchInput"
local SEARCH_WIDGET = "EWTweakerLiveSearch"
local SUB = { name = L["Options Search"] }

SUB.state = {
    matched = 0,
    results = {
        descriptions = {},
        keys = {},
        names = {},
    },
    scanned = 0,
    totals = {
        descriptions = 0,
        keys = 0,
        names = 0,
    },
}
SUB.query = ""

local RESULT_CATEGORIES = {
    names = L["Setting Names"],
    descriptions = L["Setting Descriptions"],
    keys = L["Setting Keys"],
}

local function CopyArray(source)
    local copy = {}
    for i = 1, #source do
        copy[i] = source[i]
    end
    return copy
end

local function CleanText(value)
    if value == nil then return nil end
    if type(value) ~= "string" then
        value = tostring(value)
    end

    value = gsub(value, "|c%x%x%x%x%x%x%x%x", "")
    value = gsub(value, "|r", "")
    value = gsub(value, "\n", " ")
    return value
end

local function ToSearchText(value)
    local cleaned = CleanText(value)
    if not cleaned or cleaned == "" then return nil end
    return lower(cleaned)
end

local function RefreshConfigUI()
    if E and E.RefreshGUI then
        E:RefreshGUI()
    elseif E and E.Libs and E.Libs.AceConfigRegistry then
        E.Libs.AceConfigRegistry:NotifyChange("ElvUI")
    end
end

local function ClearSearchFocus()
    if SUB.searchWidget then
        SUB.searchWidget:ClearFocus()
    end
end

local function IsResultsGroupSelected()
    local ACD = E and E.Libs and E.Libs.AceConfigDialog
    local status = ACD and ACD.Status and ACD.Status.ElvUI
    return status and status.status and status.status.groups and status.status.groups.selected == RESULTS_GROUP_KEY
end

local function SelectResultsGroup()
    local ACD = E and E.Libs and E.Libs.AceConfigDialog
    if ACD and ACD.OpenFrames and ACD.OpenFrames.ElvUI and not IsResultsGroupSelected() then
        ACD:SelectGroup("ElvUI", RESULTS_GROUP_KEY)
    end
end

local function ScoreMatch(query, haystack, weight)
    if not haystack or haystack == "" then return nil end

    local startPos = haystack:find(query, 1, true)
    if not startPos then return nil end

    if haystack == query then
        return weight + 50
    elseif startPos == 1 then
        return weight + 30
    end

    return weight + 10
end

local function ResolveOptionText(value)
    if type(value) == "string" or type(value) == "number" then
        return CleanText(value)
    end

    return nil
end

local function BuildDisplayPath(label, pathNames)
    local pathCount = #pathNames
    local lastPathName = pathNames[pathCount]
    if lastPathName == label then
        pathCount = pathCount - 1
    end

    if pathCount == 0 then
        return label
    elseif pathCount == 1 then
        return pathNames[1] .. " > " .. label
    end

    return label .. "    |cff888888" .. pathNames[1] .. " > " .. pathNames[pathCount] .. "|r"
end

local function EnsureDefaults(db)
    if db.enabled == nil then db.enabled = true end
    db.query = nil -- Search text is session-only; discard queries saved by earlier builds.
    if db.includeDescriptions == nil then db.includeDescriptions = true end
    if db.includeKeys == nil then db.includeKeys = true end
    if db.gridResults == nil then db.gridResults = true end
    if db.maxResults == nil then db.maxResults = 40 end
end

local function SelectResult(path)
    local ACD = E and E.Libs and E.Libs.AceConfigDialog
    if ACD and path and #path > 0 then
        ClearSearchFocus()
        ACD:SelectGroup("ElvUI", unpack(path))
    end
end

local function BuildEmptyCategoryArgs()
    local query = ToSearchText(SUB.query)
    if not query then
        return {
            empty = {
                order = 1,
                type = "description",
                name = L["No search query entered."],
            },
        }
    end
end

local function AddCategorySummary(args, category, results)
    args.summary = {
        order = 1,
        type = "description",
        name = format(
            "%s: %d    %s: %d    %s: %d",
            L["Scanned"], SUB.state.scanned or 0,
            L["Matched"], SUB.state.totals[category] or 0,
            L["Displayed"], #results
        ),
    }
    args.spacer = {
        order = 2,
        type = "description",
        name = " ",
    }
end

local function BuildListCategoryArgs(category)
    local emptyArgs = BuildEmptyCategoryArgs()
    if emptyArgs then return emptyArgs end

    local results = SUB.state.results[category]
    local args = {}
    if #results == 0 then
        args.empty = {
            order = 1,
            type = "description",
            name = L["No matches found."],
        }
        return args
    end

    AddCategorySummary(args, category, results)

    for i, result in ipairs(results) do
        local fullPath = result.fullPath or result.label
        local path = result.path
        local displayPath = result.displayPath or fullPath

        args["result" .. i] = {
            order = i + 2,
            type = "execute",
            width = "full",
            name = format("%d. %s", i, displayPath),
            desc = format("%s: %s", L["Path"], fullPath),
            func = function()
                SelectResult(path)
            end,
        }
    end

    return args
end

local function GetGridGroup(result)
    local names = result.pathNames or {}
    local parent = names[1] or L["General"]
    local section

    if #names < 2 then
        section = L["Direct Results"]
    else
        section = names[2]
        if #names > 2 then
            section = section .. " > " .. names[#names]
        end
    end

    return parent, section
end

local function BuildGridCategoryArgs(category)
    local emptyArgs = BuildEmptyCategoryArgs()
    if emptyArgs then return emptyArgs end

    local results = SUB.state.results[category]
    local args = {}
    if #results == 0 then
        args.empty = {
            order = 1,
            type = "description",
            name = L["No matches found."],
        }
        return args
    end

    AddCategorySummary(args, category, results)

    local parents = {}
    local parentCount = 0
    for i, result in ipairs(results) do
        local parentName, sectionName = GetGridGroup(result)
        local fullPath = result.fullPath or result.label
        local label = result.label
        local path = result.path
        local parent = parents[parentName]
        if not parent then
            parentCount = parentCount + 1
            parent = {
                order = parentCount + 2,
                sections = {},
                sectionCount = 0,
            }
            parents[parentName] = parent
            args["parent" .. parentCount] = {
                order = parent.order,
                type = "group",
                name = "|cffffffff" .. parentName .. "|r",
                guiInline = true,
                args = {},
            }
            parent.option = args["parent" .. parentCount]
        end

        local section = parent.sections[sectionName]
        if not section then
            parent.sectionCount = parent.sectionCount + 1
            section = {
                count = 0,
                option = {
                    order = parent.sectionCount,
                    type = "group",
                    name = sectionName,
                    guiInline = true,
                    args = {},
                },
            }
            parent.sections[sectionName] = section
            parent.option.args["section" .. parent.sectionCount] = section.option
        end

        section.count = section.count + 1
        section.option.args["result" .. i] = {
            order = section.count,
            type = "execute",
            width = 1,
            name = label,
            desc = format("%s: %s", L["Path"], fullPath),
            func = function()
                SelectResult(path)
            end,
        }
    end

    return args
end

local function BuildCategoryArgs(category)
    if SUB.db and SUB.db.gridResults then
        return BuildGridCategoryArgs(category)
    end

    return BuildListCategoryArgs(category)
end

local function BuildResultsArgs()
    local args = {}

    for key, label in pairs(RESULT_CATEGORIES) do
        local total = SUB.state.totals[key] or 0
        args[key] = {
            order = key == "names" and 1 or key == "descriptions" and 2 or 3,
            type = "group",
            name = format("%s (%d)", label, total),
            args = BuildCategoryArgs(key),
        }
    end

    return args
end

local function UpdateResultsGroup()
    if not E or not E.Options or not E.Options.args then return end

    SUB.resultsGroup = SUB.resultsGroup or {
        type = "group",
        name = "|cff00FF96" .. L["Options Search"] .. "|r",
        order = -0.5,
        childGroups = "tab",
        args = {},
    }
    SUB.resultsGroup.args = BuildResultsArgs()
    E.Options.args[RESULTS_GROUP_KEY] = SUB.resultsGroup
end

local function RunSearch()
    local db = SUB.db
    if not db then return end

    local includeDescriptions = db.includeDescriptions ~= false
    local includeKeys = db.includeKeys ~= false
    local maxResults = db.maxResults or 40
    local query = ToSearchText(SUB.query)

    SUB.state.matched = 0
    SUB.state.results = {
        descriptions = {},
        keys = {},
        names = {},
    }
    SUB.state.scanned = 0
    SUB.state.totals = {
        descriptions = 0,
        keys = 0,
        names = 0,
    }

    if not query or query == "" or not E or not E.Options or not E.Options.args then
        UpdateResultsGroup()
        return
    end

    local matches = {
        descriptions = {},
        keys = {},
        names = {},
    }
    local seen = {}
    local visited = {}

    local function addResult(category, score, label, pathKeys, pathNames, breadcrumb, sourceKey)
        local pathKey = concat(pathKeys, "\001")
        local dedupeKey = category .. "\001" .. pathKey .. "\001" .. tostring(sourceKey)
        if seen[dedupeKey] then return end

        seen[dedupeKey] = true
        SUB.state.matched = SUB.state.matched + 1
        SUB.state.totals[category] = SUB.state.totals[category] + 1
        matches[category][#matches[category] + 1] = {
            breadcrumb = breadcrumb ~= "" and breadcrumb or "ElvUI",
            depth = #pathKeys,
            displayPath = BuildDisplayPath(label, pathNames),
            fullPath = breadcrumb ~= "" and breadcrumb or label,
            label = label,
            path = CopyArray(pathKeys),
            pathNames = CopyArray(pathNames),
            score = score,
        }
    end

    local function walk(args, groupPath, groupNames, depth)
        if type(args) ~= "table" or visited[args] then return end
        visited[args] = true

        for key, option in pairs(args) do
            local skipOwnGroups = key == RESULTS_GROUP_KEY
                or key == SEARCH_CONTROL_KEY
                or (depth == 2 and groupPath[1] == "Tweaker" and groupPath[2] == "OptionsTweaks" and key == SEARCH_GROUP_KEY)
            local skipOptionType = type(option) == "table"
                and (option.type == "description" or option.type == "header")
            if not skipOwnGroups and not skipOptionType and type(option) == "table" then
                SUB.state.scanned = SUB.state.scanned + 1

                local optionLabel = ResolveOptionText(option.name) or tostring(key)
                local labelScore = ScoreMatch(query, ToSearchText(optionLabel), 100)
                local descScore = includeDescriptions and ScoreMatch(query, ToSearchText(ResolveOptionText(option.desc)), 70)
                local keyScore = includeKeys and ScoreMatch(query, ToSearchText(key), 55)
                local childPath = groupPath
                local childNames = groupNames
                local resultPath = groupPath
                local breadcrumb = concat(groupNames, " > ")

                if option.type == "group" then
                    childPath = CopyArray(groupPath)
                    childPath[#childPath + 1] = key
                    childNames = CopyArray(groupNames)
                    childNames[#childNames + 1] = optionLabel
                    resultPath = childPath
                    breadcrumb = concat(childNames, " > ")
                elseif breadcrumb ~= "" then
                    breadcrumb = breadcrumb .. " > " .. optionLabel
                else
                    breadcrumb = optionLabel
                end

                if labelScore then
                    local score = labelScore
                    if option.type == "group" then
                        score = score + 8
                    end
                    addResult("names", score - depth, optionLabel, resultPath, childNames, breadcrumb, key)
                end

                if descScore then
                    addResult("descriptions", descScore - depth, optionLabel, resultPath, childNames, breadcrumb, key)
                end

                if keyScore then
                    addResult("keys", keyScore - depth, optionLabel, resultPath, childNames, breadcrumb, key)
                end

                if type(option.args) == "table" then
                    walk(option.args, childPath, childNames, depth + 1)
                end
            end
        end
    end

    walk(E.Options.args, {}, {}, 0)
    for category, categoryMatches in pairs(matches) do
        sort(categoryMatches, function(a, b)
            if a.score == b.score then
                if a.depth ~= b.depth then
                    return a.depth < b.depth
                end
                if #a.fullPath ~= #b.fullPath then
                    return #a.fullPath < #b.fullPath
                end
                return a.label < b.label
            end
            return a.score > b.score
        end)

        if maxResults < 1 then maxResults = 1 end
        for i = 1, #categoryMatches do
            if i > maxResults then break end
            SUB.state.results[category][#SUB.state.results[category] + 1] = categoryMatches[i]
        end
    end

    UpdateResultsGroup()
end

local function UpdateQuery(value)
    if not SUB.db then return end

    SUB.query = value or ""
    RunSearch()
    RefreshConfigUI()

    if ToSearchText(SUB.query) then
        SelectResultsGroup()
    end
end

local function UpdateSearchPlaceholder(widget)
    if not widget or not widget.placeholder then return end

    if widget.editbox:GetText() == "" and not widget.editbox:HasFocus() then
        widget.placeholder:Show()
    else
        widget.placeholder:Hide()
    end
end

local function ShowSearchTooltip(widget)
    if not widget or not widget.editbox then return end

    GameTooltip:SetOwner(widget.editbox, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()
    GameTooltip:SetPoint("BOTTOMLEFT", widget.editbox, "TOPLEFT", 0, 0)
    GameTooltip:SetText(L["Options Search by |cff00FF96ElvUI Tweaker|r"], 1, .82, 0, true)
    GameTooltip:AddLine(L["Search all ElvUI options from one place."], 1, 1, 1, true)
    GameTooltip:AddLine(L["Press Enter to search."], 1, 1, 1, true)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["Example Searches"], 1, .82, 0, true)
    GameTooltip:AddLine("- " .. L["Search Example Bags"], 1, 1, 1, true)
    GameTooltip:AddLine("- " .. L["Search Example Castbar"], 1, 1, 1, true)
    GameTooltip:AddLine("- " .. L["Search Example Class Color"], 1, 1, 1, true)
    GameTooltip:Show()
end

local function RegisterSearchWidget()
    local AceGUI = E and E.Libs and E.Libs.AceGUI
    local baseConstructor = AceGUI and AceGUI.WidgetRegistry and AceGUI.WidgetRegistry.EditBox
    if not baseConstructor or AceGUI:GetWidgetVersion(SEARCH_WIDGET) then return end

    local function Constructor()
        local widget = baseConstructor()
        local oldAcquire = widget.OnAcquire
        local oldRelease = widget.OnRelease
        local oldSetText = widget.SetText

        widget.type = SEARCH_WIDGET
        widget.placeholder = widget.editbox:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
        widget.placeholder:SetPoint("LEFT", widget.editbox, "LEFT", 4, 0)
        widget.placeholder:SetTextColor(0.55, 0.55, 0.55)
        widget.placeholder:SetText(L["Search..."])

        widget.editbox:HookScript("OnEditFocusGained", function(frame)
            UpdateSearchPlaceholder(frame.obj)
        end)
        widget.editbox:HookScript("OnEditFocusLost", function(frame)
            UpdateSearchPlaceholder(frame.obj)
        end)
        widget.editbox:HookScript("OnEnter", function(frame)
            ShowSearchTooltip(frame.obj)
        end)
        widget.editbox:HookScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        widget.OnAcquire = function(self)
            oldAcquire(self)
            self:SetLabel()
            self.frame:SetHeight(24)
            self.editbox:SetHeight(24)
            self.editbox:ClearAllPoints()
            self.editbox:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 7, 0)
            self.editbox:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", 0, 0)
            self:DisableButton(true)
            self:SetCallback("OnTextChanged", function()
                UpdateSearchPlaceholder(self)
            end)
            SUB.searchWidget = self
            UpdateSearchPlaceholder(self)
        end

        widget.OnRelease = function(self)
            if SUB.searchWidget == self then
                SUB.searchWidget = nil
            end
            self:SetCallback("OnTextChanged")
            oldRelease(self)
        end

        widget.SetText = function(self, text)
            oldSetText(self, text)
            UpdateSearchPlaceholder(self)
        end

        return widget
    end

    AceGUI:RegisterWidgetType(SEARCH_WIDGET, Constructor, 1)
end

local function CompactShortcutRow()
    if not E or not E.Options or not E.Options.args then return false end
    if SUB.shortcutRow then return true end

    local args = E.Options.args
    local originals = {}
    local modified = 0
    local function compact(key, name, width)
        local option = args[key]
        if not option then return false end

        originals[key] = {
            customWidth = option.customWidth,
            name = option.name,
        }
        option.name = name
        option.customWidth = width
        modified = modified + 1
        return true
    end

    compact("RepositionWindow", L["Reset Window"], 122)
    compact("ToggleTutorial", L["Tutorials"], 90)
    compact("LoginMessage", L["Login Message"], 116)

    if modified > 0 then
        SUB.shortcutRow = originals
        return true
    end

    return false
end

local function RestoreShortcutRow()
    if not E or not E.Options or not E.Options.args or not SUB.shortcutRow then return end

    for key, original in pairs(SUB.shortcutRow) do
        local option = E.Options.args[key]
        if option then
            option.name = original.name
            option.customWidth = original.customWidth
        end
    end

    SUB.shortcutRow = nil
end

local function AddSearchControl()
    if not E or not E.Options or not E.Options.args then return end

    RegisterSearchWidget()
    CompactShortcutRow()
    E.Options.args[SEARCH_CONTROL_KEY] = {
        order = 1.5,
        type = "input",
        name = "",
        desc = function()
            return format(
                "%s\n\n|cffffd200%s|r\n- %s\n- %s\n- %s",
                L["Search all ElvUI options from one place."],
                L["Example Searches"],
                L["Search Example Bags"],
                L["Search Example Castbar"],
                L["Search Example Unitframe"]
            )
        end,
        dialogControl = SEARCH_WIDGET,
        customWidth = 175,
        get = function()
            return SUB.query or ""
        end,
        set = function(_, value)
            UpdateQuery(value)
        end,
    }
end

local function EnsureSearchControl()
    if not SUB.db or not SUB.db.enabled then return end
    if not E or not E.Options or not E.Options.args then return end

    local hadControl = E.Options.args[SEARCH_CONTROL_KEY] and SUB.shortcutRow
    AddSearchControl()

    if not hadControl then
        local ACD = E and E.Libs and E.Libs.AceConfigDialog
        if ACD and ACD.OpenFrames and ACD.OpenFrames.ElvUI then
            RefreshConfigUI()
        end
    end
end

local function StartControlWatcher()
    if SUB.controlWatcherActive then return end

    SUB.controlWatcher = SUB.controlWatcher or CreateFrame("Frame")
    SUB.controlWatcher:SetScript("OnEvent", function(_, _, addon)
        if addon == "ElvUI_OptionsUI" then
            EnsureSearchControl()
        end
    end)
    SUB.controlWatcher:RegisterEvent("ADDON_LOADED")
    SUB.controlWatcherActive = true

    if E and not SUB.toggleHooked then
        hooksecurefunc(E, "ToggleOptionsUI", EnsureSearchControl)
        SUB.toggleHooked = true
    end

    if WorldFrame and WorldFrame.HookScript and not SUB.worldFrameHooked then
        WorldFrame:HookScript("OnMouseDown", ClearSearchFocus)
        SUB.worldFrameHooked = true
    end
end

local function StopControlWatcher()
    if SUB.controlWatcher then
        SUB.controlWatcher:UnregisterEvent("ADDON_LOADED")
    end
    SUB.controlWatcherActive = nil
end

local function RemoveSearchControl()
    if E and E.Options and E.Options.args then
        E.Options.args[SEARCH_CONTROL_KEY] = nil
    end

    RestoreShortcutRow()
    ClearSearchFocus()
    SUB.searchWidget = nil
end

function SUB:OnEnable(db)
    SUB.db = db
    EnsureDefaults(db)
    StartControlWatcher()
    EnsureSearchControl()
    RunSearch()
    RefreshConfigUI()
end

function SUB:OnDisable(db)
    SUB.db = db or SUB.db
    StopControlWatcher()
    RemoveSearchControl()

    if E and E.Options and E.Options.args then
        E.Options.args[RESULTS_GROUP_KEY] = nil
    end

    RefreshConfigUI()
end

function SUB:GetOptions(db)
    EnsureDefaults(db)
    if db.enabled then
        SUB.db = db
        EnsureSearchControl()
        RunSearch()
    end

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
            includeDescriptions = {
                order = 2,
                type = "toggle",
                name = L["Include Descriptions"],
                desc = L["Include option descriptions in matching."],
                disabled = function() return not db.enabled end,
                get = function() return db.includeDescriptions ~= false end,
                set = function(_, value)
                    db.includeDescriptions = value and true or false
                    if db.enabled then
                        RunSearch()
                        RefreshConfigUI()
                    end
                end,
            },
            includeKeys = {
                order = 3,
                type = "toggle",
                name = L["Include Keys"],
                desc = L["Include internal option keys in matching."],
                disabled = function() return not db.enabled end,
                get = function() return db.includeKeys ~= false end,
                set = function(_, value)
                    db.includeKeys = value and true or false
                    if db.enabled then
                        RunSearch()
                        RefreshConfigUI()
                    end
                end,
            },
            gridResults = {
                order = 4,
                type = "toggle",
                name = L["Grouped Grid Results"],
                desc = L["Group results by option section and display setting matches as grid buttons."],
                disabled = function() return not db.enabled end,
                get = function() return db.gridResults == true end,
                set = function(_, value)
                    db.gridResults = value and true or false
                    if db.enabled then
                        RunSearch()
                        RefreshConfigUI()
                    end
                end,
            },
            maxResults = {
                order = 5,
                type = "range",
                name = L["Max Results"],
                desc = L["Maximum number of search results to display."],
                disabled = function() return not db.enabled end,
                min = 10,
                max = 200,
                step = 1,
                get = function() return db.maxResults or 40 end,
                set = function(_, value)
                    db.maxResults = value
                    if db.enabled then
                        RunSearch()
                        RefreshConfigUI()
                    end
                end,
            },
        },
    }
end

MOD:RegisterSubmodule("Search", SUB)
