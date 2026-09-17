-- WickCore
-- Options.lua — one "Wick's Mods" entry in the game's options, a page per product.
--
-- A:RegisterOptions(function(page, A)
--     local y = Core.Options:Heading(page, "General", -8)
--     y = Core.Options:Check(page, "Lock window", function() return A.db.profile.locked end,
--                            function(v) A.db.profile.locked = v end, y)
-- end)

local ADDON = ...
local Core = LibStub("WickCore-1.0", true)
if not Core or Core._sourceAddon ~= ADDON then return end

local Options = {}
Core.Options = Options
Options.pages = Options.pages or {}

local Chrome = Core.Chrome
local ROOT_TITLE = "Wick's Mods"

local hasSettings = rawget(_G, "Settings") and Settings.RegisterCanvasLayoutCategory and true or false
local hasLegacy   = rawget(_G, "InterfaceOptions_AddCategory") and true or false

local function paintPage(frame)
    local bg = Chrome:Texture(frame, "BACKGROUND", Chrome.Colors.void)
    bg:SetAllPoints()
end

local function ensureRoot()
    if Options.root then return Options.root end
    local frame = CreateFrame("Frame")
    frame:Hide()
    frame.name = ROOT_TITLE
    paintPage(frame)

    frame:SetScript("OnShow", function(f)
        if f.built then return end
        f.built = true
        local title = Chrome:Text(f, 16)
        title:SetPoint("TOPLEFT", 16, -16)
        title:SetText(Chrome:TitleMarkup("Wick's Mods"))
        local sub = Chrome:Text(f, 11, Chrome.Colors.muted)
        sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
        sub:SetText("Precision addons for World of Warcraft: Forever. Each addon has its own page below.")
        local y = -64
        for _, A in Core:IterateAddons() do
            if A ~= Core.self then
                local line = Chrome:Text(f, 12)
                line:SetPoint("TOPLEFT", 16, y)
                line:SetText(Chrome:TitleMarkup(A.title) .. "  |cff8F8770" .. tostring(A.version or "") .. "|r")
                y = y - 18
            end
        end
        y = y - 12
        Options:ThemeSection(f, 16, y)

        local client = Chrome:Text(f, 11, Chrome.Colors.muted)
        client:SetPoint("BOTTOMLEFT", 16, 16)
        client:SetText(table.concat(Core.Client:Report(), "  |  "))
    end)

    local root = { frame = frame }
    if hasSettings then
        root.category = Settings.RegisterCanvasLayoutCategory(frame, ROOT_TITLE)
        if Settings.RegisterAddOnCategory then Settings.RegisterAddOnCategory(root.category) end
    elseif hasLegacy then
        InterfaceOptions_AddCategory(frame)
    end
    Options.root = root
    return root
end

