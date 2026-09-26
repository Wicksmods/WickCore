-- WickCore
-- Dialect.lua — one calling convention over two API generations.
--
-- The Forever probe (1.60.1.69893) showed GetItemInfo, GetSpellInfo,
-- GetSpellCooldown, UnitAura and the container globals are nil, replaced by
-- C_Item, C_Spell, C_UnitAuras and C_Container. TBC Anniversary still has the
-- legacy globals. Each function here resolves once at load and returns a
-- table with the same field names on either client.

local ADDON = ...
local Core = LibStub("WickCore-1.0", true)
if not Core or Core._sourceAddon ~= ADDON then return end

local D = {}
Core.Dialect = D
D.paths = {}

local R = Core.Restrict
local pack = Core.pack

local function ns(name) return rawget(_G, name) end
local function fn(space, method)
    local t = ns(space)
    if type(t) == "table" and type(t[method]) == "function" then return t[method] end
end
local function glob(name)
    local v = rawget(_G, name)
    if type(v) == "function" then return v end
end

-- Record which path a label took, for /wickcore dialect.
local function chose(label, modern, legacy)
    if modern then D.paths[label] = "modern"; return modern, true end
    if legacy then D.paths[label] = "legacy"; return legacy, false end
    D.paths[label] = "missing"
end

-- ============================================================
-- Items
-- ============================================================

local itemInfo, itemInfoModern = chose("GetItemInfo", fn("C_Item", "GetItemInfo"), glob("GetItemInfo"))
local ITEM_FIELDS = {
    "name", "link", "quality", "itemLevel", "minLevel", "itemType", "itemSubType",
    "stackCount", "equipLoc", "icon", "sellPrice", "classID", "subclassID",
    "bindType", "expansionID", "setID", "isCraftingReagent",
}

-- Returns nil when the item is not cached yet (same as the game does).
function D.GetItemInfo(item)
    if not itemInfo or item == nil then return nil end
    local r = pack(itemInfo(item))
    if r[1] == nil then return nil end
    local t = {}
    for i, f in ipairs(ITEM_FIELDS) do t[f] = r[i] end
    return t
end

local itemInstant = chose("GetItemInfoInstant", fn("C_Item", "GetItemInfoInstant"), glob("GetItemInfoInstant"))
function D.GetItemInfoInstant(item)
    if not itemInstant or item == nil then return nil end
    local id, itemType, subType, equipLoc, icon, classID, subclassID = itemInstant(item)
    if not id then return nil end
    return { itemID = id, itemType = itemType, itemSubType = subType, equipLoc = equipLoc,
             icon = icon, classID = classID, subclassID = subclassID }
end

-- The name alone, which this client will give for an item it has
-- never sent, where the full GetItemInfo will not. On the older client
-- there is no such shortcut, so the full one answers instead.
local itemNameByID = fn("C_Item", "GetItemNameByID")
function D.GetItemNameByID(id)
    if id == nil then return nil end
    if itemNameByID then
        local ok, n = pcall(itemNameByID, id)
        if ok and type(n) == "string" and n ~= "" then return n end
        return nil
    end
    local t = D.GetItemInfo(id)
    return t and t.name
end

local itemCount = chose("GetItemCount", fn("C_Item", "GetItemCount"), glob("GetItemCount"))
function D.GetItemCount(item, includeBank, includeUses)
    if not itemCount or item == nil then return 0 end
    return itemCount(item, includeBank, includeUses) or 0
end

local itemIconByID = fn("C_Item", "GetItemIconByID")
local itemIconLegacy = glob("GetItemIcon")
chose("GetItemIcon", itemIconByID, itemIconLegacy)
function D.GetItemIcon(item)
    if itemIconByID then return itemIconByID(item) end
    if itemIconLegacy then return itemIconLegacy(item) end
    local t = D.GetItemInfoInstant(item)
    return t and t.icon
end

local itemStats = chose("GetItemStats", fn("C_Item", "GetItemStats"), glob("GetItemStats"))
-- Returns the ITEM_MOD_* -> value map, or nil.
function D.GetItemStats(link)
    if not itemStats or not link then return nil end
    local ok, t = pcall(itemStats, link)
    if ok and type(t) == "table" then return t end
    return nil
end

