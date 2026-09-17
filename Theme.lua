-- WickCore
-- Theme.lua — palette switching for the Wick chrome.
--
-- The chrome never changes shape: flat panels, one 1px border, L-bracket
-- corners, two-tone titles. What a theme changes is the five colors those
-- are drawn in. Fel is the brand and the default; it is also the warlock
-- theme. The other eight themes take their accent from the client's own
-- class color table (RAID_CLASS_COLORS, C_ClassColor on retail) so they
-- match what the game paints in raid frames and chat, and derive their
-- darks from that accent so each one reads as its class.
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
local CLASS_ORDER = { "SHAMAN", "DRUID", "HUNTER", "MAGE", "PRIEST", "PALADIN", "ROGUE", "WARRIOR" }

local function classAccent(token)
    if C_ClassColor and C_ClassColor.GetClassColor then
        local ok, col = pcall(C_ClassColor.GetClassColor, token)
        if ok and col and col.r then return { col.r, col.g, col.b, 1 } end
    end
    local t = rawget(_G, "RAID_CLASS_COLORS")
    if t and t[token] and t[token].r then return { t[token].r, t[token].g, t[token].b, 1 } end
    return rgb(CLASS_HEX[token] or FEL.fel)
end

-- Darks and text from an accent. The brand's own void/shadow/border/text
-- are the bases; each is pulled a little toward the accent so the whole
-- panel carries the class hue, not just its lines. Very bright accents
-- (priest, rogue) would wash the darks out, so their pull is scaled by how
-- far the accent sits from white.
local BASE = { void = rgb(FEL.void), shadow = rgb(FEL.shadow), border = rgb(FEL.border), text = rgb(FEL.text) }
local function derive(accent)
    local lum = 0.2126 * accent[1] + 0.7152 * accent[2] + 0.0722 * accent[3]
    local pull = lum > 0.8 and 0.45 or 1
    return {
        fel    = { accent[1], accent[2], accent[3], 1 },
        void   = mix(BASE.void,   accent, 0.10 * pull),
        shadow = mix(BASE.shadow, accent, 0.16 * pull),
        border = mix(BASE.border, accent, 0.38 * pull),
        text   = mix(BASE.text,   accent, 0.14 * pull),
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
        add({ id = token:lower(), name = name, class = token, colors = derive(classAccent(token)) })
    end
end
buildThemes()

-- Classic class-color addons rewrite RAID_CLASS_COLORS at login; rebuild
-- then so the themes follow, and reapply the active one.
function Chrome:RebuildThemes()
    local active = self.activeTheme
    buildThemes()
    if active and self.ThemeByID[active] then self:ApplyTheme(active) end
end

Chrome.DEFAULT_THEME = "fel"
Chrome.activeTheme = Chrome.DEFAULT_THEME

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
    local db = Core.self and Core.self.db and Core.self.db.global
    if db then db.theme = (setting == "auto" or setting == "class") and "auto" or id end
    return self:ApplyTheme(id)
end

function Chrome:ThemeSetting()
    local db = Core.self and Core.self.db and Core.self.db.global
    return db and db.theme or self.DEFAULT_THEME
end

-- Called by WickCore's own OnInitialize, before any product builds a frame.
function Chrome:ApplySavedTheme(global)
    local setting = global and global.theme or self.DEFAULT_THEME
    -- Old saved ids from the first cut map onto the class ids.
    local legacy = { storm = "shaman", wild = "druid", quiver = "hunter", arcane = "mage",
                     holy = "priest", light = "paladin", shadow = "rogue", iron = "warrior" }
    if legacy[setting] then setting = legacy[setting]; if global then global.theme = setting end end
    self:ApplyTheme(self:ResolveTheme(setting))
end
