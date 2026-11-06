-- ZBar toolbar: shown in unlock mode; slash command and reset dialog.
local _, ns = ...

local Toolbar = CreateFrame("Frame", "ZBarToolbar", UIParent)
ns.Toolbar = Toolbar
Toolbar:Hide()
Toolbar:SetSize(854, 78)
Toolbar:SetPoint("TOP", UIParent, "TOP", 0, -120)
Toolbar:SetFrameStrata("DIALOG")
Toolbar:SetClampedToScreen(true)
Toolbar:SetMovable(true)
Toolbar:EnableMouse(true)
Toolbar:RegisterForDrag("LeftButton")
Toolbar:SetScript("OnDragStart", Toolbar.StartMoving)
Toolbar:SetScript("OnDragStop", Toolbar.StopMovingOrSizing)
Toolbar:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 24,
    insets = { left = 6, right = 6, top = 6, bottom = 6 },
})

local title = Toolbar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOP", 0, -12)
title:SetText("ZBar - bars unlocked")

local hint = Toolbar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
hint:SetPoint("BOTTOM", 0, 12)

local function MakeButton(text, x, onClick)
    local b = CreateFrame("Button", nil, Toolbar, "UIPanelButtonTemplate")
    b:SetSize(136, 22)
    b:SetPoint("TOPLEFT", x, -30)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

local modeButton

local function UpdateTexts()
    if ns.mode == "modifiers" then
        modeButton:SetText("Mode: Modifiers")
        hint:SetText("Hold Ctrl or Shift to see that layer, drop a spell / macro / item on a button  |  Right-click: pet actions / clear")
    elseif ns.mode == "content" then
        modeButton:SetText("Mode: Content")
        hint:SetText("Drag a button's spell or macro to another slot, like Shift+Drag.")
    else
        modeButton:SetText("Mode: Buttons")
        hint:SetText("Drag: button  |  Alt+Drag: bar  |  Right-click: hide  |  Wheel on header / blue box: resize")
    end
end

modeButton = MakeButton("Mode: Buttons", 14, function()
    local NEXT = { buttons = "content", content = "modifiers", modifiers = "buttons" }
    ns.mode = NEXT[ns.mode] or "buttons"
    UpdateTexts()
    ns.Mover:Refresh()
end)

MakeButton("Save Layout Only", 154, function() ns.Layout:Save() end)
MakeButton("Restore Layout Only", 294, function() ns.Layout:Restore() end)
MakeButton("Factory Reset", 434, function() StaticPopup_Show("ZBAR_FACTORY_RESET") end)
local undoButton = MakeButton("Undo", 574, function() ns.Layout:Undo() end)
undoButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText("Undo")
    GameTooltip:AddLine("Undo the last move, resize or hide (this session only).", 1, 1, 1, true)
    GameTooltip:AddLine("After a role switch only the bar layout goes back, not the bar contents or gear. "
        .. "Switch back to the previous role to load those.", 1, 0.82, 0, true)
    GameTooltip:Show()
end)
undoButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
MakeButton("Lock", 714, function() ns.Mover:Lock() end)

function Toolbar:UpdateUndo()
    local n = ns.Layout:UndoCount()
    undoButton:SetText(n > 0 and ("Undo (" .. n .. ")") or "Undo")
    if n > 0 then undoButton:Enable() else undoButton:Disable() end
end

function Toolbar:Open()
    local role = ns.db and ns.db.currentRole
    title:SetText("ZBar - bars unlocked" .. (role and ("  (Role: " .. role .. ")") or ""))
    UpdateTexts()
    self:UpdateUndo()
    self:Show()
end

StaticPopupDialogs["ZBAR_FACTORY_RESET"] = {
    text = "ZBar: put every action bar back to its default Blizzard position?\nThe UI will reload. Your saved layout is kept.",
    button1 = YES,
    button2 = NO,
    OnAccept = function() ns.Layout:FactoryReset() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

SLASH_ZBAR1 = "/zbar"
SlashCmdList.ZBAR = function(msg)
    local cmd = (msg or ""):lower():match("^%s*(%S*)")
    if cmd == "" or cmd == "unlock" or cmd == "lock" then
        ns.Mover:Toggle()
    elseif cmd == "save" then
        ns.Layout:Save()
    elseif cmd == "restore" then
        ns.Layout:Restore()
    elseif cmd == "undo" then
        ns.Layout:Undo()
    elseif cmd == "reset" then
        StaticPopup_Show("ZBAR_FACTORY_RESET")
    elseif cmd == "role" then
        ns.Roles:Request((msg or ""):match("^%s*%S+%s+(%S+)"))
    elseif cmd == "saverole" then
        ns.Roles:Save()
    elseif cmd == "reloadrole" then
        ns.Roles:Reload()
    elseif cmd == "layers" or cmd == "modifiers" then
        ns.Modifiers:OpenSetup()
    elseif cmd == "options" or cmd == "config" then
        -- called twice: the first call may only open the window on 3.3.5
        InterfaceOptionsFrame_OpenToCategory(ns.OptionsPanel)
        InterfaceOptionsFrame_OpenToCategory(ns.OptionsPanel)
    else
        ns.Print("/zbar - unlock / lock the bars")
        ns.Print("/zbar save - save the layout only (positions, not bar contents)")
        ns.Print("/zbar restore - restore the layout-only save")
        ns.Print("/zbar undo - undo the last move / resize / hide (after a role switch: layout only, not bar contents)")
        ns.Print("/zbar reset - back to the default Blizzard positions")
        ns.Print("/zbar role tank | dps | healer - switch role")
        ns.Print("/zbar saverole - save layout + bars to the current role")
        ns.Print("/zbar reloadrole - load the current role's saved layout + bars again")
        ns.Print("/zbar options - open the ZBar options")
        ns.Print("/zbar layers - set up the Ctrl / Shift layers")
    end
end
