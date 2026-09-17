-- WickCore
-- Client.lua — which client are we on, and what does it allow.
--
-- Forever reports WOW_PROJECT_ID == WOW_PROJECT_MAINLINE, so the project
-- constant cannot tell it apart from retail. The interface number can:
-- Forever runs the 1.60.x line, interface 16001.

local ADDON = ...
local Core = LibStub("WickCore-1.0", true)
if not Core or Core._sourceAddon ~= ADDON then return end

local Client = {}
Core.Client = Client

do
    local version, build, date, interface = GetBuildInfo()
    Client.version   = version
    Client.build     = tonumber(build) or 0
    Client.buildDate = date
    Client.interface = tonumber(interface) or 0
end

Client.project = rawget(_G, "WOW_PROJECT_ID")

-- Line detection by interface number. Forever is the only 1.60.x client.
Client.isForever    = Client.interface >= 16000 and Client.interface < 17000
Client.isClassicEra = Client.interface >= 11000 and Client.interface < 12000
Client.isTBC        = Client.interface >= 20000 and Client.interface < 30000
Client.isWrath      = Client.interface >= 30000 and Client.interface < 40000
Client.isRetail     = Client.interface >= 100000 and not Client.isForever

-- Retail-modern API dialect: C_Item / C_Spell / C_Container / C_UnitAuras.
-- Forever, Cata Classic onward, and retail all speak it. TBC and Era do not.
Client.isModern = (rawget(_G, "C_Item") and C_Item.GetItemInfo) and true or false

-- Midnight-rule restrictions (secret values) exist on this client.
Client.hasSecrets = false
if rawget(_G, "C_Secrets") and C_Secrets.HasSecretRestrictions then
    local ok, v = pcall(C_Secrets.HasSecretRestrictions)
    Client.hasSecrets = ok and v == true
end

Client.hasTraits = (rawget(_G, "C_Traits") and rawget(_G, "C_ClassTalents")) and true or false

function Client:GameMode()
    local GR = rawget(_G, "C_GameRules")
    if GR and GR.GetActiveGameMode then
        local ok, mode = pcall(GR.GetActiveGameMode)
        if ok then return mode end
    end
    return nil
end

function Client:IsHardcore()
    local GR = rawget(_G, "C_GameRules")
    if GR and GR.IsHardcoreActive then
        local ok, v = pcall(GR.IsHardcoreActive)
        if ok then return v == true end
    end
    return false
end

function Client:IsSelfFound()
    local GR = rawget(_G, "C_GameRules")
    if GR and GR.IsSelfFoundAllowed then
        local ok, v = pcall(GR.IsSelfFoundAllowed)
        if ok then return v == true end
    end
    return false
end

function Client:Flavor()
    if self.isForever then return "forever" end
    if self.isRetail then return "retail" end
    if self.isTBC then return "tbc" end
    if self.isClassicEra then return "era" end
    if self.isWrath then return "wrath" end
    return "unknown"
end

function Client:Report()
    return {
        string.format("%s %s (%s) interface %d, project %s",
            self:Flavor(), tostring(self.version), tostring(self.build),
            self.interface, tostring(self.project)),
        string.format("dialect %s, secrets %s, traits %s, game mode %s%s",
            self.isModern and "modern" or "legacy",
            self.hasSecrets and "on" or "off",
            self.hasTraits and "yes" or "no",
            tostring(self:GameMode()),
            self:IsHardcore() and " (hardcore)" or ""),
    }
end
