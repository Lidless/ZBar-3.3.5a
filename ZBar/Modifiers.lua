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
--                db.modSavedPickup = the Pick Up Action Key before a layer took it
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

local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

-- live icon if the game can give one, else the icon saved when it was
-- assigned, else a question mark (a layer action must never be invisible)
function Mod:Icon(e)
    if not e then return nil end
    return self:RawIcon(e) or UNKNOWN_ICON
end

function Mod:RawIcon(e)
    if e.t == "spell" then return GetSpellTexture(e.name) or (select(3, GetSpellInfo(e.name))) or e.icon end
    if e.t == "macro" then
        local idx = GetMacroIndexByName(e.name)
        if idx and idx > 0 then return (select(2, GetMacroInfo(idx))) or e.icon end
        return e.icon
    elseif e.t == "item" then
        return (GetItemIcon and GetItemIcon(e.id)) or select(10, GetItemInfo(e.id)) or e.icon
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
        return name and { t = "spell", name = name, icon = GetSpellTexture(a, b or BOOKTYPE_SPELL) }
    elseif t == "macro" then
        local name, icon = GetMacroInfo(a)
        return name and { t = "macro", name = name, icon = icon }
    elseif t == "item" then
        return { t = "item", id = a, icon = GetItemIcon and GetItemIcon(a) or nil }
    elseif t == "petaction" then
        return { t = "pet", index = a }
    end
end

------------------------------------------------------------------------
-- Secure attributes on the buttons
------------------------------------------------------------------------
local proxies = {} -- button name -> stand-in button (see "Stand-ins" below)

function Mod:ApplyButton(name)
    local btn = _G[name]
    if not btn or not ns.db then return end
    self:SetLayerAttributes(btn, name)
    if proxies[name] then self:SetLayerAttributes(proxies[name], name) end
end

-- Each layer is set twice: "shift-" and "alt-shift-" (the game looks up all
-- held modifiers together, so Alt+Shift would otherwise fall back to the base
-- action). With Alt held the button's own self-cast check then sends the
-- layer spell to the player, like Alt does for the base action.
function Mod:SetLayerAttributes(btn, name)
    local m = DB().mods[name]
    for _, layer in ipairs(self.ORDER) do
        local base = self.LAYERS[layer].prefix
        for _, p in ipairs({ base, "alt-" .. base }) do
            self:SetPrefixAttributes(btn, p, self:IsOn(layer) and m and m[layer])
        end
    end
end

function Mod:SetPrefixAttributes(btn, p, e)
    do
        for _, a in ipairs(ATTRS) do btn:SetAttribute(p .. a .. "*", nil) end
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
        Mod:UpdateProxies()
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

-- The game's "Pick Up Action Key" (Shift by default) drags a spell off a
-- locked bar. With that key used as a layer, a Shift+click that moves the
-- mouse a little would pull the spell off the button, so while such a layer
-- is on the pickup key is set to none (rearranging: ZBar Content mode or
-- unlocking the bars). The old key comes back when the layer goes off.
local PICKUP = "PICKUPACTION"
local LAYER_KEY = { ctrl = "CTRL", shift = "SHIFT" }

local function PickupConflict(key)
    for layer, k in pairs(LAYER_KEY) do
        if k == key and DB().modLayers[layer] then return true end
    end
end

-- returns true if it changed the setting (the caller saves the bindings)
function Mod:UpdatePickupKey()
    if not (GetModifiedClick and SetModifiedClick) then return false end
    local db = DB()
    self.dragOpen = nil -- the drag lock (below) starts closed again
    local cur = GetModifiedClick(PICKUP)
    if PickupConflict(cur) then
        db.modSavedPickup = db.modSavedPickup or cur
        SetModifiedClick(PICKUP, "NONE")
        ns.Print("Pick Up Action Key set to none while the " .. cur:sub(1, 1) .. cur:sub(2):lower()
            .. " layer is on, so a spell cannot be dragged off a locked bar by accident. "
            .. "To move spells, open the small lock under the main bar's page number (or /zbar, Content mode).")
        return true
    end
    local saved = db.modSavedPickup
    if saved and cur ~= "NONE" then
        db.modSavedPickup = nil -- changed by the player in the meantime: keep theirs
    elseif saved and not PickupConflict(saved) then
        SetModifiedClick(PICKUP, saved)
        db.modSavedPickup = nil
        ns.Print("Pick Up Action Key is " .. saved .. " again.")
        return true
    end
    return false
