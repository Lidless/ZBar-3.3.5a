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

local unlockButton = Row("Unlock Bars", "Show the move handles. Lock again from the toolbar or with /zbar.", function()
    if ns.unlocked then
        ns.Mover:Lock()
    else
        if InCombatLockdown() then ns.Print("Cannot unlock in combat.") return end
        CloseMenus()
        ns.Mover:Unlock()
    end
    panel:refresh()
end)
Row("Save Layout Only", "Positions only, not the bar contents. Not tied to any role.", function()
    ns.Layout:Save()
    panel:refresh()
end)
Row("Restore Layout Only", "Back to the last layout-only save (positions only).", function() ns.Layout:Restore() end)
local undoButton = Row("Undo", "Undo the last move, resize or hide (this session).", function()
    ns.Layout:Undo()
    panel:refresh()
end)
-- the second line sits in the gap below the row
local undoNote = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
undoNote:SetPoint("TOPLEFT", undoButton, "BOTTOMRIGHT", 10, -1)
undoNote:SetText("After a role switch: layout only - bar contents and gear stay. Switch roles back for those.")
y = y - 12 -- room for the note line
Row("Factory Reset", "Put every bar back to its Blizzard position (reloads the UI).", function()
    StaticPopup_Show("ZBAR_FACTORY_RESET")
end)

local savedText = Label("", 16, y - 2, "GameFontDisableSmall")

------------------------------------------------------------------------
-- Role section
------------------------------------------------------------------------
local ry = y - 30
Label("Role Profiles", 16, ry, "GameFontNormal")
Label("Each role keeps its own bar positions, bar contents and gear set (this character only).", 16, ry - 18)
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

-- dual spec: role per talent group
Label("Dual spec: switch role automatically when changing spec", 16, ry - 182, "GameFontNormalSmall")
local specDrops = {}
for spec = 1, 2 do
    local x = 16 + (spec - 1) * 170
    Label("Spec " .. spec .. ":", x, ry - 202, "GameFontHighlightSmall")
    local dd = CreateFrame("Frame", "ZBarSpecDrop" .. spec, panel, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", x + 30, ry - 194)
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
mmHide:SetPoint("TOPLEFT", 360, ry - 196)
_G[mmHide:GetName() .. "Text"]:SetText("Hide minimap button")
mmHide:SetScript("OnClick", function(self)
    if ns.db then ns.Minimap:SetHidden(self:GetChecked()) end
end)
local tpNote = Label("", 360, ry - 222, "GameFontDisableSmall")

-- custom (server specific) bars: hide only
Label("Custom Bars (hide only - moving and scaling stay in their own menu)", 16, ry - 242, "GameFontNormalSmall")
-- up to 4 bars, two per row; filled in by refresh with whatever is found
local customChecks = {}
for i = 1, 4 do
    local cb = CreateFrame("CheckButton", "ZBarCustomHide" .. i, panel, "InterfaceOptionsCheckButtonTemplate")
    cb:SetPoint("TOPLEFT", 16 + ((i - 1) % 2) * 300, ry - 254 - math.floor((i - 1) / 2) * 24)
    cb:SetScript("OnClick", function(self)
        if ns.db and self.barName then ns.CustomBars:SetHidden(self.barName, self:GetChecked()) end
    end)
    cb:Hide()
    customChecks[i] = cb
end
local customNone = Label("No custom bars found on this character.", 20, ry - 260, "GameFontDisableSmall")

------------------------------------------------------------------------
function panel:refresh()
    unlockButton:SetText(ns.unlocked and "Lock Bars" or "Unlock Bars")
    local n = ns.Layout:UndoCount()
    undoButton:SetText(n > 0 and ("Undo (" .. n .. ")") or "Undo")
    if n > 0 then undoButton:Enable() else undoButton:Disable() end
    if ns.db and ns.db.savedAt then
        savedText:SetText("Last layout-only save: " .. ns.db.savedAt)
    else
        savedText:SetText("No layout-only save yet.")
    end
    if not ns.db then return end

    local db = ns.Roles.DB()
    local cur = db.currentRole
    local linked = ns.Roles:TPLinked()
    currentText:SetText("Current role: " .. (cur or "none")
        .. (linked and "   |cff8af559(follows Threat Plates)|r" or ""))
    mmHide:SetChecked(ns.Minimap:IsHidden())
    tpNote:SetText(linked and "Threat Plates found: its role button switches ZBar too." or "")
    for _, role in ipairs(ns.Roles.list) do
        local r = db.roles[role]
        roleButtons[role]:SetText(role == cur and ("> " .. role .. " <") or role)
        roleStatus[role]:SetText((r and r.savedAt) and ("Saved " .. r.savedAt) or "Not saved yet")
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