local itemSpell = chose("GetItemSpell", fn("C_Item", "GetItemSpell"), glob("GetItemSpell"))
function D.GetItemSpell(item)
    if not itemSpell or item == nil then return nil end
    local name, id = itemSpell(item)
    if not name then return nil end
    return { name = name, spellID = id }
end

local qualityColor = chose("GetItemQualityColor", fn("C_Item", "GetItemQualityColor"), glob("GetItemQualityColor"))
function D.GetItemQualityColor(quality)
    if qualityColor then
        local r, g, b, hex = qualityColor(quality or 1)
        return r, g, b, hex
    end
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality or 1]
    if c then return c.r, c.g, c.b, c.hex end
    return 1, 1, 1, "|cffffffff"
end

-- ============================================================
-- Spells
-- ============================================================

local spellInfoModern = fn("C_Spell", "GetSpellInfo")
local spellInfoLegacy = glob("GetSpellInfo")
chose("GetSpellInfo", spellInfoModern, spellInfoLegacy)

function D.GetSpellInfo(spell)
    if spell == nil then return nil end
    if spellInfoModern then
        local t = spellInfoModern(spell)
        if not t then return nil end
        return { name = t.name, icon = t.iconID, originalIcon = t.originalIconID,
                 castTime = t.castTime, minRange = t.minRange, maxRange = t.maxRange,
                 spellID = t.spellID }
    elseif spellInfoLegacy then
        local name, rank, icon, castTime, minRange, maxRange, spellID, originalIcon = spellInfoLegacy(spell)
        if not name then return nil end
        return { name = name, rank = rank, icon = icon, originalIcon = originalIcon,
                 castTime = castTime, minRange = minRange, maxRange = maxRange,
                 spellID = spellID }
    end
end

local spellName = fn("C_Spell", "GetSpellName")
function D.GetSpellName(spell)
    if spellName then return spellName(spell) end
    local t = D.GetSpellInfo(spell)
    return t and t.name
end

local spellTexture = chose("GetSpellTexture", fn("C_Spell", "GetSpellTexture"), glob("GetSpellTexture"))
function D.GetSpellTexture(spell)
    if spellTexture then return spellTexture(spell) end
    local t = D.GetSpellInfo(spell)
    return t and t.icon
end

local cdModern = fn("C_Spell", "GetSpellCooldown")
local cdLegacy = glob("GetSpellCooldown")
chose("GetSpellCooldown", cdModern, cdLegacy)

-- Values may be secret in combat on a secrets client. They are still safe to
-- pass to Cooldown:SetCooldown; use Restrict:IsSecret before doing math.
function D.GetSpellCooldown(spell)
    if spell == nil then return nil end
    if cdModern then
        local ok, t = pcall(cdModern, spell)
        if not ok or not t then return nil end
        -- isActive stays a plain boolean under combat restrictions
        -- while the times go secret, so it is the one part of a
        -- cooldown a caller may actually look at mid-fight.
        return { start = t.startTime, duration = t.duration, enabled = t.isEnabled,
                 modRate = t.modRate, active = t.isActive }
    elseif cdLegacy then
        local ok, start, duration, enabled, modRate = pcall(cdLegacy, spell)
        if not ok or start == nil then return nil end
        -- No isActive here, but nothing is secret either, so the same
        -- answer can be worked out rather than left missing.
        local active
        if type(duration) == "number" then active = duration > 0 end
        return { start = start, duration = duration, enabled = enabled,
                 modRate = modRate, active = active }
    end
end

local spellKnown = chose("IsSpellKnown", fn("C_SpellBook", "IsSpellKnown"), glob("IsSpellKnown"))
function D.IsSpellKnown(spellID, isPet)
    if not spellKnown then return false end
    local ok, v = pcall(spellKnown, spellID, isPet)
    return ok and v == true
end

-- ============================================================
-- The spellbook
-- ============================================================
--
-- Asking what the player can cast, rather than asking about a spell you
-- already knew the name of. The mage kit needs it to find the teleports
-- and portals a character actually has: Forever is Classic plus its own
-- changes, so a list of cities written here would be a guess.
--
-- The two clients disagree about all of it. Modern has skill lines, a
-- numeric bank enum, and getters that return a table. Legacy has tabs,
-- the bank as the string "spell", and tuples.

