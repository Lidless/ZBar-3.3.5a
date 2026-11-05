-- ZBar roles: Tank / DPS / Healer profiles per character.
-- A profile holds the bar layout (positions, groups, sizes, hidden parts),
-- the contents of all 120 action slots and, optionally, a gear set.
local _, ns = ...
local Roles = {}
ns.Roles = Roles

Roles.list = { "Tank", "DPS", "Healer" }
local NAMES = { tank = "Tank", dps = "DPS", healer = "Healer", heal = "Healer" }
local NUM_SLOTS = 120
local BOOK = BOOKTYPE_SPELL or "spell"

local function DB()
    local db = ns.db
    db.roles = db.roles or {}
    db.specRole = db.specRole or {}
    if db.roleAutoSave == nil then db.roleAutoSave = true end
    return db
end
Roles.DB = DB

function Roles:Normalize(role)
    return role and NAMES[role:lower()]
end

function Roles:Current()
    return ns.db and ns.db.currentRole
end

-- nil until the character's saved data is loaded (the options panel is built earlier)
function Roles:Get(role)
    return ns.db and DB().roles[role]
end

local function Refresh()
    if ns.Minimap then ns.Minimap:Update() end
    if ns.OptionsPanel and ns.OptionsPanel:IsShown() then ns.OptionsPanel:refresh() end
    if ns.Toolbar and ns.Toolbar:IsShown() then ns.Toolbar:Open() end
end
Roles.RefreshUI = Refresh

------------------------------------------------------------------------
-- Action slots
------------------------------------------------------------------------
-- spell name -> { ranks = { [rank] = bookIndex }, best = highest-rank index }
local function ScanSpellbook()
    local byName = {}
    for tab = 1, GetNumSpellTabs() do
        local _, _, offset, num = GetSpellTabInfo(tab)
        for i = offset + 1, offset + num do
            local name, rank = GetSpellName(i, BOOK)
            if name then
                local e = byName[name] or { ranks = {} }
                e.ranks[rank or ""] = i
                e.best = i -- the spellbook lists ranks from low to high
                byName[name] = e
            end
        end
    end
    return byName
end

-- what is in a slot, in a form that survives a respec
local function CaptureSlot(slot)
    local t, id, sub, extra = GetActionInfo(slot)
    if not t then return nil end
    if t == "spell" then
        local name, rank
        if extra and extra > 0 then name, rank = GetSpellInfo(extra) end
        if not name then name, rank = GetSpellName(id, BOOK) end
        if not name then return nil end
        return { t = "spell", name = name, rank = rank }
    elseif t == "macro" then
        local name = GetMacroInfo(id)
        return name and { t = "macro", name = name } or nil
    elseif t == "item" then
        return { t = "item", id = id, name = GetItemInfo(id) }
    elseif t == "companion" then
        local _, name, sid = GetCompanionInfo(sub, id)
        return { t = "companion", sub = sub, sid = sid, name = name }
    elseif t == "equipmentset" then
        return { t = "equipmentset", name = id }
    end
    return { t = t, unsupported = true }
end

local function Key(e)
    if not e then return "" end
    if e.t == "spell" then return "spell:" .. e.name .. ":" .. (e.rank or "") end
    if e.t == "item" then return "item:" .. tostring(e.id) end
    if e.t == "companion" then return "companion:" .. tostring(e.sid) end
    return e.t .. ":" .. tostring(e.name)
end

-- put the wanted action on the cursor; true if it worked
local function Pick(want, book)
    ClearCursor()
    if want.t == "spell" then
        local e = book[want.name]
        if not e then return false end
        PickupSpell(e.ranks[want.rank or ""] or e.best, BOOK)
    elseif want.t == "macro" then
        local idx = GetMacroIndexByName(want.name)
        if not idx or idx == 0 then return false end
        PickupMacro(idx)
    elseif want.t == "item" then
        PickupItem(want.id)
    elseif want.t == "companion" then
        for i = 1, GetNumCompanions(want.sub) do
            local _, _, sid = GetCompanionInfo(want.sub, i)
            if sid == want.sid then
                PickupCompanion(want.sub, i)
                break
            end
        end
    elseif want.t == "equipmentset" then
        if PickupEquipmentSetByName then PickupEquipmentSetByName(want.name) end
    else
        return false
    end
    return GetCursorInfo() ~= nil
