-- ZBar minimap button
-- Conquest of Azeroth (talent trees):
--   Left / middle / right click : three talent trees of the class (a class
--                                 with four trees: picked in the options)
--   Alt+right click             : open the ZBar options
-- Classless realm (no talent trees): any click opens the options.
--   Drag                        : move the button around the minimap
-- (no unlock here on purpose: a stray click would fill the screen with move
-- handles; unlocking stays in /zbar and the options)
-- The icon shows the tree in use. It can be hidden in the options.
local _, ns = ...
local MM = {}
ns.Minimap = MM

local NO_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local SPEC_ICON = "Interface\\Icons\\Ability_Marksmanship"
local CLICK_INDEX = { LeftButton = 1, MiddleButton = 2, RightButton = 3 }
local CLICK_NAME = { "Left click", "Middle click", "Right click" }

local button

local function Settings()
    ns.db.minimap = ns.db.minimap or {}
    local s = ns.db.minimap
    if s.angle == nil then s.angle = 200 end
    return s
end

local function UpdatePosition()
    local angle = math.rad(Settings().angle)
    local radius = (Minimap:GetWidth() / 2) + 10
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function OnDragUpdate()
    local mx, my = Minimap:GetCenter()
    local scale = Minimap:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    cx, cy = cx / scale, cy / scale
    Settings().angle = math.deg(math.atan2(cy - my, cx - mx)) % 360
    UpdatePosition()
end

local function ShowTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("ZBar")
    local R = ns.Roles
    local cur = R:Current()
    if R:Mode() == "coa" then
        GameTooltip:AddLine(" ")
        local clicks = R:ClickTrees()
        for i = 1, 3 do
            local e = clicks[i]
            if e then
                local saved = R:Get(e.key)
                GameTooltip:AddDoubleLine("|cffeda55f" .. CLICK_NAME[i] .. ":|r " .. e.label
                    .. (e.key == cur and "  |cff8af559(now)|r" or ""),
                    (saved and saved.layout) and "" or "|cffff6060not saved yet|r", 0.9, 0.9, 0.9)
            end
        end
        if #R:List() > 3 then
            GameTooltip:AddLine("(which trees are on the clicks: ZBar options)", 0.6, 0.6, 0.6)
        end
        GameTooltip:AddLine("|cffeda55fAlt+right click:|r ZBar options", 0.8, 0.8, 0.8)
    else
        GameTooltip:AddLine(R:Label(cur) .. " (profile follows the dual spec)", 1, 1, 1)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cffeda55fClick:|r ZBar options", 0.8, 0.8, 0.8)
    end
    GameTooltip:AddLine("|cffeda55fDrag:|r move this button", 0.8, 0.8, 0.8)
    GameTooltip:Show()
end

function MM:Update()
    if not button or not ns.db then return end
    if Settings().hide then
        button:Hide()
        return
    end
    local R = ns.Roles
    local icon
    if R:Mode() == "coa" then
        local e = R:Entry(R:Current())
        icon = e and R:TreeIcon(e.tree)
    else
        icon = SPEC_ICON
    end
    button.icon:SetTexture(icon or NO_ICON)
    UpdatePosition()
    button:Show()
    if GameTooltip:IsOwned(button) then ShowTooltip(button) end
end

function MM:SetHidden(hide)
    Settings().hide = hide and true or nil
    self:Update()
end

function MM:IsHidden()
    return ns.db and Settings().hide and true or false
end

local function OpenOptions()
    InterfaceOptionsFrame_OpenToCategory(ns.OptionsPanel)
    InterfaceOptionsFrame_OpenToCategory(ns.OptionsPanel)
end

function MM:Create()
    if button then return end
    button = CreateFrame("Button", "ZBarMinimapButton", Minimap)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:SetSize(31, 31)
    button:RegisterForClicks("LeftButtonUp", "MiddleButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local overlay = button:CreateTexture(nil, "OVERLAY")
    overlay:SetSize(53, 53)
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    overlay:SetPoint("TOPLEFT")

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetSize(20, 20)
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetPoint("TOPLEFT", 7, -5)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(17, 17)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    icon:SetPoint("TOPLEFT", 7, -6)
    button.icon = icon

    -- small "Z" so it is not mistaken for another addon's button
    local tag = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tag:SetPoint("BOTTOMRIGHT", -5, 5)
    tag:SetText("Z")

    button:SetScript("OnClick", function(self, mouse)
        local R = ns.Roles
        if R:Mode() ~= "coa" or (mouse == "RightButton" and IsAltKeyDown()) then
            OpenOptions()
            return
        end
        local e = R:ClickTrees()[CLICK_INDEX[mouse] or 0]
        if not e then return end
        if e.key == R:Current() then
            -- a stray click must not throw away unsaved bar changes
            ns.Print("Already on " .. e.label .. ". (Reload in the options loads its saved bars again.)")
        else
            R:Switch(e.key)
        end
    end)
    button:SetScript("OnDragStart", function(self)
        GameTooltip:Hide()
        self:SetScript("OnUpdate", OnDragUpdate)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)
    button:SetScript("OnEnter", ShowTooltip)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    self:Update()
end