end

function Mod:SetLayer(layer, on)
    if InCombatLockdown() then ns.Print("Cannot change key bindings in combat.") return false end
    local L = self.LAYERS[layer]
    local changed
    if on then changed = FreeKeys(layer) else changed = RestoreKeys(layer) end
    DB().modLayers[layer] = on and true or nil
    if self:UpdatePickupKey() then changed = true end
    if self.UpdateLock then self:UpdateLock() end
    if changed then SaveBindings(GetCurrentBindingSet()) end
    if on then
        ns.Print(L.label .. " layer on - " .. L.frees .. " now go to your buttons.")
    else
        ns.Print(L.label .. " layer off - the default " .. L.label .. " key bindings are back.")
    end
    self:ApplyAll()
    -- first time the Shift layer goes on: warn about Windows Sticky Keys
    if on and layer == "shift" and not DB().stickyKeysWarned then
        DB().stickyKeysWarned = true
        StaticPopup_Show("ZBAR_STICKY_KEYS")
    end
    if ns.ModifierPanel and ns.ModifierPanel:IsShown() then ns.ModifierPanel:refresh() end
    return true
end

-- The game's popup frames are shared by every addon, so the solid background
-- is added when this dialog shows and hidden again when it closes.
local function SolidOn(self)
    if not self.zbarSolid then
        local t = self:CreateTexture(nil, "BACKGROUND")
        t:SetPoint("TOPLEFT", 11, -11)
        t:SetPoint("BOTTOMRIGHT", -11, 11)
        t:SetTexture(0.05, 0.05, 0.05, 1)
        self.zbarSolid = t
    end
    self.zbarSolid:Show()
end
local function SolidOff(self)
    if self.zbarSolid then self.zbarSolid:Hide() end
end
ns.SolidPopupOn, ns.SolidPopupOff = SolidOn, SolidOff

StaticPopupDialogs["ZBAR_STICKY_KEYS"] = {
    OnShow = SolidOn,
    OnHide = SolidOff,
    text = "ZBar - Shift layer\n\n"
        .. "Windows has two keyboard helpers that react to Shift and can pull you out of the game "
        .. "or swallow key presses: |cffffd100Sticky keys|r and |cffffd100Filter keys|r.\n\n"
        .. "In Windows Settings > Accessibility > Keyboard, open the |cffffd100Sticky keys|r and the "
        .. "|cffffd100Filter keys|r menu and turn |cffff5555every option inside those two menus|r off "
        .. "(the rest of the Keyboard page can stay as it is). Turning off only their main switch is "
        .. "|cffff5555not enough|r - "
        .. "Windows can still pop up if an option below it is on (e.g. the keyboard shortcut, or "
        .. "\"Lock shortcut keys when pressed twice in a row\", which would make Shift stay pressed). "
        .. "Once is enough.\n\n"
        .. "If you would rather avoid it, use only the Ctrl layer - Ctrl has no such problem.",
    button1 = OKAY,
    button2 = "Use Ctrl only",
    OnCancel = function(self, data, reason)
        if reason == "clicked" then Mod:SetLayer("shift", false) end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = false,
}

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
-- While Ctrl or Shift is held: the button's tooltip shows the layer action
-- (the game would show the base action, or nothing on an empty slot)
------------------------------------------------------------------------
-- the layer entry the tooltip of this button should show now, if any
function Mod:TooltipEntry(name)
    if not ns.db or ns.unlocked or not name then return nil end
    local layer = HeldLayer()
    if not layer or not self:IsOn(layer) then return nil end
    return self:Get(name, layer), layer
