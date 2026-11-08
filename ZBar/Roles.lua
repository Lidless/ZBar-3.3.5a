-- ZBar profiles, per character.
-- Conquest of Azeroth: one profile per talent tree of the class (e.g. Slayer,
-- Infernal, Tyrant). A profile keeps the bar layout (positions, groups,
-- sizes, hidden parts), the contents of all 120 action slots, the Ctrl /
-- Shift layers, a gear set and the talent build of that tree. Switching
-- loads the talents first, then the bars (talent spells sit on them).
-- Classless realm (no talent trees): one profile per dual spec (Spec 1 /
-- Spec 2) with layout, layers and gear - the game swaps talents and bar
-- contents with the spec by itself.
local _, ns = ...
local Roles = {}
ns.Roles = Roles

local NUM_SLOTS = 120
local BOOK = BOOKTYPE_SPELL or "spell"

local function DB()
    local db = ns.db
    db.profiles = db.profiles or {}
    if db.roleAutoSave == nil then db.roleAutoSave = true end
    return db
end
Roles.DB = DB

-- nil until the character's saved data is loaded (the options panel is built earlier)
function Roles:Get(key)
    return ns.db and key and DB().profiles[key]
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

-- done(ok, reason) is called when the server confirmed the build, or on failure
-- (reason: "notready" or "timeout"; the caller prints the message)
function Talents:Apply(t, done)
    local T = _G.CoA.Talents
    local tr, apply = T.transfer, T.apply
    if not (tr and tr.edit and tr.import and apply) then
        return done(false, "notready")
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
                done(false, "timeout")
            end
        else
            local now = Talents:Current()
            if now and Talents:Same(now, t) then
                self:SetScript("OnUpdate", nil)
                -- give the spellbook a moment to pick up the new talent spells
                ns.After(0.5, function() done(true) end)
            elseif waited > 6 then
                self:SetScript("OnUpdate", nil)
                done(false, "timeout")
            end
        end
    end)
end

-- put a build into the talent window without saving it (clears an unsaved
-- import that is still showing there)
function Talents:Preview(t)
    local T = _G.CoA and _G.CoA.Talents
    local tr = T and T.transfer
    if not (t and tr and tr.edit and tr.import) then return end
    local wasShown = tr:IsShown()
    tr:Show()
    tr.edit:SetText(self:Code(t))
    tr.import:Click()
    if not wasShown then tr:Hide() end
end

StaticPopupDialogs["ZBAR_TREE_SWITCH"] = {
    text = "ZBar: switch to %s?\n\n%s",
    button1 = "Change Talents",
    button2 = CANCEL,
    OnShow = function(self) if ns.SolidPopupOn then ns.SolidPopupOn(self) end end,
    OnHide = function(self) if ns.SolidPopupOff then ns.SolidPopupOff(self) end end,
    OnAccept = function(self, data) if data then data.yes() end end,
    OnCancel = function(self, data) if data and data.no then data.no() end end,
    timeout = 0,
    whileDead = false,
    hideOnEscape = true,
}

------------------------------------------------------------------------
-- Profiles: which ones there are, which one is active
------------------------------------------------------------------------
local ROLE_FLAGS = {
    { "Tank", "Tank" }, { "Healer", "Healer" }, { "MeleeDPS", "Melee" }, { "RangedDPS", "Ranged" },
    { "CasterDPS", "Caster" }, { "Support", "Support" },
}
local ARMOR = { "Plate", "Mail", "Leather", "Cloth" }

local function Presentation(id)
    local p = _G.CoA and _G.CoA.TalentSpecPresentation
    return type(p) == "table" and p[id] or nil
end

-- "coa": the character has Conquest of Azeroth talent trees; "spec": dual spec only
function Roles:Mode()
    local t = Talents:Available() and Talents:Current()
    local s = t and Spec(t.spec)
    if s and s.class == t.class then return "coa" end
    return "spec"
end

