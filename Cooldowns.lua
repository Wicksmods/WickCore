-- WickCore
-- Cooldowns.lua — a movable row of cooldown icons, driven by a list the
-- player controls.
--
-- Blizzard's own Cooldown Manager reads its spell list from a game table
-- that only Blizzard can fill, and on this build several classes have no
-- entries at all, so the panel comes up empty with nothing a player or an
-- addon can do about it. This is the part we can own: a plain row of
-- icons for whatever spells you name, imported and exported as a string.
--
-- It works in combat because it never reads a cooldown. The values come
-- back secret and go straight into the Cooldown widget, which accepts
-- them; nothing here compares or does arithmetic on one.

local ADDON = ...
local Core = LibStub("WickCore-1.0", true)
if not Core or Core._sourceAddon ~= ADDON then return end

local Cooldowns = {}
Core.Cooldowns = Cooldowns

local Chrome, D, R = Core.Chrome, Core.Dialect, Core.Restrict
local C = Chrome.Colors

local ICON = 32
local GAP  = 4
local PAD  = 5

-- Somewhere to start per class. Names, not IDs, so they bind to whatever
-- rank the player knows and survive an ID change between builds.
Cooldowns.DEFAULTS = {
    HUNTER  = { "Rapid Fire", "Aspect of the Cheetah", "Feign Death", "Disengage", "Mend Pet", "Freezing Trap" },
    ROGUE   = { "Sprint", "Evasion", "Vanish", "Blind", "Kick", "Sap" },
    SHAMAN  = { "Bloodlust", "Elemental Mastery", "Nature's Swiftness", "Reincarnation", "Earth Shield" },
    WARLOCK = { "Death Coil", "Fear", "Howl of Terror", "Soulstone Resurrection", "Shadowburn" },
    DRUID   = { "Innervate", "Rebirth", "Nature's Swiftness", "Barkskin", "Tiger's Fury" },
    MAGE    = { "Blink", "Counterspell", "Evocation", "Ice Block", "Polymorph" },
    PRIEST  = { "Fade", "Psychic Scream", "Inner Focus", "Shadowform", "Power Infusion" },
    PALADIN = { "Divine Shield", "Lay on Hands", "Hammer of Justice", "Divine Favor", "Blessing of Freedom" },
    WARRIOR = { "Shield Wall", "Last Stand", "Recklessness", "Charge", "Pummel", "Berserker Rage" },
}

local Proto = {}
Proto.__index = Proto

-- addon: the WickCore addon object. The list lives in its profile under
-- opts.key so every product keeps its own.
function Cooldowns:New(addon, opts)
    opts = opts or {}
    local bar = setmetatable({
        addon = addon,
        key   = opts.key or "cooldownBar",
        title = opts.title or "Cooldowns",
    }, Proto)
    addon.cooldowns = bar
    return bar
end

function Proto:Store()
    local db = self.addon.db and self.addon.db.profile
    if not db then return nil end
    db[self.key] = db[self.key] or {}
    local s = db[self.key]
    if s.list == nil then
        local _, token = UnitClass("player")
        s.list = Core.copy(Cooldowns.DEFAULTS[token or ""] or {})
    end
    if s.shown == nil then s.shown = false end
    if s.locked == nil then s.locked = true end
    s.window = s.window or {}
    return s
end

-- ============================================================
-- The list
-- ============================================================

function Proto:List()
    local s = self:Store()
    return s and s.list or {}
end

