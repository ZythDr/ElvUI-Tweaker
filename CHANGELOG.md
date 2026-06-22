# Changelog

All notable changes to ElvUI Tweaker will be documented in this file.

Older release entries were reconstructed from git commit history.

## 1.5.1 - 2026-06-22

### Improved

- Added a Roll Save setting to auto-confirm bind-on-pickup loot roll popups only for rolls started by Roll Save. This is enabled by default and can be disabled in Roll Save behavior options.

## 1.5.0 - 2026-06-21

### Added

- Added **OptionsTweaks: Tabs Fix**, an opt-in module that patches ElvUI options TabGroup widgets so tabs lay out horizontally and wrap instead of collapsing into one-per-row lists on affected WotLK forks.
- Added **MiscTweaks: Roll Save**, an opt-in module that saves Need, Greed, Disenchant, or Pass choices per character by item ID and repeats them automatically on future drops.
- Added Roll Save options for right-click or modifier-right-click save triggers, immediate roll-on-save behavior, chat announcements, and manual saved-item management by item ID or item link.

### Changed

- Reworked the ElvUI Tweaker options page into an expandable tree with child pages for DataTexts, MiscTweaks, and OptionsTweaks.
- Added an ElvUI Tweaker landing page with shortcut buttons to the main module groups.
- Changed Shapeshift Remover's Add Buffs flow so pressing Enter or clicking Okay in the input field adds the buff directly, removing the separate Add button.

### Fixed

- Fixed Honor Points using the wrong vendor currency icon in the top currency display.
- Fixed vendor list view keeping its old scroll position after reopening a vendor.
- Fixed some custom vendor currencies missing from the top currency display.
- Scoped Tabs Fix to ElvUI's own options UI so it does not disturb TabGroup layouts in other Ace3 addons.

## 1.4.2 - 2026-05-24

### Fixed

- Fixed Options Search on ElvUI builds with a different AceGUI EditBox widget.

## 1.4.1 - 2026-05-24

### Tweaks

- Adjusted the Options Search editbox sizing and alignment in ElvUI's top options row.

## 1.4.0 - 2026-05-22

### New

- Added the `ElvUI-Tweaker_OptionsTweaks` addon package.
- Added the Options Search module for searching ElvUI option names, descriptions, and internal option keys.

### Improved

- Registered ElvUI Tweaker with LibElvUIPlugin as `ElvUI-Tweaker` so the ElvUI Plugins page shows the friendly addon name and TOC metadata.

## 1.3.6 - 2026-05-10

### New

- Added item status coloring and layout refinements for Vendor Tweaks.

## 1.3.5 - 2026-05-09

### Fixed

- Fixed Vendor Tweaks compatibility issues.

## 1.3.4 - 2026-04-28

### Fixed

- Finalized stability and tooltip behavior fixes.

## 1.3.3 - 2026-04-28

### Improved

- Polished Microbar behavior and tooltip handling.

## 1.3.2 - 2026-04-28

### Improved

- Overhauled Microbar Tweaks.
- Refined Microbar Tweaks module loading and option layout.
- Added the Mount Journal portrait media asset used by Microbar Tweaks.

## 1.3.1 - 2026-04-28

### New

- Added **Microbar Tweaks**.
- Added options to fix the native microbar gap, add or replace a Mounts button, and integrate with LFG addon shortcuts.

## 1.3.0 - 2026-04-28

### New

- Added **Bag Swap**, an automation module for replacing equipped bags.
- Added logic to move contents out of a bag before equipping the replacement bag.

## 1.2.1 - 2026-04-26

### Fixed

- Fixed a minor Lua error reported after the Vendor Tweaks release.

### Maintenance

- Bumped TOC versions across the core, DataTexts, and MiscTweaks packages.

## 1.2.0 - 2026-04-24

### New

- Added **Vendor Tweaks**.
- Added a compact, scrollable merchant item list.
- Added top-of-window currency tracking for vendor currencies.

## 1.1.0 - 2026-04-23

### New

- Added **Chat Editbox Mover**.

### Improved

- Enhanced Tooltip Anchor bag support.
- Moved Chat Editbox Mover credit text into the module description and polished its spacing.

### Fixed

- Fixed Game Time Display flicker on mouseover.
- Hid ChatEditboxMover from `/moveui` when the module is disabled.

## 1.0.0 - 2025-10-06

### New

- Initial release of ElvUI Tweaker for WotLK 3.3.5.
- Added the core ElvUI Tweaker addon and separated packages for MiscTweaks and DataTexts.
- Added initial MiscTweaks modules: Embed Tweaks, Five Second Rule, Game Time Display, Shapeshift Remover, and Tooltip Anchor.
- Added initial DataTexts modules: Gold Scale Fix, Movement Speed, and Online Count.
