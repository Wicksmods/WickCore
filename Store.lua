-- WickCore
-- Store.lua: settings kept in macros, for a client that will not keep them.
--
-- The Forever beta writes every addon's saved variables at logout and hands
-- back nothing at load. Macros are the one thing an addon can write that
-- provably comes back: they live on the server, survive a restart and a
-- relog, and follow the account to another machine. The Probe confirmed it
-- on 2026-09-21: an account macro written before a full quit was readable
-- again at PLAYER_LOGIN, and 240-character bodies round-trip intact.
--
-- So every Wick saved variable is serialized, dictionary-coded, base64'd
-- and spread across macros named WickCfg01, WickCfg02 and so on. Nothing
-- with any other name is ever read, edited or deleted.
--
-- Two facts shape the design.
--
-- Macros are not there at ADDON_LOADED. They arrive from the server about
-- half a second later and are reliably readable by PLAYER_LOGIN. So the
-- restore happens as each addon enables, which is at login, and the
-- addon's db is rebound to the restored table before its OnEnable runs.
-- Every product applies its settings in OnEnable, so none of them ever
-- sees defaults.
--
-- Whether this should run at all is decided by one fact, not a guess. If
-- the client handed WickCoreDB over at binding time, it is loading saved
-- variables and this stays out of the way entirely. The predecessor to
-- this guessed from "three globals look populated" and switched itself off
-- every login, because every addon populates its own defaults. That is why
-- it never saved a single macro.

local ADDON = ...
local Core = LibStub("WickCore-1.0", true)
if not Core or Core._sourceAddon ~= ADDON then return end

local Store = {}
Core.Store = Store

Store.PREFIX  = "WickCfg"    -- WickCfg01 .. WickCfg60
Store.CHUNK   = 240          -- a macro body holds 255; leave room
Store.MAX     = 60           -- of 120 account slots
Store.ICON    = 134400       -- INV_Misc_QuestionMark, a fileID this client accepts
Store.HEADER  = "WC1"
Store.DEBOUNCE = 10          -- seconds after a change before writing
Store.PERIOD   = 60          -- and a sweep this often regardless

Store.restored = {}          -- addon name -> its savedVar, once handed back from the store
Store.enabled  = nil         -- decided at first enable
Store.reason   = nil

local function say(msg) Core.Print("WickCore", msg) end

-- ============================================================
-- Serializer
-- ============================================================
-- Settings repeat their strings relentlessly: the same keys turn up in
-- every profile of every addon. Every string seen twice goes in a
-- dictionary and is referred to by number. Keys are emitted in sorted
-- order so the same table always produces the same text, which is what
-- lets "has anything changed" be a string compare.

local function collect(v, counts)
    local t = type(v)
    if t == "string" then
        counts[v] = (counts[v] or 0) + 1
    elseif t == "table" then
        for k, val in pairs(v) do
            local kt, vt = type(k), type(val)
            if (kt == "string" or kt == "number") and vt ~= "function" and vt ~= "userdata" then
                collect(k, counts)
                collect(val, counts)
            end
        end
    end
end

