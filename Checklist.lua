-- WickCore
-- Checklist.lua — the pre-pull checklist.
--
-- Everything a class sets up before the fight: shields, armors, marks,
-- weapon imbues, a stack of reagents. All of it is readable out of combat
-- and none of it is readable in combat on a secrets client, so the
-- checklist evaluates when it can and shows "in combat" when it cannot.
--
-- local list = WickCore.Checklist:New(A, {
--     { label = "Water Shield",   aura = "Water Shield",        cast = "Water Shield" },
--     { label = "Weapon imbue",   weaponEnchant = "main",       cast = "Windfury Weapon" },
--     { label = "Ankhs",          item = 17030, min = 1 },
-- })
-- list:Evaluate()  -> rows with .state = "ok" | "missing" | "unknown"

local ADDON = ...
local Core = LibStub("WickCore-1.0", true)
if not Core or Core._sourceAddon ~= ADDON then return end

local Checklist = {}
Core.Checklist = Checklist

local D, R, Chrome = Core.Dialect, Core.Restrict, Core.Chrome

local Proto = {}
Proto.__index = Proto

function Checklist:New(addon, defs)
    local list = setmetatable({ addon = addon, defs = defs or {}, rows = {} }, Proto)
    return list
end

local function hasWeaponEnchant(which)
    local f = rawget(_G, "GetWeaponEnchantInfo")
    if not f then return nil end
    local ok, mh, _, _, _, oh = pcall(f)
    if not ok then return nil end
    if which == "off" then return oh and true or false end
    return mh and true or false
end

local function auraPresent(names)
    if type(names) == "string" then names = { names } end
    for _, name in ipairs(names) do
        local aura, why = D.GetAuraBySpellName("player", name, "HELPFUL")
        if why == "restricted" then return nil end
        if aura then return true end
    end
    return false
end

-- Whether a definition is worth a row on this character at all.
--
-- Not the same question as a check returning nil. nil means the answer
-- cannot be read right now, which is worth a grey row; `when` saying no
-- means there is nothing here to report, and a row would be clutter
-- that never resolves. A mage who has not learned a teleport should not
-- carry a row about teleport reagents.
local function applies(def)
    if not def.when then return true end
    local ok, v = pcall(def.when)
    return ok and v ~= false and v ~= nil
end

local function evaluate(def, blocked)
    local state, detail
    if def.aura then
        if blocked then state = "unknown"
        else
            local present = auraPresent(def.aura)
            state = present == nil and "unknown" or (present and "ok" or "missing")
        end
    elseif def.weaponEnchant then
        local has = hasWeaponEnchant(def.weaponEnchant)
        state = has == nil and "unknown" or (has and "ok" or "missing")
    elseif def.item then
        local n = D.GetItemCount(def.item, false) or 0
        detail = tostring(n)
        state = n >= (def.min or 1) and "ok" or "missing"
    elseif def.check then
        local ok, v = pcall(def.check)
        state = (ok and v == true) and "ok" or ((ok and v == nil) and "unknown" or "missing")
    else
        state = "unknown"
    end
    if def.known and not D.IsSpellKnown(def.known) then state = "skip" end
    return { def = def, label = def.label, state = state, detail = detail }
end

-- One row per definition that applies. state: "ok", "missing",
-- "unknown" (restricted), "skip" (spell not learned).
function Proto:Evaluate()
    local rows = {}
    local blocked = R:AurasBlocked()
    for _, def in ipairs(self.defs) do
        if applies(def) then rows[#rows + 1] = evaluate(def, blocked) end
    end
    self.rows = rows
    return rows
end

-- ============================================================
-- Rendering: a column of rows inside any parent frame
-- ============================================================
-- Each row: status dot, label, optional detail, and a secure Cast button
-- when the definition names a spell. Secure attributes are set on build
-- and refreshed out of combat only.

local C = Chrome.Colors
local STATE_COLOR = {
    ok      = C.fel,
    missing = { 0.80, 0.30, 0.30, 1 },
    unknown = C.muted,
    skip    = { 0.35, 0.33, 0.40, 1 },
}

function Proto:Attach(parent, y, width)
    width = width or 300
    self.widgets = self.widgets or {}
    for i, def in ipairs(self.defs) do
        local w = self.widgets[i]
        if not w then
            w = CreateFrame("Frame", nil, parent)
            w:SetSize(width, 20)
            w.dot = Chrome:Texture(w, "ARTWORK", C.muted)
            w.dot:SetSize(8, 8)
            w.dot:SetPoint("LEFT", 2, 0)
            w.label = Chrome:Text(w, 11)
            w.label:SetPoint("LEFT", w.dot, "RIGHT", 8, 0)
            w.label:SetText(def.label)
            w.detail = Chrome:Text(w, 10, C.muted)
            w.detail:SetPoint("LEFT", w.label, "RIGHT", 6, 0)
            if def.cast then
                local b = CreateFrame("Button", nil, w, "SecureActionButtonTemplate")
                b:SetSize(48, 16)
                b:SetPoint("RIGHT", -2, 0)
                b:RegisterForClicks("AnyUp", "AnyDown")
                b:SetAttribute("type", "spell")
                b:SetAttribute("spell", def.cast)
                Chrome:AddBorder(b)
                local bg = Chrome:Texture(b, "BACKGROUND", C.shadow); bg:SetAllPoints()
                b.txt = Chrome:Text(b, 10, C.text)
                b.txt:SetPoint("CENTER")
                b.txt:SetText("cast")
                b:SetScript("OnEnter", function() b.txt:SetTextColor(C.fel[1], C.fel[2], C.fel[3], 1) end)
                b:SetScript("OnLeave", function() b.txt:SetTextColor(C.text[1], C.text[2], C.text[3], 1) end)
                w.cast = b
            end
            self.widgets[i] = w
        end
        w:ClearAllPoints()
        w:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
        y = y - 22
    end
    self.parent = parent
    self:Refresh()
    return y
end

function Proto:Refresh()
    if not self.widgets then return end
    local rows = self:Evaluate()
    for i, row in ipairs(rows) do
        local w = self.widgets[i]
        if w then
            local c = STATE_COLOR[row.state] or C.muted
            w.dot:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
            w.detail:SetText(row.state == "unknown" and (R:AurasBlocked() and "in combat" or "") or (row.detail or ""))
            if w.cast then
                if row.state == "missing" then w.cast:Show() else w.cast:Hide() end
            end
            if row.state == "skip" then w:SetAlpha(0.4) else w:SetAlpha(1) end
        end
    end
end

-- Rows that are missing right now, for chat summaries.
function Proto:Missing()
    local out = {}
    for _, row in ipairs(self:Evaluate()) do
        if row.state == "missing" then out[#out + 1] = row.label end
    end
    return out
end