end

-- fills GameTooltip (already owned by the button) with the entry
local function SetEntryTooltip(e)
    if e.t == "spell" then
        local idx = FindSpellIndex(e.name)
        if idx then GameTooltip:SetSpell(idx, BOOKTYPE_SPELL) return end
        GameTooltip:SetText(e.name)
        GameTooltip:AddLine("Not known by this character", 1, 0.2, 0.2)
    elseif e.t == "macro" then
        local idx = GetMacroIndexByName(e.name)
        local spell = idx and idx > 0 and GetMacroSpell and GetMacroSpell(idx)
        local _, itemLink = nil, nil
        if idx and idx > 0 and GetMacroItem then _, itemLink = GetMacroItem(idx) end
        local sidx = spell and FindSpellIndex(spell)
        if sidx then
            GameTooltip:SetSpell(sidx, BOOKTYPE_SPELL)
        elseif itemLink then
            GameTooltip:SetHyperlink(itemLink)
        else
            GameTooltip:SetText(e.name)
        end
        GameTooltip:AddLine("Macro: " .. e.name, 0.8, 0.8, 0.8)
    elseif e.t == "item" then
        GameTooltip:SetHyperlink("item:" .. e.id)
    elseif e.t == "pet" then
        if not (GetPetActionInfo and GetPetActionInfo(e.index) and GameTooltip:SetPetAction(e.index)) then
            GameTooltip:SetText(Mod:Describe(e))
        end
    end
end

-- the same place the game puts action button tooltips (the default tooltip
-- position, or next to the button when "Enhanced Tooltips" is off)
function Mod:AnchorTooltip(owner)
    if GetCVar("UberTooltips") == "1" and GameTooltip_SetDefaultAnchor then
        GameTooltip_SetDefaultAnchor(GameTooltip, owner)
    else
        local parent = owner:GetParent()
        local left = parent == MultiBarBottomRight or parent == MultiBarRight or parent == MultiBarLeft
        GameTooltip:SetOwner(owner, left and "ANCHOR_LEFT" or "ANCHOR_RIGHT")
    end
end

-- returns true if it showed a layer tooltip
function Mod:LayerTooltip(owner, name)
    local e, layer = self:TooltipEntry(name)
    if not e then return false end
    self:AnchorTooltip(owner)
    GameTooltip:ClearLines()
    SetEntryTooltip(e)
    GameTooltip:AddLine(self.LAYERS[layer].label .. " layer (ZBar)", 0.2, 1, 0.6)
    GameTooltip:Show()
    return true
end

local function ButtonName(frame)
    if not frame then return nil end
    if frame.zbarName then return frame.zbarName end
    local n = frame.GetName and frame:GetName()
    return n and ns.Bars.info[n] and n or nil
end

-- the game calls this on enter and again every moment while the tooltip is up
if type(ActionButton_SetTooltip) == "function" then
    hooksecurefunc("ActionButton_SetTooltip", function(self)
        local name = ButtonName(self)
        if name then Mod:LayerTooltip(self, name) end
    end)
end

