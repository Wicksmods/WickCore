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
--
-- And nothing here is a secure button. These icons track; they do not
-- cast. They were SecureActionButtonTemplate with type=spell, which
-- bought a click to cast and cost the ability to change anything during
-- a fight, because attributes on a secure button cannot be set in
-- combat. A cooldown tracker that cannot be rebuilt in combat is the
-- wrong way round, so the casting went and the bar can now be rebuilt,
-- rescaled and rewrapped whenever.

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
    -- A tracker you cannot read is no use, and one icon size does not
    -- suit every screen.
    if type(s.scale) ~= "number" then s.scale = 1 end
    -- 0 means one row however long the list gets.
    if type(s.perRow) ~= "number" then s.perRow = 0 end
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
    f:SetScript("OnDragStart", function(fr)
        if Chrome:DragAllowed(s and s.locked) then fr:StartMoving() end
    end)
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

-- A frame's point offsets are read in the frame's own scale, so a bare
-- SetScale walks the bar across the screen. Convert the offsets by the
-- ratio of the two scales and it stays where it was put.
function Proto:ApplyScale(scale)
    local f = self.frame
    if not f then return end
    local old = tonumber(f:GetScale()) or 1
    if math.abs(old - scale) < 0.001 then return end

    local point, rel, relPoint, x, y = f:GetPoint()
    f:SetScale(scale)
    if not (point and x and y) then return end

    local k = old / scale
    f:ClearAllPoints()
    f:SetPoint(point, rel or UIParent, relPoint or point, x * k, y * k)
    local st = self:Store()
    if st and st.window then Chrome:SavePosition(f, st.window) end
end

function Proto:Rebuild()
    if not self.frame then return end
    local list = self:List()
    local s = self:Store()
    local perRow = math.max(0, math.floor(tonumber(s and s.perRow) or 0))
    local scale = tonumber(s and s.scale) or 1
    if scale < 0.5 then scale = 0.5 elseif scale > 2.5 then scale = 2.5 end
    self.buttons = self.buttons or {}
    local shown = 0
    for i, name in ipairs(list) do
        local b = self.buttons[i]
        if not b then
            b = CreateFrame("Button", nil, self.frame)
            b:SetSize(ICON, ICON)
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
                GameTooltip:AddLine(self_.known and "Tracked" or "Not learned yet", 0.6, 0.6, 0.6)
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
            self.buttons[i] = b
        end
        b.spellName = name
        local info = D.GetSpellInfo(name)
        b.spellID = info and info.spellID
        b.known = info ~= nil
        b.icon:SetTexture((info and info.icon) or "Interface\\Icons\\INV_Misc_QuestionMark")
        -- Ready until a cooldown says otherwise: a freshly drawn bar
        -- should not look as though everything is on cooldown.
        self:SetReady(b, b.ready ~= false)
        b.label:SetText("")
        b:ClearAllPoints()
        local col, row = i - 1, 0
        if perRow > 0 then
            col = (i - 1) % perRow
            row = math.floor((i - 1) / perRow)
        end
        b:SetPoint("TOPLEFT", self.frame, "TOPLEFT",
            PAD + col * (ICON + GAP), -(PAD + row * (ICON + GAP)))
        b:Show()
        shown = i
    end
    for i = shown + 1, #self.buttons do self.buttons[i]:Hide() end

    local cols = (perRow > 0) and math.min(shown, perRow) or shown
    local rows = (perRow > 0) and math.ceil(shown / perRow) or 1
    self.frame:SetSize(
        math.max(ICON, cols * ICON + math.max(0, cols - 1) * GAP) + PAD * 2,
        math.max(ICON, rows * ICON + math.max(0, rows - 1) * GAP) + PAD * 2)
    -- Scale rather than resize: the icons, the borders and the cooldown
    -- swirl all move together and nothing has to be laid out twice.
    self:ApplyScale(scale)
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
            -- Whether it is ready, which is the question the bar is for.
            -- isActive survives combat as a plain boolean while the
            -- times do not, so this reads it rather than comparing a
            -- start against a duration, which would be reading secrets.
            local active = cd and cd.active
            if active ~= nil and not R:IsSecret(active) then
                self:SetReady(b, active ~= true)
            end
        end
    end
