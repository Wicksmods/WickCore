# WickCore - Changelog

## 0.3.0 - 2026-09-17

### Themes

The chrome keeps its shape and swaps its five colors. Fel stays the brand
default; the other eight themes are one per Forever class.

- Chrome.Themes: Fel (the brand, and the warlock theme) plus one theme per
  other class. Class themes take their accent from the client's class color
  table and derive void, shadow, border and text from it, so they match the
  colors the game itself uses for each class
- Chrome:SetTheme(id) mutates Chrome.Colors in place and re-tints every
  region Chrome painted with a palette token, live, no reload
- "auto" follows the player's class; the choice is saved account-wide in WickCoreDB
- Theme picker with swatches on the Wick's Mods options page; /wickcore theme
- Chrome:Register(region, token, kind) for regions products paint themselves
- Chat prefix and two-tone title colors follow the theme

## 0.1.0 - 2026-09-17

### Scaffold

Built the day the Forever beta opened, against the first two probe runs on
client 1.60.1.69893 (interface 16001) and the `forever` branch of Blizzard's UI
source.

- LibStub-versioned library `WickCore-1.0`, loadable standalone or embedded
- Addon objects: `WickCore:NewAddon`, event bus, slash registration, lifecycle
- Client detection by interface number, since Forever reports itself as Mainline
- Restriction guard: `ADDON_RESTRICTION_STATE_CHANGED`, secret-value checks,
  aura access guard that survives the in-combat throw
- Dialect shim over items, spells, cooldowns, containers, auras, quest log,
  group, money, addon messages, professions, totems, talents
- Brand chrome: palette tokens, panel builder, brackets, buttons, checks
- Profiles keyed by character, spec, class or game mode, with export/import strings
- One "Wick's Mods" options category with a page per product
- Launcher: LibDataBroker object per product, minimap button and hub fallback
- Localization tables with key fallback
- Version broadcast on the WICK prefix, guarded by the chat restriction