-- Ctrl / Shift pressed or released while the mouse is on a button: redo its tooltip
function Mod:RefreshTooltip()
    local owner = GameTooltip:IsShown() and GameTooltip:GetOwner()
    local name = ButtonName(owner)
    if not name then return end
    if owner.zbarName then
        local onEnter = owner:GetScript("OnEnter")
        if onEnter then onEnter(owner) end
    elseif not self:LayerTooltip(owner, name) then
        -- back to the base action (set here, not through the game's own
        -- function: that one writes to the secure button)
        local slot = Mod.SlotOf(owner)
        if slot and HasAction(slot) then
            GameTooltip:SetAction(slot)
            GameTooltip:Show()
        else
            GameTooltip:Hide()
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
        local holder = icons[name]
        local icon = e and self:Icon(e)
        local proxy = proxies[name]
        if proxy and proxy:IsShown() then
            -- the stand-in shows the layer icon itself
            if icon then
                proxy.icon:SetTexture(icon)
                proxy.icon:Show()
            else
                proxy.icon:Hide()
            end
            if holder then holder:Hide() end
        elseif icon or (layer and setup) then
            local btn = _G[name]
            -- a frame of its own next to the button (same parent), not a texture
            -- on the button: the game hides buttons whose base slot is empty,
            -- and the layer icon must still show there
            if not holder then
                holder = CreateFrame("Frame", nil, btn:GetParent())
                holder:EnableMouse(false)
                holder.tex = holder:CreateTexture(nil, "OVERLAY")
                holder.tex:SetPoint("TOPLEFT", 2, -2)
                holder.tex:SetPoint("BOTTOMRIGHT", -2, 2)
                icons[name] = holder
            end
            if holder:GetParent() ~= btn:GetParent() then holder:SetParent(btn:GetParent()) end
            holder:ClearAllPoints()
            holder:SetAllPoints(btn)
            holder:SetFrameLevel(btn:GetFrameLevel() + 5)
            if icon then
                holder.tex:SetTexture(icon)
                holder.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            else
                holder.tex:SetTexture(0.05, 0.05, 0.05, 0.9) -- empty slot on this layer
            end
            holder:Show()
        elseif holder then
            holder:Hide()
        end
    end
end

------------------------------------------------------------------------
-- Stand-ins: the game hides an action button whose base slot is empty
-- (unless the grid is shown), so it could not be clicked even if it has a
-- Ctrl / Shift action. Such a button gets a secure stand-in in its place:
-- empty slot frame + key text, Ctrl / Shift click does the layer action,
-- and a spell dropped on it goes to the real button's base slot.
-- Its key binding keeps working on the hidden real button anyway.
------------------------------------------------------------------------
local BINDING = {
    ActionButton = "ACTIONBUTTON",
    MultiBarBottomLeftButton = "MULTIACTIONBAR1BUTTON",
    MultiBarBottomRightButton = "MULTIACTIONBAR2BUTTON",
    MultiBarRightButton = "MULTIACTIONBAR3BUTTON",
    MultiBarLeftButton = "MULTIACTIONBAR4BUTTON",
}

local function SlotOf(btn)
    if btn.action then return btn.action end
    if ActionButton_CalculateAction then return ActionButton_CalculateAction(btn, "LeftButton") end
end
Mod.SlotOf = SlotOf

local function HasLayerAction(name)
    for _, layer in ipairs(Mod.ORDER) do
        if Mod:IsOn(layer) and Mod:Get(name, layer) then return true end
    end
end

local function KeyText(info)
    local cmd = BINDING[info.bar.prefix]
    local key = cmd and GetBindingKey(cmd .. info.index)
    return key and GetBindingText(key, "KEY_", 1) or ""
end

local function Proxy(name)
    local p = proxies[name]
    if p then return p end
    local info = ns.Bars.info[name]
    local btn = info.btn
    p = CreateFrame("Button", "ZBarStandIn" .. name, btn:GetParent(), "SecureActionButtonTemplate")
    p:RegisterForClicks("AnyUp")
    -- Alt (or the self-cast key set in the options) casts on yourself, like real buttons
    p:SetAttribute("checkselfcast", true)
    p:SetAttribute("checkfocuscast", true)

    p.slotArt = p:CreateTexture(nil, "BACKGROUND")
    p.slotArt:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    p.slotArt:SetSize(66, 66)
    p.slotArt:SetPoint("CENTER", 0, -1)

    p.icon = p:CreateTexture(nil, "ARTWORK")
    p.icon:SetPoint("TOPLEFT", 2, -2)
    p.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    p.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    p.icon:Hide()

    p.hotkey = p:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmallGray")
    p.hotkey:SetPoint("TOPRIGHT", -2, -2)
    p.hotkey:SetJustifyH("RIGHT")

    p:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    local function PlaceBase()
        local slot = SlotOf(btn)
        if slot and GetCursorInfo() and not InCombatLockdown() then PlaceAction(slot) end
    end
    p:SetScript("OnReceiveDrag", PlaceBase)
    p:HookScript("OnMouseUp", function(_, mouse)
        if mouse == "LeftButton" and GetCursorInfo() then PlaceBase() end
    end)
    p.zbarName = name
    p:SetScript("OnEnter", function(self)
        if Mod:LayerTooltip(self, name) then return end
        Mod:AnchorTooltip(self)
        GameTooltip:SetText(info.label .. "  |cff888888(empty)|r")
        Mod:LayerLines(name)
        GameTooltip:Show()
    end)
    p:SetScript("OnLeave", function() GameTooltip:Hide() end)

    proxies[name] = p
    Mod:SetLayerAttributes(p, name)
    return p
