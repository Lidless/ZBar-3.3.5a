-- ZBar modifier layers: a second and third action on every action button.
-- Hold Ctrl or Shift while pressing the button's key (or clicking it) and the
-- button does its Ctrl / Shift action instead. Alt is left alone: it stays the
-- game's self-cast key.
--
-- Works with the secure button attributes ("ctrl-type*", "shift-spell*", ...),
-- so it works in combat. Pressing Ctrl+1 only reaches the button when Ctrl+1
-- has no key binding of its own, so turning a layer on frees the default
-- bindings in its way (Ctrl+1-0 pet bar keys, Shift+1-6 bar paging); turning
-- it off puts them back.
--
-- Per character: db.modLayers = { ctrl = true, shift = true }
--                db.mods = { [buttonName] = { ctrl = entry, shift = entry } }
--                db.modSavedBinds = { [key] = original binding }
-- entry: { t = "spell", name } | { t = "macro", name } | { t = "item", id } | { t = "pet", index }
-- The mods are also part of the role profiles.
local _, ns = ...
local Mod = {}
ns.Modifiers = Mod

local function Keys(prefix, last)
    local t = {}
    for i = 1, last do t[#t + 1] = prefix .. (i % 10) end
    return t
end

Mod.LAYERS = {
    ctrl = { label = "Ctrl", prefix = "ctrl-", keys = Keys("CTRL-", 10),
             frees = "Ctrl+1 to Ctrl+0 (by default: the pet bar keys)" },
    shift = { label = "Shift", prefix = "shift-", keys = Keys("SHIFT-", 6),
              frees = "Shift+1 to Shift+6 (by default: switching the main bar page)" },
}
Mod.ORDER = { "ctrl", "shift" }
local ATTRS = { "type", "spell", "macro", "item", "action" }

local function DB()
    local db = ns.db
    db.modLayers = db.modLayers or {}
    db.mods = db.mods or {}
    db.modSavedBinds = db.modSavedBinds or {}
    if db.modShowIcons == nil then db.modShowIcons = true end
    return db
end
Mod.DB = DB

function Mod:IsOn(layer)
    return ns.db and DB().modLayers[layer] and true or false
end

------------------------------------------------------------------------
-- Entries
------------------------------------------------------------------------
local function PetActionName(i)
    if not GetPetActionInfo then return nil end
    local name, _, _, isToken = GetPetActionInfo(i)
    if name and isToken then name = _G[name] end
    return name
end

function Mod:Describe(e)
    if not e then return "|cff888888none|r" end
    if e.t == "spell" then return e.name end
    if e.t == "macro" then return "Macro: " .. e.name end
    if e.t == "item" then return (GetItemInfo(e.id)) or ("Item " .. e.id) end
    if e.t == "pet" then
        local n = PetActionName(e.index)
        return "Pet Action " .. e.index .. (n and (" (" .. n .. ")") or "")
    end
    return "?"
end

function Mod:Icon(e)
    if not e then return nil end
    if e.t == "spell" then return GetSpellTexture(e.name) end
    if e.t == "macro" then
        local idx = GetMacroIndexByName(e.name)
        if idx and idx > 0 then return (select(2, GetMacroInfo(idx))) end
    elseif e.t == "item" then
        return GetItemIcon and GetItemIcon(e.id) or select(10, GetItemInfo(e.id))
    elseif e.t == "pet" and GetPetActionInfo then
        local _, _, tex, isToken = GetPetActionInfo(e.index)
        if tex and isToken then tex = _G[tex] end
        return tex
    end
end

-- what is on the cursor, as an entry
local function FromCursor()
    local t, a, b = GetCursorInfo()
    if t == "spell" then
        local name = GetSpellName(a, b or BOOKTYPE_SPELL)
        return name and { t = "spell", name = name }
    elseif t == "macro" then
        local name = GetMacroInfo(a)
        return name and { t = "macro", name = name }
    elseif t == "item" then
        return { t = "item", id = a }
    elseif t == "petaction" then
        return { t = "pet", index = a }
    end
end

------------------------------------------------------------------------
-- Secure attributes on the buttons
------------------------------------------------------------------------
function Mod:ApplyButton(name)
    local btn = _G[name]
    if not btn or not ns.db then return end
    local m = DB().mods[name]
    for _, layer in ipairs(self.ORDER) do
        local p = self.LAYERS[layer].prefix
        for _, a in ipairs(ATTRS) do btn:SetAttribute(p .. a .. "*", nil) end
        local e = self:IsOn(layer) and m and m[layer]
        if e then
            if e.t == "spell" then
                btn:SetAttribute(p .. "type*", "spell")
                btn:SetAttribute(p .. "spell*", e.name)
            elseif e.t == "macro" then
                btn:SetAttribute(p .. "type*", "macro")
                btn:SetAttribute(p .. "macro*", e.name)
            elseif e.t == "item" then
                btn:SetAttribute(p .. "type*", "item")
                btn:SetAttribute(p .. "item*", "item:" .. e.id)
            elseif e.t == "pet" then
                btn:SetAttribute(p .. "type*", "pet")
                btn:SetAttribute(p .. "action*", e.index)
            end
        end
    end
end

function Mod:ApplyAll()
    if not ns.db then return end
    ns.RunOOC("modifiers", function()
        for name in pairs(ns.Bars.info) do Mod:ApplyButton(name) end
        Mod:UpdateIcons()
    end)
end

------------------------------------------------------------------------
-- Freeing / restoring the default key bindings
------------------------------------------------------------------------
local function FreeKeys(layer)
    local db = DB()
    local changed = false
    for _, key in ipairs(Mod.LAYERS[layer].keys) do
        local action = GetBindingAction(key)
        if action and action ~= "" then
            if not db.modSavedBinds[key] then db.modSavedBinds[key] = action end
            SetBinding(key)
            changed = true
        end
    end
    return changed
end

local function RestoreKeys(layer)
    local db = DB()
    local changed = false
    for _, key in ipairs(Mod.LAYERS[layer].keys) do
        local action = db.modSavedBinds[key]
        if action then
            if (GetBindingAction(key) or "") == "" then SetBinding(key, action) end
            db.modSavedBinds[key] = nil
            changed = true
        end
    end
    return changed
end

function Mod:SetLayer(layer, on)
    if InCombatLockdown() then ns.Print("Cannot change key bindings in combat.") return false end
    local L = self.LAYERS[layer]
    local changed
    if on then changed = FreeKeys(layer) else changed = RestoreKeys(layer) end
    if changed then SaveBindings(GetCurrentBindingSet()) end
    DB().modLayers[layer] = on and true or nil
    if on then
        ns.Print(L.label .. " layer on - " .. L.frees .. " now go to your buttons.")
    else
        ns.Print(L.label .. " layer off - the default " .. L.label .. " key bindings are back.")
    end
    self:ApplyAll()
    return true
end

------------------------------------------------------------------------
-- Assigning
------------------------------------------------------------------------
local function Store(name, layer, e)
    local mods = DB().mods
    mods[name] = mods[name] or {}
    mods[name][layer] = e
    if not next(mods[name]) then mods[name] = nil end
end

function Mod:Set(name, layer, e)
    if InCombatLockdown() then ns.Print("Cannot change this in combat.") return end
    Store(name, layer, e)
    self:ApplyAll()
    local info = ns.Bars.info[name]
    ns.Print((info and info.label or name) .. " - " .. self.LAYERS[layer].label .. ": " .. self:Describe(e))
    if ns.Mover then ns.Mover:Refresh() end
end

function Mod:Get(name, layer)
    local m = ns.db and DB().mods[name]
    return m and m[layer]
end

-- something dropped on a button in "Mode: Modifiers"
function Mod:Drop(name)
    if not GetCursorInfo() then return end
    local ctrl, shift = IsControlKeyDown(), IsShiftKeyDown()
    local layer = (ctrl and not shift and "ctrl") or (shift and not ctrl and "shift")
    if not layer then
        ns.Print("Hold Ctrl or Shift while dropping, to choose which layer it goes on.")
        return
    end
    if not self:IsOn(layer) then
        ns.Print("The " .. self.LAYERS[layer].label .. " layer is off - turn it on in Interface > AddOns > ZBar > Ctrl / Shift Layers.")
        return
    end
    local e = FromCursor()
    if not e then
        ns.Print("Only spells, macros and items can go on a layer. Pet actions: right-click the button.")
        return
    end
    ClearCursor()
    self:Set(name, layer, e)
end

-- right-click menu: pet actions and clear, per layer
local menuFrame
function Mod:Menu(name)
    menuFrame = menuFrame or CreateFrame("Frame", "ZBarModifierMenu", UIParent, "UIDropDownMenuTemplate")
    local info = ns.Bars.info[name]
    local list = { { text = info and info.label or name, isTitle = true, notCheckable = true } }
    for _, layer in ipairs(self.ORDER) do
        local L = self.LAYERS[layer]
        local sub = {}
        if self:Get(name, layer) then
            table.insert(sub, { text = "Clear", notCheckable = true, func = function() Mod:Set(name, layer, nil) end })
        end
        for i = 1, (NUM_PET_ACTION_SLOTS or 10) do
            local n = PetActionName(i)
            table.insert(sub, {
                text = "Pet Action " .. i .. (n and (" (" .. n .. ")") or ""),
                notCheckable = true,
                func = function()
                    CloseDropDownMenus()
                    Mod:Set(name, layer, { t = "pet", index = i })
                end,
            })
        end
        table.insert(list, {
            text = L.label .. ": " .. self:Describe(self:Get(name, layer)) .. (self:IsOn(layer) and "" or "  |cffff5555(layer off)|r"),
            notCheckable = true,
            hasArrow = self:IsOn(layer),
            disabled = not self:IsOn(layer),
            menuList = sub,
        })
    end
    table.insert(list, { text = "Close", notCheckable = true, func = function() CloseDropDownMenus() end })
    EasyMenu(list, menuFrame, "cursor", 0, 0, "MENU")
end

function Mod:Tooltip(name)
    for _, layer in ipairs(self.ORDER) do
        local L = self.LAYERS[layer]
        GameTooltip:AddDoubleLine(L.label .. ":", self:Describe(self:Get(name, layer))
            .. (self:IsOn(layer) and "" or " |cffff5555(off)|r"), 1, 0.82, 0, 1, 1, 1)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Hold Ctrl or Shift and drop a spell, macro or item here.", 0.8, 0.8, 0.8, true)
    GameTooltip:AddLine("Right-click: pet actions / clear.", 0.8, 0.8, 0.8)
end

function Mod:Marks(name)
    local c, s = self:Get(name, "ctrl"), self:Get(name, "shift")
    return (c and "C" or "") .. ((c and s) and " " or "") .. (s and "S" or "")
end

function Mod:ClearAll()
    if InCombatLockdown() then ns.Print("Cannot change this in combat.") return end
    DB().mods = {}
    self:ApplyAll()
    ns.Print("All Ctrl / Shift actions cleared.")
    if ns.Mover then ns.Mover:Refresh() end
end

------------------------------------------------------------------------
-- Content mode with Ctrl / Shift held: move layer actions like base actions.
-- The key held when the drag starts picks the source layer, the key held
-- at the drop picks the target layer (none = the button's base slot).
-- Layer to layer drops swap, like the base buttons do.
------------------------------------------------------------------------
local function HeldLayer()
    local ctrl, shift = IsControlKeyDown(), IsShiftKeyDown()
    return (ctrl and not shift and "ctrl") or (shift and not ctrl and "shift") or nil
end

local function FindSpellIndex(name)
    local found
    for tab = 1, GetNumSpellTabs() do
        local _, _, offset, num = GetSpellTabInfo(tab)
        for i = offset + 1, offset + num do
            if GetSpellName(i, BOOKTYPE_SPELL) == name then found = i end -- last = highest rank
        end
    end
    return found
end

-- put a layer entry's game object on the cursor (pet actions have none)
local function PickupEntry(e)
    ClearCursor()
    if e.t == "spell" then
        local idx = FindSpellIndex(e.name)
        if idx then PickupSpell(idx, BOOKTYPE_SPELL) end
    elseif e.t == "macro" then
        local idx = GetMacroIndexByName(e.name)
        if idx and idx > 0 then PickupMacro(idx) end
    elseif e.t == "item" then
        PickupItem(e.id)
    end
end

-- returns true if it handled the drag start (a modifier was held)
function Mod:ContentDragStart(name)
    local layer = HeldLayer()
    self.carry = nil
    if not layer then return false end
    local e = self:Get(name, layer)
    if e then
        PickupEntry(e)
        self.carry = { from = name, layer = layer, entry = e }
    end
    return true
end

-- returns true if it handled the drop; slot = the button's base action slot
function Mod:ContentDrop(name, slot)
    local carry = self.carry
    if carry and not GetCursorInfo() and carry.entry.t ~= "pet" then
        carry, self.carry = nil, nil -- the pick-up was cancelled
    end
    local layer = HeldLayer()
    if not layer then
        if not carry then return false end -- plain base drop: Blizzard handling
        self.carry = nil
        if carry.entry.t == "pet" then
            ns.Print("Pet actions can only go on a Ctrl or Shift layer.")
            return true
        end
        -- layer action -> this button's base slot (the old base action stays
        -- on the cursor, like a normal swap)
        if slot then PlaceAction(slot) end
        Store(carry.from, carry.layer, nil)
        self:ApplyAll()
        if ns.Mover then ns.Mover:Refresh() end
        return true
    end
    if not self:IsOn(layer) then
        ns.Print("The " .. self.LAYERS[layer].label .. " layer is off - turn it on in Interface > AddOns > ZBar > Ctrl / Shift Layers.")
        return true
    end
    local entry = carry and carry.entry or FromCursor()
    if not entry then return true end
    local old = self:Get(name, layer)
    if carry then
        if not (carry.from == name and carry.layer == layer) then
            Store(name, layer, entry)
            Store(carry.from, carry.layer, old) -- swap (or move, if this one was empty)
        end
    else
        Store(name, layer, entry) -- from a base slot or the spellbook
    end
    ClearCursor()
    self.carry = nil
    self:ApplyAll()
    if ns.Mover then ns.Mover:Refresh() end
    local info = ns.Bars.info[name]
    ns.Print((info and info.label or name) .. " - " .. self.LAYERS[layer].label .. ": " .. self:Describe(entry)
        .. ((old and not carry) and ("  (replaced " .. self:Describe(old) .. ")") or ""))
    return true
end

function Mod:LayerLines(name)
    for _, layer in ipairs(self.ORDER) do
        local e = self:Get(name, layer)
        if e then
            GameTooltip:AddDoubleLine(self.LAYERS[layer].label .. ":", self:Describe(e), 1, 0.82, 0, 1, 1, 1)
        end
    end
end

------------------------------------------------------------------------
-- While Ctrl or Shift is held: show that layer's icons on the buttons
------------------------------------------------------------------------
local icons = {}

-- Normal play: only buttons that have something on the held layer change.
-- Setup (unlock, Mode: Modifiers): the whole held layer is shown, empty
-- slots as dark squares, so you see where there is room.
function Mod:UpdateIcons()
    local layer
    local setup = ns.unlocked and (ns.mode == "modifiers" or ns.mode == "content")
    if ns.db and (setup or DB().modShowIcons) and not GetCurrentKeyBoardFocus() then
        local ctrl, shift = IsControlKeyDown(), IsShiftKeyDown()
        layer = (ctrl and not shift and "ctrl") or (shift and not ctrl and "shift")
        if layer and not setup and not self:IsOn(layer) then layer = nil end
    end
    for name in pairs(ns.Bars.info) do
        local e = layer and self:Get(name, layer)
        local tex = icons[name]
        local icon = e and self:Icon(e)
        if icon or (layer and setup) then
            if not tex then
                local btn = _G[name]
                tex = btn:CreateTexture(nil, "OVERLAY")
                tex:SetPoint("TOPLEFT", btn, "TOPLEFT", 2, -2)
                tex:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
                icons[name] = tex
            end
            if icon then
                tex:SetTexture(icon)
                tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            else
                tex:SetTexture(0.05, 0.05, 0.05, 0.9) -- empty slot on this layer
            end
            tex:Show()
        elseif tex then
            tex:Hide()
        end
    end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("MODIFIER_STATE_CHANGED")
ev:RegisterEvent("PET_BAR_UPDATE")
ev:SetScript("OnEvent", function(_, event)
    if not ns.ready then return end
    Mod:UpdateIcons()
end)

------------------------------------------------------------------------
-- Startup (called from Core once the bars are set up)
------------------------------------------------------------------------
function Mod:Init()
    local db = DB()
    -- the binding set may be account-wide and changed on another character:
    -- make sure the keys of the layers that are on are still free
    local changed = false
    for _, layer in ipairs(self.ORDER) do
        if db.modLayers[layer] and FreeKeys(layer) then changed = true end
    end
    if changed then SaveBindings(GetCurrentBindingSet()) end
    self:ApplyAll()
end

-- role profiles
function Mod:Snapshot()
    return ns.DeepCopy(DB().mods)
end

function Mod:Load(mods)
    if not mods then return end
    DB().mods = ns.DeepCopy(mods)
    self:ApplyAll()
end
