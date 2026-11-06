-- ZBar minimap button
--   Left click       : DPS role
--   Middle click     : Tank role
--   Right click      : Healer role
--   Alt+right click  : open the ZBar options
--   Shift+left click : unlock / lock the bars
--   Drag             : move the button around the minimap
-- (one button per role: no stepping through a role you don't want, which
-- matters when roles also change talents)
-- The icon shows the current role. It can be hidden in the options
-- (handy when Threat Plates already has its own role button).
local _, ns = ...
local MM = {}
ns.Minimap = MM

local ROLE_ICON = {
    Tank = "Interface\\Icons\\Ability_Defend",
    DPS = "Interface\\Icons\\Ability_DualWield",
    Healer = "Interface\\Icons\\Spell_Holy_FlashHeal",
}
local NO_ROLE_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local CLICK_ROLE = { LeftButton = "DPS", MiddleButton = "Tank", RightButton = "Healer" }

local button

local function Settings()
    ns.db.minimap = ns.db.minimap or {}
    local s = ns.db.minimap
    if s.angle == nil then s.angle = 200 end -- next to the Threat Plates button (225)
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
    local role = ns.Roles:Current()
    local r = role and ns.Roles:Get(role)
    if role then
        GameTooltip:AddLine("Role: " .. role .. ((r and r.actions) and "" or " |cffFF3333(bars not saved yet)|r"), 1, 1, 1)
    else
        GameTooltip:AddLine("Role: none chosen yet", 1, 1, 1)
    end
    if ns.Roles:TPLinked() then
        GameTooltip:AddLine("Linked to Threat Plates", 0.54, 0.96, 0.35)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("|cffeda55fLeft click:|r DPS", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("|cffeda55fMiddle click:|r Tank", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("|cffeda55fRight click:|r Healer", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("|cffeda55fAlt+right click:|r ZBar options", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("|cffeda55fShift+left click:|r unlock / lock the bars", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("|cffeda55fDrag:|r move this button", 0.8, 0.8, 0.8)
    GameTooltip:Show()
end

function MM:Update()
    if not button or not ns.db then return end
    if Settings().hide then
        button:Hide()
        return
    end
    local role = ns.Roles:Current()
    button.icon:SetTexture(ROLE_ICON[role] or NO_ROLE_ICON)
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

    -- small "Z" so it is not mistaken for the Threat Plates button
    local tag = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tag:SetPoint("BOTTOMRIGHT", -5, 5)
    tag:SetText("Z")

    button:SetScript("OnClick", function(self, mouse)
        if mouse == "RightButton" and IsAltKeyDown() then
            InterfaceOptionsFrame_OpenToCategory(ns.OptionsPanel)
            InterfaceOptionsFrame_OpenToCategory(ns.OptionsPanel)
        elseif mouse == "LeftButton" and IsShiftKeyDown() then
            ns.Mover:Toggle()
        else
            local role = CLICK_ROLE[mouse]
            if not role then return end
            if role == ns.Roles:Current() then
                ns.Print("Already in the " .. role .. " role. (Reload Role in the options loads it again.)")
            else
                ns.Roles:Request(role)
            end
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
