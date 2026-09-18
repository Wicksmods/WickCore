-- WickCore
-- Core.lua — library registration, addon objects, event bus, utilities.
--
-- WickCore is the floor every Wick product stands on. It can load as its own
-- addon or be embedded under Libs/ in a product; LibStub keeps the newest copy.
-- Every other file in this library checks Core._sourceAddon so that an older
-- embedded copy stays silent when a newer one has already been accepted.

local ADDON = ...
local MAJOR, MINOR = "WickCore-1.0", 1

local Core = LibStub:NewLibrary(MAJOR, MINOR)
if not Core then return end

Core._sourceAddon = ADDON
Core.MAJOR, Core.MINOR = MAJOR, MINOR
Core.VERSION = "0.3.0"
_G.WickCore = Core

-- Persist across a same-session upgrade of the library.
Core.addons = Core.addons or {}
Core.order  = Core.order  or {}
Core.debug  = Core.debug  or false

-- ============================================================
-- Utilities
-- ============================================================

-- Lua 5.1 has no table.pack. Trailing nils matter to us.
function Core.pack(...)
    return { n = select("#", ...), ... }
end

-- pcall that returns (true, ...) or (false, err). Errors are logged when
-- Core.debug is on and never propagate.
function Core.safe(fn, ...)
    local r = Core.pack(pcall(fn, ...))
    if r[1] then
        return true, unpack(r, 2, r.n)
    end
    if Core.debug then Core.Print("WickCore", "error: " .. tostring(r[2])) end
    return false, r[2]
end