-- the profiles of this character, in order: { key, name, label, tree }
function Roles:List()
    local list = {}
    if self:Mode() == "coa" then
        local cls = Talents:Current().class
        for id, s in pairs(_G.CoA.TalentData.specs) do
            if type(s) == "table" and s.class == cls then
                list[#list + 1] = { key = "tree" .. id, tree = id, name = s.name or ("Tree " .. id), order = s.order or id }
            end
        end
        table.sort(list, function(a, b) return a.order < b.order end)
        for _, e in ipairs(list) do
            local kind = self:TreeKind(e.tree)
            e.label = kind and (e.name .. " - " .. kind) or e.name
        end
    else
        for i = 1, 2 do list[i] = { key = "spec" .. i, name = "Spec " .. i, label = "Spec " .. i } end
    end
    return list
end

function Roles:Entry(key)
    for _, e in ipairs(self:List()) do
        if e.key == key then return e end
    end
end

function Roles:Label(key)
    local e = key and self:Entry(key)
    return e and e.label or tostring(key)
end

-- Melee / Caster / Tank ... from the game's own spec presentation
function Roles:TreeKind(id)
    local p = Presentation(id)
    if not p then return nil end
    local kinds = {}
    for _, f in ipairs(ROLE_FLAGS) do
        if p[f[1]] == 1 or p[f[1]] == true then kinds[#kinds + 1] = f[2] end
    end
    return #kinds > 0 and table.concat(kinds, " / ") or nil
end

-- "Agility | Leather | Normal" - primary stats, armor, difficulty
function Roles:TreeInfo(id)
    local p = Presentation(id)
    if not p then return nil end
    local parts = {}
    if type(p.PrimaryStats) == "table" then
        local stats = {}
        for k, v in pairs(p.PrimaryStats) do
            if type(v) == "string" then stats[#stats + 1] = v
            elseif type(k) == "string" and v then stats[#stats + 1] = k end
        end
        table.sort(stats)
        if #stats > 0 then parts[#parts + 1] = table.concat(stats, ", ") end
    end
    local armor = {}
    for _, a in ipairs(ARMOR) do
        if p[a] == 1 or p[a] == true then armor[#armor + 1] = a end
    end
    if #armor > 0 then parts[#parts + 1] = table.concat(armor, " / ") end
    if p.DifficultyRating then parts[#parts + 1] = tostring(p.DifficultyRating) end
    return #parts > 0 and table.concat(parts, " | ") or nil
end

function Roles:TreeIcon(id)
    local s = Spec(id)
    return s and s.icon and ("Interface\\Icons\\" .. s.icon) or nil
end

-- the active profile: the talent tree in use, or the active dual spec
function Roles:Current()
    if not ns.db then return nil end
    if self:Mode() == "coa" then
        return "tree" .. Talents:Current().spec
    end
    return "spec" .. (GetActiveTalentGroup and GetActiveTalentGroup() or 1)
end

------------------------------------------------------------------------
-- Save / load
------------------------------------------------------------------------
-- merge: automatic save while switching. A respec removes unlearned talent
-- spells from the bars, so slots that are empty now keep what was saved before.
function Roles:Save(key, quiet, merge)
    key = key or self:Current()
    if not key then return end
    if InCombatLockdown() then ns.Print("Cannot save in combat.") return end
    local db = DB()
    local r = db.profiles[key] or {}
    r.layout = ns.DeepCopy(ns.db.layout)
    if ns.Modifiers then r.mods = ns.Modifiers:Snapshot() end
    if key:sub(1, 4) == "tree" then
        -- the build of the tree in use (never another tree's)
        local t = Talents:Current()
        if t and ("tree" .. t.spec) == key then r.talents = t end
        local now = self:CaptureActions()
        if merge and r.actions then
            for slot = 1, NUM_SLOTS do
                if now[slot] then r.actions[slot] = now[slot] end
            end
        else
            r.actions = now
        end
    end
    r.savedAt = date("%Y-%m-%d %H:%M")
    db.profiles[key] = r
    if not quiet then ns.Print(self:Label(key) .. " saved (bar positions" .. (r.actions and ", bars" or "")
        .. ", layers" .. (r.talents and ", talents" or "") .. ").") end
    Refresh()
end

-- puts a profile's layout, layers, bars (tree profiles) and gear on
local function LoadProfile(key, r, quiet)
    ns.Layout:PushUndo(nil, nil, "Note: this undid a profile switch - only the bar layout went back, "
        .. "the bar contents, Ctrl / Shift layers and gear did not.")
    local layout = ns.DeepCopy(r.layout)
    ns.Blocks:Merge(layout, ns.db.layout)
    ns.db.layout = layout
    ns.Layout:Apply()
    if r.mods and ns.Modifiers then ns.Modifiers:Load(r.mods) end
    local missing, lostMacros = {}, {}
    if r.actions then missing, lostMacros = Roles:LoadActions(r.actions) end
    Roles:EquipSet(r.gear)
    if not quiet then ns.Print("Switched to " .. Roles:Label(key) .. ".") end
    if #missing > 0 then
        ns.Print("Not available, slot left unchanged: " .. table.concat(missing, ", "))
    end
    for _, line in ipairs(lostMacros) do ns.Print(line) end
end

-- load the active profile's layout and bars again (and its talents, if they differ)
function Roles:Reload()
    self:Switch(self:Current())
end

-- Conquest of Azeroth: switch talent tree (minimap button, options, /zbar tree)
function Roles:Switch(key)
    if not key then return end
    if InCombatLockdown() then ns.Print("Cannot switch in combat.") return end
    if self:Mode() ~= "coa" then
        ns.Print("No talent trees on this character: profiles follow the dual spec.")
        return
    end
    local e = self:Entry(key)
    if not e then ns.Print("Unknown talent tree.") return end
    local r = self:Get(key)
    local now = Talents:Current()
    local want = r and r.talents
    local fresh = not want
    if fresh then
        -- never saved: an empty build of that tree (all its points to spend)
        want = { version = _G.CoA.TalentData.version, class = now.class, spec = e.tree, ranks = {} }
    end
    if now.spec == e.tree and Talents:Same(now, want) then
        -- same tree, same talents: only the bars
        if r and r.layout then
            self.switching = true
            LoadProfile(key, r)
            self.switching = nil
        else
            ns.Print(e.label .. " is not saved yet: set up your bars and press Save.")
        end
        Refresh()
        return
    end
    if now.spec == e.tree and fresh then
        ns.Print(e.label .. " is not saved yet: set up your bars and press Save.")
        return
    end
    local text = fresh
        and ("This tree is not saved yet: it starts with no talent points spent\n(the talent button glows until you spend them).\nYour bars stay as they are - set them up and press Save.")
        or ("This also loads the talents saved with this tree:\n|cffffd100" .. Talents:Summary(want)
            .. "|r\n\nTalents load first, then the bars (talent spells are on them).")
    StaticPopup_Show("ZBAR_TREE_SWITCH", e.label, text, {
        yes = function()
            if InCombatLockdown() then ns.Print("Cannot change talents in combat.") return end
            Roles:DoSwitch(key, want, fresh)
        end,
    })
end

function Roles:DoSwitch(key, talents, fresh)
    local db = DB()
    local cur = self:Current()
    local before = Talents:Current()
    -- auto-save only refreshes a profile that was saved before
    if cur and cur ~= key and db.roleAutoSave and db.profiles[cur] then self:Save(cur, true, true) end
    self.switching = true
    Talents:Apply(talents, function(ok, reason)
        local function Finish()
            if InCombatLockdown() then
                ns.RunOOC("treefinish", Finish)
                return
            end
            self.switching = nil
            self.lastKey = self:Current()
            if ok then
                local r = db.profiles[key]
                if r and r.layout and not fresh then
                    ns.Print("Talents changed: " .. Talents:Summary(talents) .. ".")
                    LoadProfile(key, r)
                else
                    ns.Print("Switched to " .. self:Label(key) .. " - no talent points spent yet. "
                        .. "Bars left as they are: set them up and press Save.")
                end
            elseif fresh then
                ns.Print("Could not switch to " .. self:Label(key) .. " (" .. (reason == "timeout" and "timed out" or "talent window not ready")
                    .. "). Activate it in the talent window once, then save it here.")
            else
                ns.Print("Switch failed (" .. (reason == "timeout" and "timed out" or "talent window not ready")
                    .. "), please try again. Still " .. self:Label(cur) .. ".")
            end
            Refresh()
        end
        if ok then Finish() return end
        Finish()
        -- the server may still take the new build a bit later: put the old one back
        if not before then return end
        ns.After(2, function()
            local now = Talents:Current()
            if not now or Talents:Same(now, before) then
                Talents:Preview(before)
                return
            end
            self.switching = true
            Talents:Apply(before, function(back)
                self.switching = nil
                self.lastKey = self:Current()
                ns.Print(back and ("Your previous talents are back: " .. Talents:Summary(before) .. ".")
                    or "Your talents could not be put back - check the talent window.")
                Refresh()
            end)
        end)
    end)
end

function Roles:SetGear(key, name)
    local db = DB()
    db.profiles[key] = db.profiles[key] or {}
    db.profiles[key].gear = (name ~= "" and name) or nil
    Refresh()
end

------------------------------------------------------------------------
-- Changes made outside ZBar
------------------------------------------------------------------------
-- talent tree changed in the game's own window: the old tree's bars are
-- saved, the new tree's bars loaded (talents were set there already)
function Roles:CheckTree()
    if not ns.ready or not ns.db or self.switching or self:Mode() ~= "coa" then return end
    local key = self:Current()
    local last = self.lastKey
    self.lastKey = key
    if not last or last == key or last:sub(1, 4) ~= "tree" then return end
    local function Go()
        if DB().roleAutoSave and DB().profiles[last] then
            -- bars and layout of the old tree; its talents can no longer be read
            local r = DB().profiles[last]
            local keep = r and r.talents
            self:Save(last, true, true)
            if DB().profiles[last] then DB().profiles[last].talents = keep end
        end
        local r = DB().profiles[key]
        if r and r.layout then
            LoadProfile(key, r)
        else
            ns.Print("Talent tree changed to " .. self:Label(key) .. " - not saved yet, bars left as they are.")
        end
        Refresh()
    end
    if InCombatLockdown() then ns.RunOOC("treechange", Go) else Go() end
end

-- dual spec (classless realm): layout, layers and gear follow the spec; the
-- game swaps the talents and the bar contents itself
local ev = CreateFrame("Frame")
ev:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
ev:SetScript("OnEvent", function(_, _, newGroup, oldGroup)
    if not ns.ready or not ns.db or Roles:Mode() ~= "spec" then return end
    local new = "spec" .. (newGroup or GetActiveTalentGroup())
    local old = (oldGroup and ("spec" .. oldGroup)) or Roles.lastKey
    Roles.lastKey = new
    ns.After(1, function()
        ns.RunOOC("specswitch", function()
            if old and old ~= new and DB().roleAutoSave and DB().profiles[old] then Roles:Save(old, true) end
            local r = DB().profiles[new]
            if r and r.layout then LoadProfile(new, r) end
            Refresh()
        end)
    end)
end)

-- called once the layout is ready (Core Setup)
function Roles:OnReady()
    local db = DB()
    -- fresh start: the old Tank / DPS / Healer role profiles are gone
    db.roles, db.currentRole, db.specRole, db.roleTalents = nil, nil, nil, nil
    self.lastKey = self:Current()
    Refresh()
end

------------------------------------------------------------------------
-- Unspent talent points (Conquest of Azeroth): the game says nothing about
-- them, so the talent micro button glows while there are points to spend
-- and its tooltip says how many. Points to spend = the budget of each tree
-- (all points earned) minus the points spent there.
------------------------------------------------------------------------
function Talents:Unspent()
    if not self:Available() then return nil end
    local ok, st = pcall(_G.Ex_GetCoATalentState)
    local cur = self:Current()
    if not ok or type(st) ~= "table" or not cur then return nil end
    local cp, sp = self:Points(cur)
    local c = math.max(0, (tonumber(st.classBudget) or 0) - cp)
    local s = math.max(0, (tonumber(st.specBudget) or 0) - sp)
    return c, s
end

local pointsGlow, pointsC, pointsS = nil, 0, 0

local function PointsText()
    local parts = {}
    if pointsC > 0 then parts[#parts + 1] = pointsC .. " class" end
    if pointsS > 0 then parts[#parts + 1] = pointsS .. " spec" end
    return table.concat(parts, " and ") .. " talent point" .. ((pointsC + pointsS) > 1 and "s" or "") .. " to spend"
end

local function CreateGlow()
    local btn = _G.TalentMicroButton
    if pointsGlow or not btn then return end
    local g = btn:CreateTexture(nil, "OVERLAY")
    g:SetTexture("Interface\\Buttons\\UI-MicroButton-Hilight")
    g:SetBlendMode("ADD")
    g:SetAllPoints(btn)
    g:Hide()
    -- a soft pulse, like the game's own "something to do here" flash
    local t = 0
    local pulse = CreateFrame("Frame", nil, btn)
    pulse:SetScript("OnUpdate", function(_, elapsed)
        t = t + elapsed
        g:SetAlpha(0.35 + 0.65 * math.abs(math.sin(t * 2.5)))
    end)
    pulse:Hide()
    g.pulse = pulse
    btn:HookScript("OnEnter", function()
        if pointsC + pointsS > 0 and GameTooltip:IsOwned(btn) then
            GameTooltip:AddLine("ZBar: " .. PointsText() .. ".", 0.54, 0.96, 0.35)
            GameTooltip:Show()
        end
    end)
    pointsGlow = g
end

function Roles:UpdateTalentPoints()
    local c, s = Talents:Unspent()
    pointsC, pointsS = c or 0, s or 0
    CreateGlow()
    if not pointsGlow then return end
    if pointsC + pointsS > 0 then
        pointsGlow:Show()
        pointsGlow.pulse:Show()
    else
        pointsGlow:Hide()
        pointsGlow.pulse:Hide()
    end
end

-- no event tells when points are spent or earned on CoA: look every few
-- seconds (a cheap table read), and right away on login and level up
local pointsEv = CreateFrame("Frame")
pointsEv:RegisterEvent("PLAYER_ENTERING_WORLD")
pointsEv:RegisterEvent("PLAYER_LEVEL_UP")
local pointsWait = 0
pointsEv:SetScript("OnEvent", function()
    ns.After(1, function() Roles:UpdateTalentPoints() end)
end)
pointsEv:SetScript("OnUpdate", function(_, elapsed)
    pointsWait = pointsWait + elapsed
    if pointsWait < 3 then return end
    pointsWait = 0
    Roles:UpdateTalentPoints()
    Roles:CheckTree()
end)
