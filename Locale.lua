-- WickCore
-- Locale.lua — per-addon string tables with a safe fallback.
--
-- local L = A:NewLocale("enUS", true)
-- L["Open"] = "Open"
-- local L = A:NewLocale("deDE")
-- L["Open"] = "Öffnen"
-- ... later, A.L["Open"] returns the active language, or the key itself.

local ADDON = ...
local Core = LibStub("WickCore-1.0", true)
if not Core or Core._sourceAddon ~= ADDON then return end

local Locale = {}
Core.Locale = Locale
Locale.tables = Locale.tables or {}

local active = GetLocale and GetLocale() or "enUS"
Locale.active = active

-- Returns a table to fill, or nil when this locale is neither the default nor
-- the client's language (so the file's assignments are skipped cheaply).
function Locale:New(addonName, locale, isDefault)
    if locale ~= active and not isDefault then return nil end
    local L = self:Get(addonName)
    if isDefault then
        -- Default strings fill only where a translation has not landed.
        return setmetatable({}, { __newindex = function(_, k, v)
            if rawget(L, k) == nil then rawset(L, k, v == true and k or v) end
        end })
    end
    return setmetatable({}, { __newindex = function(_, k, v)
        rawset(L, k, v == true and k or v)
    end })
end

function Locale:Get(addonName)
    local L = self.tables[addonName]
    if not L then
        L = setmetatable({}, { __index = function(_, k) return k end })
        self.tables[addonName] = L
    end
    return L
end
