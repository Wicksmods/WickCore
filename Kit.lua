-- WickCore
-- Kit.lua — the class kit panel: Talents, Checklist, Racials in one window.
--
-- local kit = WickCore.Kit:New(A, {
--     checklist = { ...Checklist definitions... },
--     racials   = true,
--     builds    = { { name = "...", text = "...", note = "..." } },   -- optional seed
-- })
-- kit:Toggle()

local ADDON = ...
local Core = LibStub("WickCore-1.0", true)
if not Core or Core._sourceAddon ~= ADDON then return end

local Kit = {}
Core.Kit = Kit

local Chrome, Talents, Checklist, Racials, R = Core.Chrome, Core.Talents, Core.Checklist, Core.Racials, Core.Restrict
local C = Chrome.Colors

local Proto = {}
Proto.__index = Proto

local TAB_H = 22

function Kit:New(addon, opts)
    opts = opts or {}
    local kit = setmetatable({ addon = addon, opts = opts }, Proto)
    if opts.checklist then kit.checklist = Checklist:New(addon, opts.checklist) end
    Talents:Bind(addon)
    if opts.builds then Talents:Seed(opts.builds) end
    addon.kit = kit
    return kit
end

-- ============================================================
-- Panel
-- ============================================================

function Proto:Build()
    if self.panel then return self.panel end
    local A = self.addon
    local db = A.db and A.db.profile
    if db and not db.kitWindow then db.kitWindow = {} end

    local p = Chrome:NewPanel("Wick" .. A.name .. "Kit", {
        title = A.title, width = 420, height = 320, strata = "DIALOG",
        resizable = true, minWidth = 360, minHeight = 240, db = db and db.kitWindow,
    })
    self.panel = p

    -- Tab strip
    local strip = CreateFrame("Frame", nil, p)
    strip:SetPoint("TOPLEFT", 1, -Chrome.HEADER_H - 1)
    strip:SetPoint("TOPRIGHT", -1, -Chrome.HEADER_H - 1)
    strip:SetHeight(TAB_H)
    local sbg = Chrome:Texture(strip, "BACKGROUND", C.shadow); sbg:SetAllPoints()
    local sdiv = Chrome:Texture(strip, "BORDER", C.border)
    sdiv:SetPoint("BOTTOMLEFT"); sdiv:SetPoint("BOTTOMRIGHT"); sdiv:SetHeight(1)

    p.content:ClearAllPoints()
    p.content:SetPoint("TOPLEFT", 10, -Chrome.HEADER_H - TAB_H - 10)
    p.content:SetPoint("BOTTOMRIGHT", -10, 10)

    self.tabs, self.panes = {}, {}
    local defs = { { id = "talents", label = "Talents" }, { id = "checklist", label = "Checklist" }, { id = "racials", label = "Racials" } }
    local x = 8
    for _, t in ipairs(defs) do
        if (t.id ~= "checklist" or self.checklist) and (t.id ~= "racials" or self.opts.racials ~= false) then
            local b = CreateFrame("Button", nil, strip)
            b:SetSize(80, TAB_H)
            b:SetPoint("LEFT", x, 0)
            b.lbl = Chrome:Text(b, 11, C.muted)
            b.lbl:SetPoint("CENTER")
            b.lbl:SetText(t.label)
            b.under = Chrome:Texture(b, "OVERLAY", C.fel)
            b.under:SetPoint("BOTTOMLEFT", 8, 0); b.under:SetPoint("BOTTOMRIGHT", -8, 0); b.under:SetHeight(2)
            b.under:Hide()
            b:SetScript("OnClick", function() self:Select(t.id) end)
            self.tabs[t.id] = b
            local pane = CreateFrame("Frame", nil, p.content)
            pane:SetAllPoints()
            pane:Hide()
            self.panes[t.id] = pane
            x = x + 84
        end
    end

    self:BuildTalents(self.panes.talents)
    if self.panes.checklist then self:BuildChecklist(self.panes.checklist) end
    if self.panes.racials then self:BuildRacials(self.panes.racials) end

    p:SetScript("OnShow", function() self:Refresh() end)
    R:OnChange(function() if p:IsShown() then self:Refresh() end end)
    self:Select("talents")
    return p
end

function Proto:Select(id)
    self.active = id
    for tid, b in pairs(self.tabs) do
        local on = tid == id
        b.lbl:SetTextColor(on and C.fel[1] or C.muted[1], on and C.fel[2] or C.muted[2], on and C.fel[3] or C.muted[3], 1)
        if on then b.under:Show() else b.under:Hide() end
        if on then self.panes[tid]:Show() else self.panes[tid]:Hide() end
    end
    self:Refresh()
end

function Proto:Toggle()
    self:Build()
    self.panel:Toggle()
end

function Proto:Show() self:Build(); self.panel:Show() end

function Proto:Refresh()
    if not self.panel or not self.panel:IsShown() then return end
    if self.active == "talents" then self:RefreshTalents()
    elseif self.active == "checklist" and self.checklist then self.checklist:Refresh()
    elseif self.active == "racials" then Racials:Refresh() end
end

-- ============================================================
-- Talents tab
-- ============================================================

