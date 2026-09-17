-- WickCore
-- Theme.lua — palette switching for the Wick chrome.
--
-- The chrome never changes shape: flat panels, one 1px border, L-bracket
-- corners, two-tone titles. What a theme changes is the five colors those
-- are drawn in. Fel is the brand and the default; the other themes are one
-- per class, so a shaman can sit in storm blue and a paladin in gold while
-- every panel still reads as Wick.
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
    local r = tonumber(hex:sub(1, 2), 16) / 255
    local g = tonumber(hex:sub(3, 4), 16) / 255
    local b = tonumber(hex:sub(5, 6), 16) / 255
    return { r, g, b, a or 1 }
end

-- accent / void / shadow / border / text, as hex.
local DEFS = {
    { id = "fel",     name = "Fel",     class = "WARLOCK", accent = "4FC778", void = "0D0A14", shadow = "171124", border = "383058", text = "D4C8A1" },
    { id = "storm",   name = "Storm",   class = "SHAMAN",  accent = "4FA8E8", void = "0A0F16", shadow = "12202C", border = "2A4A62", text = "CFD8E0" },
    { id = "wild",    name = "Wild",    class = "DRUID",   accent = "E8A33C", void = "0C0F0A", shadow = "161D12", border = "35482B", text = "D9CFA8" },
    { id = "quiver",  name = "Quiver",  class = "HUNTER",  accent = "D2A85A", void = "0E0C09", shadow = "1C1710", border = "4A3C24", text = "E0D4B0" },
    { id = "arcane",  name = "Arcane",  class = "MAGE",    accent = "6FC8F0", void = "0A0A18", shadow = "141432", border = "2E2E6A", text = "D4D6E8" },
    { id = "holy",    name = "Holy",    class = "PRIEST",  accent = "F2E2A0", void = "0F0E14", shadow = "1D1B26", border = "4A4560", text = "ECE6D6" },
    { id = "light",   name = "Light",   class = "PALADIN", accent = "F5C242", void = "110E0C", shadow = "201915", border = "553F2E", text = "E8DCC4" },
    { id = "shadow",  name = "Shadow",  class = "ROGUE",   accent = "E6D24A", void = "0A0A0B", shadow = "151517", border = "3A3A40", text = "D8D4CC" },
    { id = "iron",    name = "Iron",    class = "WARRIOR", accent = "C79C6E", void = "100B0A", shadow = "1E1412", border = "522F2A", text = "E0D0C0" },
}

Chrome.Themes = {}       -- ordered, as above
Chrome.ThemeByID = {}
Chrome.ThemeByClass = {}
for _, d in ipairs(DEFS) do
    local t = {
        id = d.id, name = d.name, class = d.class,
        hex = { fel = d.accent, void = d.void, shadow = d.shadow, border = d.border, text = d.text },
        colors = {
            fel    = rgb(d.accent),
            void   = rgb(d.void),
            shadow = rgb(d.shadow),
            border = rgb(d.border),
            text   = rgb(d.text),
        },
    }
    -- Muted sits two thirds of the way from the void to the text.
    local v, x = t.colors.void, t.colors.text
    t.colors.muted = { x[1] * 0.67 + v[1] * 0.33, x[2] * 0.67 + v[2] * 0.33, x[3] * 0.67 + v[3] * 0.33, 1 }
    Chrome.Themes[#Chrome.Themes + 1] = t
    Chrome.ThemeByID[t.id] = t
    Chrome.ThemeByClass[t.class] = t
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
    self:ApplyTheme(self:ResolveTheme(setting))
end