end

-- One place that decides how an icon looks, since three things want a
-- say: whether the spell is learned, whether it is ready, and the
-- redraw that happens before any cooldown has been read.
function Proto:SetReady(b, ready)
    if not b.known then
        b.icon:SetDesaturated(true)
        b.icon:SetAlpha(0.4)
        return
    end
    b.ready = ready
    b.icon:SetDesaturated(not ready)
    b.icon:SetAlpha(ready and 1 or 0.55)
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

-- Clamped rather than refused: a number out of range is a typo, not a
-- reason to do nothing and say nothing.
function Proto:SetScale(v)
    local s = self:Store()
    v = tonumber(v)
    if not s or not v then return nil end
    if v < 0.5 then v = 0.5 elseif v > 2.5 then v = 2.5 end
    s.scale = v
    self:Rebuild()
    return v
end

function Proto:SetPerRow(n)
    local s = self:Store()
    n = tonumber(n)
    if not s or not n then return nil end
    n = math.max(0, math.floor(n))
    s.perRow = n
    self:Rebuild()
    return n
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
-- One wording for both places these appear.
local SCALE_OPTS = { step = 0.1, format = "%.1fx" }
local ROW_OPTS = { step = 1, text = function(v)
    return v > 0 and tostring(v) or "one row"
end }

function Proto:OptionRow(page, y)
    local O = Core.Options
    y = O:Check(page, "Show the cooldown bar",
        function() local s = self:Store(); return s and s.shown == true end,
        function(v) self:SetShown(v) end, y)
    y = O:Check(page, "Lock the cooldown bar",
        function() return self:IsLocked() end,
        function(v) self:SetLocked(v) end, y)
    y = O:Stepper(page, "Icon scale",
        function() local s = self:Store(); return s and s.scale or 1 end,
        function(v) self:SetScale(v) end, y, SCALE_OPTS)
    y = O:Stepper(page, "Icons per row",
        function() local s = self:Store(); return s and s.perRow or 0 end,
        function(v) self:SetPerRow(v) end, y, ROW_OPTS)
    y = O:Note(page, "A row of icons for the spells you name, since the game's own cooldown manager is empty for some classes. Edit it with the cd command: add, remove, list, import, export, reset.", y)
    return y
end

-- ============================================================
-- The kit tab
-- ============================================================
-- The same controls as the options row, plus the list itself, so the bar
-- can be built without leaving the kit window.

local ROW_H = 22

