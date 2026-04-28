# ElvUI Tweaker (WotLK 3.3.5)

ElvUI Tweaker is a modular plugin for ElvUI-Epoch or ElvUI_WotLK for client 3.3.5. It adds a bunch of small, handy quality-of-life features and customizations that aren't available in the base ElvUI package.

Everything is optional and opt-in. If you don't want a specific feature, you can simply leave it disabled it in the options menu.

## Features

The addon is split into different packages so you only load what you need. Right now, it includes:

### Misc Tweaks

A collection of general interface improvements:

- **Vendor Tweaks:** Replaces the default 10-item grid merchant layout with a compact, scrollable list view. Inspired by GnomishVendorShrinker.
  - **Currency Display**: Dynamically shows relevant currencies (Honor, Arena Points, Tokens) in a skinned tab at the top of the window.
  - **Alternate Rows**: Subtle row highlighting for easier item scanning.
  - **Adjustable Layout**: Change how many items are visible (8-16) to suit your preference.

- **Microbar Tweaks:** A universal microbar editor to declutter and customize your shortcut bar.
  - **Granular Visibility**: Toggle any of the 10 native buttons (Character, Spellbook, PVP, etc.) on or off individually via a checklist.
  - **Custom Shortcuts**: Replace any native button—or add a new 11th button—with a high-fidelity LFG Integration or Mount Journal shortcut.
  - **Smart Layout**: Automatically adjusts bar width and prevents row wrapping, even when exceeding the native 10-button limit.
  - **Dynamic Animations**: Includes a synced, animated eye for the LFG integration that mimics the modern WoW experience.

- **Bag Swap:** Automates the tedious process of upgrading your equipped bags.
  - **Smart Replacement**: When you have a new bag on your cursor and click an equipped bag, the module automatically moves all items from the old bag into your free inventory/bank slots.
  - **Zero-Error Handshake**: Once the bag is cleared, it automatically swaps in the new bag from your cursor, eliminating the annoying "You can't replace a bag that is not empty" error message.

- **Chat Editbox Mover:** Detaches the chat typing box from the main chat window so you can place it anywhere on your screen.
- **Five Second Rule:** Adds a visual "spark" to the Player UnitFrame's power/mana bar that tracks your mana regeneration ticks, and visualizes the 5-second delay before natural mana regeneration resumes after casting a spell.
- **Tooltip Anchor:** This module lets you attach the in-game tooltip to various bag addons to avoid having the tooltip overlapping the bag frames.
- Supported Bag Addons: `AdiBags`, `ArkInventory`, `Bagnon`, `Combuctor`, `ElvUI`, `GudaBags`, and `OneBag3`.

> [!NOTE]  
> For any other bag addons, you can use the `Custom` option to attach the tooltip to your bag frame.  
> To add a custom frame, you'll need to provide a frame name to attach the tooltip to.  
> To idenfity a frame, type `/fstack` and hover over the bag frame to see the frame name. For example: `ElvUI_ContainerFrame` for ElvUI's bags.  

- **Game Time Display:** Adds back the ability to see the in-game day/night cycle, this can be very useful for certain quests and abilities in the game.
- **Shapeshift Remover:** Automatically removes specific transformation buffs (like Noggenfogger Elixir) that prevent you from taking actions like using flight paths or mounting. You can configure the list of buffs to remove in the GUI.

> [!NOTE]
> Shapeshift Remover can also be triggered manually in macros by adding `/removeshapeshift` to a separate line.

- **Embed Tweaks:** Adds the ability to auto-hide embedded addons such as `Details`, `Omen`, `Recount`, or `Skada` when they're being embedded by ElvUI_AddOnSkins into the right Chat Frame.

> [!NOTE]
> ElvUI_AddOnSkins must be installed in order to embed addons into the right chat frame. Embed Tweaks does not embed addons itself.

### DataTexts

Tweaks and additions to ElvUI's DataTexts:

- **Movement Speed:** See exactly how fast your character is running, flying, or riding as a percentage.
- **Online Count:** Runs a hidden search in the background to show you the total number of players currently online on your entire server. (Do not use this on Project Epoch until /who is fixed)
- **Gold Scale Fix:** Lets you adjust the size and exact position of the gold, silver, and copper coin icons inside your Gold datatext, this can be useful for higher resolutions and lower UI scale setups.

## Installation & Usage

1. Download or clone the repository.
2. Extract `ElvUI-Tweaker-main` and open the extracted folder
2. Inside of `ElvUI-Tweaker-main`, move the `ElvUI-Tweaker` folder along with `ElvUI-Tweaker_DataTexts` and `ElvUI-Tweaker_MiscTweaks` folders into your `WoW/Interface/AddOns` directory.
3. Restart WoW
4. Once in-game, you can configure ElvUI-Tweaker via `/ec` and looking for the **ElvUI Tweaker** tab on the left side. From there, you can enable, disable, and tweak any and all modules to your liking.
