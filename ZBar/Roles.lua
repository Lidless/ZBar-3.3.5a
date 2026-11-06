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

-- action slot -> readable place ("Bottom Left Bar button 3")
local PAGE_NAMES = {
    "Main Bar", "Main Bar (page 2)", "Right Bar", "Right Bar 2", "Bottom Right Bar", "Bottom Left Bar",
}
local function SlotLabel(slot)
    local page, i = math.floor((slot - 1) / 12) + 1, (slot - 1) % 12 + 1
    local bar = PAGE_NAMES[page] or ("Stance / form page " .. (page - 6))
    return bar .. " button " .. i
end

-- returns the names of the actions that could not be placed, and the
-- macros that were not found (one line each in chat: the user may have
-- deleted them on purpose, so they are not recreated)
function Roles:LoadActions(actions)
    local book = ScanSpellbook()
    local missing, seen, lostMacros = {}, {}, {}
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
                elseif want.t == "macro" then
                    table.insert(lostMacros, string.format("%s: macro \"%s\" not found - maybe it was deleted. Slot left unchanged.",
                        SlotLabel(slot), want.name))
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
    return missing, lostMacros
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
-- Talents (Conquest of Azeroth): saved with the role when the option is on.
-- Reads the build with Ex_GetCoATalentState() (no window needed) and loads
-- it through the talent window's own Import + Save Changes, found by their
-- field names on the CoA talent controller (CoA.Talents.transfer.import,
-- CoA.Talents.apply), not by their position in the window.
------------------------------------------------------------------------
local Talents = {}
Roles.Talents = Talents

function Talents:Available()
    return type(_G.Ex_GetCoATalentState) == "function" and type(_G.CoA) == "table"
        and type(_G.CoA.Talents) == "table" and type(_G.CoA.TalentData) == "table"
        and (type(_G.IsCoAEnabled) ~= "function" or _G.IsCoAEnabled()) and true or false
end

function Talents:Current()
    if not self:Available() then return nil end
    local ok, st = pcall(_G.Ex_GetCoATalentState)
    if not ok or type(st) ~= "table" or type(st.ranks) ~= "table" then return nil end
    local t = { version = st.version, class = st.class, spec = st.spec, ranks = {} }
    for id, r in pairs(st.ranks) do
        if type(r) == "number" and r > 0 then t.ranks[id] = r end
    end
    return t
end

local nodeIndex
local function Node(id)
    if not nodeIndex then
        nodeIndex = {}
        for _, n in pairs(_G.CoA.TalentData.nodes or {}) do
            if type(n) == "table" and n.id then nodeIndex[n.id] = n end
        end
    end
    return nodeIndex[id]
end

local function Spec(id)
    local specs = _G.CoA and _G.CoA.TalentData and _G.CoA.TalentData.specs
    return specs and specs[id]
end

function Talents:SpecName(t)
    local s = Spec(t.spec)
    return s and s.name or ("Spec " .. tostring(t.spec))
end

