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
local function Row(text, help, onClick, extra)
    local b = Button(text, 160, 16, y, onClick)
    local fs = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    fs:SetPoint("LEFT", b, "RIGHT", 10, 0)
    fs:SetPoint("RIGHT", panel, "RIGHT", -16, 0) -- long texts wrap instead of running off the page
    fs:SetJustifyH("LEFT")
    fs:SetText(help)
    y = y - 26 - (extra or 0)
    return b
end

-- save, restore and undo of the layout are on the unlock toolbar, not here
local unlockButton = Row("Unlock Bars", "Unlock, save, restore and undo the layout - all on the toolbar that opens.\nLock again there or with /zbar.", function()
    if ns.unlocked then
        ns.Mover:Lock()
    else
        if InCombatLockdown() then ns.Print("Cannot unlock in combat.") return end
        CloseMenus()
        ns.Mover:Unlock()
    end
    panel:refresh()
end, 6) -- two lines of text
Row("Factory Reset", "Put every bar back to its Blizzard position (reloads the UI).", function()
    StaticPopup_Show("ZBAR_FACTORY_RESET")
end)

------------------------------------------------------------------------
-- Profiles: one per talent tree (Conquest of Azeroth) or per dual spec
------------------------------------------------------------------------
local ry = y - 14
local profTitle = Label("Talent Trees", 16, ry, "GameFontNormal")
local profDesc = Label("", 16, ry - 18)
profDesc:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
ry = ry - 12 -- the description takes two lines: everything below moves down
local currentText = Label("", 16, ry - 34, "GameFontHighlight")
currentText:SetPoint("RIGHT", panel, "RIGHT", -16, 0)

local slots = {} -- up to 4 columns (a class has 3 or 4 trees): { button, status, info, gear, key }
local COL = 145

