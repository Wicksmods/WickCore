-- WickCore
-- Version.lua — suite-wide version broadcast.
--
-- Every registered product announces itself on the WICK prefix when the
-- player logs in, joins a group, or the guild roster changes. Seeing a newer
-- version of an installed product prints one notice per session. Addon chat
-- is blocked during encounters, keystones and PvP matches, so sends route
-- through the Dialect guard and simply skip when restricted.

local ADDON = ...
local Core = LibStub("WickCore-1.0", true)
if not Core or Core._sourceAddon ~= ADDON then return end

local Version = {}
Core.Version = Version
Version.PREFIX = "WICK"
Version.registered = Version.registered or {}
Version.newest = Version.newest or {}
Version.notified = Version.notified or {}

local D = Core.Dialect
local THROTTLE = 30
local lastSend = 0

function Version:Register(addon)
    if not addon.version then return end
    self.registered[addon.name] = addon
    self.newest[addon.name] = self.newest[addon.name] or addon.version
    self:_Schedule(5)
end

local function channels()
    local out = {}
    if IsInRaid and IsInRaid() then out[#out + 1] = "RAID"
    elseif IsInGroup and IsInGroup() then out[#out + 1] = "PARTY" end
    if IsInGuild and IsInGuild() then out[#out + 1] = "GUILD" end
    return out
end

function Version:Broadcast(force)
    local now = GetTime and GetTime() or 0
    if not force and now - lastSend < THROTTLE then return end
    lastSend = now
    local chans = channels()
    if #chans == 0 then return end
    for name, addon in pairs(self.registered) do
        local msg = "V\t" .. name .. "\t" .. tostring(addon.version)
        for _, chan in ipairs(chans) do
            D.SendAddonMessage(self.PREFIX, msg, chan)
        end
    end
end

function Version:_Schedule(delay)
    if self.pending then return end
    self.pending = true
    local function go()
        self.pending = false
        self:Broadcast(true)
    end
    if rawget(_G, "C_Timer") and C_Timer.After then C_Timer.After(delay, go) else go() end
end

function Version:OnMessage(prefix, text, _, sender)
    if prefix ~= self.PREFIX then return end
    local kind, name, ver = text:match("^(%a)\t([^\t]+)\t(.+)$")
    if kind ~= "V" or not name then return end
    local mine = self.registered[name]
    if not mine then return end
    if Core.compareVersions(ver, self.newest[name]) > 0 then
        self.newest[name] = ver
    end
    if Core.compareVersions(ver, mine.version) > 0 and not self.notified[name] then
        self.notified[name] = true
        mine:Print(string.format("a newer version is out: %s (you have %s)", ver, mine.version))
    end
end

-- Wiring
D.RegisterAddonPrefix(Version.PREFIX)
local A = Core.self
A:On("CHAT_MSG_ADDON", function(prefix, text, channel, sender)
    Version:OnMessage(prefix, text, channel, sender)
end)
A:On("GROUP_ROSTER_UPDATE", function() Version:Broadcast() end)
A:On("GUILD_ROSTER_UPDATE", function() Version:Broadcast() end)
