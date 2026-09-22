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
        if parent.themePickers then for _, pk in ipairs(parent.themePickers) do pk.Paint() end end
        for _, sw in ipairs(swatches) do
            if sw.Paint then sw.Paint() end
            local on = sw.theme.id == Chrome.activeTheme
            sw.ring:SetShown(on)
            sw.label:SetTextColor(on and C.fel[1] or C.muted[1], on and C.fel[2] or C.muted[2], on and C.fel[3] or C.muted[3], 1)
        end
        if parent.themeAuto then parent.themeAuto.Refresh() end
        if parent.themeNote then
            local t = Chrome.ThemeByID[Chrome.activeTheme]
            parent.themeNote:SetText(setting == "auto" and ("Following your class: " .. (t and t.name or "?"))
                or (t and t.custom and "Custom: your main and accent colors."
                or ((t and t.name or "?") .. (t and t.class and (" is the " .. t.class:sub(1, 1) .. t.class:sub(2):lower() .. " theme.") or ""))))
        end
    end
    local SW = 52
    for i, def in ipairs(Chrome.Themes) do
        local id = def.id
        local b = CreateFrame("Button", nil, parent)
        b:SetSize(SW, 40)
        b:SetPoint("TOPLEFT", x + (i - 1) * (SW + 5), y)
        local bg = b:CreateTexture(nil, "BACKGROUND")
        bg:SetPoint("TOPLEFT", 0, 0); bg:SetPoint("BOTTOMRIGHT", 0, 14)
        local strip = b:CreateTexture(nil, "ARTWORK")
        strip:SetPoint("TOPLEFT", 1, -1); strip:SetPoint("TOPRIGHT", -1, -1); strip:SetHeight(7)
        local acc = b:CreateTexture(nil, "OVERLAY")
        acc:SetPoint("BOTTOMLEFT", bg, "BOTTOMLEFT", 4, 4); acc:SetSize(SW - 8, 3)
        local edge = b:CreateTexture(nil, "BORDER")
        edge:SetPoint("BOTTOMLEFT", bg, "BOTTOMLEFT", 0, 0); edge:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", 0, 0); edge:SetHeight(1)
        local ring = b:CreateTexture(nil, "OVERLAY")
        ring:SetPoint("TOPLEFT", bg, "TOPLEFT", 0, 0); ring:SetPoint("TOPRIGHT", bg, "TOPRIGHT", 0, 0); ring:SetHeight(2)
        ring:Hide()
        b.ring = ring
        b.label = Chrome:Text(b, 10, C.muted)
        b.label:SetPoint("BOTTOM", 0, 0)
        b.label:SetText(def.name)
        -- Themes rebuild when class colors or custom colors change, so the
        -- swatch re-reads its theme by id each refresh.
        b.Paint = function()
            local t = Chrome.ThemeByID[id]
            if not t then return end
            b.theme = t
            bg:SetColorTexture(t.colors.void[1], t.colors.void[2], t.colors.void[3], 1)
            strip:SetColorTexture(t.colors.shadow[1], t.colors.shadow[2], t.colors.shadow[3], 1)
            acc:SetColorTexture(t.colors.fel[1], t.colors.fel[2], t.colors.fel[3], 1)
            edge:SetColorTexture(t.colors.border[1], t.colors.border[2], t.colors.border[3], 1)
            ring:SetColorTexture(t.colors.fel[1], t.colors.fel[2], t.colors.fel[3], 1)
        end
        b.Paint()
        b:SetScript("OnClick", function() Chrome:SetTheme(id); refresh() end)
        b:SetScript("OnEnter", function()
            local t = b.theme
            GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
            GameTooltip:SetText(t.name, 1, 1, 1)
            if t.class then GameTooltip:AddLine(t.class:sub(1, 1) .. t.class:sub(2):lower() .. " theme", 0.6, 0.6, 0.6) end
            if t.custom then GameTooltip:AddLine("Your own main and accent colors, set below.", 0.6, 0.6, 0.6) end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        swatches[#swatches + 1] = b
    end
    y = y - 46

    -- Custom theme colors: two picker buttons that open Blizzard's color picker.
    local function hexToRGB(h) return tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255 end
    local function openPicker(r, g, b, onChange, onCancel)
        local f = ColorPickerFrame
        if not f then return end
        if f.SetupColorPickerAndShow then
            f:SetupColorPickerAndShow({ r = r, g = g, b = b, hasOpacity = false, swatchFunc = onChange, cancelFunc = onCancel })
        else
            f.func, f.cancelFunc, f.opacityFunc, f.hasOpacity = onChange, onCancel, nil, false
            f:SetColorRGB(r, g, b)
            f:Show()
        end
    end
    local pickers = {}
    local function makePicker(which, label, offsetX)
        local b = CreateFrame("Button", nil, parent)
        b:SetSize(150, 20)
        b:SetPoint("TOPLEFT", x + offsetX, y)
        local sw = b:CreateTexture(nil, "ARTWORK")
        sw:SetSize(14, 14); sw:SetPoint("LEFT", 0, 0)
        local swEdge = CreateFrame("Frame", nil, b)
        swEdge:SetPoint("TOPLEFT", sw, "TOPLEFT", -1, 1); swEdge:SetPoint("BOTTOMRIGHT", sw, "BOTTOMRIGHT", 1, -1)
        Chrome:AddBorder(swEdge)
        b.lbl = Chrome:Text(b, 11)
        b.lbl:SetPoint("LEFT", sw, "RIGHT", 8, 0)
        b.Paint = function()
            local h = Chrome.customColors[which]
            local r, g, bb = hexToRGB(h)
            sw:SetColorTexture(r, g, bb, 1)
            b.lbl:SetText(label .. "  |cff8F8770" .. h .. "|r")
        end
        b:SetScript("OnClick", function()
            local before = Chrome.customColors[which]
            local r, g, bb = hexToRGB(before)
            local function apply()
                local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                if which == "main" then Chrome:SetCustomColors({ nr, ng, nb }, nil) else Chrome:SetCustomColors(nil, { nr, ng, nb }) end
                if Chrome.activeTheme ~= "custom" then Chrome:SetTheme("custom") end
                refresh()
            end
            openPicker(r, g, bb, apply, function()
                if which == "main" then Chrome:SetCustomColors(before, nil) else Chrome:SetCustomColors(nil, before) end
                refresh()
            end)
        end)
        b.Paint()
        pickers[#pickers + 1] = b
        return b
    end
    local customHead = Chrome:Text(parent, 11, C.muted)
    customHead:SetPoint("TOPLEFT", x, y)
    customHead:SetText("Custom:")
    makePicker("main", "Main", 58)
    makePicker("accent", "Accent", 220)
    local resetBtn = Chrome:Button(parent, "Reset", 60, 20)
    resetBtn:SetPoint("TOPLEFT", x + 384, y)
    resetBtn:SetScript("OnClick", function()
        Chrome:SetCustomColors(Chrome.CUSTOM_DEFAULT.main, Chrome.CUSTOM_DEFAULT.accent)
        refresh()
    end)
    parent.themePickers = pickers
    y = y - 26
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

-- Pages outgrew the panel once the client-error and profile sections
-- arrived, so they scroll. A bare ScrollFrame keeps the flat look:
-- Blizzard's scroll templates bring their dialog textures with them.
local function makeScroller(parent)
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    local body = CreateFrame("Frame", nil, scroll)
    body:SetSize(1, 1)
    scroll:SetScrollChild(body)

    local track = Chrome:Texture(parent, "ARTWORK", Chrome.Colors.border)
    track:SetWidth(2)
    local thumb = Chrome:Texture(parent, "OVERLAY", Chrome.Colors.fel)
    thumb:SetWidth(2)
    track:Hide()
    thumb:Hide()

    local function span(f) return tonumber(f:GetHeight()) or 0 end
    local function range() return math.max(0, span(body) - span(scroll)) end

    local function refresh()
        local r = range()
        if r <= 0 then
            track:Hide()
            thumb:Hide()
            scroll:SetVerticalScroll(0)
            return
        end
        track:Show()
        thumb:Show()
        local view, full = span(scroll), span(body)
        local th = math.max(20, view * (view / full))
        thumb:SetHeight(th)
        local at = math.min(r, math.max(0, tonumber(scroll:GetVerticalScroll()) or 0))
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", track, "TOP", 0, -((at / r) * (view - th)))
    end

    local function scrollBy(delta)
        local r = range()
        if r <= 0 then return end
        local at = math.min(r, math.max(0, ((tonumber(scroll:GetVerticalScroll()) or 0) - delta * 32)))
        scroll:SetVerticalScroll(at)
        refresh()
    end

    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(_, delta) scrollBy(delta) end)
    -- The body is the thing under the cursor over most of the page.
    body:EnableMouseWheel(true)
    body:SetScript("OnMouseWheel", function(_, delta) scrollBy(delta) end)

    scroll.track, scroll.thumb, scroll.Refresh = track, thumb, refresh
    return scroll, body
end

-- Lay the body out to fit what was built into it, then show or hide the bar.
local function fitBody(scroll, body)
    local w = tonumber(scroll:GetWidth()) or 0
    if w > 0 then body:SetWidth(w) end
    body:SetHeight(math.max(1, -(body.__extent or 0) + 16))
    scroll:Refresh()
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
        local scroll, body = makeScroller(p)
        scroll:SetPoint("TOPLEFT", 16, -48)
        scroll:SetPoint("BOTTOMRIGHT", -22, 16)
        scroll.track:SetPoint("TOPRIGHT", p, "TOPRIGHT", -14, -48)
        scroll.track:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -14, 16)
        p.scroll, p.body = scroll, body
        Core.safe(buildFn, body, addon)
        fitBody(scroll, body)
        -- The panel has no size yet on the first show, so measure again once
        -- the frame system has placed it, and on every resize after that.
        scroll:SetScript("OnSizeChanged", function() fitBody(scroll, body) end)
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function() fitBody(scroll, body) end)
        end
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

