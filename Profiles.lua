-- WickCore
-- Profiles.lua — saved variables with profiles, keyed switching, import/export.
--
-- Shape of a product's SavedVariables:
--   { profiles = { Default = {...}, ... }, profileKeys = { ["Name - Realm"] = "Default" },
--     global = {...}, char = { ["Name - Realm"] = {...} } }
--
-- A.db.profile / A.db.global / A.db.char are live tables with defaults applied.

local ADDON = ...
local Core = LibStub("WickCore-1.0", true)
if not Core or Core._sourceAddon ~= ADDON then return end

local Profiles = {}
Core.Profiles = Profiles

local DBProto = {}
DBProto.__index = DBProto

-- ============================================================
-- Keys
-- ============================================================

function Profiles:CharKey()
    local name = UnitName and UnitName("player") or "Unknown"
    local realm = GetRealmName and GetRealmName() or "Realm"
    return name .. " - " .. realm
end

function Profiles:ClassKey()
    local _, token = UnitClass("player")
    return token or "UNKNOWN"
end

-- Spec on a trait client is the active talent config; elsewhere a class is
-- as fine as it gets.
function Profiles:SpecKey()
    local CT = rawget(_G, "C_ClassTalents")
    if CT and CT.GetActiveConfigID then
        local ok, id = pcall(CT.GetActiveConfigID)
        if ok and id then return self:ClassKey() .. ":" .. tostring(id) end
    end
    local SI = rawget(_G, "C_SpecializationInfo")
    if SI and SI.GetSpecialization then
        local ok, spec = pcall(SI.GetSpecialization)
        if ok and spec then return self:ClassKey() .. ":" .. tostring(spec) end
    end
    return self:ClassKey()
end

function Profiles:ModeKey()
    local mode = Core.Client:GameMode()
    local hc = Core.Client:IsHardcore() and ":hc" or ""
    return tostring(mode or "default") .. hc
end

-- ============================================================
-- Init
-- ============================================================

function Profiles:Init(addon, savedVar, defaults)
    defaults = defaults or {}
    local sv = _G[savedVar]
    -- Exactly what the client had handed over at binding time. If this
    -- says the variable is missing, the client did not load the file.
    do
        local t = type(sv)
        local keyed = 0
        if t == "table" and type(sv.profileKeys) == "table" then
            for _ in pairs(sv.profileKeys) do keyed = keyed + 1 end
        end
        Profiles.lastInit = ("%s: var=%s, profileKeys=%d, theme=%s"):format(
            savedVar, t, keyed,
            tostring(t == "table" and sv.global and sv.global.theme))
    end
    if type(sv) ~= "table" then
        sv = {}
        _G[savedVar] = sv
    end
    sv.profiles    = sv.profiles    or {}
    sv.profileKeys = sv.profileKeys or {}
    sv.global      = sv.global      or {}
    sv.char        = sv.char        or {}
    sv.keyMode     = sv.keyMode     or "char"

    local db = setmetatable({
        addon     = addon,
        savedVar  = savedVar,
        sv        = sv,
        defaults  = defaults,
        callbacks = {},
    }, DBProto)

    db.charKey = self:CharKey()
    db.global  = Core.applyDefaults(sv.global, defaults.global or {})
    sv.char[db.charKey] = Core.applyDefaults(sv.char[db.charKey] or {}, defaults.char or {})
    db.char = sv.char[db.charKey]

    db:_Select(db:_KeyFor(sv.keyMode))
    return db
end

-- The client assigns saved variables around ADDON_LOADED. If our binding
-- ever happens before that, the client's assignment replaces the global
-- and leaves us holding an abandoned table: every read sees defaults and
-- nothing is ever written back, while the real values sit on disk. Check
-- at login and adopt the live table when that has happened.
function DBProto:Rebind()
    local live = _G[self.savedVar]
    if type(live) ~= "table" or live == self.sv then return false end
    live.profiles    = live.profiles    or {}
    live.profileKeys = live.profileKeys or {}
    live.global      = live.global      or {}
    live.char        = live.char        or {}
    live.keyMode     = live.keyMode     or self.sv.keyMode or "char"
    self.sv = live
    self.global = Core.applyDefaults(live.global, self.defaults.global or {})
    live.char[self.charKey] = Core.applyDefaults(live.char[self.charKey] or {}, self.defaults.char or {})
    self.char = live.char[self.charKey]
    self:_Select(self:_KeyFor(live.keyMode))
    self:_Fire("OnProfileChanged", self.profileName, self.profileName)
    return true
end

-- The lookup key for the current keying mode.
function DBProto:_KeyFor(mode)
    if mode == "spec" then return "spec:" .. Profiles:SpecKey() end
    if mode == "mode" then return "mode:" .. Profiles:ModeKey() end
    if mode == "class" then return "class:" .. Profiles:ClassKey() end
    return self.charKey
end

function DBProto:_Select(key)
    local name = self.sv.profileKeys[key] or "Default"
    self.sv.profileKeys[key] = name
    self.key = key
    self.profileName = name
    self.sv.profiles[name] = Core.applyDefaults(self.sv.profiles[name] or {}, self.defaults.profile or {})
    self.profile = self.sv.profiles[name]
end

-- ============================================================
-- Profile management
-- ============================================================