end

function Mod:UpdateProxies()
    if not ns.db then return end
    if InCombatLockdown() then
        self.proxyPending = true -- showing / hiding secure buttons waits for combat to end
        self:UpdateIcons()
        return
    end
    self.proxyPending = nil
    for name, info in pairs(ns.Bars.info) do
        local btn = info.btn
        local need = info.managed and not ns.unlocked and not btn:IsShown()
            and btn:GetParent() ~= ns.Groups.hiddenParent and HasLayerAction(name)
        local p = proxies[name]
        if need then
            p = Proxy(name)
            if p:GetParent() ~= btn:GetParent() then p:SetParent(btn:GetParent()) end
            p:ClearAllPoints()
            p:SetAllPoints(btn)
            p:SetFrameLevel(btn:GetFrameLevel() + 1)
            p.hotkey:SetText(KeyText(info))
            p:Show()
        elseif p and p:IsShown() then
            p:Hide()
        end
    end
    self:UpdateIcons()
end

local pendingProxy = false
local function QueueProxies()
    if pendingProxy then return end
    pendingProxy = true
    -- after the game has updated its own buttons for the same event
    ns.After(0.1, function()
        pendingProxy = false
        Mod:UpdateProxies()
    end)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("MODIFIER_STATE_CHANGED")
ev:RegisterEvent("PET_BAR_UPDATE")
ev:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
ev:RegisterEvent("ACTIONBAR_SHOWGRID")
ev:RegisterEvent("ACTIONBAR_HIDEGRID")
ev:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
ev:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
ev:RegisterEvent("UPDATE_BINDINGS")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function(_, event)
    if not ns.ready then return end
    if event == "MODIFIER_STATE_CHANGED" then
        Mod:UpdateIcons()
        Mod:RefreshTooltip()
    elseif event == "PET_BAR_UPDATE" then
        Mod:UpdateIcons()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if Mod.proxyPending then QueueProxies() end
    else
        QueueProxies()
    end
end)

------------------------------------------------------------------------
-- Drag lock: while a layer has taken the Pick Up Action Key, a small lock
-- under the main bar's page number opens it again for a while (Blizzard-like
-- Shift+drag). It locks itself again when combat starts or after 2 minutes
-- without dragging.
--
-- Moving a spell this way also moves the button's Ctrl / Shift actions:
-- the whole button goes with it (a swap when the other button is not empty).
------------------------------------------------------------------------
local LOCK_IDLE = 120
local lockButton, lockDeadline
-- the 3.3.5 client has no open-lock picture: the dungeon finder's lock, gold
-- when locked, green when open
local LOCK_TEX = "Interface\\LFGFrame\\UI-LFG-ICON-LOCK"

-- a layer took the pickup key, so there is something to unlock
function Mod:LockNeeded()
    return ns.db and DB().modSavedPickup ~= nil
end

local function PickupKey()
    return DB().modSavedPickup or "SHIFT"
end

local function KeyLabel(k)
    return k:sub(1, 1) .. k:sub(2):lower()
end