-- Every helper reports how far down the page it reached, so the scroll
-- child can be sized to its content without each addon having to say.
local function consume(parent, y)
    parent.__extent = math.min(parent.__extent or 0, y)
    return y
end

function Options:Heading(parent, text, y)
    local fs = Chrome:Heading(parent, text)
    fs:SetPoint("TOPLEFT", 0, y)
    return consume(parent, y - 22)
end

function Options:Check(parent, label, get, set, y)
    -- Every change made through an options page is something worth
    -- keeping, so the store hears about it.
    local c = Chrome:Check(parent, label, get, function(...)
        set(...)
        if Core.Store then Core.Store:Dirty() end
    end)
    c:SetPoint("TOPLEFT", 0, y)
    return consume(parent, y - 22)
end

function Options:Button(parent, text, onClick, y, width)
    local b = Chrome:Button(parent, text, width)
    b:SetPoint("TOPLEFT", 0, y)
    b:SetScript("OnClick", onClick)
    return consume(parent, y - 28)
end

function Options:Note(parent, text, y)
    local fs = Chrome:Text(parent, 11, Chrome.Colors.muted)
    fs:SetPoint("TOPLEFT", 0, y)
    local w = tonumber(parent:GetWidth())
    fs:SetWidth((w and w > 80) and (w - 8) or 520)
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    -- Ask the font string how tall it actually came out.
    local h = tonumber(fs.GetStringHeight and fs:GetStringHeight())
    if not h or h <= 0 then
        h = 13 + select(2, text:gsub("\n", "")) * 13
    end
    return consume(parent, y - math.ceil(h) - 6)
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
