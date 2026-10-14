-------------------------------------------------------------------------------
--  EllesmereUI_GoldNames  (standalone add-on, no EllesmereUI file edited)
--
--  The bug (EllesmereUI 9.5.4, EllesmereUI_GoldLedger.lua): the account gold
--  ledger shared by Bags and the Data Bars Gold block keys every character
--  as "Name-Realm" from UnitName("player"). On WoW Forever every character
--  also has a surname (UnitName's second value), and two characters with the
--  same first name land on one key and overwrite each other's balance.
--
--  The fix patches the ledger table from the outside (EllesmereUI.GetGoldLedger
--  returns one shared table, and every caller looks its functions up on it at
--  call time, so replaced fields take effect everywhere):
--   * GL.CharKey        -> "First Last-Realm" on Forever (retail unchanged);
--   * GL.RecordCharacter -> after the original write, stores firstName and
--     surname on the entry, sets entry.name per the Name Format, and drops
--     the legacy first-name-only entry ("First-Realm"), which may hold another
--     same-first-name character's balance.
--  Display: the Data Bars tooltip shows entry.name; the Bags gold tooltip shows
--  the key without the realm, so its name strings are rewritten after it lays
--  out. Name Format: /goldnames first | last | full (default first).
--  If a future EllesmereUI renames these functions, the add-on does nothing and
--  says so once in chat.
-------------------------------------------------------------------------------
local ADDON_NAME = ...
local EUI = _G.EllesmereUI
local PREFIX = "|cff0cd29fEUI Gold Names:|r "

local VALID = { first = true, last = true, full = true }

local function DB()
    local db = _G.EllesmereUI_GoldNamesDB
    if type(db) ~= "table" then
        db = {}
        _G.EllesmereUI_GoldNamesDB = db
    end
    return db
end

local function NameFormat()
    local f = DB().nameFormat
    if VALID[f] then return f end
    return "first"
end

local function DisplayName(first, surname)
    if not surname then return first end
    local f = NameFormat()
    if f == "full" then return first .. " " .. surname end
    if f == "last" then return surname end
    return first
end

-- UnitNameUnmodified ignores the show-surname display preference, so the key
-- never changes with that setting. Surname only on Forever.
local function NameParts()
    local name, surname = (UnitNameUnmodified or UnitName)("player")
    if type(surname) ~= "string" or surname == "" then surname = nil end
    if not (EUI and EUI.IS_FOREVER) then surname = nil end
    if type(name) ~= "string" or name == "" then name = nil end
    return name, surname
end

-------------------------------------------------------------------------------
--  Ledger patch
-------------------------------------------------------------------------------
local GL  -- the patched ledger table, nil until patched

local function RefreshNames()
    if not GL then return end
    local chars = GL.Data().chars
    if type(chars) ~= "table" then return end
    for _, e in pairs(chars) do
        if type(e) == "table" and type(e.firstName) == "string" then
            e.name = DisplayName(e.firstName, e.surname)
        end
    end
end

local function Patch()
    if GL then return true end
    if not (EUI and type(EUI.GetGoldLedger) == "function") then return false end
    local ledger = EUI.GetGoldLedger()
    if type(ledger) ~= "table" or type(ledger.CharKey) ~= "function"
       or type(ledger.RecordCharacter) ~= "function" or type(ledger.Data) ~= "function" then
        return false
    end
    if ledger._goldNamesPatched then GL = ledger; return true end

    local origCharKey, origRecord = ledger.CharKey, ledger.RecordCharacter

    ledger.CharKey = function(...)
        local name, surname = NameParts()
        if not surname then return origCharKey(...) end
        local realm = GetRealmName()
        if not name or not realm then return nil end
        return name .. " " .. surname .. "-" .. realm
    end

    ledger.RecordCharacter = function(...)
        local money = origRecord(...)
        local name, surname = NameParts()
        local realm = GetRealmName()
        if name and surname and realm and money ~= nil
           and (not ledger.IsTracking or ledger.IsTracking()) then
            local chars = ledger.Data().chars
            local key = ledger.CharKey()
            local e = key and chars[key]
            if type(e) == "table" then
                e.firstName, e.surname = name, surname
                e.name = DisplayName(name, surname)
                local legacy = name .. "-" .. realm
                if legacy ~= key and chars[legacy] ~= nil then chars[legacy] = nil end
            end
        end
        return money
    end

    ledger._goldNamesPatched = true
    GL = ledger
    return true
end

-- As early as possible: before Bags / Data Bars register with the ledger
-- (they do it on login). Retried on login below if EllesmereUI was not ready.
Patch()

-------------------------------------------------------------------------------
--  Bags gold tooltip: it prints Ambiguate(key, "short") = "First Last", so the
--  name strings are rewritten after it lays out (hooked on its SetSize, the
--  last layout call), and the frame is narrowed by what the names lost.
-------------------------------------------------------------------------------
local bagsTT, inRewrite

local function ShortOf(key)
    if Ambiguate then return Ambiguate(key, "short") or key end
    return (key:gsub("%-.*$", ""))
end

local function RewriteBagsTooltip()
    if inRewrite or not (GL and bagsTT and bagsTT:IsShown()) then return end
    local map, any = {}, false
    for key, e in pairs(GL.Data().chars) do
        if type(key) == "string" and type(e) == "table" and type(e.firstName) == "string" and e.surname then
            local shown = DisplayName(e.firstName, e.surname)
            local short = ShortOf(key)
            if shown ~= short then map[short] = shown; any = true end
        end
    end
    if not any then return end

    local hint = bagsTT._hint
    local oldMax, newMax, changed = 0, 0, false
    for _, r in ipairs({ bagsTT:GetRegions() }) do
        if r ~= hint and r ~= bagsTT._title and r.GetObjectType and r:GetObjectType() == "FontString"
           and r:IsShown() and r:GetNumPoints() > 0 and (r:GetPoint(1)) == "TOPLEFT" then
            local w = r:GetStringWidth() or 0
            if w > oldMax then oldMax = w end
            local t = r:GetText()
            if type(t) == "string" then
                local hex, inner = t:match("^|c(%x%x%x%x%x%x%x%x)(.-)|r$")
                local nm = inner and map[inner]
                if nm then
                    r:SetText("|c" .. hex .. nm .. "|r")
                    changed = true
                end
            end
            w = r:GetStringWidth() or 0
            if w > newMax then newMax = w end
        end
    end
    if not changed or newMax >= oldMax then return end

    local w, h = bagsTT:GetSize()
    local minW = 0
    if hint then minW = (hint:GetStringWidth() or 0) + 16 end
    local newW = w - (oldMax - newMax)
    if newW < minW then newW = minW end
    inRewrite = true
    bagsTT:SetSize(newW, h)
    inRewrite = false
end

local function IsBagsGoldTooltip(f)
    return type(f) == "table" and f._title and f._hint and f._fadeInAG
       and f.GetFrameStrata and f:GetFrameStrata() == "TOOLTIP"
end

local function FindBagsTooltip(anchor)
    if bagsTT then return bagsTT end
    for _, f in ipairs({ UIParent:GetChildren() }) do
        if IsBagsGoldTooltip(f) and f:GetNumPoints() > 0 and select(2, f:GetPoint(1)) == anchor then
            bagsTT = f
            hooksecurefunc(f, "SetSize", RewriteBagsTooltip)
            return f
        end
    end
end

local function HookBagsFooter()
    local bags = _G.EUI_Bags
    local footer, money = bags and bags.Footer, bags and bags.Money
    if not (footer and money) then return false end
    for _, child in ipairs({ footer:GetChildren() }) do
        if not child._goldNamesHooked and child:IsMouseEnabled() and child:GetNumPoints() > 0
           and select(2, child:GetPoint(1)) == money then
            child._goldNamesHooked = true
            child:HookScript("OnEnter", function(self)
                if FindBagsTooltip(self) then RewriteBagsTooltip() end
            end)
            return true
        end
    end
    return false
end

local function WatchBags()
    local bags = _G.EUI_Bags
    if not bags or bags._goldNamesWatch then return end
    bags._goldNamesWatch = true
    if HookBagsFooter() then return end
    -- The footer is built lazily; try again whenever the bag window opens.
    local done = false
    bags:HookScript("OnShow", function()
        if done then return end
        C_Timer.After(0, function() if not done then done = HookBagsFooter() end end)
    end)
end

-------------------------------------------------------------------------------
--  Events, slash command
-------------------------------------------------------------------------------
local warned
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON_NAME then
            local db = DB()
            -- Carry over the Name Format chosen earlier in the Bags options cog, if any.
            if not VALID[db.nameFormat] then
                local b = EUI and EUI._bagsDB
                local old = b and b.profile and b.profile.goldNameFormat
                if VALID[old] then db.nameFormat = old end
            end
        end
        if arg1 == "EllesmereUIBags" then WatchBags() end
    elseif event == "PLAYER_LOGIN" then
        if not Patch() and not warned then
            warned = true
            print(PREFIX .. "EllesmereUI gold ledger not found (EllesmereUI changed?). Gold names are not fixed.")
        end
        WatchBags()
    elseif event == "PLAYER_ENTERING_WORLD" then
        if GL then
            -- Re-record under the full-name key (drops a first-name entry an
            -- earlier session or an unpatched write left behind), then re-label
            -- every entry with the current Name Format.
            GL.RecordCharacter()
            RefreshNames()
        end
        ev:UnregisterEvent("PLAYER_ENTERING_WORLD")
    end
end)

SLASH_EUIGOLDNAMES1 = "/goldnames"
SlashCmdList.EUIGOLDNAMES = function(msg)
    msg = (msg or ""):lower():match("^%s*(%S*)")
    if VALID[msg] then
        DB().nameFormat = msg
        RefreshNames()
        print(PREFIX .. "Name Format: " .. msg)
    else
        local status = GL and "active" or "NOT active"
        local key = GL and GL.CharKey() or "?"
        print(PREFIX .. status .. ", this character is stored as \"" .. tostring(key) .. "\".")
        print(PREFIX .. "Name Format: " .. NameFormat() .. "  (/goldnames first | last | full)")
    end
end
