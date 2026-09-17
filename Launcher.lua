-- WickCore
-- Launcher.lua — one Wick button, a data object per product.
--
-- Products register a launcher and get a LibDataBroker object when a broker
-- display is installed. Without one, WickCore draws a single minimap button
-- that opens a small hub listing every registered product.

local ADDON = ...
local Core = LibStub("WickCore-1.0", true)
if not Core or Core._sourceAddon ~= ADDON then return end

local Launcher = {}
Core.Launcher = Launcher
Launcher.entries = Launcher.entries or {}

local Chrome = Core.Chrome
local LDB = LibStub("LibDataBroker-1.1", true)

Launcher.ICON = "Interface\\Icons\\INV_Misc_Candle_03"

-- opts: { icon, onClick(button), tooltip(GameTooltip), text }
function Launcher:Register(addon, opts)
    opts = opts or {}
    local entry = { addon = addon, opts = opts }
    self.entries[addon.name] = entry

    if LDB then
        local ok, obj = pcall(LDB.NewDataObject, LDB, addon.title, {
            type = "launcher",
            icon = opts.icon or self.ICON,
            label = addon.title,
            text = opts.text,
            OnClick = function(_, button)
                if opts.onClick then Core.safe(opts.onClick, addon, button)
                elseif addon.Toggle then Core.safe(addon.Toggle, addon) end
            end,
            OnTooltipShow = function(tt)
                if opts.tooltip then Core.safe(opts.tooltip, tt, addon)
                else tt:AddLine(Chrome:TitleMarkup(addon.title)) end
            end,
        })
        if ok then entry.ldb = obj end
    end

    self:EnsureMinimapButton()
    return entry
end

-- ============================================================
-- Minimap button (fallback when no broker display is present)
-- ============================================================

function Launcher:EnsureMinimapButton()
    if self.button or not rawget(_G, "Minimap") then return end
    local db = Core.self.db and Core.self.db.global.minimap or { angle = 220 }
    self.db = db

    local b = CreateFrame("Button", "WickCoreMinimapButton", Minimap)
    b:SetSize(28, 28)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetMovable(true)

    local bg = Chrome:Texture(b, "BACKGROUND", Chrome.Colors.void)
    bg:SetPoint("TOPLEFT", 3, -3)
    bg:SetPoint("BOTTOMRIGHT", -3, 3)
    Chrome:AddBrackets(b)
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(self.ICON)
    icon:SetPoint("TOPLEFT", 6, -6)
    icon:SetPoint("BOTTOMRIGHT", -6, 6)
    b.icon = icon

    local function place()
        local angle = math.rad(db.angle or 220)
        local r = (Minimap:GetWidth() / 2) + 6
        b:ClearAllPoints()
        b:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
    end

    b:SetScript("OnDragStart", function(s)
        s.dragging = true
        s:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            cx, cy = cx / scale, cy / scale
            db.angle = math.deg(math.atan2(cy - my, cx - mx))
            place()
        end)
    end)
    b:SetScript("OnDragStop", function(s)
        s.dragging = false
        s:SetScript("OnUpdate", nil)
    end)
    b:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            Core.Options:Open()
        else
            Launcher:ToggleHub()
        end
    end)
    b:SetScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_LEFT")
        local e = Launcher.entries.WickCore
        if e and e.opts.tooltip then Core.safe(e.opts.tooltip, GameTooltip, Core.self) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    place()
    if db.hidden then b:Hide() end
    self.button = b
end

function Launcher:SetMinimapHidden(hidden)
    if self.db then self.db.hidden = hidden and true or false end
    if self.button then
        if hidden then self.button:Hide() else self.button:Show() end
    end
end

-- ============================================================
-- Hub: every registered product, one row each
-- ============================================================

function Launcher:ToggleHub()
    if not self.hub then
        local p = Chrome:NewPanel("WickCoreHubFrame", { title = "Wick's Mods", width = 260, height = 120, strata = "DIALOG" })
        p:ClearAllPoints()
        if self.button then p:SetPoint("TOPRIGHT", self.button, "BOTTOMLEFT", 0, -4)
        else p:SetPoint("CENTER") end
        self.hub = p
    end
    local p = self.hub
    if p:IsShown() then p:Hide() return end

    -- Rebuild rows each open; the roster can change with LoadOnDemand.
    if p.rows then for _, r in ipairs(p.rows) do r:Hide() end end
    p.rows = {}
    local y = 0
    for name, entry in pairs(self.entries) do
        if name ~= "WickCore" then
            local row = Chrome:Button(p.content, Chrome:TitleMarkup(entry.addon.title), 240, 22)
            row.label:ClearAllPoints()
            row.label:SetPoint("LEFT", 8, 0)
            row:SetPoint("TOPLEFT", 0, y)
            row:SetScript("OnClick", function(_, button)
                p:Hide()
                if entry.opts.onClick then Core.safe(entry.opts.onClick, entry.addon, button)
                elseif entry.addon.Toggle then Core.safe(entry.addon.Toggle, entry.addon) end
            end)
            p.rows[#p.rows + 1] = row
            y = y - 26
        end
    end
    if #p.rows == 0 then
        local none = Chrome:Text(p.content, 11, Chrome.Colors.muted)
        none:SetPoint("TOPLEFT", 4, -4)
        none:SetText("No Wick addons registered yet.")
        p.rows[1] = none
        y = -26
    end
    p:SetHeight(Chrome.HEADER_H + 16 + (-y) + 8)
    p:Show()
end