function Core.split(s, sep)
    local out = {}
    for piece in string.gmatch(s .. sep, "(.-)" .. sep:gsub("%p", "%%%0")) do
        out[#out + 1] = piece
    end
    return out
end

function Core.trim(s)
    return (tostring(s):gsub("^%s+", ""):gsub("%s+$", ""))
end

function Core.wipe(t)
    for k in pairs(t) do t[k] = nil end
    return t
end

-- Deep copy with defaults applied: any key missing in dst is copied from src.
function Core.applyDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            Core.applyDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

function Core.copy(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = Core.copy(v) end
    return out
end

-- Compare "1.2.3" style versions. Returns -1, 0, 1.
function Core.compareVersions(a, b)
    local pa, pb = Core.split(tostring(a), "."), Core.split(tostring(b), ".")
    for i = 1, math.max(#pa, #pb) do
        local x, y = tonumber(pa[i]) or 0, tonumber(pb[i]) or 0
        if x < y then return -1 end
        if x > y then return 1 end
    end
    return 0
end

Core.COLOR_ACCENT = "|cff4FC778"
Core.COLOR_TEXT   = "|cffD4C8A1"

function Core.Print(prefix, msg)
    local frame = DEFAULT_CHAT_FRAME
    if not frame then return end
    frame:AddMessage(Core.COLOR_ACCENT .. tostring(prefix) .. "|r: " .. tostring(msg))
end

-- ============================================================
-- Addon objects
-- ============================================================
--
-- local A = WickCore:NewAddon("WicksBags", {
--     title    = "Wick's Bags",
--     version  = "1.0.0",
--     savedVar = "WicksBagsDB",
--     defaults = { profile = { ... }, global = { ... } },
-- })
-- function A:OnInitialize() ... end   -- saved variables ready
-- function A:OnEnable() ... end       -- player logged in

local AddonProto = {}
AddonProto.__index = AddonProto

function Core:NewAddon(name, opts)
    opts = opts or {}
    if self.addons[name] then return self.addons[name] end

    local A = setmetatable({
        name     = name,
        title    = opts.title or name,
        version  = opts.version,
        opts     = opts,
        handlers = {},
    }, AddonProto)

    A.frame = CreateFrame("Frame")
    A.frame:SetScript("OnEvent", function(_, event, ...)
        local hs = A.handlers[event]
        if not hs then return end
        for i = 1, #hs do
            local ok, err = pcall(hs[i], ...)
            if not ok then A:Debug(event .. " handler: " .. tostring(err)) end
        end
    end)

    -- opts.loadedName lets an embedded copy key its init off the host addon.
    local loadedName = opts.loadedName or name
    A:On("ADDON_LOADED", function(loaded)
        if loaded ~= loadedName then return end
        A:_Init()
    end)
    A:On("PLAYER_LOGIN", function()
        -- Login is the first moment the saved variable is certainly the
        -- client's own table, so adopt it before anything reads settings.
        if A.db and A.db.Rebind then Core.safe(A.db.Rebind, A.db) end
        A:_Enable()
    end)

    self.addons[name] = A
    table.insert(self.order, name)
    return A
end

function Core:GetAddon(name) return self.addons[name] end

function Core:IterateAddons()
    local i = 0
    return function()
        i = i + 1
        local name = self.order[i]
        if name then return name, self.addons[name] end
    end
end

-- Register a handler. Game events are registered on the addon frame; names
-- starting with WICK_ are internal and only reachable through :Fire.
function AddonProto:On(event, fn)
    local hs = self.handlers[event]
    if not hs then
        hs = {}
        self.handlers[event] = hs
        if not event:find("^WICK_") then
            pcall(self.frame.RegisterEvent, self.frame, event)
        end
    end
    hs[#hs + 1] = fn
    return self
end

function AddonProto:Off(event)
    self.handlers[event] = nil
    if not event:find("^WICK_") then
        pcall(self.frame.UnregisterEvent, self.frame, event)
    end
end

function AddonProto:Fire(event, ...)
    local hs = self.handlers[event]
    if not hs then return end
    for i = 1, #hs do
        local ok, err = pcall(hs[i], ...)
        if not ok then self:Debug(event .. " handler: " .. tostring(err)) end
    end
end

function AddonProto:_Init()
    if self.initialized then return end
    self.initialized = true
    if self.opts.savedVar then
        self.db = Core.Profiles:Init(self, self.opts.savedVar, self.opts.defaults)
    end
    self.L = Core.Locale:Get(self.name)
    if self.OnInitialize then Core.safe(self.OnInitialize, self) end
    -- A LoadOnDemand addon initializes after PLAYER_LOGIN already fired.
    if IsLoggedIn and IsLoggedIn() then self:_Enable() end
end

function AddonProto:_Enable()
    if self.enabled or not self.initialized then return end
    self.enabled = true
    -- Adopt the real saved-variable table if our binding beat the client to it.
    if self.db and self.db.Rebind then Core.safe(self.db.Rebind, self.db) end
    if self.version then Core.Version:Register(self) end
    if self.OnEnable then Core.safe(self.OnEnable, self) end
end

function AddonProto:Print(msg) Core.Print(self.title, msg) end

function AddonProto:Debug(msg)
    if Core.debug then Core.Print(self.title .. " debug", msg) end
end

-- A:RegisterSlash(fn, "/wbags", "/wb")
function AddonProto:RegisterSlash(fn, ...)
    local key = "WICK_" .. self.name:upper():gsub("[^%w]", "")
    for i = 1, select("#", ...) do
        _G["SLASH_" .. key .. i] = select(i, ...)
    end
    SlashCmdList[key] = function(msg)
        Core.safe(fn, self, Core.trim(msg or ""))
    end
end

-- Convenience passthroughs so products do not reach into Core.* directly.
function AddonProto:RegisterOptions(buildFn) return Core.Options:Register(self, buildFn) end
function AddonProto:OpenOptions() return Core.Options:Open(self.name) end
function AddonProto:RegisterLauncher(opts) return Core.Launcher:Register(self, opts) end
function AddonProto:NewLocale(locale, isDefault) return Core.Locale:New(self.name, locale, isDefault) end

-- ============================================================
-- WickCore's own addon object and /wickcore
-- ============================================================

Core.self = Core:NewAddon("WickCore", {
    title      = "WickCore",
    version    = Core.VERSION,
    savedVar   = "WickCoreDB",
    loadedName = ADDON,
    defaults   = {
        global = {
            minimap = { angle = 220, hidden = false },
            debug   = false,
            theme   = "fel",     -- a theme id, or "auto" for the class theme
            classColors = "client",  -- "client" or "classic" for the TBC-era codes
            custom  = { main = "383058", accent = "4FC778" },  -- the Custom theme's two colors
        },
    },
})

function Core.self:OnInitialize()
    Core.debug = self.db.global.debug and true or false
    if Core.Chrome and Core.Chrome.ApplySavedTheme then Core.Chrome:ApplySavedTheme("init") end
end

function Core.self:OnEnable()
    self:RegisterSlash(function(_, msg)
        if msg == "debug" then
            Core.debug = not Core.debug
            self.db.global.debug = Core.debug
            self:Print("debug " .. (Core.debug and "on" or "off"))
        elseif msg == "dialect" then
            for _, line in ipairs(Core.Dialect:Report()) do self:Print(line) end
        elseif msg == "addons" then
            for name, A in Core:IterateAddons() do
                self:Print(string.format("%s %s%s", A.title, A.version or "?",
                    A.enabled and "" or " (not enabled)"))
            end
        elseif msg:match("^store") then
            if msg:match("clear") then
                for key in pairs(Core.Persist and Core.Persist.tracked or {}) do Core.Persist:Clear(key) end
                self:Print("settings store cleared.")
            else
                self:Print("settings store: " .. (Core.Persist and Core.Persist:Report() or "not loaded"))
            end
        elseif msg == "options" then
            self:OpenOptions()
        elseif msg:match("^theme") then
            local want = msg:match("^theme%s+(%S+)")
            local Chrome = Core.Chrome
            if want == "dump" then
                -- The class colors this client reports, for comparing against other UIs.
                for _, t in ipairs(Chrome.Themes) do
                    self:Print(("%-8s accent %s  void %s  shadow %s  border %s  text %s"):format(
                        t.id, "|cff" .. t.hex.fel .. t.hex.fel .. "|r", t.hex.void, t.hex.shadow, t.hex.border, t.hex.text))
                end
            elseif not want or want == "list" then
                local names = {}
                for _, t in ipairs(Chrome.Themes) do
                    names[#names + 1] = (t.id == Chrome.activeTheme and "|cff" .. t.hex.fel .. t.id .. "|r" or t.id)
                end
                local saved = Chrome:SavedThemeSetting()
                self:Print("theme: " .. tostring(Chrome:ThemeSetting()) .. " (" .. Chrome.activeTheme .. "), class colors: " .. Chrome.classColorSet .. ". Use /wickcore theme <id|auto|classic|client|dump>.")
                self:Print("saved to disk: " .. tostring(saved) .. (saved == Chrome:ThemeSetting() and "" or "  |cffE04B4B(not matching, report this)|r"))
                self:Print("applied this session: " .. tostring(Chrome.applyLog or "never"))
                self:Print("at file load: " .. tostring(Chrome.bootTrace or "?"))
                local vt = Core.Profiles and Core.Profiles.varTypes
                if vt then
                    local parts = {}
                    for name, t in pairs(vt) do parts[#parts + 1] = name .. "=" .. t end
                    table.sort(parts)
                    self:Print("every saved variable at binding: " .. table.concat(parts, "  "))
                end
                local tr = Core.Profiles and Core.Profiles.traces
                self:Print("WickCoreDB at binding: " .. tostring(tr and tr.WickCoreDB or "never bound"))
                self:Print("WickCoreDB now: " .. type(rawget(_G, "WickCoreDB"))
                    .. ", db bound: " .. tostring(Core.self.db ~= nil)
                    .. ", db.sv is the global: " .. tostring(Core.self.db and Core.self.db.sv == rawget(_G, "WickCoreDB")))
                self:Print("live table now: theme=" .. tostring(rawget(_G, "WickCoreDB") and WickCoreDB.global and WickCoreDB.global.theme))
                self:Print("custom: /wickcore theme custom <main hex> <accent hex>, or pick colors on the options page.")
                self:Print("themes: " .. table.concat(names, " "))
            elseif want == "custom" and msg:match("^theme%s+custom%s+%S") then
                local main, accent = msg:match("^theme%s+custom%s+#?(%x+)%s*#?(%x*)")
                local t = Chrome:SetCustomColors(main, accent ~= "" and accent or nil)
                Chrome:SetTheme("custom")
                self:Print(("custom theme: main %s, accent |cff%s%s|r"):format(Chrome.customColors.main, t.hex.fel, Chrome.customColors.accent))
            elseif want == "classic" or want == "client" then
                Chrome:SetClassColorSet(want)
                self:Print("class colors: " .. (want == "classic" and "Classic-era set (as TBC UIs show them)" or "this client's set"))
            elseif want == "auto" or want == "class" or Chrome.ThemeByID[want] then
                local t = Chrome:SetTheme(want)
                self:Print("theme set to " .. t.name .. (want == "auto" and " (following your class)" or ""))
            else
                self:Print("unknown theme '" .. want .. "'. /wickcore theme list")
            end
        else
            for _, line in ipairs(Core.Client:Report()) do self:Print(line) end
            self:Print("restrictions: " .. Core.Restrict:Summary())
            self:Print("/wickcore dialect | addons | options | theme | store | debug")
        end
    end, "/wickcore", "/wc")

    self:RegisterLauncher({
        tooltip = function(tt)
            tt:AddLine(Core.COLOR_TEXT .. "Wick's|r " .. Core.COLOR_ACCENT .. "Mods|r")
            for name, A in Core:IterateAddons() do
                if A ~= Core.self then
                    tt:AddDoubleLine(A.title, A.version or "", 0.83, 0.78, 0.63, 0.5, 0.5, 0.5)
                end
            end
            tt:AddLine(" ")
            tt:AddLine("Left-click: hub   Right-click: options", 0.5, 0.5, 0.5)
        end,
    })
end