-- Theme picker: one swatch per theme, the active one bracketed in its own
-- accent, plus a check to follow the player's class.
function Options:ThemeSection(parent, x, y)
    local C = Chrome.Colors
    local head = Chrome:Heading(parent, "Theme")
    head:SetPoint("TOPLEFT", x, y)
    y = y - 22
    local swatches = {}
    local function refresh()
        local setting = Chrome:ThemeSetting()
        for _, sw in ipairs(swatches) do
            local on = sw.theme.id == Chrome.activeTheme
            sw.ring:SetShown(on)
            sw.label:SetTextColor(on and C.fel[1] or C.muted[1], on and C.fel[2] or C.muted[2], on and C.fel[3] or C.muted[3], 1)
        end
        if parent.themeAuto then parent.themeAuto.Refresh() end
        if parent.themeNote then
            local t = Chrome.ThemeByID[Chrome.activeTheme]
            parent.themeNote:SetText(setting == "auto" and ("Following your class: " .. (t and t.name or "?"))
                or ((t and t.name or "?") .. (t and t.class and (" is the " .. t.class:sub(1, 1) .. t.class:sub(2):lower() .. " theme.") or "")))
        end
    end
    local SW = 56
    for i, t in ipairs(Chrome.Themes) do
        local b = CreateFrame("Button", nil, parent)
        b:SetSize(SW, 40)
        b:SetPoint("TOPLEFT", x + (i - 1) * (SW + 6), y)
        local bg = b:CreateTexture(nil, "BACKGROUND")
        bg:SetColorTexture(t.colors.void[1], t.colors.void[2], t.colors.void[3], 1)
        bg:SetPoint("TOPLEFT", 0, 0); bg:SetPoint("BOTTOMRIGHT", 0, 14)
        local strip = b:CreateTexture(nil, "ARTWORK")
        strip:SetColorTexture(t.colors.shadow[1], t.colors.shadow[2], t.colors.shadow[3], 1)
        strip:SetPoint("TOPLEFT", 1, -1); strip:SetPoint("TOPRIGHT", -1, -1); strip:SetHeight(7)
        local acc = b:CreateTexture(nil, "OVERLAY")
        acc:SetColorTexture(t.colors.fel[1], t.colors.fel[2], t.colors.fel[3], 1)
        acc:SetPoint("BOTTOMLEFT", bg, "BOTTOMLEFT", 4, 4); acc:SetSize(SW - 8, 3)
        local edge = b:CreateTexture(nil, "BORDER")
        edge:SetColorTexture(t.colors.border[1], t.colors.border[2], t.colors.border[3], 1)
        edge:SetPoint("BOTTOMLEFT", bg, "BOTTOMLEFT", 0, 0); edge:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", 0, 0); edge:SetHeight(1)
        local ring = b:CreateTexture(nil, "OVERLAY")
        ring:SetColorTexture(t.colors.fel[1], t.colors.fel[2], t.colors.fel[3], 1)
        ring:SetPoint("TOPLEFT", bg, "TOPLEFT", 0, 0); ring:SetPoint("TOPRIGHT", bg, "TOPRIGHT", 0, 0); ring:SetHeight(2)
        ring:Hide()
        b.ring = ring
        b.label = Chrome:Text(b, 10, C.muted)
        b.label:SetPoint("BOTTOM", 0, 0)
        b.label:SetText(t.name)
        b.theme = t
        b:SetScript("OnClick", function() Chrome:SetTheme(t.id); refresh() end)
        b:SetScript("OnEnter", function()
            GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
            GameTooltip:SetText(t.name, 1, 1, 1)
            if t.class then GameTooltip:AddLine(t.class:sub(1, 1) .. t.class:sub(2):lower() .. " theme", 0.6, 0.6, 0.6) end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        swatches[#swatches + 1] = b
    end
    y = y - 46
    parent.themeAuto = Chrome:Check(parent, "Follow my class",
        function() return Chrome:ThemeSetting() == "auto" end,
        function(v) Chrome:SetTheme(v and "auto" or Chrome.activeTheme); refresh() end)
    parent.themeAuto:SetPoint("TOPLEFT", x, y)
    parent.themeNote = Chrome:Text(parent, 10, C.muted)
    parent.themeNote:SetPoint("LEFT", parent.themeAuto, "RIGHT", 20, 0)
    y = y - 22
    parent.themeClassic = Chrome:Check(parent, "Classic-era class colors (the set TBC UIs show)",
        function() return Chrome.classColorSet == "classic" end,
        function(v) Chrome:SetClassColorSet(v and "classic" or "client"); refresh() end)
    parent.themeClassic:SetPoint("TOPLEFT", x, y)
    parent.themeClassic:SetWidth(360)
    y = y - 22
    refresh()
    Chrome:OnThemeChanged(refresh)
    return y
end

-- Register a page for an addon. buildFn(page, addon) runs on first show.
function Options:Register(addon, buildFn)
    local root = ensureRoot()
    local page = CreateFrame("Frame")
    page:Hide()
    page.name = addon.title
    page.parent = ROOT_TITLE
    paintPage(page)
    page:SetScript("OnShow", function(p)
        if p.built then return end
        p.built = true
        local title = Chrome:Text(p, 16)
        title:SetPoint("TOPLEFT", 16, -16)
        title:SetText(Chrome:TitleMarkup(addon.title))
        local ver = Chrome:Text(p, 11, Chrome.Colors.muted)
        ver:SetPoint("LEFT", title, "RIGHT", 10, 0)
        ver:SetText(tostring(addon.version or ""))
        local body = CreateFrame("Frame", nil, p)
        body:SetPoint("TOPLEFT", 16, -48)
        body:SetPoint("BOTTOMRIGHT", -16, 16)
        p.body = body
        Core.safe(buildFn, body, addon)
    end)

    local entry = { frame = page }
    if hasSettings and root.category and Settings.RegisterCanvasLayoutSubcategory then
        entry.category = Settings.RegisterCanvasLayoutSubcategory(root.category, page, addon.title)
    elseif hasLegacy then
        InterfaceOptions_AddCategory(page)
    end
    self.pages[addon.name] = entry
    return page
end

function Options:Open(addonName)
    local entry = addonName and self.pages[addonName] or self.root
    if not entry then return end
    if hasSettings and Settings.OpenToCategory and entry.category then
        local id = entry.category.GetID and entry.category:GetID() or entry.category.ID
        Settings.OpenToCategory(id)
    elseif rawget(_G, "InterfaceOptionsFrame_OpenToCategory") then
        InterfaceOptionsFrame_OpenToCategory(entry.frame)
        InterfaceOptionsFrame_OpenToCategory(entry.frame)
    end
end

-- ============================================================
-- Layout helpers: each returns the next y offset
-- ============================================================

function Options:Heading(parent, text, y)
    local fs = Chrome:Heading(parent, text)
    fs:SetPoint("TOPLEFT", 0, y)
    return y - 22
end

function Options:Check(parent, label, get, set, y)
    local c = Chrome:Check(parent, label, get, set)
    c:SetPoint("TOPLEFT", 0, y)
    return y - 22
end

function Options:Button(parent, text, onClick, y, width)
    local b = Chrome:Button(parent, text, width)
    b:SetPoint("TOPLEFT", 0, y)
    b:SetScript("OnClick", onClick)
    return y - 28
end

function Options:Note(parent, text, y)
    local fs = Chrome:Text(parent, 11, Chrome.Colors.muted)
    fs:SetPoint("TOPLEFT", 0, y)
    fs:SetWidth(520)
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    return y - 18 - (select(2, text:gsub("\n", "")) * 13)
end

-- Standard profile controls every product gets for free.
function Options:ProfileSection(parent, addon, y)
    local db = addon.db
    if not db then return y end
    y = self:Heading(parent, "Profiles", y)
    y = self:Note(parent, "Current: " .. db:GetCurrentProfile() .. "   Keyed by: " .. db:GetKeyMode(), y)
    for _, mode in ipairs({ "char", "spec", "class", "mode" }) do
        y = self:Check(parent, "Key profiles by " .. mode,
            function() return db:GetKeyMode() == mode end,
            function(v) if v then db:SetKeyMode(mode) end end, y)
    end
    y = self:Button(parent, "Reset profile", function() db:ResetProfile() end, y, 110)
    y = self:Button(parent, "Copy export string", function()
        Options:ShowExport(addon, db:Export())
    end, y, 150)
    return y
end

-- A panel with a selectable EditBox holding an export string, or accepting an import.
function Options:ShowExport(addon, text, onImport)
    if not self.exportPanel then
        local p = Chrome:NewPanel("WickCoreExportFrame", { title = "Wick's Export", width = 520, height = 200, strata = "DIALOG" })
        local eb = CreateFrame("EditBox", nil, p.content)
        eb:SetMultiLine(true)
        eb:SetAutoFocus(true)
        eb:SetFontObject("GameFontHighlightSmall")
        eb:SetAllPoints()
        eb:SetScript("OnEscapePressed", function() p:Hide() end)
        p.editBox = eb
        self.exportPanel = p
    end
    local p = self.exportPanel
    p.title:SetText(Chrome:TitleMarkup(addon.title) .. "  |cff8F8770" .. (onImport and "import" or "export") .. "|r")
    p.editBox:SetText(text or "")
    p.editBox:HighlightText()
    p.editBox:SetScript("OnEnterPressed", function(eb)
        if onImport then onImport(eb:GetText()); p:Hide() end
    end)
    p:Show()
end
