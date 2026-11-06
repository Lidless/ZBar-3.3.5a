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

-- returns true if it showed a layer tooltip
function Mod:LayerTooltip(owner, name)
    local e, layer = self:TooltipEntry(name)
    if not e then return false end
    if not GameTooltip:IsOwned(owner) then GameTooltip:SetOwner(owner, "ANCHOR_RIGHT") end
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
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if Mod:LayerTooltip(self, name) then return end
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