function Proto:Add(name)
    name = Core.trim(tostring(name or ""))
    if name == "" then return false, "name a spell" end
    local id = tonumber(name)
    if id then
        local info = D.GetSpellInfo(id)
        if not info or not info.name then return false, "no spell with id " .. id end
        name = info.name
    end
    local list = self:List()
    for _, n in ipairs(list) do
        if n:lower() == name:lower() then return false, name .. " is already there" end
    end
    list[#list + 1] = name
    self:Rebuild()
    return true, name
end

function Proto:Remove(name)
    name = Core.trim(tostring(name or "")):lower()
    local list = self:List()
    for i, n in ipairs(list) do
        if n:lower() == name or tostring(i) == name then
            local gone = table.remove(list, i)
            self:Rebuild()
            return true, gone
        end
    end
    return false, "not in the list"
end

function Proto:Reset()
    local s = self:Store()
    if not s then return end
    local _, token = UnitClass("player")
    s.list = Core.copy(Cooldowns.DEFAULTS[token or ""] or {})
    self:Rebuild()
end

-- A plain, readable string: the names joined by semicolons behind a tag.
-- Easy to paste in chat or into a guide, unlike an encoded blob.
function Proto:Export()
    return "WICKCD1:" .. table.concat(self:List(), ";")
end

function Proto:Import(text, append)
    text = tostring(text or "")
    local body = text:match("^%s*WICKCD1:(.*)$") or text
    local names = {}
    for raw in (body .. ";"):gmatch("(.-);") do
        local piece = Core.trim(raw)
        if piece ~= "" then names[#names + 1] = piece end
    end
    if #names == 0 then return false, "nothing to import" end
    local s = self:Store()
    if not s then return false, "no profile" end
    if append then
        for _, n in ipairs(names) do
            local dup = false
            for _, have in ipairs(s.list) do if have:lower() == n:lower() then dup = true break end end
            if not dup then s.list[#s.list + 1] = n end
        end
    else
        s.list = names
    end
    self:Rebuild()
    return true, #names
end

-- ============================================================
-- The bar
-- ============================================================

function Proto:Build()
    if self.frame then return self.frame end
    local s = self:Store()
    local f = CreateFrame("Frame", "Wick" .. self.addon.name .. "Cooldowns", UIParent)
    self.frame = f
    f:SetSize(ICON + PAD * 2, ICON + PAD * 2)
    f:SetPoint("CENTER", 0, -180)
    f:SetFrameStrata("MEDIUM")
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(fr) if s and not s.locked then fr:StartMoving() end end)
    f:SetScript("OnDragStop", function(fr)
        fr:StopMovingOrSizing()
        if s then Chrome:SavePosition(fr, s.window) end
    end)
    local bg = Chrome:Texture(f, "BACKGROUND", C.voidBG); bg:SetAllPoints()
    Chrome:AddBorder(f)
    Chrome:AddBrackets(f)
    if s and s.window and s.window.point then
        local w, h = f:GetWidth(), f:GetHeight()
        Chrome:RestorePosition(f, s.window)
        f:SetSize(w, h)
    end
    f:Hide()
    self.buttons = {}
    R:OnChange(function() if f:IsShown() then self:Refresh() end end)
    -- Cooldowns tick without any event, so the sweep needs its own beat.
    self.ticker = C_Timer and C_Timer.NewTicker and C_Timer.NewTicker(1, function()
        if f:IsShown() then self:Refresh() end
    end)
    self:Rebuild()
    return f
end

function Proto:Rebuild()
    if not self.frame then return end
    local list = self:List()
    self.buttons = self.buttons or {}
    local shown = 0
    for i, name in ipairs(list) do
        local b = self.buttons[i]
        if not b then
            b = CreateFrame("Button", nil, self.frame, "SecureActionButtonTemplate")
            b:SetSize(ICON, ICON)
            b:RegisterForClicks("AnyUp", "AnyDown")
            b:SetAttribute("type", "spell")
            Chrome:AddBorder(b)
            b.icon = b:CreateTexture(nil, "ARTWORK")
            b.icon:SetPoint("TOPLEFT", 1, -1)
            b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
            b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
            b.cd:SetAllPoints(b.icon)
            b.label = Chrome:Text(b, 9, C.muted)
            b.label:SetPoint("BOTTOM", 0, 1)
            b:SetScript("OnEnter", function(self_)
                GameTooltip:SetOwner(self_, "ANCHOR_TOP")
                GameTooltip:SetText(self_.spellName or "?", 1, 1, 1)
                GameTooltip:AddLine(self_.known and "Click to cast" or "Not learned yet", 0.6, 0.6, 0.6)
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
            self.buttons[i] = b
        end
        b.spellName = name
        b:SetAttribute("spell", name)
        local info = D.GetSpellInfo(name)
        b.spellID = info and info.spellID
        b.known = info ~= nil
        b.icon:SetTexture((info and info.icon) or "Interface\\Icons\\INV_Misc_QuestionMark")
        b.icon:SetDesaturated(not b.known)
        b.icon:SetAlpha(b.known and 1 or 0.4)
        b.label:SetText("")
        b:ClearAllPoints()
        b:SetPoint("LEFT", self.frame, "LEFT", PAD + (i - 1) * (ICON + GAP), 0)
        b:Show()
        shown = i
    end
    for i = shown + 1, #self.buttons do self.buttons[i]:Hide() end
    self.frame:SetSize(math.max(ICON, shown * ICON + math.max(0, shown - 1) * GAP) + PAD * 2, ICON + PAD * 2)
    self:Refresh()
end

function Proto:Refresh()
    if not self.frame or not self.frame:IsShown() then return end
    for _, b in ipairs(self.buttons or {}) do
        if b:IsShown() and b.spellID then
            local cd = D.GetSpellCooldown(b.spellID)
            -- Secret in combat. Straight through, never read.
            if cd and cd.start ~= nil and cd.duration ~= nil then
                pcall(b.cd.SetCooldown, b.cd, cd.start, cd.duration, cd.modRate)
            end
        end
    end
end

function Proto:SetShown(on)
    local s = self:Store()
    if s then s.shown = on and true or false end
    self:Build()
    if on then self.frame:Show(); self:Rebuild() else self.frame:Hide() end
end

function Proto:Toggle()
    local s = self:Store()
    self:SetShown(not (s and s.shown))
    return s and s.shown
end

function Proto:SetLocked(locked)
    local s = self:Store()
    if s then s.locked = locked and true or false end
end

function Proto:IsLocked()
    local s = self:Store()
    return not s or s.locked ~= false
end

-- Restore on login, once the profile is bound.
function Proto:Init()
    local s = self:Store()
    if s and s.shown then self:SetShown(true) end
end

-- The options row every product shows, so the bar is discoverable without
-- knowing the slash command. Off until the player turns it on.
function Proto:OptionRow(page, y)
    local O = Core.Options
    y = O:Check(page, "Show the cooldown bar",
        function() local s = self:Store(); return s and s.shown == true end,
        function(v) self:SetShown(v) end, y)
    y = O:Check(page, "Lock the cooldown bar",
        function() return self:IsLocked() end,
        function(v) self:SetLocked(v) end, y)
    y = O:Note(page, "A row of icons for the spells you name, since the game's own cooldown manager is empty for some classes. Edit it with the cd command: add, remove, list, import, export, reset.", y)
    return y
end

-- One slash handler a product can delegate its "cd" subcommand to.
-- Returns true when it handled the input.
function Proto:Command(rest)
    local A = self.addon
    rest = Core.trim(tostring(rest or ""))
    local verb, arg = rest:match("^(%S*)%s*(.*)$")
    verb = (verb or ""):lower()
    if verb == "" or verb == "toggle" then
        A:Print("cooldown bar " .. (self:Toggle() and "shown" or "hidden") .. ".")
    elseif verb == "add" then
        local ok, why = self:Add(arg)
        A:Print(ok and ("added " .. tostring(why)) or ("add: " .. tostring(why)))
    elseif verb == "remove" or verb == "rem" then
        local ok, why = self:Remove(arg)
        A:Print(ok and ("removed " .. tostring(why)) or ("remove: " .. tostring(why)))
    elseif verb == "list" then
        local list = self:List()
        A:Print(#list == 0 and "the bar is empty." or ("bar: " .. table.concat(list, ", ")))
    elseif verb == "export" then
        Core.Options:ShowExport(A, self:Export())
    elseif verb == "import" then
        Core.Options:ShowExport(A, "", function(text)
            local ok, why = self:Import(text)
            A:Print(ok and ("imported " .. tostring(why) .. " spells") or ("import: " .. tostring(why)))
        end)
    elseif verb == "reset" then
        self:Reset()
        A:Print("bar reset to the default for your class.")
    elseif verb == "lock" then
        self:SetLocked(true); A:Print("cooldown bar locked.")
    elseif verb == "unlock" then
        self:SetLocked(false); A:Print("cooldown bar unlocked: drag it into place, then lock.")
    else
        A:Print("cd: toggle | add <spell> | remove <spell> | list | import | export | reset | lock | unlock")
    end
    return true
end