function Proto:AttachPane(pane)
    self.pane = pane
    pane.note = Chrome:Text(pane, 10, C.muted)
    pane.note:SetPoint("TOPLEFT", 0, 0)
    pane.note:SetWidth(380)
    pane.note:SetJustifyH("LEFT")
    pane.note:SetText("The game's own cooldown manager is empty for some classes and cannot be added to. This row is ours: name the spells you want to watch.")

    pane.showCheck = Chrome:Check(pane, "Show the bar",
        function() local st = self:Store(); return st and st.shown == true end,
        function(v) self:SetShown(v); self:RefreshPane() end)
    pane.showCheck:SetPoint("TOPLEFT", 0, -30)
    pane.lockCheck = Chrome:Check(pane, "Locked",
        function() return self:IsLocked() end,
        function(v) self:SetLocked(v) end)
    pane.lockCheck:SetPoint("TOPLEFT", 150, -30)

    pane.scaleStep = Chrome:Stepper(pane, "Icon scale",
        function() local st = self:Store(); return st and st.scale or 1 end,
        function(v) self:SetScale(v) end, SCALE_OPTS)
    pane.scaleStep:SetPoint("TOPLEFT", 0, -54)
    pane.rowStep = Chrome:Stepper(pane, "Icons per row",
        function() local st = self:Store(); return st and st.perRow or 0 end,
        function(v) self:SetPerRow(v) end, ROW_OPTS)
    pane.rowStep:SetPoint("TOPLEFT", 240, -54)

    pane.listTop = -80
    pane.rows = {}
    pane.empty = Chrome:Text(pane, 11, C.muted)
    pane.empty:SetPoint("TOPLEFT", 0, pane.listTop)

    local add = Chrome:Button(pane, "Add spell", 80, 20)
    add:SetPoint("BOTTOMLEFT", 0, 0)
    add:SetScript("OnClick", function()
        Core.Options:ShowExport(self.addon, "", function(text)
            local ok, why = self:Add(text)
            self.addon:Print(ok and ("added " .. tostring(why)) or ("add: " .. tostring(why)))
            self:RefreshPane()
        end)
    end)
    local imp = Chrome:Button(pane, "Import", 70, 20)
    imp:SetPoint("LEFT", add, "RIGHT", 6, 0)
    imp:SetScript("OnClick", function()
        Core.Options:ShowExport(self.addon, "", function(text)
            local ok, why = self:Import(text)
            self.addon:Print(ok and ("imported " .. tostring(why) .. " spells") or ("import: " .. tostring(why)))
            self:RefreshPane()
        end)
    end)
    local exp = Chrome:Button(pane, "Export", 70, 20)
    exp:SetPoint("LEFT", imp, "RIGHT", 6, 0)
    exp:SetScript("OnClick", function() Core.Options:ShowExport(self.addon, self:Export()) end)
    local rst = Chrome:Button(pane, "Reset", 70, 20)
    rst:SetPoint("LEFT", exp, "RIGHT", 6, 0)
    rst:SetScript("OnClick", function() self:Reset(); self:RefreshPane() end)

    self:RefreshPane()
end

function Proto:RefreshPane()
    local pane = self.pane
    if not pane then return end
    if pane.showCheck and pane.showCheck.Refresh then pane.showCheck.Refresh() end
    if pane.lockCheck and pane.lockCheck.Refresh then pane.lockCheck.Refresh() end
    local list = self:List()
    pane.empty:SetShown(#list == 0)
    pane.empty:SetText("Nothing tracked yet. Add a spell, or import a list.")
    local y = pane.listTop
    for i, name in ipairs(list) do
        local r = pane.rows[i]
        if not r then
            r = CreateFrame("Frame", nil, pane)
            r:SetSize(380, ROW_H)
            r.icon = r:CreateTexture(nil, "ARTWORK")
            r.icon:SetSize(16, 16)
            r.icon:SetPoint("LEFT", 2, 0)
            r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            r.name = Chrome:Text(r, 11)
            r.name:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
            r.del = Chrome:Button(r, "x", 18, 18)
            r.del:SetPoint("RIGHT", 0, 0)
            pane.rows[i] = r
        end
        local info = D.GetSpellInfo(name)
        r.icon:SetTexture((info and info.icon) or "Interface\\Icons\\INV_Misc_QuestionMark")
        r.icon:SetDesaturated(info == nil)
        r.name:SetText(name .. (info and "" or "  (not learned)"))
        r.del:SetScript("OnClick", function() self:Remove(name); self:RefreshPane() end)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 0, y)
        r:Show()
        y = y - ROW_H
    end
    for i = #list + 1, #pane.rows do pane.rows[i]:Hide() end
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
    elseif verb == "scale" then
        local v = self:SetScale(arg)
        A:Print(v and ("bar scale " .. ("%.1f"):format(v) .. "x.")
            or "scale: give me a number between 0.5 and 2.5.")
    elseif verb == "row" or verb == "rows" or verb == "perrow" then
        local n = self:SetPerRow(arg)
        A:Print(n and (n > 0 and ("wrapping every " .. n .. " icons.")
            or "one row, however long the list gets.")
            or "row: give me a number, or 0 for one row.")
    elseif verb == "lock" then
        self:SetLocked(true); A:Print("cooldown bar locked.")
    elseif verb == "unlock" then
        self:SetLocked(false); A:Print("cooldown bar unlocked: drag it into place, then lock.")
    else
        A:Print("cd: toggle | add <spell> | remove <spell> | list | scale <n> | row <n> | import | export | reset | lock | unlock")
    end
    return true
end
