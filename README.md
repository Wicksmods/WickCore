# WickCore

> The shared platform under every Wick addon for World of Warcraft: Forever.

Part of the **[Wick suite](https://github.com/Wicksmods/WickSuite)**. WickCore is
a library, not a player-facing addon. It carries the brand chrome and every
table-stakes capability so no product builds its own: profiles, one options
panel, import and export strings, a launcher, localization, version broadcast,
and a shim that speaks the client's API dialect.

## Why it exists

Forever runs retail's engine at level 60 (interface `16001`, `WOW_PROJECT_ID`
is Mainline) with Midnight's addon restrictions. Against the TBC Anniversary
suite that meant:

- `GetItemInfo`, `GetSpellInfo`, `GetSpellCooldown`, `UnitAura` and the
  container globals are gone. 73 of the suite's 219 bare globals are nil.
- The player's own health and power are secret at all times. Ratings, totems
  and cooldowns go secret in combat. Aura queries in combat throw.
- Talents are the retail trait system, with native loadouts and import strings.

WickCore absorbs all of that once.

## Using it from a product

```lua
local A = WickCore:NewAddon("WicksBags", {
    title    = "Wick's Bags",
    version  = "1.0.0",
    savedVar = "WicksBagsDB",
    defaults = { profile = { locked = false, window = {} } },
})

function A:OnInitialize()
    self.panel = WickCore.Chrome:NewPanel("WicksBagsFrame", {
        title = self.title, width = 420, height = 320,
        resizable = true, db = self.db.profile.window,
    })
    self:RegisterSlash(function(_, msg) self.panel:Toggle() end, "/wbags", "/wb")
    self:RegisterOptions(function(page)
        local O = WickCore.Options
        local y = O:Heading(page, "General", 0)
        y = O:Check(page, "Lock window", function() return self.db.profile.locked end,
                    function(v) self.db.profile.locked = v end, y)
        y = O:ProfileSection(page, self, y - 8)
    end)
    self:RegisterLauncher({ onClick = function() self.panel:Toggle() end })
end

function A:OnEnable()
    local D = WickCore.Dialect
    local item = D.GetItemInfo(6948)          -- same table on Forever and TBC
    for aura in D.IterateAuras("player") do   -- yields nothing while blocked
        -- ...
    end
    WickCore.Restrict:OnChange(function(kind, active)
        if kind == "Combat" then self:Refresh() end
    end)
end
```

## Modules

| Module | Entry points |
|---|---|
| `Core` | `NewAddon`, `safe`, `pack`, `applyDefaults`, `compareVersions`, `Print` |
| `Client` | `isForever`, `isModern`, `hasSecrets`, `hasTraits`, `GameMode()`, `IsHardcore()` |
| `Restrict` | `IsActive(kind)`, `AurasBlocked()`, `CooldownsSecret()`, `ChatBlocked()`, `IsSecret(v)`, `Guard(fn)`, `OnChange(fn)` |
| `Dialect` | item, spell, cooldown, container, aura, quest, group, coin, addon message, profession, totem, talent config |
| `Chrome` | `NewPanel`, `AddBorder`, `AddBrackets`, `Button`, `Check`, `Heading`, `TitleMarkup`, position save/restore |
| `Profiles` | `A.db.profile/global/char`, `SetProfile`, `CopyProfile`, `ResetProfile`, `SetKeyMode`, `Export`, `Import` |
| `Options` | `Register`, `Open`, `Heading`, `Check`, `Button`, `Note`, `ProfileSection`, `ShowExport` |
| `Launcher` | `Register`, minimap button, hub |
| `Locale` | `A:NewLocale(locale, isDefault)`, `A.L` |
| `Version` | automatic; `Register` is called on enable |

`/wickcore` prints the client report and restriction state. `/wickcore dialect`
shows which path each shimmed call resolved to.

## Embedding

Copy the folder to `Libs/WickCore/` in a product and list its files in the
product's TOC after `LibStub.lua`. The newest copy wins at runtime. Add
`WickCoreDB` to the product's `SavedVariables` if you want the minimap position
to persist without the standalone addon installed.

## Offline test

```
python WickSuite/tools/core-harness/run.py            # Forever-shaped stub client
python WickSuite/tools/core-harness/run.py --legacy   # TBC-shaped stub client
```

## License

MIT with a trademark carve-out for the Wick name, logomark and visual system.
LibStub is public domain. Full policy:
[WickSuite/TRADEMARK.md](https://github.com/Wicksmods/WickSuite/blob/main/TRADEMARK.md).