local pageMoved
local function UpdateLockButton()
    if not lockButton then return end
    local num = _G.MainMenuBarPageNumber
    if Mod:LockNeeded() then
        -- the page number moves up a little, the lock sits under it
        if num and not pageMoved then
            local point, rel, relPoint, x, y = num:GetPoint(1)
            if point then
                pageMoved = { point, rel, relPoint, x, y }
                num:ClearAllPoints()
                num:SetPoint(point, rel, relPoint, x, (y or 0) + 9)
            end
        end
        lockButton.icon:SetTexture(LOCK_TEX)
        if Mod.dragOpen then
            lockButton.icon:SetVertexColor(0.3, 1, 0.3)
            lockButton.glow:Show()
        else
            lockButton.icon:SetVertexColor(1, 1, 1)
            lockButton.glow:Hide()
        end
        lockButton:Show()
    else
        if num and pageMoved then
            num:ClearAllPoints()
            num:SetPoint(unpack(pageMoved))
            pageMoved = nil
        end
        lockButton:Hide()
    end
end

function Mod:SetDragOpen(open)
    if open and not self:LockNeeded() then open = false end
    open = open and true or nil
    if open == self.dragOpen then UpdateLockButton() return end
    self.dragOpen = open
    if open then
        SetModifiedClick(PICKUP, PickupKey()) -- for now only, not saved
        lockDeadline = GetTime() + LOCK_IDLE
        ns.Print("Spell dragging open: " .. KeyLabel(PickupKey()) .. "+drag moves a spell together with its "
            .. "Ctrl / Shift actions. Locks again when combat starts or after 2 minutes without dragging.")
    else
        SetModifiedClick(PICKUP, "NONE")
        lockDeadline = nil
        ns.Print("Spell dragging locked.")
    end
    UpdateLockButton()
    if lockButton and GameTooltip:IsOwned(lockButton) then lockButton:GetScript("OnEnter")(lockButton) end
end

