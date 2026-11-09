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
        hint:SetText("Drag a button's spell or macro to another slot  |  Hold Ctrl / Shift to move that layer instead")
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
    GameTooltip:AddLine("After a talent tree / profile switch only the bar layout goes back, not the bar contents, Ctrl / Shift layers or gear. "
        .. "Switch back to the previous tree to load those.", 1, 0.82, 0, true)
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
    local key = ns.db and ns.Roles:Current()
    title:SetText("ZBar - bars unlocked" .. (key and ("  (" .. ns.Roles:Label(key) .. ")") or ""))
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
    elseif cmd == "tree" or cmd == "role" then
        -- /zbar tree 2   or   /zbar tree infernal
        local arg = ((msg or ""):match("^%s*%S+%s+(.-)%s*$") or ""):lower()
        local list, pick = ns.Roles:List(), nil
        pick = list[tonumber(arg) or 0]
        if not pick then
            for _, e in ipairs(list) do
                if e.name:lower() == arg then pick = e end
            end
        end
        if pick then
            ns.Roles:Switch(pick.key)
        else
            local names = {}
            for i, e in ipairs(list) do names[#names + 1] = i .. " = " .. e.label end
            ns.Print("Usage: /zbar tree 1-3 or name (" .. table.concat(names, ", ") .. ")")
        end
    elseif cmd == "saverole" or cmd == "savetree" then
        ns.Roles:Save()
    elseif cmd == "reloadrole" or cmd == "reloadtree" then
        ns.Roles:Reload()
    elseif cmd == "layers" or cmd == "modifiers" then
        ns.Modifiers:OpenSetup()
    elseif cmd == "talentdebug" then
        ns.Roles.Talents:ToggleDebug()
    elseif cmd == "dragdebug" then
        ns.Modifiers:ToggleDragDebug()
    elseif cmd == "macro" or cmd == "macros" then
        ns.OpenSubPanel(ns.MacroPanel)
    elseif cmd == "options" or cmd == "config" then
        -- called twice: the first call may only open the window on 3.3.5
        InterfaceOptionsFrame_OpenToCategory(ns.OptionsPanel)
        InterfaceOptionsFrame_OpenToCategory(ns.OptionsPanel)
    else
        ns.Print("/zbar - unlock / lock the bars")
        ns.Print("/zbar save - save the layout only (positions, not bar contents)")
        ns.Print("/zbar restore - restore the layout-only save")
        ns.Print("/zbar undo - undo the last move / resize / hide (after a tree switch: layout only, not bar contents / layers)")
        ns.Print("/zbar reset - back to the default Blizzard positions")
        ns.Print("/zbar tree 1-3 | name - switch talent tree (Conquest of Azeroth)")
        ns.Print("/zbar savetree - save layout, bars, layers and talents to the current tree (or dual spec)")
        ns.Print("/zbar reloadtree - load the current tree's saved layout + bars again")
        ns.Print("/zbar options - open the ZBar options")
        ns.Print("/zbar layers - set up the Ctrl / Shift layers")
        ns.Print("/zbar macro - open the macro builder")
    end
end