end

function Roles:CaptureActions()
    local actions = {}
    for slot = 1, NUM_SLOTS do actions[slot] = CaptureSlot(slot) end
    return actions
end

-- returns the names of the actions that could not be placed
function Roles:LoadActions(actions)
    local book = ScanSpellbook()
    local missing, seen = {}, {}
    ClearCursor()
    for slot = 1, NUM_SLOTS do
        local want = actions[slot]
        local have = CaptureSlot(slot)
        if Key(want) ~= Key(have) then
            if not want then
                -- empty in the profile: empty it here too
                PickupAction(slot)
                ClearCursor()
            elseif not want.unsupported then
                if Pick(want, book) then
                    PlaceAction(slot)
                    ClearCursor()
                else
                    local n = want.name or tostring(want.id)
                    if not seen[n] then
                        seen[n] = true
                        table.insert(missing, n)
                    end
                end
            end
        end
    end
    ClearCursor()
    return missing
end

------------------------------------------------------------------------
-- Gear (Blizzard Equipment Manager sets)
------------------------------------------------------------------------
function Roles:GearSets()
    local list = {}
    if GetNumEquipmentSets then
        for i = 1, GetNumEquipmentSets() do
            local name = GetEquipmentSetInfo(i)
            if name then table.insert(list, name) end
        end
    end
    return list
end

function Roles:EquipSet(name)
    if not name or name == "" then return end
    if not GetEquipmentSetItemIDs or not UseEquipmentSet then return end
    local ids = GetEquipmentSetItemIDs(name)
    if not ids then
        ns.Print("Gear set \"" .. name .. "\" was not found - gear not changed.")
        return
    end
    -- slots the set wants empty need a free bag slot each; swaps need none
    local EMPTY = EQUIPMENT_SET_EMPTY_SLOT or 0
    local need = 0
    for slot, id in pairs(ids) do
        if id == EMPTY and GetInventoryItemLink("player", slot) then need = need + 1 end
    end
    local free = 0
    for bag = 0, 4 do
        local n, bagType = GetContainerNumFreeSlots(bag)
        if (bagType or 0) == 0 then free = free + (n or 0) end
    end
    if need > free then
        ns.Print(string.format("Not enough bag space for gear set \"%s\" (%d free, %d needed) - gear not changed.", name, free, need))
        return
    end
    UseEquipmentSet(name)
end

------------------------------------------------------------------------
-- Save / switch
------------------------------------------------------------------------
-- merge: automatic save while switching. A respec removes unlearned talent
-- spells from the bars, so slots that are empty now keep what was saved before.
function Roles:Save(role, quiet, merge)
    role = role or self:Current()
    if not role then
        ns.Print("Pick a role first (Tank, DPS or Healer).")
        return
    end
    if InCombatLockdown() then ns.Print("Cannot save a role in combat.") return end
    local db = DB()
    local r = db.roles[role] or {}
    r.layout = ns.DeepCopy(ns.db.layout)
    local now = self:CaptureActions()
    if merge and r.actions then
        for slot = 1, NUM_SLOTS do
            if now[slot] then r.actions[slot] = now[slot] end
        end
    else
        r.actions = now
    end
    r.savedAt = date("%Y-%m-%d %H:%M")
    db.roles[role] = r
    db.currentRole = role
    if not quiet then ns.Print(role .. " role saved (bar positions and contents).") end
    Refresh()
end

-- load the current role's saved layout and bars again
function Roles:Reload()
    local role = self:Current()
    if not role then
        ns.Print("Pick a role first (Tank, DPS or Healer).")
        return
    end
    self:Switch(role)
end

