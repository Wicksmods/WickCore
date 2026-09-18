-- WickCore
-- Persist.lua — a settings store for a client that never reads saved
-- variables back.
--
-- On the Forever beta, every addon's saved variables are written at logout
-- and come back empty at load, so nothing a player configures survives.
-- Console variables do survive, through a different mechanism, so this
-- keeps a copy of each store there and restores it when the client hands
-- us nothing. It engages only in that case: on a client that loads saved
-- variables properly it does nothing at all.
--
-- The copy is serialized, base64 encoded so the value is safe inside
-- Config.wtf, and split across numbered console variables because each
-- one holds a limited amount of text.

local ADDON = ...
local Core = LibStub("WickCore-1.0", true)
if not Core or Core._sourceAddon ~= ADDON then return end

local Persist = {}
Core.Persist = Persist

local CHUNK      = 900   -- characters per console variable
local MAX_CHUNKS = 24    -- about 21KB encoded, per store

local CV = rawget(_G, "C_CVar")
local function cvGet(n) if CV and CV.GetCVar then return CV.GetCVar(n) end local f = rawget(_G, "GetCVar"); return f and f(n) end
local function cvSet(n, v) if CV and CV.SetCVar then return CV.SetCVar(n, v) end local f = rawget(_G, "SetCVar"); if f then return f(n, v) end end
local function cvRegister(n)
    if CV and CV.RegisterCVar then pcall(CV.RegisterCVar, n, "") end
end

Persist.AVAILABLE = (CV and CV.RegisterCVar and CV.SetCVar and CV.GetCVar) and true or false
Persist.engaged = false   -- true once a store had to be restored from here

-- ============================================================
-- base64, so the payload is safe as a console variable value
-- ============================================================
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local ENCMAP, DECMAP = {}, {}
for i = 1, 64 do
    local c = B64:sub(i, i)
    ENCMAP[i - 1] = c
    DECMAP[c] = i - 1
end

local function b64encode(s)
    local out, n = {}, 0
    for i = 1, #s, 3 do
        local a, b, c = s:byte(i, i + 2)
        local v = a * 65536 + (b or 0) * 256 + (c or 0)
        n = n + 1
        out[n] = ENCMAP[math.floor(v / 262144)]
            .. ENCMAP[math.floor(v / 4096) % 64]
            .. (b and ENCMAP[math.floor(v / 64) % 64] or "=")
            .. (c and ENCMAP[v % 64] or "=")
    end
    return table.concat(out)
end

local function b64decode(s)
    s = s:gsub("[^A-Za-z0-9+/]", "")
    local out, n = {}, 0
    for i = 1, #s, 4 do
        local c1, c2 = DECMAP[s:sub(i, i)], DECMAP[s:sub(i + 1, i + 1)]
        if not c1 or not c2 then break end
        local c3, c4 = DECMAP[s:sub(i + 2, i + 2)], DECMAP[s:sub(i + 3, i + 3)]
        local v = c1 * 262144 + c2 * 4096 + (c3 or 0) * 64 + (c4 or 0)
        n = n + 1
        out[n] = string.char(math.floor(v / 65536))
            .. (c3 and string.char(math.floor(v / 256) % 256) or "")
            .. (c4 and string.char(v % 256) or "")
    end
    return table.concat(out)
end

-- ============================================================
-- Store
-- ============================================================
local function slot(key, i) return ("wick_%s_%d"):format(key:lower(), i) end
local function countSlot(key) return ("wick_%s_n"):format(key:lower()) end

function Persist:Save(key, tbl)
    if not self.AVAILABLE or type(tbl) ~= "table" then return false end
    local ok, payload = pcall(Core.Serialize, tbl)
    if not ok or type(payload) ~= "string" then return false end
    local encoded = b64encode(payload)
    local n = math.ceil(#encoded / CHUNK)
    if n > MAX_CHUNKS then
        Core.Print("WickCore", ("%s is too large to keep in the console-variable store (%d KB)."):format(key, math.floor(#encoded / 1024)))
        return false
    end
    -- Clear any chunks left by a previously larger save.
    local prev = tonumber(cvGet(countSlot(key)) or "") or 0
    for i = n + 1, prev do
        cvRegister(slot(key, i))
        cvSet(slot(key, i), "")
    end
    for i = 1, n do
        cvRegister(slot(key, i))
        cvSet(slot(key, i), encoded:sub((i - 1) * CHUNK + 1, i * CHUNK))
    end
    cvRegister(countSlot(key))
    cvSet(countSlot(key), tostring(n))
    return true, n
end

function Persist:Load(key)
    if not self.AVAILABLE then return nil end
    cvRegister(countSlot(key))
    local n = tonumber(cvGet(countSlot(key)) or "") or 0
    if n < 1 then return nil end
    local parts = {}
    for i = 1, n do
        cvRegister(slot(key, i))
        local piece = cvGet(slot(key, i))
        if not piece or piece == "" then return nil end
        parts[i] = piece
    end
    local decoded = b64decode(table.concat(parts))
    if decoded == "" then return nil end
    local value = Core.Deserialize(decoded)
    return type(value) == "table" and value or nil
end

function Persist:Clear(key)
    if not self.AVAILABLE then return end
    local n = tonumber(cvGet(countSlot(key)) or "") or 0
    for i = 1, n do
        cvRegister(slot(key, i))
        cvSet(slot(key, i), "")
    end
    cvSet(countSlot(key), "0")
end

-- ============================================================
-- Tracking: every profile database that had to fall back
-- ============================================================
Persist.tracked = {}

function Persist:Track(key, db)
    self.tracked[key] = db
end

function Persist:SaveAll()
    if not self.engaged then return 0 end
    local saved = 0
    for key, db in pairs(self.tracked) do
        if db and type(db.sv) == "table" and self:Save(key, db.sv) then saved = saved + 1 end
    end
    return saved
end

function Persist:Report()
    if not self.AVAILABLE then return "console-variable store unavailable on this client" end
    if not self.engaged then return "not needed: the client loads saved variables normally" end
    local names = {}
    for key in pairs(self.tracked) do
        local n = tonumber(cvGet(countSlot(key)) or "") or 0
        names[#names + 1] = key .. "=" .. n
    end
    table.sort(names)
    return "in use, chunks per store: " .. (#names > 0 and table.concat(names, " ") or "none yet")
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGOUT")
f:SetScript("OnEvent", function() Persist:SaveAll() end)