function Proto:BuildTalents(pane)
    local y = 0
    pane.summary = Chrome:Text(pane, 11)
    pane.summary:SetPoint("TOPLEFT", 0, y)
    pane.summary:SetText("")
    y = y - 20

    local row = CreateFrame("Frame", nil, pane)
    row:SetPoint("TOPLEFT", 0, y); row:SetSize(380, 24)
    local exportBtn = Chrome:Button(row, "Export", 70)
    exportBtn:SetPoint("LEFT", 0, 0)
    exportBtn:SetScript("OnClick", function()
        local str, why = Talents:Export()
        if str then Core.Options:ShowExport(self.addon, str)
        else self.addon:Print("export: " .. tostring(why)) end
    end)
    local importBtn = Chrome:Button(row, "Import", 70)
    importBtn:SetPoint("LEFT", exportBtn, "RIGHT", 6, 0)
    importBtn:SetScript("OnClick", function()
        Core.Options:ShowExport(self.addon, "", function(text)
            local ok, why = Talents:Import(text, "Imported")
            self.addon:Print(ok and "build imported as a new loadout" or ("import: " .. tostring(why)))
            self:RefreshTalents()
        end)
    end)
    local saveBtn = Chrome:Button(row, "Save current", 96)
    saveBtn:SetPoint("LEFT", importBtn, "RIGHT", 6, 0)
    saveBtn:SetScript("OnClick", function()
        local ok, why = Talents:SaveCurrent()
        self.addon:Print(ok and "build saved" or ("save: " .. tostring(why)))
        self:RefreshTalents()
    end)
    y = y - 30

    pane.listHead = Chrome:Heading(pane, "Saved builds")
    pane.listHead:SetPoint("TOPLEFT", 0, y)
    y = y - 20
    pane.listTop = y
    pane.rows = {}
    pane.empty = Chrome:Text(pane, 11, C.muted)
    pane.empty:SetPoint("TOPLEFT", 0, y)
    pane.empty:SetText(Talents:IsAvailable() and "None yet. Save the current build, or import a string."
        or "This client has no trait talent system.")
end

function Proto:RefreshTalents()
    local pane = self.panes.talents
    if not pane then return end
    local s = Talents:Summary()
    if s then
        local parts = {}
        for _, c in ipairs(s.spent) do parts[#parts + 1] = tostring(c.spent) end
        pane.summary:SetText(("Active: %s%s"):format(tostring(s.name or "loadout"),
            #parts > 0 and ("   points " .. table.concat(parts, " / ")) or ""))
    else
        pane.summary:SetText(Talents:IsAvailable() and "Active: (none)" or "Talents unavailable on this client")
    end
    local list = Talents:List()
    pane.empty:SetShown(#list == 0)
    local y = pane.listTop
    for i, build in ipairs(list) do
        local r = pane.rows[i]
        if not r then
            r = CreateFrame("Frame", nil, pane)
            r:SetSize(380, 22)
            r.name = Chrome:Text(r, 11)
            r.name:SetPoint("LEFT", 2, 0)
            r.note = Chrome:Text(r, 10, C.muted)
            r.note:SetPoint("LEFT", r.name, "RIGHT", 8, 0)
            r.apply = Chrome:Button(r, "Apply", 56, 18)
            r.apply:SetPoint("RIGHT", -60, 0)
            r.del = Chrome:Button(r, "x", 18, 18)
            r.del:SetPoint("RIGHT", -38, 0)
            r.copy = Chrome:Button(r, "Copy", 36, 18)
            r.copy:SetPoint("RIGHT", 0, 0)
            pane.rows[i] = r
        end
        r.name:SetText(build.name or ("Build " .. i))
        r.note:SetText(build.curated and "curated" or (build.note or ""))
        r.apply:SetScript("OnClick", function()
            local ok, why = Talents:Apply(build)
            self.addon:Print(ok and ("applied " .. tostring(build.name)) or ("apply: " .. tostring(why)))
        end)
        r.del:SetScript("OnClick", function() Talents:Delete(i); self:RefreshTalents() end)
        r.copy:SetScript("OnClick", function() Core.Options:ShowExport(self.addon, build.text) end)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 0, y)
        r:Show()
        y = y - 24
    end
    for i = #list + 1, #pane.rows do pane.rows[i]:Hide() end
end

-- ============================================================
-- Checklist tab
-- ============================================================

function Proto:BuildChecklist(pane)
    pane.note = Chrome:Text(pane, 10, C.muted)
    pane.note:SetPoint("TOPLEFT", 0, 0)
    pane.note:SetText("Read from your own auras out of combat. Rows go quiet the moment combat starts.")
    self.checklist:Attach(pane, -20, 380)
end

-- ============================================================
-- Racials tab
-- ============================================================

function Proto:BuildRacials(pane)
    local data, token = Racials:ForPlayer()
    pane.head = Chrome:Text(pane, 11)
    pane.head:SetPoint("TOPLEFT", 0, 0)
    pane.head:SetText(data and ("Actives for " .. tostring(token)) or ("No racial data for " .. tostring(token)))
    local y = -22
    if data then
        y = Racials:Attach(pane, y)
        pane.passives = Chrome:Text(pane, 10, C.muted)
        pane.passives:SetPoint("TOPLEFT", 0, y - 6)
        pane.passives:SetText("Passives: " .. table.concat(data.passives or {}, ", "))
    end
    pane.credit = Chrome:Text(pane, 9, C.muted)
    pane.credit:SetPoint("BOTTOMLEFT", 0, 0)
    pane.credit:SetText(Racials.ATTRIBUTION)
end