function DBProto:GetProfiles()
    local names = {}
    for name in pairs(self.sv.profiles) do names[#names + 1] = name end
    table.sort(names)
    return names
end

function DBProto:GetCurrentProfile() return self.profileName end

function DBProto:SetProfile(name)
    if not name or name == "" then return end
    local old = self.profileName
    self.sv.profileKeys[self.key] = name
    self:_Select(self.key)
    if old ~= name then self:_Fire("OnProfileChanged", name, old) end
end

function DBProto:CopyProfile(from)
    local src = self.sv.profiles[from]
    if not src or from == self.profileName then return false end
    Core.wipe(self.profile)
    for k, v in pairs(Core.copy(src)) do self.profile[k] = v end
    Core.applyDefaults(self.profile, self.defaults.profile or {})
    self:_Fire("OnProfileChanged", self.profileName, self.profileName)
    return true
end

function DBProto:ResetProfile()
    Core.wipe(self.profile)
    Core.applyDefaults(self.profile, self.defaults.profile or {})
    self:_Fire("OnProfileReset", self.profileName)
end

function DBProto:DeleteProfile(name)
    if name == self.profileName or name == "Default" then return false end
    self.sv.profiles[name] = nil
    for key, pname in pairs(self.sv.profileKeys) do
        if pname == name then self.sv.profileKeys[key] = "Default" end
    end
    return true
end

-- "char" (default), "spec", "class" or "mode" (game mode + hardcore).
function DBProto:SetKeyMode(mode)
    self.sv.keyMode = mode
    local old = self.profileName
    self:_Select(self:_KeyFor(mode))
    if old ~= self.profileName then self:_Fire("OnProfileChanged", self.profileName, old) end
end

function DBProto:GetKeyMode() return self.sv.keyMode end

function DBProto:On(event, fn)
    self.callbacks[event] = self.callbacks[event] or {}
    table.insert(self.callbacks[event], fn)
end

function DBProto:_Fire(event, ...)
    local hs = self.callbacks[event]
    if not hs then return end
    for i = 1, #hs do pcall(hs[i], ...) end
end

-- ============================================================
-- Serializer
-- ============================================================
-- Length-prefixed, so any byte content survives. Encoded once more for chat
-- safety: "|" and "~" are escaped, everything else passes through.
--
--   S<len>:<bytes>   string
--   N<repr>;         number
--   T / F            booleans
--   {  k v k v  }    table

local function serialize(v, out)
    local t = type(v)
    if t == "string" then
        out[#out + 1] = "S" .. #v .. ":" .. v
    elseif t == "number" then
        out[#out + 1] = "N" .. string.format("%.17g", v) .. ";"
    elseif t == "boolean" then
        out[#out + 1] = v and "T" or "F"
    elseif t == "table" then
        out[#out + 1] = "{"
        for k, val in pairs(v) do
            local kt, vt = type(k), type(val)
            if (kt == "string" or kt == "number") and (vt ~= "function" and vt ~= "userdata") then
                serialize(k, out)
                serialize(val, out)
            end
        end
        out[#out + 1] = "}"
    else
        out[#out + 1] = "F"
    end
end

local function deserialize(s, pos)
    local c = s:sub(pos, pos)
    if c == "S" then
        local len, colon = s:match("^(%d+)():", pos + 1)
        if not len then error("bad string at " .. pos) end
        local start = colon + 1
        len = tonumber(len)
        return s:sub(start, start + len - 1), start + len
    elseif c == "N" then
        local num, after = s:match("^([^;]+);()", pos + 1)
        if not num then error("bad number at " .. pos) end
        return tonumber(num), after
    elseif c == "T" then return true, pos + 1
    elseif c == "F" then return false, pos + 1
    elseif c == "{" then
        local t = {}
        pos = pos + 1
        while s:sub(pos, pos) ~= "}" do
            if pos > #s then error("unterminated table") end
            local k, v
            k, pos = deserialize(s, pos)
            v, pos = deserialize(s, pos)
            t[k] = v
        end
        return t, pos + 1
    end
    error("unexpected byte at " .. pos)
end

function Core.Serialize(v)
    local out = {}
    serialize(v, out)
    return table.concat(out)
end

function Core.Deserialize(s)
    local ok, v = pcall(function() return (deserialize(s, 1)) end)
    if ok then return v end
    return nil, v
end

-- Single pass each way. A two-pass gsub would turn a literal "~p" in the
-- payload into "|" on the way back.
local ENC = { ["~"] = "~~", ["|"] = "~p" }
local DEC = { ["~"] = "~", ["p"] = "|" }

local function encode(s)
    return (s:gsub("[~|]", ENC))
end

local function decode(s)
    return (s:gsub("~(.)", DEC))
end

local PREFIX = "WICK1:"

-- Export the current profile as a paste-able string.
function DBProto:Export(extra)
    local payload = { addon = self.addon.name, version = self.addon.version, profile = self.profile, extra = extra }
    return PREFIX .. encode(Core.Serialize(payload))
end

-- Import a string into the current profile. Returns true, payload or false, reason.
function DBProto:Import(str, allowOtherAddon)
    str = Core.trim(str or "")
    if str:sub(1, #PREFIX) ~= PREFIX then return false, "not a Wick export string" end
    local payload, err = Core.Deserialize(decode(str:sub(#PREFIX + 1)))
    if type(payload) ~= "table" or type(payload.profile) ~= "table" then
        return false, err or "malformed"
    end
    if payload.addon ~= self.addon.name and not allowOtherAddon then
        return false, "string is for " .. tostring(payload.addon)
    end
    Core.wipe(self.profile)
    for k, v in pairs(payload.profile) do self.profile[k] = v end
    Core.applyDefaults(self.profile, self.defaults.profile or {})
    self:_Fire("OnProfileChanged", self.profileName, self.profileName)
    return true, payload
end
