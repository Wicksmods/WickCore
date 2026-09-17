-- WickCore
-- Restrict.lua — Midnight-rule awareness.
--
-- On Forever the player's own health, power, ratings and totems become secret
-- values in combat, and aura queries do not go secret, they throw. Anything
-- that reads player state routes through here so it goes quiet the moment a
-- restriction activates and comes back when it clears.

local ADDON = ...
local Core = LibStub("WickCore-1.0", true)
if not Core or Core._sourceAddon ~= ADDON then return end

local R = {}
Core.Restrict = R

local RA    = rawget(_G, "C_RestrictedActions")
local TYPES = rawget(_G, "Enum") and Enum.AddOnRestrictionType or nil

R.hasSecrets = Core.Client.hasSecrets
R.KINDS = { "Combat", "Encounter", "ChallengeMode", "PvPMatch", "Map", "Chat" }

-- Reverse map enum value -> name for the state-change event payload.
local byValue = {}
if TYPES then
    for name, value in pairs(TYPES) do byValue[value] = name end
end

function R:IsSecret(v)
    local f = rawget(_G, "issecretvalue")
    if not f then return false end
    local ok, s = pcall(f, v)
    return ok and s == true
end

-- Is a restriction type active right now. Falls back to combat lockdown on
-- clients without the 12.0 API.
function R:IsActive(kind)
    if RA and RA.IsAddOnRestrictionActive and TYPES and TYPES[kind] ~= nil then
        local ok, v = pcall(RA.IsAddOnRestrictionActive, TYPES[kind])
        if ok then return v == true end
    end
    if kind == "Combat" then
        return InCombatLockdown() and true or false
    end
    return false
end

function R:IsCombat() return self:IsActive("Combat") end

function R:AnyActive()
    for _, kind in ipairs(self.KINDS) do
        if self:IsActive(kind) then return true, kind end
    end
    return false
end

-- Auras on a secrets client cannot be read under combat, encounter, keystone
-- or PvP restrictions. The call raises rather than returning a secret.
function R:AurasBlocked()
    if not self.hasSecrets then return false end
    return self:IsActive("Combat") or self:IsActive("Encounter")
        or self:IsActive("ChallengeMode") or self:IsActive("PvPMatch")
end

function R:CooldownsSecret()
    local S = rawget(_G, "C_Secrets")
    if S and S.ShouldCooldownsBeSecret then
        local ok, v = pcall(S.ShouldCooldownsBeSecret)
        if ok then return v == true end
    end
    return false
end

function R:ChatBlocked()
    local CI = rawget(_G, "C_ChatInfo")
    if CI and CI.InChatMessagingLockdown then
        local ok, v = pcall(CI.InChatMessagingLockdown)
        if ok and v then return true end
    end
    return self:IsActive("Chat")
end

-- Run fn only when auras are readable, swallowing the secret-access error.
-- Returns nil, reason when it could not run.
function R:Guard(fn, ...)
    if self:AurasBlocked() then return nil, "restricted" end
    local r = Core.pack(pcall(fn, ...))
    if not r[1] then return nil, tostring(r[2]) end
    return unpack(r, 2, r.n)
end

-- Return v unless it is secret, in which case return fallback.
function R:Plain(v, fallback)
    if self:IsSecret(v) then return fallback end
    return v
end

function R:Summary()
    local active = {}
    for _, kind in ipairs(self.KINDS) do
        if self:IsActive(kind) then active[#active + 1] = kind end
    end
    return string.format("secrets %s, active: %s, auras %s, cooldowns %s",
        self.hasSecrets and "on" or "off",
        #active > 0 and table.concat(active, ",") or "none",
        self:AurasBlocked() and "blocked" or "readable",
        self:CooldownsSecret() and "secret" or "readable")
end

-- ============================================================
-- Change notifications
-- ============================================================
-- R:OnChange(function(kind, active) ... end)

R.callbacks = R.callbacks or {}

function R:OnChange(fn)
    self.callbacks[#self.callbacks + 1] = fn
end

local function fire(kind, active)
    for i = 1, #R.callbacks do
        local ok, err = pcall(R.callbacks[i], kind, active)
        if not ok and Core.debug then Core.Print("WickCore", "restriction callback: " .. tostring(err)) end
    end
end

local frame = CreateFrame("Frame")
local hasStateEvent = pcall(frame.RegisterEvent, frame, "ADDON_RESTRICTION_STATE_CHANGED")
if not hasStateEvent then
    pcall(frame.RegisterEvent, frame, "PLAYER_REGEN_DISABLED")
    pcall(frame.RegisterEvent, frame, "PLAYER_REGEN_ENABLED")
end

frame:SetScript("OnEvent", function(_, event, a, b)
    if event == "ADDON_RESTRICTION_STATE_CHANGED" then
        -- a = AddOnRestrictionType value, b = AddOnRestrictionState (0 inactive)
        local kind = byValue[a] or tostring(a)
        fire(kind, b ~= 0)
    elseif event == "PLAYER_REGEN_DISABLED" then
        fire("Combat", true)
    elseif event == "PLAYER_REGEN_ENABLED" then
        fire("Combat", false)
    end
end)
