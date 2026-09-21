-- WickCore
-- Chrome.lua — the Wick visual system, built once.
--
-- Locked palette, flat panels, single 1px muted-purple border, fel-green
-- L-bracket corners with 10px arms 2px thick flush to the corners. Products
-- call Chrome:NewPanel and get all of it; they never draw their own frame.

local ADDON = ...
local Core = LibStub("WickCore-1.0", true)
if not Core or Core._sourceAddon ~= ADDON then return end

local Chrome = {}
Core.Chrome = Chrome

-- ============================================================
-- Palette (locked, do not drift)
-- Fel #4FC778 · Void #0D0A14 · Shadow #171124 · Border #383058 · Text #D4C8A1
-- ============================================================
Chrome.Colors = {
    fel      = { 0.310, 0.780, 0.471, 1 },
    void     = { 0.051, 0.039, 0.078, 1 },
    voidBG   = { 0.051, 0.039, 0.078, 0.97 },
    shadow   = { 0.090, 0.067, 0.141, 1 },
    border   = { 0.220, 0.188, 0.345, 1 },
    text     = { 0.831, 0.784, 0.631, 1 },
    muted    = { 0.560, 0.530, 0.440, 1 },
    white    = { 1, 1, 1, 1 },
}
Chrome.Hex = {
    fel    = "4FC778",
    void   = "0D0A14",
    shadow = "171124",
    border = "383058",
    text   = "D4C8A1",
}

Chrome.BRACKET  = 10
Chrome.HEADER_H = 22
Chrome.FONT     = "Fonts\\FRIZQT__.TTF"

local C = Chrome.Colors

-- ============================================================
-- Palette registry
-- ============================================================
-- Every region Chrome paints with a palette token is remembered (weakly)
-- with the token's name, so a theme switch can re-tint it in place. A
-- color table that is not one of the tokens is a one-off and is left alone.
local TOKEN_OF = {}
for name, tbl in pairs(Chrome.Colors) do TOKEN_OF[tbl] = name end
local tinted = setmetatable({}, { __mode = "k" })

-- Register a region a product painted itself. kind: "texture" or "text".
function Chrome:Register(region, token, kind)
    if type(token) == "table" then token = TOKEN_OF[token] end
    if not token or not C[token] then return region end
    tinted[region] = { token = token, kind = kind or "texture" }
    return region
end

function Chrome:Retint()
    for region, info in pairs(tinted) do
        local c = C[info.token]
        if c then
            if info.kind == "text" then
                if region.SetTextColor then region:SetTextColor(c[1], c[2], c[3], c[4] or 1) end
            elseif region.SetColorTexture then
                region:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
            end
        end
    end
end

-- ============================================================
-- Primitives
-- ============================================================

function Chrome:Texture(parent, layer, color)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND")
    if color then
        t:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
        if TOKEN_OF[color] then tinted[t] = { token = TOKEN_OF[color], kind = "texture" } end
    end
    return t
end

function Chrome:Text(parent, size, color, flags)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(self.FONT, size or 12, flags or "")
    color = color or C.text
    fs:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    if TOKEN_OF[color] then tinted[fs] = { token = TOKEN_OF[color], kind = "text" } end
    return fs
end

-- Four 1px muted-purple edges.
function Chrome:AddBorder(f, color)
    color = color or C.border
    local top    = self:Texture(f, "BORDER", color); top:SetPoint("TOPLEFT");    top:SetPoint("TOPRIGHT");    top:SetHeight(1)
    local bot    = self:Texture(f, "BORDER", color); bot:SetPoint("BOTTOMLEFT"); bot:SetPoint("BOTTOMRIGHT"); bot:SetHeight(1)
    local left   = self:Texture(f, "BORDER", color); left:SetPoint("TOPLEFT");   left:SetPoint("BOTTOMLEFT"); left:SetWidth(1)
    local right  = self:Texture(f, "BORDER", color); right:SetPoint("TOPRIGHT"); right:SetPoint("BOTTOMRIGHT"); right:SetWidth(1)
    f.border = { top = top, bottom = bot, left = left, right = right }