local numSkillLines = fn("C_SpellBook", "GetNumSpellBookSkillLines")
local skillLineInfo = fn("C_SpellBook", "GetSpellBookSkillLineInfo")
local bookItemInfoModern = fn("C_SpellBook", "GetSpellBookItemInfo")
local bookItemNameModern = fn("C_SpellBook", "GetSpellBookItemName")
local bookItemTexModern = fn("C_SpellBook", "GetSpellBookItemTexture")

local numSpellTabs = glob("GetNumSpellTabs")
local spellTabInfo = glob("GetSpellTabInfo")
local bookItemNameLegacy = glob("GetSpellBookItemName")
local bookItemTexLegacy = glob("GetSpellBookItemTexture")
local bookItemInfoLegacy = glob("GetSpellBookItemInfo")

chose("SpellBook", numSkillLines and bookItemNameModern,
      numSpellTabs and bookItemNameLegacy)

-- The player's own book, never the pet's.
local function playerBank()
    local e = rawget(_G, "Enum")
    local bank = e and e.SpellBookSpellBank
    -- Player is 0 on every build that has the enum; the fallback is for
    -- one that has the functions but not the table.
    return (bank and bank.Player) or 0
end

local function modernItem(index, bank)
    if bookItemInfoModern then
        local ok, t = pcall(bookItemInfoModern, index, bank)
        if ok and type(t) == "table" and t.name then
            return { index = index, name = t.name, rank = t.subName,
                     icon = t.iconID, spellID = t.spellID,
                     isPassive = t.isPassive == true }
        end
    end
    local ok, name, rank = pcall(bookItemNameModern, index, bank)
    if not ok or not name then return nil end
    local icon
    if bookItemTexModern then
        local okTex, tex = pcall(bookItemTexModern, index, bank)
        icon = okTex and tex or nil
    end
    return { index = index, name = name, rank = rank, icon = icon }
end

local function legacyItem(index)
    local ok, name, rank = pcall(bookItemNameLegacy, index, "spell")
    if not ok or not name then return nil end
    local icon, spellID
    if bookItemTexLegacy then
        local okTex, tex = pcall(bookItemTexLegacy, index, "spell")
        icon = okTex and tex or nil
    end
    if bookItemInfoLegacy then
        -- (skillType, id), and the id is only a spell id for a SPELL.
        local okInfo, kind, id = pcall(bookItemInfoLegacy, index, "spell")
        if okInfo and kind == "SPELL" then spellID = id end
    end
    return { index = index, name = name, rank = rank, icon = icon, spellID = spellID }
end