-- points spent in the class tree and the spec tree (the spec's free passive not counted)
function Talents:Points(t)
    local s = Spec(t.spec)
    local passive = s and s.passiveNode
    local cp, sp = 0, 0
    for id, r in pairs(t.ranks) do
        if id ~= passive then
            local n = Node(id)
            if n then
                cp = cp + r * (n.classCost or 0)
                sp = sp + r * (n.specCost or 0)
            end
        end
    end
    return cp, sp
end

function Talents:Summary(t)
    if not t then return nil end
    local cp, sp = self:Points(t)
    return string.format("%s - %d class / %d spec points", self:SpecName(t), cp, sp)
end

-- talent names (with ranks) for tooltips
function Talents:Names(t)
    local list = {}
    local s = Spec(t.spec)
    local passive = s and s.passiveNode
    for id, r in pairs(t.ranks) do
        if id ~= passive then
            local n = Node(id)
            local name = n and n.name or ("#" .. tostring(id))
            if n and n.max and n.max > 1 then name = name .. " " .. r .. "/" .. n.max end
            list[#list + 1] = name
        end
    end
    table.sort(list)
    return list
end

-- same spec and same talents (the spec's free passive point is ignored:
-- the game grants it by itself and it is not part of the build code)
function Talents:Same(a, b)
    if not a or not b or a.spec ~= b.spec then return false end
    local s = Spec(a.spec)
    local passive = s and s.passiveNode
    for id, r in pairs(a.ranks) do if id ~= passive and b.ranks[id] ~= r then return false end end
    for id, r in pairs(b.ranks) do if id ~= passive and a.ranks[id] ~= r then return false end end
    return true
end

-- the same code the game's Share Build window shows
function Talents:Code(t)
    local s = Spec(t.spec)
    local passive = s and s.passiveNode
    local parts = {}
    for id, r in pairs(t.ranks) do
        if id ~= passive then parts[#parts + 1] = tostring(id) .. "=" .. tostring(r) end
    end
    table.sort(parts)
    return string.format("CoA:%s:%s:%s:%s", tostring(t.version), tostring(t.class), tostring(t.spec),
        table.concat(parts, ","))
end

local function ApplyEnabled(btn)
    if btn.coaDisabled ~= nil then return not btn.coaDisabled end
    local e = btn:IsEnabled()
    return e == true or e == 1
end

local watcher = CreateFrame("Frame")

-- done(ok) is called when the server confirmed the build, or on failure
function Talents:Apply(t, done)
    local T = _G.CoA.Talents
    local tr, apply = T.transfer, T.apply
    if not (tr and tr.edit and tr.import and apply) then
        ns.Print("Talent window not ready - talents were not changed.")
        return done(false)
    end
    local version = _G.CoA.TalentData.version
    if t.version and version and t.version ~= version then
        ns.Print("Note: the talent data changed since this build was saved - it may not load completely.")
    end
    local wasShown = tr:IsShown()
    tr:Show()
    tr.edit:SetText(self:Code(t))
    tr.import:Click()
    if not wasShown then tr:Hide() end

    local waited, clicked = 0, false
    watcher:SetScript("OnUpdate", function(self, elapsed)
        waited = waited + elapsed
        if not clicked then
            if ApplyEnabled(apply) then
                clicked, waited = true, 0
                apply:Click()
            elseif waited > 3 then
                self:SetScript("OnUpdate", nil)
                ns.Print("The saved talent build could not be loaded (Save Changes stayed disabled).")
                done(false)
            end
        else
            local now = Talents:Current()
            if now and Talents:Same(now, t) then
                self:SetScript("OnUpdate", nil)
                -- give the spellbook a moment to pick up the new talent spells
                ns.After(0.5, function() done(true) end)
            elseif waited > 6 then
                self:SetScript("OnUpdate", nil)
                ns.Print("Talents were sent, but the server has not confirmed them yet.")
                done(false)
            end
        end
    end)
end

StaticPopupDialogs["ZBAR_ROLE_TALENTS"] = {
    text = "ZBar: switching to %s.\n\nChange your talents to the build saved with this role?\n|cffffd100%s|r",
    button1 = "Change Talents",
    button2 = "Bars Only",
    OnAccept = function(self, data) if data then data.yes() end end,
    OnCancel = function(self, data) if data then data.no() end end,
    timeout = 0,
    whileDead = false,
    hideOnEscape = true,
}

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
    if ns.Modifiers then r.mods = ns.Modifiers:Snapshot() end
    -- talents only on a manual save: the automatic save runs while switching,
    -- possibly right after a respec, and would store the new build in the old role
    if not merge and db.roleTalents and Talents:Available() then
        r.talents = Talents:Current()
    end
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
        .. "the bar contents, Ctrl / Shift layers and gear did not. Switch back to the previous role to load those.")
    local layout = ns.DeepCopy(r.layout)
    ns.Blocks:Merge(layout, ns.db.layout)
    ns.db.layout = layout
    ns.Layout:Apply()

    if r.mods and ns.Modifiers then ns.Modifiers:Load(r.mods) end

    -- bars come after the talents, so spells of a new build are already known
    local function Finish()
        if InCombatLockdown() then
            ns.RunOOC("rolefinish", Finish)
            return
        end
        local missing, lostMacros = self:LoadActions(r.actions)
        self:EquipSet(r.gear)
        ns.Print("Switched to " .. role .. ".")
        if #missing > 0 then
            ns.Print("Not available, slot left unchanged: " .. table.concat(missing, ", "))
        end
        for _, line in ipairs(lostMacros) do ns.Print(line) end
        Refresh()
    end

    local want = db.roleTalents and r.talents and Talents:Available() and r.talents
    local now = want and Talents:Current()
    if want and now and not Talents:Same(now, want) then
        StaticPopup_Show("ZBAR_ROLE_TALENTS", role, Talents:Summary(want), {
            yes = function()
                if InCombatLockdown() then
                    ns.Print("Cannot change talents in combat - only the bars were switched.")
                    Finish()
                    return
                end
                Talents:Apply(want, function(ok)
                    if ok then ns.Print("Talents changed: " .. Talents:Summary(want) .. ".") end
                    Finish()
                end)
            end,
            no = Finish,
        })
        return
    end
    Finish()
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
