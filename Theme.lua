-- WickCore
-- Theme.lua — palette switching for the Wick chrome.
--
-- The chrome never changes shape: flat panels, one 1px border, L-bracket
-- corners, two-tone titles. What a theme changes is the five colors those
-- are drawn in. Fel is the brand and the default; it is also the warlock
-- theme. The other eight themes take their accent from the client's own
-- class color table (RAID_CLASS_COLORS, C_ClassColor on retail) so they
-- match what the game paints in raid frames and chat, and sit on deep
-- companion darks the way Fel's green sits on the brand's purple.
--
-- Chrome.Colors is mutated in place so every reference a product holds
-- follows the switch, and every region Chrome created with a palette token
-- is re-tinted live through the registry Chrome keeps.

local ADDON = ...
local Core = LibStub("WickCore-1.0", true)
if not Core or Core._sourceAddon ~= ADDON then return end

local Chrome = Core.Chrome
local C = Chrome.Colors

local function rgb(hex, a)
    return { tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255, a or 1 }
end
local function hex(c)
    return ("%02X%02X%02X"):format(math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end
local function mix(a, b, t)
    return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t, 1 }
end

-- The brand palette, verbatim. Never derived.
local FEL = { fel = "4FC778", void = "0D0A14", shadow = "171124", border = "383058", text = "D4C8A1" }

-- Blizzard's class colors, as a fallback when the client table is absent.
local CLASS_HEX = {
    WARRIOR = "C69B6D", PALADIN = "F48CBA", HUNTER = "AAD372", ROGUE = "FFF468", PRIEST = "FFFFFF",
    SHAMAN = "0070DD", MAGE = "3FC7EB", WARLOCK = "8788EE", DRUID = "FF7C0A",
}
-- The Classic-era set, the one TBC and its class-colored UIs still show.
local CLASSIC_HEX = {
    WARRIOR = "C79C6E", PALADIN = "F58CBA", HUNTER = "ABD473", ROGUE = "FFF569", PRIEST = "FFFFFF",
    SHAMAN = "0070DE", MAGE = "69CCF0", WARLOCK = "9482C9", DRUID = "FF7D0A",
}
local CLASS_ORDER = { "SHAMAN", "DRUID", "HUNTER", "MAGE", "PRIEST", "PALADIN", "ROGUE", "WARRIOR" }

-- "client" reads the game's table; "classic" uses the Classic-era codes.
Chrome.classColorSet = "client"

local function classAccent(token)
    if Chrome.classColorSet == "classic" then return rgb(CLASSIC_HEX[token] or CLASS_HEX[token]) end
    if C_ClassColor and C_ClassColor.GetClassColor then
        local ok, col = pcall(C_ClassColor.GetClassColor, token)
        if ok and col and col.r then return { col.r, col.g, col.b, 1 } end
    end
    local t = rawget(_G, "RAID_CLASS_COLORS")
    if t and t[token] and t[token].r then return { t[token].r, t[token].g, t[token].b, 1 } end
    return rgb(CLASS_HEX[token] or FEL.fel)
end

-- The class colour in the set the player chose, for anything in the
-- suite that paints by class. Comforts colours health bars with this so
-- "classic" means classic everywhere, not only in the chrome.
function Chrome:ClassColor(token)
    local c = classAccent(token)
    return c[1], c[2], c[3]
end

-- The brand's darks are not the accent's hue: Fel's green sits on a deep
-- saturated purple. Each class theme gets the same treatment, a companion
-- hue for void, shadow and border at the brand's own saturation and
-- lightness, with the client's class color left untouched as the accent.
-- Hue and saturation per class; lightness is fixed to match Fel's darks.
local DARK_HUE = {
    SHAMAN  = { h = 215, s = 0.42 },   -- deep sea
    DRUID   = { h = 24,  s = 0.42 },   -- umber
    HUNTER  = { h = 112, s = 0.30 },   -- forest
    MAGE    = { h = 236, s = 0.40 },   -- midnight
    PRIEST  = { h = 42,  s = 0.24 },   -- candle-lit oak
    PALADIN = { h = 346, s = 0.36 },   -- crimson
    ROGUE   = { h = 222, s = 0.12 },   -- charcoal
    WARRIOR = { h = 8,   s = 0.40 },   -- blood and rust
}
local DARK_L = { void = 0.06, shadow = 0.10, border = 0.27 }

