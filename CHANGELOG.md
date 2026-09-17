# WickCore - Changelog

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
