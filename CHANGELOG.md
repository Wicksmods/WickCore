# WickCore - Changelog

## 0.9.2 — 2026-09-24

### Changed

- The cooldown bar tracks rather than casts. It was built out of secure
  cast buttons, which cannot be changed during a fight, which is when a
  cooldown tracker is worth having. Clicking an icon no longer casts.
- The bar has a scale and a row width, and anything on cooldown dims,
  so it answers at a glance the question it exists for.
- A checklist row can say it does not apply to this character, instead
  of sitting grey forever next to something you will never have.

### Fixed

- Settings changed outside the options page are kept. Picking a theme
  or dragging a window wrote the setting and never told the part of
  WickCore that survives a restart, so your theme came back to the old
  one at the next login.
- A window sized in code opens at the size the code says. A size saved
  under an older layout was being restored over it.
- The version handler no longer compares a chat payload the client has
  marked unreadable.

## 0.9.1

### Your theme stops resetting

A login that read the theme before the settings had arrived fell back to
Fel and then saved Fel over your real choice, so one early read lost the
setting for good. On this client the settings come from the macro store,
which can land after login, so reading nothing at login is normal and
has to be harmless. It only writes back a choice it actually read now.

## 0.9.0

One version across the suite for the Forever beta. Every addon carried a
number of its own that said nothing about how finished it was, so they are
aligned here and the suite goes to 1.0.0 together at launch.

## 0.4.0 - 2026-09-21

### Settings that survive this client

The Forever beta writes saved variables at logout and hands nothing back at
load. Macros are the one thing an addon can write that provably comes back,
so every Wick saved variable is now kept in account macros named WickCfg01
onward as well: dictionary-coded, base64, 240 characters a macro, 60 macros
at most. Restored as each addon enables, before its OnEnable, so no product
applies defaults it did not choose. Written ten seconds after an options
change, once a minute if anything differs, and at logout.

- Core.Store: Encode/Decode, Read/Write/Clear, RestoreFor, Save, Dirty.
  Deterministic encoding, so "changed" is a string compare
- DBProto:RebindTo(table), which Rebind now uses; db.handedOver records
  whether the client itself supplied the table (a WicksProfile bake does
  not count)
- Runs only when the client handed WickCoreDB over as nil. If saved
  variables start loading, it stays out of the way and says so
- /wickcore store [save|clear]
- Addons declare cache paths with storeExclude (Bags: global.alts, the
  alt inventory snapshot) and those are left out of the store, so a cache
  cannot grow past the budget and take an addon's settings down with it
- Bodies are escaped rather than base64: settings are printable text, and
  base64 made every one a third bigger. Fifty-four macros became about
  twenty. Anything the base64 version wrote still reads back

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