local function hsl(h, s, l)
    local c = (1 - math.abs(2 * l - 1)) * s
    local hp = (h % 360) / 60
    local x = c * (1 - math.abs(hp % 2 - 1))
    local r, g, b = 0, 0, 0
    if hp < 1 then r, g = c, x elseif hp < 2 then r, g = x, c elseif hp < 3 then g, b = c, x
    elseif hp < 4 then g, b = x, c elseif hp < 5 then r, b = x, c else r, b = c, x end
    local m = l - c / 2
    return { r + m, g + m, b + m, 1 }
end

local function rgbToHsl(c)
    local r, g, b = c[1], c[2], c[3]
    local mx, mn = math.max(r, g, b), math.min(r, g, b)
    local l = (mx + mn) / 2
    if mx == mn then return 0, 0, l end
    local d = mx - mn
    local s = l > 0.5 and d / (2 - mx - mn) or d / (mx + mn)
    local h
    if mx == r then h = (g - b) / d + (g < b and 6 or 0)
    elseif mx == g then h = (b - r) / d + 2
    else h = (r - g) / d + 4 end
    return h * 60, s, l
end

-- The custom theme: the player picks a main color, whose hue and
-- saturation drive the dark family, and an accent, used untouched.
Chrome.CUSTOM_DEFAULT = { main = "383058", accent = FEL.fel }
Chrome.customColors = { main = Chrome.CUSTOM_DEFAULT.main, accent = Chrome.CUSTOM_DEFAULT.accent }

local TEXT = rgb(FEL.text)
local function derive(accent, token, dark)
    local d = dark or DARK_HUE[token] or { h = 258, s = 0.33 }
    return {
        fel    = { accent[1], accent[2], accent[3], 1 },
        void   = hsl(d.h, d.s, DARK_L.void),
        shadow = hsl(d.h, d.s, DARK_L.shadow),
        border = hsl(d.h, d.s * 0.9, DARK_L.border),
        text   = { TEXT[1], TEXT[2], TEXT[3], 1 },
    }
end

local function finish(t)
    local v, x = t.colors.void, t.colors.text
    t.colors.muted = { x[1] * 0.67 + v[1] * 0.33, x[2] * 0.67 + v[2] * 0.33, x[3] * 0.67 + v[3] * 0.33, 1 }
    t.hex = {}
    for k, c in pairs(t.colors) do if k ~= "muted" then t.hex[k] = hex(c) end end
    return t
end

Chrome.Themes = {}
Chrome.ThemeByID = {}
Chrome.ThemeByClass = {}

