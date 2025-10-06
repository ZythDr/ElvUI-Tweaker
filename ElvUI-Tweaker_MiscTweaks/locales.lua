local AceLocale = LibStub:GetLibrary("AceLocale-3.0-ElvUI")
local L = AceLocale:NewLocale("ElvUI", "enUS", true)
if not L then return end

L["MiscTweaks"] = "MiscTweaks"
L["Enable"] = "Enable"

-- Custom Max Level
L["Custom Max Level"] = "Custom Max Level"
L["Set the max player level for Databars."] = "Set the max player level for Databars."
L["This tweak is useful for servers with custom level caps, such as level 60 on 3.3.5 clients."] = "This tweak is useful for servers with custom level caps, such as level 60 on 3.3.5 clients."
L["Credit"] = "Credit"
L["Fix by Belrand (Epoch Addons Discord)"] = "Fix by Belrand (Epoch Addons Discord)"

-- Tooltip anchor tweak
L["Tooltip Anchor"] = "Tooltip Anchor"
L["Bag Addon/Frame"] = "Bag Addon/Frame"
L["Custom Frame Name"] = "Custom Frame Name"
L["Enter the global frame name to anchor to (e.g. 'MyCustomBagFrame')."] = "Enter the global frame name to anchor to (e.g. 'MyCustomBagFrame')."
L["Select your bag addon or choose Custom to enter a frame name."] = "Select your bag addon or choose Custom to enter a frame name."
L["Anchor Point"] = "Anchor Point"
L["Choose which point on the target frame to anchor the tooltip."] = "Choose which point on the target frame to anchor the tooltip."
L["Top Left"] = "Top Left"
L["Top Right"] = "Top Right"
L["Bottom Left"] = "Bottom Left"
L["Bottom Right"] = "Bottom Right"
L["Center"] = "Center"
L["Left"] = "Left"
L["Right"] = "Right"
L["Top"] = "Top"
L["Bottom"] = "Bottom"
L["When enabled, anchors the tooltip to the selected point of the specified frame if it is visible."] = "When enabled, anchors the tooltip to the selected point of the specified frame if it is visible."
L["Enable custom tooltip anchoring."] = "Enable custom tooltip anchoring."
L["Disabling this option reverts to ElvUI's default tooltip behavior."] = "Disabling this option reverts to ElvUI's default tooltip behavior."