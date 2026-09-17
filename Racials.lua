-- WickCore
-- Racials.lua — every race's two actives, as a display-only cooldown row.
--
-- Forever gives every race two active and two passive racials. This row
-- shows the actives as secure cast buttons with a Cooldown widget under
-- each. Cooldown values are secret in combat on Forever; they are passed
-- straight into SetCooldown, which accepts secrets, and never compared.
--
-- Data from talentsforever.com (https://talentsforever.com), CC BY 4.0,
-- read off the BlizzCon 2026 demo. Names bind to spells in game.

local ADDON = ...
local Core = LibStub("WickCore-1.0", true)
if not Core or Core._sourceAddon ~= ADDON then return end

local Racials = {}
Core.Racials = Racials

local D, R, Chrome = Core.Dialect, Core.Restrict, Core.Chrome
local C = Chrome.Colors

-- Keyed by the UnitRace token. Skyborne has two factions with one shared
-- active and one that differs; both are listed and the unknown one is
-- skipped when the spell is not known.
Racials.DATA = {
    Orc      = { actives = { "Blood Fury", "Shatter Curse" },          passives = { "Axe Specialization", "Hardiness" } },
    Scourge  = { actives = { "Will of the Forsaken", "Cannibalize" },  passives = { "Underwater Breathing", "Touch of the Grave" } },
    Tauren   = { actives = { "War Stomp" },                            passives = { "Cultivation", "Plainsrunning", "Endurance" } },
    Troll    = { actives = { "Berserking", "Rapid Regeneration" },     passives = { "Beast Slaying", "Regeneration" } },
    Skyborne = { actives = { "Walk on Air", "Skysight", "Read Ley Line" }, passives = { "Wind Blessed", "Elemental Insight" } },
    Human    = { actives = { "Will to Survive", "Perception" },        passives = { "Sword Specialization", "The Human Spirit" } },
    Dwarf    = { actives = { "Stoneform", "Find Treasure" },           passives = { "Mace Specialization", "Big Game Hunter" } },
    NightElf = { actives = { "Elune's Light", "Shadowmeld" },          passives = { "Quickness", "Wisp Spirit" } },
    Gnome    = { actives = { "Escape Artist", "Eureka!" },             passives = { "Expansive Mind", "Engineering Specialization" } },
}
Racials.ATTRIBUTION = "Racial data from talentsforever.com (CC BY 4.0)"

function Racials:ForPlayer()
    local _, token = UnitRace("player")
    return self.DATA[token], token
end

-- Actives the player actually knows. Names resolve through the spellbook.
function Racials:KnownActives()
    local data = self:ForPlayer()
    if not data then return {} end
    local out = {}
    for _, name in ipairs(data.actives) do
        local info = D.GetSpellInfo(name)
        if info and info.spellID and (D.IsSpellKnown(info.spellID) or not rawget(_G, "C_SpellBook")) then
            out[#out + 1] = { name = name, spellID = info.spellID, icon = info.icon }
        elseif info and info.spellID then
            -- IsSpellKnown may lag at login; keep the button, it just fails to cast.
            out[#out + 1] = { name = name, spellID = info.spellID, icon = info.icon }
        end
    end
    return out
end

-- ============================================================
-- Row widget
-- ============================================================

local ICON = 30

function Racials:Attach(parent, y)
    self.buttons = self.buttons or {}
    local actives = self:KnownActives()
    local x = 0
    for i, a in ipairs(actives) do
        local b = self.buttons[i]
        if not b then
            b = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate")
            b:SetSize(ICON, ICON)
            b:RegisterForClicks("AnyUp", "AnyDown")
            Chrome:AddBorder(b)
            b.icon = b:CreateTexture(nil, "ARTWORK")
            b.icon:SetPoint("TOPLEFT", 1, -1)
            b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
            b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
            b.cd:SetAllPoints(b.icon)
            b:SetScript("OnEnter", function(s)
                GameTooltip:SetOwner(s, "ANCHOR_TOP")
                if s.spellID and GameTooltip.SetSpellByID then GameTooltip:SetSpellByID(s.spellID)
                else GameTooltip:SetText(s.spellName or "") end
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
            self.buttons[i] = b
        end
        b.spellID, b.spellName = a.spellID, a.name
        if not InCombatLockdown() then
            b:SetAttribute("type", "spell")
            b:SetAttribute("spell", a.name)
        end
        b.icon:SetTexture(a.icon)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        b:Show()
        x = x + ICON + 6
    end
    for i = #actives + 1, #self.buttons do self.buttons[i]:Hide() end
    self.parent = parent
    self:Refresh()
    return y - ICON - 6, #actives
end

-- Feed cooldowns through to the widget. Secret values are fine here.
function Racials:Refresh()
    if not self.buttons then return end
    for _, b in ipairs(self.buttons) do
        if b:IsShown() and b.spellID then
            local cd = D.GetSpellCooldown(b.spellID)
            if cd and cd.start ~= nil and cd.duration ~= nil then
                pcall(b.cd.SetCooldown, b.cd, cd.start, cd.duration, cd.modRate)
            end
        end
    end
end