local function sortedKeys(t)
    local keys = {}
    for k, v in pairs(t) do
        local kt, vt = type(k), type(v)
        if (kt == "string" or kt == "number") and vt ~= "function" and vt ~= "userdata" then
            keys[#keys + 1] = k
        end
    end
    table.sort(keys, function(a, b)
        local ta, tb = type(a), type(b)
        if ta ~= tb then return ta < tb end
        return a < b
    end)
    return keys
end

local function ser(v, out, dict)
    local t = type(v)
    if t == "string" then
        local i = dict[v]
        if i then out[#out + 1] = "R" .. i .. ";"
        else out[#out + 1] = "S" .. #v .. ":" .. v end
    elseif t == "number" then
        out[#out + 1] = "N" .. tostring(v) .. ";"
    elseif t == "boolean" then
        out[#out + 1] = v and "T" or "F"
    elseif t == "table" then
        out[#out + 1] = "{"
        for _, k in ipairs(sortedKeys(v)) do
            ser(k, out, dict)
            ser(v[k], out, dict)
        end
        out[#out + 1] = "}"
    else
        out[#out + 1] = "F"
    end
end

local function deser(s, pos, dict)
    local c = s:sub(pos, pos)
    if c == "S" then
        local len, colon = s:match("^(%d+)():", pos + 1)
        if not len then error("bad string at " .. pos) end
        local start = colon + 1
        len = tonumber(len)
        return s:sub(start, start + len - 1), start + len
    elseif c == "R" then
        local n, after = s:match("^(%d+);()", pos + 1)
        if not n then error("bad reference at " .. pos) end
        local str = dict[tonumber(n)]
        if str == nil then error("reference outside the dictionary at " .. pos) end
        return str, after
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
            k, pos = deser(s, pos, dict)
            v, pos = deser(s, pos, dict)
            t[k] = v
        end
        return t, pos + 1
    end
    error("unexpected byte at " .. pos)
end

function Store:Encode(tbl)
    local counts = {}
    collect(tbl, counts)
    local list, index = {}, {}
    for str, n in pairs(counts) do
        -- A string seen once costs more as a reference than written out.
        if n >= 2 then list[#list + 1] = str end
    end
    table.sort(list)
    for i, str in ipairs(list) do index[str] = i end

    local o = { self.HEADER, "D", tostring(#list), ";" }
    for _, str in ipairs(list) do o[#o + 1] = #str .. ":" .. str end
    ser(tbl, o, index)
    return table.concat(o)
end

function Store:Decode(payload)
    if type(payload) ~= "string" or payload:sub(1, #self.HEADER) ~= self.HEADER then
        return nil, "not a store payload"
    end
    local ok, result = pcall(function()
        local count, pos = payload:match("^D(%d+);()", #self.HEADER + 1)
        if not count then error("bad dictionary") end
        local list = {}
        for i = 1, tonumber(count) do
            local len, colon = payload:match("^(%d+)():", pos)
            if not len then error("bad dictionary entry " .. i) end
            local start = colon + 1
            len = tonumber(len)
            list[i] = payload:sub(start, start + len - 1)
            pos = start + len
        end
        return (deser(payload, pos, list))
    end)
    if ok then return result end
    return nil, result
end

-- Base64, so a body is plain text whatever the settings contain.
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local ENC, DEC = {}, {}
for i = 1, 64 do
    local ch = B64:sub(i, i)
    ENC[i - 1] = ch
    DEC[ch] = i - 1
end

local function b64enc(s)
    local o, n = {}, 0
    for i = 1, #s, 3 do
        local a, b, c = s:byte(i, i + 2)
        local v = a * 65536 + (b or 0) * 256 + (c or 0)
        n = n + 1
        o[n] = ENC[math.floor(v / 262144)] .. ENC[math.floor(v / 4096) % 64]
            .. (b and ENC[math.floor(v / 64) % 64] or "=")
            .. (c and ENC[v % 64] or "=")
    end
    return table.concat(o)
end

local function b64dec(s)
    s = s:gsub("[^A-Za-z0-9+/]", "")
    local o, n = {}, 0
    for i = 1, #s, 4 do
        local c1, c2 = DEC[s:sub(i, i)], DEC[s:sub(i + 1, i + 1)]
        if not c1 or not c2 then break end
        local c3, c4 = DEC[s:sub(i + 2, i + 2)], DEC[s:sub(i + 3, i + 3)]
        local v = c1 * 262144 + c2 * 4096 + (c3 or 0) * 64 + (c4 or 0)
        n = n + 1
        o[n] = string.char(math.floor(v / 65536))
            .. (c3 and string.char(math.floor(v / 256) % 256) or "")
            .. (c4 and string.char(v % 256) or "")
    end
    return table.concat(o)
end

Store.b64enc, Store.b64dec = b64enc, b64dec

-- ============================================================
-- Macros
-- ============================================================
-- Only the account scope, and only names of ours. Account slots are
-- packed 1..GetNumMacros(); GetMacroIndexByName is not trusted, because
-- on this build it only searched one scope.

local NAME_PATTERN = "^" .. Store.PREFIX .. "(%d%d)$"

local function nameFor(i) return ("%s%02d"):format(Store.PREFIX, i) end

local function ours()
    local found = {}
    if not GetNumMacros or not GetMacroInfo then return found end
    local g = GetNumMacros()
    for i = 1, (g or 0) do
        local name, _, body = GetMacroInfo(i)
        local n = name and tonumber(name:match(NAME_PATTERN))
        if n then found[n] = { index = i, body = body or "" } end
    end
    return found
end
Store.Ours = ours

function Store:MacrosPresent()
    if not GetNumMacros then return false end
    local g, c = GetNumMacros()
    return (g or 0) + (c or 0) > 0
end

-- Read everything of ours and decode it. nil when nothing is stored, or
-- when the macros have not arrived yet: the two look the same and the
-- caller decides which by asking MacrosPresent.
function Store:Read()
    local mine = ours()
    local parts = {}
    local i = 1
    while mine[i] do
        parts[#parts + 1] = mine[i].body
        i = i + 1
    end
    if #parts == 0 then return nil end
    local decoded, err = self:Decode(b64dec(table.concat(parts)))
    if type(decoded) ~= "table" then
        self.readError = err
        return nil
    end
    return decoded, #parts
end

function Store:Write(tbl)
    if not CreateMacro or not EditMacro then return false, "no macro api" end
    if InCombatLockdown and InCombatLockdown() then return false, "in combat" end

    local payload = self:Encode(tbl)
    local encoded = b64enc(payload)
    local needed = math.ceil(#encoded / self.CHUNK)

    -- Over budget: shed the heaviest addon rather than save nothing.
    self.dropped = nil
    while needed > self.MAX do
        local worst, worstSize
        for name, value in pairs(tbl) do
            local size = #b64enc(self:Encode({ [name] = value }))
            if not worstSize or size > worstSize then worst, worstSize = name, size end
        end
        if not worst then return false, "too big and nothing to drop" end
        tbl[worst] = nil
        self.dropped = (self.dropped and (self.dropped .. ", ") or "") .. worst
        if next(tbl) == nil then return false, "too big for the macro budget" end
        payload = self:Encode(tbl)
        encoded = b64enc(payload)
        needed = math.ceil(#encoded / self.CHUNK)
    end

    local mine = ours()
    for i = 1, needed do
        local body = encoded:sub((i - 1) * self.CHUNK + 1, i * self.CHUNK)
        local have = mine[i]
        if have then
            if have.body ~= body then
                local ok, err = pcall(EditMacro, have.index, nameFor(i), self.ICON, body)
                if not ok then return false, "EditMacro: " .. tostring(err) end
            end
        else
            -- A boolean, never 1: the Classic-line binding reads integer 1
            -- as false. nil is "account", and account is what we want.
            local ok, slot = pcall(CreateMacro, nameFor(i), self.ICON, body, nil)
            if not ok then return false, "CreateMacro: " .. tostring(slot) end
            if type(slot) ~= "number" then return false, "out of macro slots" end
        end
    end
    -- Leftovers from a larger save, highest slot first so the indexes of
    -- the ones still to delete do not shift under us.
    local extra = {}
    for n, m in pairs(mine) do if n > needed then extra[#extra + 1] = m.index end end
    table.sort(extra, function(a, b) return a > b end)
    for _, idx in ipairs(extra) do pcall(DeleteMacro, idx) end

    self.lastEncoded = encoded
    self.lastCount = needed
    self.lastBytes = #encoded
    return true, needed
end

function Store:Clear()
    local mine = ours()
    local idx = {}
    for _, m in pairs(mine) do idx[#idx + 1] = m.index end
    table.sort(idx, function(a, b) return a > b end)
    local n = 0
    for _, i in ipairs(idx) do
        if pcall(DeleteMacro, i) then n = n + 1 end
    end
    self.lastEncoded = nil
    return n
end

-- ============================================================
-- Deciding whether to run
-- ============================================================
-- One fact: did the client hand WickCoreDB over at binding. WickCore
-- always has a saved variable on disk after the first logout, so if the
-- client loads any, it loads that one. WicksProfile assigning it at file
-- scope does not count as the client; Profiles:Init already knows that.

function Store:Decide()
    if self.enabled ~= nil then return self.enabled end
    local db = Core.self and Core.self.db
    if not db then
        self.enabled = false
        self.reason = "WickCore has no db"
        return false
    end
    if db.handedOver then
        self.enabled = false
        self.reason = "the client handed saved variables over, so they are being kept the normal way"
        return false
    end
    if not GetNumMacros then
        self.enabled = false
        self.reason = "this client has no macro API"
        return false
    end
    self.enabled = true
    self.reason = "the client handed nothing over at load"
    return true
end

-- ============================================================
-- Restore
-- ============================================================

-- The decoded store, read once per session. nil until the macros have
-- arrived; a second call after they have arrived reads them.
function Store:Data()
    if self.cache then return self.cache end
    local data, count = self:Read()
    if data then
        self.cache = data
        self.cacheCount = count
        self.stamp = data.__stamp
    elseif not self:MacrosPresent() then
        self.waiting = true
    end
    return self.cache
end

-- Called from AddonProto:_Enable, before the addon's OnEnable. Hands
-- the addon back its table if the store has one and the client did not.
function Store:RestoreFor(addon)
    if not self:Decide() then return false end
    local db = addon and addon.db
    local var = addon and addon.opts and addon.opts.savedVar
    if not db or not var or db.handedOver then return false end
    -- Keyed by addon, not by saved variable: two addons reading one
    -- variable (the harness does it; a product never should) must each
    -- be handed the table once.
    if self.restored[addon.name] then return false end
    local data = self:Data()
    if not data or type(data[var]) ~= "table" then
        if self.waiting then self:WatchForArrival() end
        return false
    end
    if db:RebindTo(Core.copy(data[var])) then
        self.restored[addon.name] = var
        return true
    end
    return false
end

-- Every enabled addon at once, for the late-arrival case.
function Store:RestoreAll()
    local n = 0
    for _, addon in Core:IterateAddons() do
        if addon.enabled and self:RestoreFor(addon) then n = n + 1 end
    end
    if n > 0 and Core.Chrome and Core.Chrome.ApplySavedTheme then
        pcall(Core.Chrome.ApplySavedTheme, Core.Chrome, "store")
    end
    return n
end

-- Macros arrive from the server a moment after addons load. On this
-- client that moment is before PLAYER_LOGIN, but a slower login could
-- push it later, so anyone who asked before they arrived gets them when
-- they do.
function Store:Poll()
    if self.cache then return true end
    local data = self:Data()
    if not data then return false end
    self.waiting = false
    local n = self:RestoreAll()
    if n > 0 then
        say(("settings arrived a moment late and were put back for %d addon%s."):format(n, n == 1 and "" or "s"))
    end
    return true
end

function Store:WatchForArrival()
    if self.watching or not (C_Timer and C_Timer.NewTicker) then return end
    self.watching = true
    local ticks = 0
    local t
    t = C_Timer.NewTicker(0.5, function()
        ticks = ticks + 1
        if self:Poll() or ticks >= 60 then
            t:Cancel()
            self.watching = false
        end
    end)
end

-- ============================================================
-- Save
-- ============================================================

function Store:Snapshot()
    local out, count = {}, 0
    for _, addon in Core:IterateAddons() do
        local var = addon.opts and addon.opts.savedVar
        local db = addon.db
        if var and db and type(db.sv) == "table" then
            out[var] = db.sv
            count = count + 1
        end
    end
    out.__stamp = date and date("%Y-%m-%d %H:%M") or nil
    return out, count
end

-- Write only when something changed, unless forced. In combat the write
-- is refused by the client, so it is remembered and done when combat
-- ends.
function Store:Save(force)
    if not self:Decide() then return false, self.reason end
    local snap, count = self:Snapshot()
    if count == 0 then return false, "nothing to save" end
    if InCombatLockdown and InCombatLockdown() then
        self.pendingAfterCombat = true
        return false, "in combat"
    end
    -- The stamp changes every minute; compare without it or nothing is
    -- ever "unchanged".
    local stamp = snap.__stamp
    snap.__stamp = nil
    local encoded = b64enc(self:Encode(snap))
    snap.__stamp = stamp
    if not force and encoded == self.lastEncoded then return true, 0 end
    local ok, info = self:Write(snap)
    if ok then
        self.lastEncoded = encoded
        self.pendingAfterCombat = nil
        if self.dropped and self.warnedDropped ~= self.dropped then
            self.warnedDropped = self.dropped
            say("settings are larger than the macro budget, so these are not being kept: " .. self.dropped)
        end
    else
        if self.lastFailure ~= info then
            self.lastFailure = info
            say("could not save settings to macros: " .. tostring(info))
        end
    end
    return ok, info
end

-- Something changed. Save soon, not now: options pages change several
-- things in a row.
function Store:Dirty()
    if self.enabled == false then return end
    self.dirtyToken = (self.dirtyToken or 0) + 1
    local token = self.dirtyToken
    if C_Timer and C_Timer.After then
        C_Timer.After(self.DEBOUNCE, function()
            if token == self.dirtyToken then self:Save() end
        end)
    else
        self:Save()
    end
end

-- ============================================================
-- Wiring
-- ============================================================

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_LOGOUT")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        if not Store:Decide() then return end
        -- Anyone who enabled before the macros arrived is picked up here.
        if Store.waiting then Store:Poll() end
        local n = 0
        for _ in pairs(Store.restored) do n = n + 1 end
        if n > 0 then
            say(("settings put back from %d macro%s%s."):format(Store.cacheCount or 0,
                (Store.cacheCount or 0) == 1 and "" or "s",
                Store.stamp and (", saved " .. Store.stamp) or ""))
        elseif Store.cache then
            say("a settings store exists in your macros but nothing here needed it.")
        else
            say("this client hands no settings back at load, so they will be kept in macros named " .. Store.PREFIX .. "NN from here on.")
        end
        if C_Timer and C_Timer.NewTicker then
            C_Timer.NewTicker(Store.PERIOD, function() Store:Save() end)
        end
        -- The first snapshot, once every addon has enabled.
        if C_Timer and C_Timer.After then C_Timer.After(5, function() Store:Save() end) end
    elseif event == "PLAYER_LOGOUT" then
        -- Best effort. The periodic save is what this relies on; this
        -- only catches the last minute.
        if Store.enabled then Store:Save() end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if Store.pendingAfterCombat then Store:Save() end
    end
end)

-- /wickcore store [save|clear]
function Store:Command(arg)
    arg = Core.trim(arg or ""):lower()
    if arg == "save" then
        local ok, info = self:Save(true)
        say(ok and ("saved into %d macro%s, %d characters."):format(info, info == 1 and "" or "s", self.lastBytes or 0)
            or ("not saved: " .. tostring(info)))
        return
    end
    if arg == "clear" then
        local n = self:Clear()
        say(("removed %d %s macro%s. Settings will be saved again in a minute unless you disable this."):format(n, self.PREFIX, n == 1 and "" or "s"))
        return
    end
    self:Decide()
    say(("store: %s (%s)."):format(self.enabled and "on" or "off", tostring(self.reason)))
    local mine = ours()
    local n = 0
    for _ in pairs(mine) do n = n + 1 end
    say(("macros: %d of %d used, %s."):format(n, self.MAX, self.stamp and ("last saved " .. self.stamp) or "nothing read this session"))
    local names = {}
    for name in pairs(self.restored) do names[#names + 1] = name end
    table.sort(names)
    say("put back this session: " .. (#names > 0 and table.concat(names, ", ") or "nothing"))
    if self.readError then say("last read error: " .. tostring(self.readError)) end
end