-- fromSpec: switched by a dual spec change; the server has already swapped
-- the bar contents, so only the old role's layout may be saved, not its bars
function Roles:Switch(role, fromSpec)
    role = self:Normalize(role) or role
    if not (role == "Tank" or role == "DPS" or role == "Healer") then
        ns.Print("Usage: /zbar role tank | dps | healer")
        return
    end
    if InCombatLockdown() then ns.Print("Cannot switch roles in combat.") return end
    local db = DB()
    local cur = db.currentRole

    if cur and cur ~= role and db.roleAutoSave then
        if fromSpec then
            if db.roles[cur] then db.roles[cur].layout = ns.DeepCopy(ns.db.layout) end
        else
            self:Save(cur, true, true)
        end
    end
    db.currentRole = role

    local r = db.roles[role]
    if not r or not r.actions then
        ns.Print(role .. " role is not saved yet - your bars were left as they are. "
            .. "Set them up and press Save Role (or /zbar saverole).")
        if r and r.gear then self:EquipSet(r.gear) end
        Refresh()
        return
    end

    ns.Layout:PushUndo(nil, nil, "Note: this undid a role switch - only the bar layout went back, "
        .. "the bar contents and gear did not. Switch back to the previous role to load those.")
    local layout = ns.DeepCopy(r.layout)
    ns.Blocks:Merge(layout, ns.db.layout)
    ns.db.layout = layout
    ns.Layout:Apply()

    local missing = self:LoadActions(r.actions)
    self:EquipSet(r.gear)
    ns.Print("Switched to " .. role .. ".")
    if #missing > 0 then
        ns.Print("Not available, slot left unchanged: " .. table.concat(missing, ", "))
    end
    Refresh()
end

function Roles:SetGear(role, name)
    local db = DB()
    db.roles[role] = db.roles[role] or {}
    db.roles[role].gear = (name ~= "" and name) or nil
    Refresh()
end

------------------------------------------------------------------------
-- Dual spec: optional role per talent group
------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
ev:SetScript("OnEvent", function()
    if not ns.ready or not ns.db or not GetActiveTalentGroup then return end
    local role = DB().specRole[GetActiveTalentGroup()]
    if role and role ~= Roles:Current() then
        -- give the spellbook a moment to update after the spec change
        ns.After(1, function()
            ns.RunOOC("roleswitch", function() Roles:Request(role, true) end)
        end)
    end
end)

------------------------------------------------------------------------
-- Threat Plates link: if Threat Plates (with the Tank/DPS/Healer role
-- selector) is installed, it is the boss. Every role change goes through
-- it, and ZBar follows whatever role it is set to.
------------------------------------------------------------------------
local TP_ROLE = { Tank = "TANK", DPS = "DPS", Healer = "HEALER" }
local FROM_TP = { TANK = "Tank", DPS = "DPS", HEALER = "Healer" }

function Roles:TPLinked()
    local tp = _G.TidyPlatesThreat
    return tp and type(tp.SetRole) == "function" and type(tp.GetRole) == "function"
        and tp.db and tp.db.char and true or false
end

-- every role change from ZBar (options, minimap button, /zbar role, dual spec)
function Roles:Request(role, fromSpec)
    role = self:Normalize(role) or role
    if not TP_ROLE[role] then
        ns.Print("Usage: /zbar role tank | dps | healer")
        return
    end
    if self:TPLinked() then
        self.pendingSpec = fromSpec
        self.requested = role
        _G.TidyPlatesThreat:SetRole(TP_ROLE[role]) -- the hook below does the switch
        return
    end
    self:Switch(role, fromSpec)
end

local function OnTPRole()
    if not ns.ready or not ns.db then return end
    local role = FROM_TP[_G.TidyPlatesThreat:GetRole()]
    local fromSpec, requested = Roles.pendingSpec, Roles.requested
    Roles.pendingSpec, Roles.requested = nil, nil
    -- same role as now: nothing to do (unless it was clicked in ZBar = reload it)
    if not role or (role == Roles:Current() and requested ~= role) then
        Refresh()
        return
    end
    if InCombatLockdown() then
        ns.Print("Bars will switch to " .. role .. " when combat ends.")
    end
    ns.RunOOC("roleswitch", function() Roles:Switch(role, fromSpec) end)
end

-- called once the layout is ready (Core Setup)
function Roles:OnReady()
    if not self:TPLinked() then return end
    if not self.hooked then
        hooksecurefunc(_G.TidyPlatesThreat, "SetRole", OnTPRole)
        self.hooked = true
    end
    -- follow the role Threat Plates already has, if the player chose one there
    local tp = _G.TidyPlatesThreat
    local role = FROM_TP[tp:GetRole()]
    if tp.db.char.roleChosen and role and role ~= self:Current() then
        self:Switch(role)
    end
end
