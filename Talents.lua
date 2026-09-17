-- WickCore
-- Talents.lua — the trait system, made small.
--
-- Forever runs retail's trait system: C_Traits and C_ClassTalents, with
-- native loadouts and import strings. This module gives products four
-- verbs: Export the active build, Import a string as a new loadout, Save
-- the active build into the account-wide library, Apply a saved build.
-- Blizzard's own import parser is reused by loading Blizzard_PlayerSpells
-- on demand, so string compatibility is whatever the client's is.

local ADDON = ...
local Core = LibStub("WickCore-1.0", true)
if not Core or Core._sourceAddon ~= ADDON then return end

local Talents = {}
Core.Talents = Talents

local CT = rawget(_G, "C_ClassTalents")
local TR = rawget(_G, "C_Traits")

function Talents:IsAvailable()
    return CT ~= nil and TR ~= nil and CT.GetActiveConfigID ~= nil
end

function Talents:ActiveConfigID()
    if not self:IsAvailable() then return nil end
    local ok, id = pcall(CT.GetActiveConfigID)
    return ok and id or nil
end

function Talents:ConfigInfo(configID)
    configID = configID or self:ActiveConfigID()
    if not configID or not TR.GetConfigInfo then return nil end
    local ok, info = pcall(TR.GetConfigInfo, configID)
    return ok and info or nil
end

function Talents:TreeID(configID)
    local info = self:ConfigInfo(configID)
    return info and info.treeIDs and info.treeIDs[1] or nil
end

-- Points spent per tree currency, for a compact "31/20/0" style summary.
function Talents:Summary()
    local configID = self:ActiveConfigID()
    local info = self:ConfigInfo(configID)
    if not info then return nil end
    local out = { configID = configID, name = info.name, treeID = self:TreeID(configID), spent = {} }
    if TR.GetTreeCurrencyInfo and out.treeID then
        local ok, currencies = pcall(TR.GetTreeCurrencyInfo, configID, out.treeID, false)
        if ok and type(currencies) == "table" then
            for _, c in ipairs(currencies) do
                out.spent[#out.spent + 1] = { spent = c.spent or 0, quantity = c.quantity or 0, max = c.maxQuantity or 0 }
            end
        end
    end
    return out
end

-- The active build as a Blizzard import string, or nil, reason.
function Talents:Export()
    local configID = self:ActiveConfigID()
    if not configID or not TR.GenerateImportString then return nil, "no active talent config" end
    local ok, str = pcall(TR.GenerateImportString, configID)
    if not ok or type(str) ~= "string" or str == "" then return nil, "export failed" end
    return str
end

-- Make sure Blizzard's import parser is present. It lives in a
-- LoadOnDemand addon that only loads when the talent frame opens.
local function ensureParser()
    if rawget(_G, "ClassTalentImportExportMixin") then return true end
    local AO = rawget(_G, "C_AddOns")
    if AO and AO.LoadAddOn then pcall(AO.LoadAddOn, "Blizzard_PlayerSpells") end
    return rawget(_G, "ClassTalentImportExportMixin") ~= nil
end

-- Import a string as a new named loadout on the current character.
-- Returns true, or false, reason. Never touches combat state.
function Talents:Import(text, name)
    if not self:IsAvailable() then return false, "talent system not available" end
    if InCombatLockdown() then return false, "not in combat" end
    text = Core.trim(text or "")
    if text == "" then return false, "empty string" end
    name = Core.trim(name or "")
    if name == "" then name = "Wick " .. date("%m-%d %H:%M") end
    if not ensureParser() then return false, "Blizzard talent UI not loaded" end

    local configID = self:ActiveConfigID()
    local treeID = self:TreeID(configID)
    if not configID or not treeID then return false, "no active talent config" end

    -- A private object carrying the mixin's parser methods plus the few
    -- frame-side hooks the parser expects. Errors are captured, not shown.
    local parser = CreateFromMixins(ClassTalentImportExportMixin)
    local errText
    parser.GetConfigID = function() return configID end
    parser.GetTreeInfo = function() return TR.GetTreeInfo and TR.GetTreeInfo(configID, treeID) or { ID = treeID } end
    parser.IsInspecting = function() return false end
    parser.ShowImportError = function(_, msg) errText = msg end
    parser.OnTraitConfigCreateStarted = function() end

    local ok, success = pcall(parser.ImportLoadout, parser, text, name)
    if not ok then return false, tostring(success) end
    if not success then return false, tostring(errText or "import failed") end
    return true
end

-- ============================================================
-- Saved build library (account-wide, per class)
-- ============================================================
-- Products call Talents:Bind(A) once; builds live in A.db.global.talentBuilds.

function Talents:Bind(addon)
    self.addon = addon
    local g = addon.db and addon.db.global
    if g and not g.talentBuilds then g.talentBuilds = {} end
    return self
end

local function classToken()
    local _, token = UnitClass("player")
    return token or "UNKNOWN"
end

function Talents:List()
    local g = self.addon and self.addon.db and self.addon.db.global
    if not g or not g.talentBuilds then return {} end
    return g.talentBuilds[classToken()] or {}
end

function Talents:SaveCurrent(name, note)
    local str, why = self:Export()
    if not str then return false, why end
    local g = self.addon.db.global
    g.talentBuilds[classToken()] = g.talentBuilds[classToken()] or {}
    local list = g.talentBuilds[classToken()]
    local summary = self:Summary()
    list[#list + 1] = {
        name = Core.trim(name or "") ~= "" and name or ("Build " .. (#list + 1)),
        text = str,
        note = note,
        saved = time and time() or 0,
        level = UnitLevel and UnitLevel("player") or nil,
        config = summary and summary.name or nil,
    }
    return true, list[#list]
end

-- Seed curated builds (from talentsforever data or the product) without
-- overwriting a player's saved ones. entries = { {name, text, note}, ... }
function Talents:Seed(entries)
    local g = self.addon and self.addon.db and self.addon.db.global
    if not g then return end
    g.talentBuilds[classToken()] = g.talentBuilds[classToken()] or {}
    local list = g.talentBuilds[classToken()]
    local seen = {}
    for _, b in ipairs(list) do seen[b.text] = true end
    for _, e in ipairs(entries or {}) do
        if e.text and not seen[e.text] then
            list[#list + 1] = { name = e.name, text = e.text, note = e.note, curated = true }
            seen[e.text] = true
        end
    end
end

function Talents:Delete(index)
    local list = self:List()
    if list[index] then table.remove(list, index) return true end
    return false
end

function Talents:Apply(build)
    if not build or not build.text then return false, "no build" end
    return self:Import(build.text, build.name)
end