end

-- Fel-green L-brackets. If a resizeButton is passed the BOTTOMRIGHT bracket
-- is parented to it so it doubles as the grip.
function Chrome:AddBrackets(parent, resizeButton, color)
    color = color or C.fel
    local B = self.BRACKET
    parent.brackets = {}
    for _, point in ipairs({ "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }) do
        local host = (point == "BOTTOMRIGHT" and resizeButton) or parent
        local h = self:Texture(host, "OVERLAY", color)
        h:SetPoint(point, host, point, 0, 0)
        h:SetSize(B, 2)
        local v = self:Texture(host, "OVERLAY", color)
        v:SetPoint(point, host, point, 0, 0)
        v:SetSize(2, B)
        parent.brackets[point] = { h, v }
    end
end

-- Two-tone title: "Wick's" in text color, the noun in fel green.
function Chrome:TitleMarkup(title)
    local pre, noun = tostring(title):match("^(Wick'?s?)%s+(.+)$")
    if pre then
        return "|cff" .. self.Hex.text .. pre .. "|r |cff" .. self.Hex.fel .. noun .. "|r"
    end
    return "|cff" .. self.Hex.text .. tostring(title) .. "|r"
end

-- ============================================================
-- Dragging
-- ============================================================
-- One rule for every locked thing in the suite. A lock is there to stop
-- an accidental nudge while you are clicking the bar, not to stop you
-- moving it on purpose, and hunting for the unlock checkbox every time
-- is worse than the accident. Shift always moves the frame.
--
-- Anything with a lock asks this rather than testing the flag itself, so
-- the answer is the same everywhere and there is one place to change it.
function Chrome:DragAllowed(locked)
    if not locked then return true end
    local shift = rawget(_G, "IsShiftKeyDown")
    return (shift and shift()) and true or false
end

-- ============================================================
-- Panel
-- ============================================================
-- local panel = Chrome:NewPanel("WicksBagsFrame", {
--     title = "Wick's Bags", width = 400, height = 300,
--     resizable = true, minWidth = 260, minHeight = 120,
--     closable = true, strata = "MEDIUM", db = A.db.profile.window,
-- })
-- panel.content is the inset frame products draw into.

function Chrome:NewPanel(name, o)
    o = o or {}
    local f = CreateFrame("Frame", name, o.parent or UIParent)
    f:SetSize(o.width or 400, o.height or 240)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(s) s:StartMoving() end)
    f:SetScript("OnDragStop", function(s)
        s:StopMovingOrSizing()
        if s.db then Chrome:SavePosition(s, s.db) end
    end)
    if o.strata then f:SetFrameStrata(o.strata) end
    f:Hide()

    local bg = self:Texture(f, "BACKGROUND", C.voidBG); bg:SetAllPoints()
    self:AddBorder(f)

    -- Header strip
    local H = self.HEADER_H
    local header = self:Texture(f, "ARTWORK", C.shadow)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(H)
    local sep = self:Texture(f, "ARTWORK", C.border)
    sep:SetPoint("TOPLEFT", 1, -H - 1)
    sep:SetPoint("TOPRIGHT", -1, -H - 1)
    sep:SetHeight(1)
    f.header = header

    f.title = self:Text(f, 12)
    f.title:SetPoint("LEFT", f, "TOPLEFT", 10, -H / 2)
    f.title:SetText(self:TitleMarkup(o.title or name))

    -- Close glyph
    if o.closable ~= false then
        local close = CreateFrame("Button", nil, f)
        close:SetSize(H, H)
        close:SetPoint("TOPRIGHT", -1, -1)
        local x = self:Text(close, 13)
        x:SetPoint("CENTER")
        x:SetText("x")
        close:SetScript("OnEnter", function() x:SetTextColor(C.fel[1], C.fel[2], C.fel[3], 1) end)
        close:SetScript("OnLeave", function() x:SetTextColor(C.text[1], C.text[2], C.text[3], 1) end)
        close:SetScript("OnClick", function() f:Hide() end)
        f.close = close
    end

    -- Content inset
    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT", 8, -H - 8)
    content:SetPoint("BOTTOMRIGHT", -8, 8)
    f.content = content

    -- Resize grip doubles as the BOTTOMRIGHT bracket
    local grip
    if o.resizable then
        f:SetResizable(true)
        local minW, minH = o.minWidth or 200, o.minHeight or 100
        if f.SetResizeBounds then f:SetResizeBounds(minW, minH)
        elseif f.SetMinResize then f:SetMinResize(minW, minH) end
        grip = CreateFrame("Button", nil, f)
        grip:SetSize(self.BRACKET + 2, self.BRACKET + 2)
        grip:SetPoint("BOTTOMRIGHT", 0, 0)
        grip:EnableMouse(true)
        grip:SetScript("OnMouseDown", function(_, btn)
            if btn == "LeftButton" then f:StartSizing("BOTTOMRIGHT") end
        end)
        grip:SetScript("OnMouseUp", function()
            f:StopMovingOrSizing()
            if f.db then Chrome:SavePosition(f, f.db) end
            if f.OnResized then f.OnResized(f) end
        end)
        f.grip = grip
    end

    self:AddBrackets(f, grip)

    if o.db then
        f.db = o.db
        self:RestorePosition(f, o.db)
    end

    f.Toggle = function(s) if s:IsShown() then s:Hide() else s:Show() end end
    return f
end

-- ============================================================
-- Position persistence
-- ============================================================

function Chrome:SavePosition(f, db)
    local point, _, relPoint, x, y = f:GetPoint()
    db.point, db.relPoint, db.x, db.y = point, relPoint, x, y
    db.width, db.height = f:GetWidth(), f:GetHeight()
end

function Chrome:RestorePosition(f, db)
    if db.width and db.height then f:SetSize(db.width, db.height) end
    if db.point then
        f:ClearAllPoints()
        f:SetPoint(db.point, UIParent, db.relPoint or db.point, db.x or 0, db.y or 0)
    end
end

-- ============================================================
-- Small widgets in the same voice
-- ============================================================

function Chrome:Button(parent, text, width, height)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width or 90, height or 22)
    local bg = self:Texture(b, "BACKGROUND", C.shadow); bg:SetAllPoints()
    self:AddBorder(b)
    b.label = self:Text(b, 11)
    b.label:SetPoint("CENTER")
    b.label:SetText(text)
    b:SetScript("OnEnter", function(s)
        for _, t in pairs(s.border) do t:SetColorTexture(C.fel[1], C.fel[2], C.fel[3], 1) end
    end)
    b:SetScript("OnLeave", function(s)
        for _, t in pairs(s.border) do t:SetColorTexture(C.border[1], C.border[2], C.border[3], 1) end
    end)
    return b
end

-- Check box: 14px bordered square, fel fill when checked.
function Chrome:Check(parent, label, get, set)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(220, 18)
    local box = CreateFrame("Frame", nil, b)
    box:SetSize(14, 14)
    box:SetPoint("LEFT", 0, 0)
    local bbg = self:Texture(box, "BACKGROUND", C.void); bbg:SetAllPoints()
    self:AddBorder(box)
    local fill = self:Texture(box, "ARTWORK", C.fel)
    fill:SetPoint("TOPLEFT", 3, -3)
    fill:SetPoint("BOTTOMRIGHT", -3, 3)
    b.fill = fill
    b.label = self:Text(b, 11)
    b.label:SetPoint("LEFT", box, "RIGHT", 8, 0)
    b.label:SetText(label)
    local function refresh() if get() then fill:Show() else fill:Hide() end end
    b:SetScript("OnClick", function() set(not get()); refresh() end)
    b.Refresh = refresh
    refresh()
    return b
end

function Chrome:Heading(parent, text)
    local fs = self:Text(parent, 12, C.fel)
    fs:SetText(text)
    return fs
end

function Chrome:Divider(parent)
    local t = self:Texture(parent, "ARTWORK", C.border)
    t:SetHeight(1)
    return t
end
