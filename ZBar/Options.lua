-- ZBar options panel: Interface > AddOns > ZBar
local _, ns = ...

local panel = CreateFrame("Frame", "ZBarOptionsPanel", UIParent)
panel.name = "ZBar"
panel:Hide()

local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText("ZBar " .. ns.VERSION)

local desc = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
desc:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
desc:SetJustifyH("LEFT")
desc:SetText("Rearrange the default action bars without replacing them. Layouts are saved per character.")

-- the sub-pages are easy to miss behind the small + in the list: buttons for them
local function PageButton(text, w, x, getPanel)
    local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    b:SetSize(w, 22)
    b:SetPoint("TOPRIGHT", x, -12)
    b:SetText(text)
    b:SetScript("OnClick", function() ns.OpenSubPanel(getPanel()) end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:SetText(text)
        GameTooltip:AddLine("Also in the list on the left: click the + next to ZBar.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end
local macroPage = PageButton("Macro Builder >", 130, -16, function() return ns.MacroPanel end)
local layerPage = PageButton("Ctrl / Shift Layers >", 150, -152, function() return ns.ModifierPanel end)
local pagesText = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
pagesText:SetPoint("RIGHT", layerPage, "LEFT", -8, 0)
pagesText:SetText("More pages:")

local function CloseMenus()
    if InterfaceOptionsFrame and InterfaceOptionsFrame:IsShown() then HideUIPanel(InterfaceOptionsFrame) end
    if GameMenuFrame and GameMenuFrame:IsShown() then HideUIPanel(GameMenuFrame) end
end

local function Button(text, w, x, y, onClick)
    local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    b:SetSize(w, 22)
    b:SetPoint("TOPLEFT", x, y)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

local function Label(text, x, y, font)
    local fs = panel:CreateFontString(nil, "ARTWORK", font or "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetJustifyH("LEFT")
    fs:SetText(text or "")
    return fs
end

------------------------------------------------------------------------
-- Layout section
------------------------------------------------------------------------
Label("Layout", 16, -58, "GameFontNormal")

local y = -78
local function Row(text, help, onClick)
    local b = Button(text, 160, 16, y, onClick)
    local fs = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    fs:SetPoint("LEFT", b, "RIGHT", 10, 0)
    fs:SetText(help)
    y = y - 26
    return b
end

-- save, restore and undo of the layout are on the unlock toolbar, not here
local unlockButton = Row("Unlock Bars", "Unlock, save, restore and undo the layout - all on the toolbar that opens. Lock again there or with /zbar.", function()
    if ns.unlocked then
        ns.Mover:Lock()
    else
        if InCombatLockdown() then ns.Print("Cannot unlock in combat.") return end
        CloseMenus()
        ns.Mover:Unlock()
    end
    panel:refresh()
end)
Row("Factory Reset", "Put every bar back to its Blizzard position (reloads the UI).", function()
    StaticPopup_Show("ZBAR_FACTORY_RESET")
end)

------------------------------------------------------------------------
-- Role section
------------------------------------------------------------------------
local ry = y - 14
Label("Role Profiles", 16, ry, "GameFontNormal")
Label("Each role keeps its own bar positions, bar contents, Ctrl / Shift layers, gear set and (optionally) talents - this character only.", 16, ry - 18)
local currentText = Label("", 16, ry - 34, "GameFontHighlight")

local roleButtons, roleStatus, gearDrops = {}, {}, {}

local function GearDropdown(role, x, yy)
    local dd = CreateFrame("Frame", "ZBarGearDrop" .. role, panel, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", x - 16, yy)
    UIDropDownMenu_SetWidth(dd, 120)
    UIDropDownMenu_Initialize(dd, function()
        local r = ns.Roles:Get(role)
        local cur = r and r.gear
        local function Add(text, value)
            local info = UIDropDownMenu_CreateInfo()
            info.text = text
            info.value = value
            info.checked = (cur or "") == value
            info.func = function()
                ns.Roles:SetGear(role, value)
                panel:refresh()
            end
            UIDropDownMenu_AddButton(info)
        end
        Add("No gear change", "")
        for _, name in ipairs(ns.Roles:GearSets()) do Add(name, name) end
    end)
    return dd
end

for i, role in ipairs(ns.Roles.list) do
    local x = 16 + (i - 1) * 170
    roleButtons[role] = Button(role, 150, x, ry - 54, function()
        ns.Roles:Request(role)
        panel:refresh()
    end)
    roleButtons[role]:SetScript("OnEnter", function(self)
        local r = ns.Roles:Get(role)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(role)
        GameTooltip:AddLine((r and r.savedAt) and ("Saved " .. r.savedAt) or "Not saved yet", 1, 1, 1)
        local T = ns.Roles.Talents
        if r and r.talents and T:Available() then
            GameTooltip:AddLine("Talents: " .. T:Summary(r.talents), 1, 0.82, 0)
            for _, n in ipairs(T:Names(r.talents)) do GameTooltip:AddLine("  " .. n, 0.8, 0.8, 0.8) end
        end
        GameTooltip:Show()
    end)
    roleButtons[role]:SetScript("OnLeave", function() GameTooltip:Hide() end)
    roleStatus[role] = Label("", x, ry - 80, "GameFontDisableSmall")
    Label("Gear set:", x, ry - 98, "GameFontNormalSmall")
    gearDrops[role] = GearDropdown(role, x, ry - 110)
end

local saveRoleButton = Button("Save Role (layout + bars)", 200, 16, ry - 148, function()
    ns.Roles:Save()
    panel:refresh()
end)
local reloadRoleButton = Button("Reload Role", 130, 222, ry - 148, function()
    ns.Roles:Reload()
    panel:refresh()
end)

local auto = CreateFrame("CheckButton", "ZBarRoleAutoSave", panel, "InterfaceOptionsCheckButtonTemplate")
auto:SetPoint("LEFT", reloadRoleButton, "RIGHT", 12, 0)
_G[auto:GetName() .. "Text"]:SetText("Auto-save when switching roles")
auto:SetScript("OnClick", function(self)
    if ns.db then ns.Roles.DB().roleAutoSave = self:GetChecked() and true or false end
end)

-- talents (Conquest of Azeroth)
local talentCheck = CreateFrame("CheckButton", "ZBarRoleTalents", panel, "InterfaceOptionsCheckButtonTemplate")
talentCheck:SetPoint("TOPLEFT", 16, ry - 172)
_G[talentCheck:GetName() .. "Text"]:SetText("Save talents with roles (Conquest of Azeroth) - asks before changing them")
talentCheck:SetScript("OnClick", function(self)
    if ns.db then ns.Roles.DB().roleTalents = self:GetChecked() and true or nil end
    panel:refresh()
end)

-- dual spec: role per talent group
Label("Dual spec: switch role automatically when changing spec", 16, ry - 204, "GameFontNormalSmall")
local specDrops = {}
for spec = 1, 2 do
    local x = 16 + (spec - 1) * 170
    Label("Spec " .. spec .. ":", x, ry - 224, "GameFontHighlightSmall")
    local dd = CreateFrame("Frame", "ZBarSpecDrop" .. spec, panel, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", x + 30, ry - 216)
    UIDropDownMenu_SetWidth(dd, 90)
    UIDropDownMenu_Initialize(dd, function()
        local cur = ns.db and ns.Roles.DB().specRole[spec]
        local function Add(text, value)
            local info = UIDropDownMenu_CreateInfo()
            info.text = text
            info.checked = (cur or "") == (value or "")
            info.func = function()
                if ns.db then ns.Roles.DB().specRole[spec] = value end
                panel:refresh()
            end
            UIDropDownMenu_AddButton(info)
        end
        Add("Off", nil)
        for _, role in ipairs(ns.Roles.list) do Add(role, role) end
    end)
    specDrops[spec] = dd
end

-- minimap button (Threat Plates has its own role button, so this one can go)
local mmHide = CreateFrame("CheckButton", "ZBarHideMinimap", panel, "InterfaceOptionsCheckButtonTemplate")
mmHide:SetPoint("TOPLEFT", 360, ry - 218)
_G[mmHide:GetName() .. "Text"]:SetText("Hide minimap button")
mmHide:SetScript("OnClick", function(self)
    if ns.db then ns.Minimap:SetHidden(self:GetChecked()) end
end)
local tpNote = Label("", 360, ry - 244, "GameFontDisableSmall")

-- custom (server specific) bars: hide only
Label("Custom Bars (hide only - moving and scaling stay in their own menu)", 16, ry - 264, "GameFontNormalSmall")
-- up to 4 bars, two per row; filled in by refresh with whatever is found
local customChecks = {}
for i = 1, 4 do
    local cb = CreateFrame("CheckButton", "ZBarCustomHide" .. i, panel, "InterfaceOptionsCheckButtonTemplate")
    cb:SetPoint("TOPLEFT", 16 + ((i - 1) % 2) * 300, ry - 276 - math.floor((i - 1) / 2) * 24)
    cb:SetScript("OnClick", function(self)
        if ns.db and self.barName then ns.CustomBars:SetHidden(self.barName, self:GetChecked()) end
    end)
    cb:Hide()
    customChecks[i] = cb
end
local customNone = Label("No custom bars found on this character.", 20, ry - 282, "GameFontDisableSmall")

------------------------------------------------------------------------
function panel:refresh()
    unlockButton:SetText(ns.unlocked and "Lock Bars" or "Unlock Bars")
    if not ns.db then return end

    local db = ns.Roles.DB()
    local cur = db.currentRole
    local linked = ns.Roles:TPLinked()
    local T = ns.Roles.Talents
    local nowT = T:Available() and T:Current()
    currentText:SetText("Current role: " .. (cur or "none")
        .. (linked and "   |cff8af559(follows Threat Plates)|r" or "")
        .. (nowT and ("   |cffaaaaaaTalents now: " .. T:Summary(nowT) .. "|r") or ""))
    talentCheck:SetChecked(db.roleTalents)
    if T:Available() then
        talentCheck:Enable()
        _G[talentCheck:GetName() .. "Text"]:SetTextColor(1, 1, 1)
    else
        talentCheck:Disable()
        _G[talentCheck:GetName() .. "Text"]:SetTextColor(0.5, 0.5, 0.5)
    end
    mmHide:SetChecked(ns.Minimap:IsHidden())
    tpNote:SetText(linked and "Threat Plates found: its role button switches ZBar too." or "")
    for _, role in ipairs(ns.Roles.list) do
        local r = db.roles[role]
        roleButtons[role]:SetText(role == cur and ("> " .. role .. " <") or role)
        local status = (r and r.savedAt) and ("Saved " .. r.savedAt:sub(6)) or "Not saved yet"
        if r and r.talents and ns.Roles.Talents:Available() then
            local cp, sp = ns.Roles.Talents:Points(r.talents)
            status = status .. " | " .. ns.Roles.Talents:SpecName(r.talents) .. " " .. cp .. "/" .. sp
        end
        roleStatus[role]:SetText(status)
        UIDropDownMenu_SetText(gearDrops[role], (r and r.gear) or "No gear change")
    end
    local saved = cur and db.roles[cur] and db.roles[cur].actions
    if cur then saveRoleButton:Enable() else saveRoleButton:Disable() end
    if saved then reloadRoleButton:Enable() else reloadRoleButton:Disable() end
    saveRoleButton:SetText(cur and ("Save " .. cur .. " (layout + bars)") or "Save Role (layout + bars)")
    reloadRoleButton:SetText(cur and ("Reload " .. cur) or "Reload Role")
    auto:SetChecked(db.roleAutoSave)
    for spec = 1, 2 do
        UIDropDownMenu_SetText(specDrops[spec], db.specRole[spec] or "Off")
    end
    local bars = ns.CustomBars:OptionList()
    for i, cb in ipairs(customChecks) do
        local b = bars[i]
        if b then
            cb.barName = b.name
            _G[cb:GetName() .. "Text"]:SetText("Hide " .. b.label .. (b.found and "" or "  |cff888888(not found now)|r"))
            cb:SetChecked(ns.CustomBars:IsHidden(b.name))
            cb:Show()
        else
            cb.barName = nil
            cb:Hide()
        end
    end
    if #bars == 0 then customNone:Show() else customNone:Hide() end
end
panel:SetScript("OnShow", function(self) self:refresh() end)

InterfaceOptions_AddCategory(panel)
ns.OptionsPanel = panel

------------------------------------------------------------------------
-- Sub-panel: Interface > AddOns > ZBar > Ctrl / Shift Layers
------------------------------------------------------------------------
local mp = CreateFrame("Frame", "ZBarModifierPanel", UIParent)
mp.name = "Ctrl / Shift Layers"
mp.parent = "ZBar"
mp:Hide()

-- Everything is chained below the previous element, so a text that wraps
-- to two lines pushes the rest down instead of overlapping it.
local last -- the element the next one goes below

local function Below(region, x, gap)
    if last then
        region:SetPoint("TOPLEFT", last.region, "BOTTOMLEFT", x - last.x, -(gap or 6))
    else
        region:SetPoint("TOPLEFT", x, -16)
    end
    last = { region = region, x = x }
    return region
end

local function MText(text, x, font, gap)
    local fs = mp:CreateFontString(nil, "ARTWORK", font or "GameFontHighlightSmall")
    fs:SetWidth(560 - (x - 16))
    fs:SetJustifyH("LEFT")
    fs:SetText(text or "")
    return Below(fs, x, gap)
end

local function MCheck(name, text, gap)
    local cb = CreateFrame("CheckButton", name, mp, "InterfaceOptionsCheckButtonTemplate")
    _G[name .. "Text"]:SetText(text)
    Below(cb, 16, gap)
    -- the check box art has empty space under it; texts below it start a bit higher
    last = { region = cb, x = 16 }
    return cb
end

MText("ZBar - Ctrl / Shift Layers", 16, "GameFontNormalLarge")
MText("Give every action button a second and a third action: hold Ctrl or Shift while you press its key "
    .. "(or click it). Works in combat. Alt is not touched - it stays the game's self-cast key.", 16, nil, 10)

local layerChecks = {}
for i, layer in ipairs(ns.Modifiers.ORDER) do
    local L = ns.Modifiers.LAYERS[layer]
    local cb = MCheck("ZBarLayer" .. L.label, "Use the " .. L.label .. " layer", i == 1 and 14 or 10)
    cb:SetScript("OnClick", function(self)
        if not ns.db then return end
        if not ns.Modifiers:SetLayer(layer, self:GetChecked()) then
            self:SetChecked(ns.Modifiers:IsOn(layer)) -- refused (combat)
        end
    end)
    MText("Frees " .. L.frees .. ". Turning it off puts those key bindings back.", 44, "GameFontDisableSmall", 0)
    if layer == "shift" then
        MText("|cffffd100Windows:|r in Settings > Accessibility > Keyboard, open the |cffffd100Sticky keys|r and "
            .. "|cffffd100Filter keys|r menus and turn every option inside those two menus off - turning off only "
            .. "their main switch is not enough. (The rest of the Keyboard page can stay as it is.) "
            .. "Or use only the Ctrl layer.", 44, "GameFontDisableSmall", 4)
    end
    layerChecks[layer] = cb
end
MText("Pet actions: put them on any Ctrl or Shift slot (right-click a button in Mode: Modifiers).",
    44, "GameFontDisableSmall", 8)

local showIcons = MCheck("ZBarLayerIcons", "Show the Ctrl / Shift actions on the buttons while the key is held", 10)
showIcons:SetScript("OnClick", function(self)
    if ns.db then
        ns.Modifiers.DB().modShowIcons = self:GetChecked() and true or false
        ns.Modifiers:UpdateIcons()
    end
end)

MText("How to assign", 16, "GameFontNormal", 14)
MText("1. Click Set Up (or type /zbar layers) - the bars unlock in Mode: Modifiers.\n"
    .. "2. Pick up a spell, macro or item, hold Ctrl or Shift and drop it on a button.\n"
    .. "3. Right-click a button for pet actions or to clear a layer.\n"
    .. "4. Lock the bars. Ctrl / Shift + the button's key now does the new action.", 16, nil, 6)

local function MButton(text, w, onClick, nextTo)
    local b = CreateFrame("Button", nil, mp, "UIPanelButtonTemplate")
    b:SetSize(w, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    if nextTo then
        b:SetPoint("LEFT", nextTo, "RIGHT", 10, 0)
    else
        Below(b, 16, 12)
    end
    return b
end
local setUp = MButton("Set Up", 120, function() ns.Modifiers:OpenSetup() end)
MButton("Clear All Ctrl / Shift Actions", 220, function() StaticPopup_Show("ZBAR_CLEAR_LAYERS") end, setUp)

MText("Saved per character and in each role profile. If your key bindings are account-wide "
    .. "(not \"Character Specific\"), freeing the keys affects your other characters too.", 16, "GameFontDisableSmall", 12)

function mp:refresh()
    if not ns.db then return end
    for layer, cb in pairs(layerChecks) do cb:SetChecked(ns.Modifiers:IsOn(layer)) end
    showIcons:SetChecked(ns.Modifiers.DB().modShowIcons)
end
mp:SetScript("OnShow", function(self) self:refresh() end)
InterfaceOptions_AddCategory(mp)
ns.ModifierPanel = mp

function ns.Modifiers:OpenSetup()
    if InCombatLockdown() then ns.Print("Cannot unlock in combat.") return end
    CloseMenus()
    if not ns.unlocked then ns.Mover:Unlock() end
    ns.mode = "modifiers"
    ns.Toolbar:Open()
    ns.Mover:Refresh()
    if not ns.Modifiers:IsOn("ctrl") and not ns.Modifiers:IsOn("shift") then
        ns.Print("Both layers are off - turn them on in Interface > AddOns > ZBar > Ctrl / Shift Layers.")
    end
end

StaticPopupDialogs["ZBAR_CLEAR_LAYERS"] = {
    text = "ZBar: remove every Ctrl and Shift action from all buttons?",
    button1 = YES,
    button2 = NO,
    OnAccept = function() ns.Modifiers:ClearAll() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}