local function add(t)
    finish(t)
    Chrome.Themes[#Chrome.Themes + 1] = t
    Chrome.ThemeByID[t.id] = t
    if t.class then Chrome.ThemeByClass[t.class] = t end
end

local function buildThemes()
    Chrome.Themes, Chrome.ThemeByID, Chrome.ThemeByClass = {}, {}, {}
    add({ id = "fel", name = "Fel", class = "WARLOCK", brand = true,
          colors = { fel = rgb(FEL.fel), void = rgb(FEL.void), shadow = rgb(FEL.shadow), border = rgb(FEL.border), text = rgb(FEL.text) } })
    for _, token in ipairs(CLASS_ORDER) do
        local name = token:sub(1, 1) .. token:sub(2):lower()
        add({ id = token:lower(), name = name, class = token, colors = derive(classAccent(token), token) })
    end
    local cc = Chrome.customColors
    local h, s = rgbToHsl(rgb(cc.main))
    add({ id = "custom", name = "Custom", custom = true,
          colors = derive(rgb(cc.accent), nil, { h = h, s = math.max(0.08, math.min(0.6, s)) }) })
end
buildThemes()

local function cleanHex(v)
    v = tostring(v or ""):gsub("^#", ""):upper()
    if #v == 3 then v = v:gsub("(.)", "%1%1") end
    return v:match("^%x%x%x%x%x%x$")
end

-- Set the custom theme's two colors (hex strings or {r,g,b} tables).
-- Rebuilds the theme and repaints if it is the active one.
function Chrome:SetCustomColors(main, accent)
    if type(main) == "table" then main = hex(main) end
    if type(accent) == "table" then accent = hex(accent) end
    main = cleanHex(main) or self.customColors.main
    accent = cleanHex(accent) or self.customColors.accent
    self.customColors.main, self.customColors.accent = main, accent
    self:SaveTheme()
    self:RebuildThemes()
    return self.ThemeByID.custom
end

-- Classic class-color addons rewrite RAID_CLASS_COLORS at login; rebuild
-- then so the themes follow, and reapply the active one.
function Chrome:RebuildThemes()
    local active = self.activeTheme
    buildThemes()
    if active and self.ThemeByID[active] then self:ApplyTheme(active) end
end

Chrome.DEFAULT_THEME = "fel"
Chrome.activeTheme = Chrome.DEFAULT_THEME

-- The player's choice lives here first. The saved variable is written on
-- every change and again at logout, so a change made before the profile
-- was bound still survives the session.
Chrome.themeSetting = Chrome.DEFAULT_THEME

-- What the client handed us before any of our own code touched it. If the
-- saved variable is missing here, the client never loaded the file and no
-- amount of reading it later will help.
do
    local sv = rawget(_G, "WickCoreDB")
    Chrome.bootTrace = ("sv=%s, global=%s, theme=%s"):format(
        type(sv),
        type(sv) == "table" and type(sv.global) or "nil",
        tostring(type(sv) == "table" and sv.global and sv.global.theme))
end

-- Always go to the live saved variable first. The client assigns it just
-- before ADDON_LOADED, and if our profile was ever bound to a table the
-- client then replaced, that copy is an orphan: reads see defaults and
-- writes are never serialized, while the real values sit untouched on
-- disk. Reading the global directly is immune to that.
local function themeStore()
    local sv = rawget(_G, "WickCoreDB")
    if type(sv) == "table" then
        sv.global = sv.global or {}
        return sv.global
    end
    return Core.self and Core.self.db and Core.self.db.global
end

-- True when the profile layer is holding a table the client has replaced.
local function profileIsOrphaned()
    local sv = rawget(_G, "WickCoreDB")
    local db = Core.self and Core.self.db and Core.self.db.global
    if type(sv) ~= "table" or not db then return nil end
    return sv.global ~= db
end

-- True once a saved theme has been read back, or the player has chosen
-- one. Until then the value on disk is better than anything in memory
-- and must not be overwritten.
Chrome.themeKnown = false

function Chrome:SaveTheme()
    local g = themeStore()
    if not g then return false end
    self.themeKnown = true
    g.theme = self.themeSetting
    g.classColors = self.classColorSet
    g.custom = { main = self.customColors.main, accent = self.customColors.accent }
    -- The saved variable is written and never read back by this client,
    -- so the choice only survives if the macro store writes it too, and
    -- the store writes when something says it is dirty. Nothing did:
    -- the options page marks its own check boxes and a theme is picked
    -- from a list somewhere else entirely.
    if Core.Store then Core.Store:Dirty() end
    return true
end

-- Two moments matter. At logout the choice is written once more, right
-- before the client serializes saved variables. At login it is read and
-- applied again: the init-time pass runs inside a protected call that
-- swallows its own errors, and anything loading after it could have
-- repainted, so login is the authoritative application.
local flush = CreateFrame("Frame")
flush:RegisterEvent("PLAYER_LOGOUT")
flush:RegisterEvent("PLAYER_LOGIN")
flush:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGOUT" then
        -- Never write a default we only fell back to. A session that
        -- failed to read the setting must leave the good value alone.
        if Chrome.themeKnown then Chrome:SaveTheme() end
        return
    end
    Chrome:ApplySavedTheme("login")
end)