-- Every spell in the player's book, in book order.
--
-- Ranks are left alone rather than folded together: the caller knows
-- whether it wants one entry per rank, and a mage's teleports have no
-- ranks anyway.
function D.SpellBookSpells()
    local out = {}
    if numSkillLines and bookItemNameModern then
        local bank = playerBank()
        local okN, lines = pcall(numSkillLines)
        if not okN or not lines then return out end
        for line = 1, lines do
            local info
            if skillLineInfo then
                local okLine, t = pcall(skillLineInfo, line)
                if okLine then info = t end
            end
            -- A guild or off-spec line is not this character's own
            -- casting, so it does not belong in the answer.
            if type(info) == "table" and not info.isGuild and not info.shouldHide then
                local offset = info.itemIndexOffset or 0
                for i = 1, (info.numSpellBookItems or 0) do
                    local item = modernItem(offset + i, bank)
                    if item then out[#out + 1] = item end
                end
            end
        end
        return out
    end

    if numSpellTabs and bookItemNameLegacy then
        local okN, tabs = pcall(numSpellTabs)
        if not okN or not tabs then return out end
        for tab = 1, tabs do
            local okT, _, _, offset, count = pcall(spellTabInfo, tab)
            if okT and count then
                for i = 1, count do
                    local item = legacyItem((offset or 0) + i)
                    if item then out[#out + 1] = item end
                end
            end
        end
    end
    return out
end

-- ============================================================
-- Containers
-- ============================================================

local numSlots = chose("GetContainerNumSlots", fn("C_Container", "GetContainerNumSlots"), glob("GetContainerNumSlots"))
function D.GetContainerNumSlots(bag)
    if not numSlots then return 0 end
    return numSlots(bag) or 0
end

local freeSlots = chose("GetContainerNumFreeSlots", fn("C_Container", "GetContainerNumFreeSlots"), glob("GetContainerNumFreeSlots"))
function D.GetContainerNumFreeSlots(bag)
    if not freeSlots then return 0, 0 end
    return freeSlots(bag)
end

local ciModern = fn("C_Container", "GetContainerItemInfo")
local ciLegacy = glob("GetContainerItemInfo")
chose("GetContainerItemInfo", ciModern, ciLegacy)

-- Field names follow C_Container's ContainerItemInfo table.
function D.GetContainerItemInfo(bag, slot)
    if ciModern then
        return ciModern(bag, slot)
    elseif ciLegacy then
        local icon, count, locked, quality, readable, lootable, link, filtered, noValue, itemID, bound = ciLegacy(bag, slot)
        if icon == nil and link == nil then return nil end
        return { iconFileID = icon, stackCount = count, isLocked = locked, quality = quality,
                 isReadable = readable, hasLoot = lootable, hyperlink = link, isFiltered = filtered,
                 hasNoValue = noValue, itemID = itemID, isBound = bound }
    end
end

local ciLink = chose("GetContainerItemLink", fn("C_Container", "GetContainerItemLink"), glob("GetContainerItemLink"))
function D.GetContainerItemLink(bag, slot)
    if not ciLink then return nil end
    return ciLink(bag, slot)
end

local ciID = chose("GetContainerItemID", fn("C_Container", "GetContainerItemID"), glob("GetContainerItemID"))
function D.GetContainerItemID(bag, slot)
    if not ciID then return nil end
    return ciID(bag, slot)
end

local useItem = chose("UseContainerItem", fn("C_Container", "UseContainerItem"), glob("UseContainerItem"))
function D.UseContainerItem(bag, slot, target)
    if useItem then return useItem(bag, slot, target) end
end

local pickupItem = chose("PickupContainerItem", fn("C_Container", "PickupContainerItem"), glob("PickupContainerItem"))
function D.PickupContainerItem(bag, slot)
    if pickupItem then return pickupItem(bag, slot) end
end

-- ============================================================
-- Auras (always guarded)
-- ============================================================

local auraModern = fn("C_UnitAuras", "GetAuraDataByIndex")
local auraLegacy = glob("UnitAura")
chose("UnitAura", auraModern, auraLegacy)

local function legacyAura(unit, index, filter)
    local name, icon, count, dispel, duration, expires, source, stealable, showPersonal, spellId = auraLegacy(unit, index, filter)
    if not name then return nil end
    return { name = name, icon = icon, applications = count, dispelName = dispel,
             duration = duration, expirationTime = expires, sourceUnit = source,
             isStealable = stealable, nameplateShowPersonal = showPersonal, spellId = spellId }
end

-- Returns the aura table, or nil plus a reason ("restricted" / error text).
function D.GetAura(unit, index, filter)
    if auraModern then
        return R:Guard(auraModern, unit, index, filter or "HELPFUL")
    elseif auraLegacy then
        return R:Guard(legacyAura, unit, index, filter or "HELPFUL")
    end
    return nil, "missing"
end

local auraByName = fn("C_UnitAuras", "GetAuraDataBySpellName")
function D.GetAuraBySpellName(unit, name, filter)
    if auraByName then
        return R:Guard(auraByName, unit, name, filter or "HELPFUL")
    end
    for aura in D.IterateAuras(unit, filter) do
        if aura.name == name then return aura end
    end
    return nil
end

-- for aura in D.IterateAuras("player", "HELPFUL") do ... end
-- Yields nothing at all while auras are blocked.
function D.IterateAuras(unit, filter, max)
    local i, limit = 0, max or 40
    return function()
        while i < limit do
            i = i + 1
            local aura = D.GetAura(unit, i, filter)
            if aura == nil then return nil end
            return aura
        end
    end
end

-- ============================================================
-- Quest log
-- ============================================================

local numQuests = chose("GetNumQuestLogEntries", fn("C_QuestLog", "GetNumQuestLogEntries"), glob("GetNumQuestLogEntries"))
function D.GetNumQuestLogEntries()
    if not numQuests then return 0, 0 end
    return numQuests()
end

local questInfo = fn("C_QuestLog", "GetInfo")
local questTitle = glob("GetQuestLogTitle")
chose("GetQuestLogTitle", questInfo, questTitle)

function D.GetQuestLogEntry(index)
    if questInfo then
        local t = questInfo(index)
        if not t then return nil end
        return { title = t.title, level = t.level, isHeader = t.isHeader, isComplete = t.isComplete,
                 questID = t.questID, index = t.questLogIndex or index }
    elseif questTitle then
        local title, level, _, isHeader, _, isComplete, _, questID = questTitle(index)
        if not title then return nil end
        return { title = title, level = level, isHeader = isHeader, isComplete = isComplete,
                 questID = questID, index = index }
    end
end

-- ============================================================
-- Group, money, chat
-- ============================================================

local groupMembers = glob("GetNumGroupMembers")
local raidMembers, partyMembers = glob("GetNumRaidMembers"), glob("GetNumPartyMembers")
chose("GetNumGroupMembers", groupMembers, raidMembers)
function D.GetNumGroupMembers()
    if groupMembers then return groupMembers() end
    if raidMembers and partyMembers then
        local r = raidMembers()
        if r > 0 then return r end
        local p = partyMembers()
        return p > 0 and p + 1 or 0
    end
    return 0
end

local coinString = chose("GetCoinTextureString", fn("C_CurrencyInfo", "GetCoinTextureString"), glob("GetCoinTextureString"))
function D.CoinString(copper)
    copper = tonumber(copper) or 0
    if coinString then return coinString(copper) end
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    return string.format("%dg %ds %dc", g, s, c)
end

local regPrefix = chose("RegisterAddonMessagePrefix", fn("C_ChatInfo", "RegisterAddonMessagePrefix"), glob("RegisterAddonMessagePrefix"))
function D.RegisterAddonPrefix(prefix)
    if regPrefix then return pcall(regPrefix, prefix) end
    return false
end

local sendMsg = chose("SendAddonMessage", fn("C_ChatInfo", "SendAddonMessage"), glob("SendAddonMessage"))
-- Returns true if the message was handed to the client, false if blocked.
function D.SendAddonMessage(prefix, text, channel, target)
    if not sendMsg or R:ChatBlocked() then return false end
    local ok = pcall(sendMsg, prefix, text, channel, target)
    return ok
end

-- ============================================================
-- Professions, totems, talents
-- ============================================================

local profInfo = fn("C_TradeSkillUI", "GetBaseProfessionInfo")
local tsLine = glob("GetTradeSkillLine")
chose("GetTradeSkillLine", profInfo, tsLine)

-- Only meaningful while a profession window is open, on either client.
function D.GetTradeSkillLine()
    if profInfo then
        local ok, t = pcall(profInfo)
        if ok and t then
            return { name = t.professionName, rank = t.skillLevel, maxRank = t.maxSkillLevel,
                     professionID = t.professionID, skillLineID = t.profession }
        end
    elseif tsLine then
        local name, rank, maxRank = tsLine()
        if name then return { name = name, rank = rank, maxRank = maxRank } end
    end
    return nil
end

local totemInfo = glob("GetTotemInfo")
chose("GetTotemInfo", totemInfo, nil)
-- Fields may be secret in combat on a secrets client; .secret says so.
function D.GetTotemInfo(slot)
    if not totemInfo then return nil end
    local ok, have, name, start, duration, icon, modRate, spellID = pcall(totemInfo, slot)
    if not ok then return nil end
    return { haveTotem = have, name = name, startTime = start, duration = duration,
             icon = icon, modRate = modRate, spellID = spellID, secret = R:IsSecret(have) }
end

-- Talents are the retail trait system on Forever; the legacy tab API is nil.
D.hasTraits = Core.Client.hasTraits
chose("Talents", D.hasTraits and fn("C_ClassTalents", "GetActiveConfigID") or nil, glob("GetTalentInfo"))

function D.GetActiveTalentConfigID()
    local f = fn("C_ClassTalents", "GetActiveConfigID")
    if not f then return nil end
    local ok, id = pcall(f)
    return ok and id or nil
end

-- ============================================================
-- Report
-- ============================================================

function D:Report()
    local labels = {}
    for label in pairs(self.paths) do labels[#labels + 1] = label end
    table.sort(labels)
    local out = {}
    for _, label in ipairs(labels) do
        out[#out + 1] = string.format("%-24s %s", label, self.paths[label])
    end
    return out
end