local function CreateLockButton()
    local art = _G.MainMenuBarArtFrame
    local num = _G.MainMenuBarPageNumber
    if lockButton or not (art and num) then return end
    local b = CreateFrame("Button", "ZBarDragLock", art)
    b:SetSize(20, 20)
    b:SetPoint("TOP", num, "BOTTOM", 0, 1)
    b:SetFrameLevel(art:GetFrameLevel() + 5)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(15, 18) -- the picture's own shape, as the dungeon finder shows it
    b.icon:SetPoint("CENTER")
    b.icon:SetTexCoord(0, 0.71875, 0, 0.875)
    b.glow = b:CreateTexture(nil, "BACKGROUND")
    b.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    b.glow:SetBlendMode("ADD")
    b.glow:SetVertexColor(0.3, 1, 0.3)
    b.glow:SetPoint("CENTER")
    b.glow:SetSize(40, 40)
    b.glow:Hide()
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetScript("OnClick", function()
        if InCombatLockdown() and not Mod.dragOpen then
            ns.Print("Spell dragging cannot be opened in combat.")
            return
        end
        Mod:SetDragOpen(not Mod.dragOpen)
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(Mod.dragOpen and "Spell dragging: open" or "Spell dragging: locked")
        GameTooltip:AddLine(Mod.dragOpen
            and (KeyLabel(PickupKey()) .. "+drag moves a spell with its Ctrl / Shift actions. Click to lock.")
            or ("Click to open: " .. KeyLabel(PickupKey()) .. "+drag moves spells again, with their Ctrl / Shift actions."),
            1, 1, 1, true)
        GameTooltip:AddLine("Locked while a layer uses the " .. KeyLabel(PickupKey())
            .. " key, so a spell is not pulled off by accident. Locks again in combat or after 2 minutes.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnUpdate", function()
        if lockDeadline and GetTime() > lockDeadline and not GetCursorInfo() then Mod:SetDragOpen(false) end
    end)
    lockButton = b
end

function Mod:UpdateLock()
    CreateLockButton()
    if not self:LockNeeded() then self.dragOpen = nil end
    UpdateLockButton()
end

-- the whole button moves: base action (the game does that) + its layers
-- carry = { origin = name, from = name or nil, slot = slot on the cursor, pending = layers or nil }
local carry

local function Layers(name)
    local m = DB().mods[name]
    return m and ns.DeepCopy(m) or nil
end

local function SetLayers(name, layers)
    DB().mods[name] = (layers and next(layers)) and ns.DeepCopy(layers) or nil
end

local function Label(name)
    local info = ns.Bars.info[name]
    return info and info.label or name
end

local function Debug(...)
    if not Mod.dragDebug then return end
    local t = {}
    for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end
    ns.Print("|cff999999drag:|r " .. table.concat(t, " "))
end

function Mod:ToggleDragDebug()
    self.dragDebug = not self.dragDebug
    ns.Print("Drag debug " .. (self.dragDebug and "on" or "off") .. ".")
end

local function DragStart(btn, name)
    Debug("start", name, "slot", SlotOf(btn), "cursor", GetCursorInfo(), "unlocked", ns.unlocked)
    if ns.unlocked or not GetCursorInfo() then return end -- ZBar's own unlock mode has its own handling
    carry = { origin = name, from = name, slot = SlotOf(btn) }
    if lockDeadline then lockDeadline = GetTime() + LOCK_IDLE end
end

-- something from the cursor landed on button "name" (its slot changed)
local function Dropped(name)
    Debug("dropped on", name)
    local moving
    if carry.from then
        moving = Layers(carry.from)
        SetLayers(carry.from, nil)
    else
        moving = carry.pending
    end
    local old = Layers(name)
    SetLayers(name, moving)
    carry.from, carry.pending = nil, old
    carry.slot = SlotOf(ns.Bars.info[name].btn)
    if lockDeadline then lockDeadline = GetTime() + LOCK_IDLE end
    Mod:ApplyAll()
end

-- the cursor got empty: the drag is over
local function DragEnd()
    Debug("end", carry and carry.pending and "with pending layers" or "")
    local c = carry
    carry = nil
    if not c or not c.pending then return end
    -- the other button's spell was thrown away: its Ctrl / Shift actions are
    -- not, they go to the button the drag started from (if it has none now)
    local into = c.origin
    if into and not DB().mods[into] then
        SetLayers(into, c.pending)
        ns.Print("Ctrl / Shift actions of the removed spell went to " .. Label(into) .. ".")
    else
        ns.Print("The Ctrl / Shift actions of the removed spell were removed too.")
    end
    Mod:ApplyAll()
end

local hooked = {}
function Mod:HookDrags()
    for name, info in pairs(ns.Bars.info) do
        local btn = info.btn
        if btn and not hooked[btn] and btn:GetScript("OnDragStart") then
            hooked[btn] = true
            btn:HookScript("OnDragStart", function(self) DragStart(self, name) end)
        end
    end
end

local dragEv = CreateFrame("Frame")
dragEv:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
dragEv:RegisterEvent("CURSOR_UPDATE")
dragEv:RegisterEvent("PLAYER_REGEN_DISABLED")
dragEv:SetScript("OnEvent", function(_, event, slot)
    if not ns.ready then return end
    if event == "PLAYER_REGEN_DISABLED" then
        if Mod.dragOpen then Mod:SetDragOpen(false) end
    elseif event == "ACTIONBAR_SLOT_CHANGED" then
        if carry then
            local f = GetMouseFocus()
            Debug("slot", slot, "carry slot", carry.slot, "focus", f and f.GetName and f:GetName())
        end
        if not carry or ns.unlocked or slot == carry.slot then return end
        local name = ButtonName(GetMouseFocus())
        local info = name and ns.Bars.info[name]
        if info and SlotOf(info.btn) == slot then Dropped(name) end
    elseif event == "CURSOR_UPDATE" then
        if carry and not GetCursorInfo() then
            -- placing and clearing come in the same moment: decide a bit later
            ns.After(0.05, function()
                if carry and not GetCursorInfo() then DragEnd() end
            end)
        end
    end
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
    if self:UpdatePickupKey() then changed = true end
    if changed then SaveBindings(GetCurrentBindingSet()) end
    self:ApplyAll()
    self:HookDrags()
    self:UpdateLock()
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
