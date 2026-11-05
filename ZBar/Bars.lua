-- ZBar bars: registry of the default Blizzard action buttons.
local _, ns = ...
local Bars = {}
ns.Bars = Bars

Bars.list = {
    { key = "MainBar",     label = "Main Bar",     prefix = "ActionButton",              frame = "MainMenuBar" },
    { key = "BottomLeft",  label = "Bottom Left",  prefix = "MultiBarBottomLeftButton",  frame = "MultiBarBottomLeft" },
    { key = "BottomRight", label = "Bottom Right", prefix = "MultiBarBottomRightButton", frame = "MultiBarBottomRight" },
    { key = "Right",       label = "Right",        prefix = "MultiBarRightButton",       frame = "MultiBarRight" },
    { key = "Right2",      label = "Right 2",      prefix = "MultiBarLeftButton",        frame = "MultiBarLeft" },
}

Bars.info  = {} -- button name -> { name, btn, bar, index, label, managed, prepared }
Bars.order = {}

-- attributes a Blizzard button may read from its parent ("useparent-<attr>")
local PARENT_ATTRS = { "unit", "checkselfcast", "checkfocuscast", "actionbar" }

function Bars:Init()
    wipe(self.info)
    wipe(self.order)
    for _, bar in ipairs(self.list) do
        for i = 1, 12 do
            local name = bar.prefix .. i
            local btn = _G[name]
            if btn then
                self.info[name] = {
                    name = name, btn = btn, bar = bar, index = i,
                    label = bar.label .. " " .. i,
                }
                table.insert(self.order, name)
            end
        end
    end
end

function Bars:IsBarEnabled(bar)
    if bar.key == "MainBar" then return true end
    local f = _G[bar.frame]
    return f and f:IsShown() and true or false
end

-- rect in UIParent coordinates: left, bottom, width, height, scale
function Bars:GetAbsRect(frame)
    local l, b = frame:GetLeft(), frame:GetBottom()
    if not l or not b then return nil end
    local s = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return l * s, b * s, frame:GetWidth() * s, frame:GetHeight() * s, s
end

local function GetParentAttr(parent, attr)
    if not parent then return nil end
    if SecureButton_GetAttribute then return SecureButton_GetAttribute(parent, attr) end
    return parent:GetAttribute(attr)
end

-- Make the button independent of its Blizzard parent before reparenting it,
-- so it keeps the same action page and unit settings in a ZBar group.
function Bars:Prepare(info)
    if info.prepared then return end
    local btn = info.btn
    local parent = btn:GetParent()

    if info.bar.key ~= "MainBar" then
        -- multi bars get their page from the parent bar frame: pin it on the button
        local slot = btn.action
        if not slot and ActionButton_CalculateAction then
            slot = ActionButton_CalculateAction(btn, "LeftButton")
        end
        if slot and slot > 0 then
            btn:SetAttribute("actionpage", math.floor((slot - 1) / 12) + 1)
            btn:SetAttribute("useparent-actionpage", nil)
        end
    end

    for _, attr in ipairs(PARENT_ATTRS) do
        if btn:GetAttribute("useparent-" .. attr) then
            btn:SetAttribute(attr, GetParentAttr(parent, attr))
            btn:SetAttribute("useparent-" .. attr, nil)
        end
    end

    info.origParent = parent
    info.prepared = true
end

-- The main bar art (MainMenuBarTexture0/1) draws the 12 empty slot frames.
-- Hide it as soon as any main bar button is hidden or moved off its default spot.
-- Default spot: BOTTOMLEFT of MainMenuBar + (8 + (i-1)*42, 4), as in the Blizzard XML.
local ART = { "MainMenuBarTexture0", "MainMenuBarTexture1" }

function Bars:SyncMainArt(layout)
    local mx, my, _, _, ms = self:GetAbsRect(MainMenuBar)
    local moved = not mx
    if not moved then
        for i = 1, 12 do
            local name = "ActionButton" .. i
            local b = layout.buttons[name]
            if not b or not layout.groups[b.g] or b.hidden then
                moved = true
                break
            end
            local x, y = ns.Layout:AbsRect(name, layout)
            local ex, ey = mx + (8 + (i - 1) * 42) * ms, my + 4 * ms
            if math.abs(x - ex) > 4 or math.abs(y - ey) > 4 then
                moved = true
                break
            end
        end
    end
    for _, n in ipairs(ART) do
        local t = _G[n]
        if t then t:SetAlpha(moved and 0 or 1) end
    end
end

-- Stance / form pages (BonusActionButton1-12) follow the main bar buttons slot by slot.
function Bars:SyncBonus(layout)
    local bonusFrame = BonusActionBarFrame
    if not bonusFrame then return end
    bonusFrame:SetFrameLevel(ns.BASE_LEVEL + 20)

    local any = false
    for i = 1, 12 do
        local mainName = "ActionButton" .. i
        local main, bonus = _G[mainName], _G["BonusActionButton" .. i]
        local b = layout.buttons[mainName]
        local info = self.info[mainName]
        if main and bonus and b and info and info.managed and layout.groups[b.g] then
            any = true
            local g = layout.groups[b.g]
            local hide = b.hidden and not ns.unlocked
            bonus:ClearAllPoints()
            bonus:SetScale(g.scale * UIParent:GetEffectiveScale() / bonusFrame:GetEffectiveScale())
            bonus:SetPoint("CENTER", main, "CENTER", 0, 0)
            bonus:SetFrameLevel(bonusFrame:GetFrameLevel() + 2)
            bonus:SetAlpha(hide and 0 or 1)
            bonus:EnableMouse(not hide)
        end
    end

    -- the stance bar art would otherwise slide up over the old main bar spot
    if any then
        for _, n in ipairs({ "BonusActionBarTexture0", "BonusActionBarTexture1" }) do
            local t = _G[n]
            if t then t:SetAlpha(0) end
        end
    end
end