local listeners = {}
function Chrome:OnThemeChanged(fn) listeners[#listeners + 1] = fn end

-- "auto" resolves to the player's class theme; unknown ids fall back to Fel.
function Chrome:ResolveTheme(setting)
    if setting == "auto" or setting == "class" then
        local _, token = UnitClass("player")
        local t = token and self.ThemeByClass[token]
        return t and t.id or self.DEFAULT_THEME
    end
    if setting and self.ThemeByID[setting] then return setting end
    return self.DEFAULT_THEME
end

local function copyInto(dst, src, alpha)
    dst[1], dst[2], dst[3], dst[4] = src[1], src[2], src[3], alpha or src[4] or 1
end

-- Repaint the palette. Every table in Chrome.Colors keeps its identity.
function Chrome:ApplyTheme(id)
    local t = self.ThemeByID[id] or self.ThemeByID[self.DEFAULT_THEME]
    copyInto(C.fel,    t.colors.fel)
    copyInto(C.void,   t.colors.void)
    copyInto(C.voidBG, t.colors.void, 0.97)
    copyInto(C.shadow, t.colors.shadow)
    copyInto(C.border, t.colors.border)
    copyInto(C.text,   t.colors.text)
    copyInto(C.muted,  t.colors.muted)
    for k, v in pairs(t.hex) do self.Hex[k] = v end
    Core.COLOR_ACCENT = "|cff" .. t.hex.fel
    Core.COLOR_TEXT   = "|cff" .. t.hex.text
    self.activeTheme = t.id
    self:Retint()
    for _, fn in ipairs(listeners) do Core.safe(fn, t) end
    return t
end

-- Choose a theme and remember it. setting may be a theme id or "auto".
function Chrome:SetTheme(setting)
    local id = self:ResolveTheme(setting)
    self.themeSetting = (setting == "auto" or setting == "class") and "auto" or id
    self:SaveTheme()
    return self:ApplyTheme(id)
end

-- Switch the class color source and rebuild the class themes on the spot.
function Chrome:SetClassColorSet(which)
    which = which == "classic" and "classic" or "client"
    self.classColorSet = which
    self:SaveTheme()
    self:RebuildThemes()
    return which
end

function Chrome:ThemeSetting()
    return self.themeSetting or self.DEFAULT_THEME
end

-- What is actually on disk right now, for diagnosing a lost setting.
function Chrome:SavedThemeSetting()
    local g = themeStore()
    return g and g.theme
end

-- Called by WickCore's own OnInitialize, before any product builds a frame.
function Chrome:ApplySavedTheme(source)
    local global = themeStore()
    -- Did we actually read a choice, or are we falling back? The two must
    -- not be treated alike, because this function saves at the end.
    local stored = global and global.theme
    local setting = stored or self.DEFAULT_THEME
    -- Trace for /wickcore theme, so a silent failure is visible.
    self.applyLog = (self.applyLog and (self.applyLog .. ", ") or "")
        .. tostring(source or "init") .. "=" .. tostring(setting)
        .. (profileIsOrphaned() and " (orphaned profile)" or "")
    -- Old saved ids from the first cut map onto the class ids.
    local legacy = { storm = "shaman", wild = "druid", quiver = "hunter", arcane = "mage",
                     holy = "priest", light = "paladin", shadow = "rogue", iron = "warrior" }
    if legacy[setting] then setting = legacy[setting] end
    self.themeSetting = setting
    local rebuild = false
    if global and global.classColors == "classic" then
        self.classColorSet = "classic"
        rebuild = true
    end
    if global and type(global.custom) == "table" then
        self.customColors.main = cleanHex(global.custom.main) or self.customColors.main
        self.customColors.accent = cleanHex(global.custom.accent) or self.customColors.accent
        rebuild = true
    end
    if rebuild then buildThemes() end
    -- Only write back a choice we actually read.
    --
    -- This used to save unconditionally, so a login that read nothing fell
    -- back to Fel and then wrote Fel over the real setting: one read that
    -- came too early turned into the choice being gone for good. On this
    -- client the settings arrive from the macro store, which can land after
    -- login, and Store re-applies with source "store" when it does. The
    -- logout path has always guarded this with themeKnown; this is the same
    -- guard at the other end.
    if stored then self:SaveTheme() end
    self:ApplyTheme(self:ResolveTheme(setting))
end