local function GearDropdown(i, x, yy)
    local dd = CreateFrame("Frame", "ZBarGearDrop" .. i, panel, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", x - 16, yy)
    UIDropDownMenu_SetWidth(dd, 100)
    UIDropDownMenu_Initialize(dd, function()
        local key = slots[i] and slots[i].key -- the game runs this once while the column is still being built
        local r = key and ns.Roles:Get(key)
        local cur = r and r.gear
        local function Add(text, value)
            local info = UIDropDownMenu_CreateInfo()
            info.text = text
            info.value = value
            info.checked = (cur or "") == value
            info.func = function()
                if key then ns.Roles:SetGear(key, value) end
                panel:refresh()
            end
            UIDropDownMenu_AddButton(info)
        end
        Add("No gear change", "")
        for _, name in ipairs(ns.Roles:GearSets()) do Add(name, name) end
    end)
    return dd
end

for i = 1, 4 do
    local x = 16 + (i - 1) * COL
    local s = {}
    s.button = Button("", COL - 6, x, ry - 54, function()
        if s.key and ns.Roles:Mode() == "coa" then
            if s.key == ns.Roles:Current() then
                ns.Print("Already on " .. ns.Roles:Label(s.key) .. ". (Reload loads its saved bars again.)")
            else
                ns.Roles:Switch(s.key)
            end
        end
        panel:refresh()
    end)
    s.button:SetScript("OnEnter", function(self)
        if not s.key then return end
        local R = ns.Roles
        local r = R:Get(s.key)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(R:Label(s.key))
        local e = R:Entry(s.key)
        local info = e and e.tree and R:TreeInfo(e.tree)
        if info then GameTooltip:AddLine(info, 0.8, 0.8, 0.8) end
        GameTooltip:AddLine((r and r.savedAt) and ("Saved " .. r.savedAt) or "Not saved yet", 1, 1, 1)
        local T = R.Talents
        if r and r.talents and T:Available() then
            GameTooltip:AddLine("Talents: " .. T:Summary(r.talents), 1, 0.82, 0)
            for _, n in ipairs(T:Names(r.talents)) do GameTooltip:AddLine("  " .. n, 0.8, 0.8, 0.8) end
        end
        GameTooltip:Show()
    end)
    s.button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    s.status = Label("", x, ry - 82, "GameFontDisableSmall")
    s.info = Label("", x, ry - 100, "GameFontHighlightSmall")
    s.info:SetWidth(COL - 8)
    s.info:SetSpacing(3)
    s.gearLabel = Label("Gear set:", x, ry - 152, "GameFontNormalSmall")
    s.gear = GearDropdown(i, x, ry - 164)
    slots[i] = s
end

local saveRoleButton = Button("Save", 220, 16, ry - 204, function()
    ns.Roles:Save()
    panel:refresh()
end)
local reloadRoleButton = Button("Reload", 150, 242, ry - 204, function()
    ns.Roles:Reload()
    panel:refresh()
end)

local auto = CreateFrame("CheckButton", "ZBarRoleAutoSave", panel, "InterfaceOptionsCheckButtonTemplate")
auto:SetPoint("LEFT", reloadRoleButton, "RIGHT", 12, 0)
_G[auto:GetName() .. "Text"]:SetText("Auto-save when switching")
auto:SetScript("OnClick", function(self)
    if ns.db then ns.Roles.DB().roleAutoSave = self:GetChecked() and true or false end
end)

-- a class with four trees: which three are on the minimap button's clicks
local clickLabel = Label("Minimap clicks:", 16, ry - 242, "GameFontNormalSmall")
local clickDrops = {}
local CLICK_NAMES = { "Left", "Middle", "Right" }
for i = 1, 3 do
    local x = 110 + (i - 1) * 165
    local lbl = Label(CLICK_NAMES[i], x, ry - 242, "GameFontHighlightSmall")
    local dd = CreateFrame("Frame", "ZBarClickTree" .. i, panel, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", x + 22, ry - 234)
    UIDropDownMenu_SetWidth(dd, 100)
    UIDropDownMenu_Initialize(dd, function()
        if not ns.db then return end
        local cur = ns.Roles:ClickTrees()[i]
        for _, e in ipairs(ns.Roles:List()) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = e.name
            info.checked = cur and cur.key == e.key
            info.func = function()
                ns.Roles:SetClickTree(i, e.key)
                panel:refresh()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    clickDrops[i] = { dd = dd, label = lbl }
end

local mmHide = CreateFrame("CheckButton", "ZBarHideMinimap", panel, "InterfaceOptionsCheckButtonTemplate")
mmHide:SetPoint("TOPLEFT", 16, ry - 266)
_G[mmHide:GetName() .. "Text"]:SetText("Hide minimap button")
mmHide:SetScript("OnClick", function(self)
    if ns.db then ns.Minimap:SetHidden(self:GetChecked()) end
end)

-- custom (server specific) bars: hide only
Label("Custom Bars (hide only - moving and scaling stay in their own menu)", 16, ry - 300, "GameFontNormalSmall")
-- up to 4 bars, two per row; filled in by refresh with whatever is found
local customChecks = {}
for i = 1, 4 do
    local cb = CreateFrame("CheckButton", "ZBarCustomHide" .. i, panel, "InterfaceOptionsCheckButtonTemplate")
    cb:SetPoint("TOPLEFT", 16 + ((i - 1) % 2) * 300, ry - 314 - math.floor((i - 1) / 2) * 26)
    cb:SetScript("OnClick", function(self)
        if ns.db and self.barName then ns.CustomBars:SetHidden(self.barName, self:GetChecked()) end
    end)
    cb:Hide()
    customChecks[i] = cb
end
local customNone = Label("No custom bars found on this character.", 20, ry - 320, "GameFontDisableSmall")

------------------------------------------------------------------------
function panel:refresh()
    unlockButton:SetText(ns.unlocked and "Lock Bars" or "Unlock Bars")
    if not ns.db then return end

    local R = ns.Roles
    local db = R.DB()
    local coa = R:Mode() == "coa"
    local cur = R:Current()
    local T = R.Talents
    local nowT = coa and T:Current()
    profTitle:SetText(coa and "Talent Trees" or "Dual Spec Profiles")
    profDesc:SetText(coa
        and "Each talent tree keeps its own bars, layout, Ctrl / Shift layers, gear and talents (this character only).\nSwitch here or with the minimap button: left / middle / right click."
        or "No talent trees here: each dual spec keeps its own layout, Ctrl / Shift layers and gear.\nThe game swaps talents and bar contents with the spec itself.")
    -- points still to spend, when there are any
    local free = ""
    if nowT then
        local c, sp = T:Unspent()
        if c and sp and c + sp > 0 then
            local parts = {}
            if c > 0 then parts[#parts + 1] = c .. " class" end
            if sp > 0 then parts[#parts + 1] = sp .. " spec" end
            free = "   |cff8af559" .. table.concat(parts, " / ") .. " to spend|r"
        end
    end
    currentText:SetText("Now: " .. R:Label(cur)
        .. (nowT and ("   |cffaaaaaaTalents: " .. T:Summary(nowT) .. "|r") or "") .. free)
    mmHide:SetChecked(ns.Minimap:IsHidden())
    local list = R:List()
    for i, s in ipairs(slots) do
        local e = list[i]
        s.key = e and e.key
        if e then
            local r = db.profiles[e.key]
            s.button:SetText(e.key == cur and ("> " .. e.label .. " <") or e.label)
            s.button:Show()
            s.status:SetText((r and r.savedAt) and ("Saved " .. r.savedAt:sub(6)) or "Not saved yet")
            s.info:SetText(e.tree and (R:TreeInfo(e.tree) or "") or "")
            UIDropDownMenu_SetText(s.gear, (r and r.gear) or "No gear change")
            s.status:Show() s.info:Show() s.gearLabel:Show() s.gear:Show()
            -- dual spec profiles switch with the game's spec, not here
            if coa then s.button:Enable() else s.button:Disable() end
        else
            s.button:Hide() s.status:Hide() s.info:Hide() s.gearLabel:Hide() s.gear:Hide()
        end
    end
    -- four trees: pick the three on the minimap clicks
    local many = coa and #list > 3
    local clicks = many and R:ClickTrees() or {}
    for i, c in ipairs(clickDrops) do
        if many then
            UIDropDownMenu_SetText(c.dd, clicks[i] and clicks[i].name or "-")
            c.dd:Show() c.label:Show()
        else
            c.dd:Hide() c.label:Hide()
        end
    end
    if many then clickLabel:Show() else clickLabel:Hide() end
    local saved = cur and db.profiles[cur] and db.profiles[cur].layout
    if cur then saveRoleButton:Enable() else saveRoleButton:Disable() end
    if saved then reloadRoleButton:Enable() else reloadRoleButton:Disable() end
    saveRoleButton:SetText("Save " .. R:Label(cur))
    reloadRoleButton:SetText("Reload " .. ((R:Entry(cur) or {}).name or ""))
    auto:SetChecked(db.roleAutoSave)
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

MText("Saved per character and in each talent tree profile. If your key bindings are account-wide "
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
