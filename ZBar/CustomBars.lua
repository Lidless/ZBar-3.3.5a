-- ZBar custom bars: server / client specific frames that ZBar can only hide
-- (they keep their own move and scale menu). Example: the Conquest of Azeroth
-- class resource bars (CoAResourceSegmentBar, CoAResourceOrb, ...).
--
-- Every matching frame that does not belong to another matching frame is a
-- separate item and can be hidden on its own. A frame belongs to another one
-- if it is its child or is anchored to it (e.g. CoAResourceView3 belongs to
-- CoAResourceSegmentBar) - those are hidden together.
--
-- Hidden state lives in the layout (layout.custom[frameName] = true), so it
-- is part of undo, the layout-only save and the role profiles.
--
-- Three ways to hide one:
--   * "Hide (ZBar)" line added to the bar's own right-click menu
--   * unlock mode: blue box on the bar, right-click = hide / show
--   * Interface > AddOns > ZBar: checkbox
local _, ns = ...
local CB = {}
ns.CustomBars = CB

local GROUPS = {
    { prefix = "CoAResource", label = "Class Resource" },
}
local PRETTY = { SegmentBar = "Segment Bar", Orb = "Orb" }
local OLD_KEYS = { CoAResource = true } -- 0.9.0 hid all of them with one key

local moved = {}   -- frame -> { parent = original parent, alpha = original alpha }
local items = {}   -- { name, label, frame, members = { frames } }, sorted by name
local itemOf = {}  -- frame (item frame or member) -> item
local scanned = false

local function L() return ns.db and ns.db.layout end

local function IsFrame(obj)
    return type(obj) == "table" and type(rawget(obj, 0)) == "userdata"
        and type(obj.IsObjectType) == "function" and obj:IsObjectType("Frame")
end

local function GroupOf(name)
    for _, g in ipairs(GROUPS) do
        if name:sub(1, #g.prefix) == g.prefix then return g end
    end
end

local function Pretty(name)
    local g = GroupOf(name)
    if not g then return name end
    local rest = name:sub(#g.prefix + 1)
    rest = PRETTY[rest] or rest:gsub("(%l)(%u)", "%1 %2"):gsub("(%a)(%d)", "%1 %2")
    return g.label .. ": " .. rest
end

local function RealParent(f)
    return (moved[f] and moved[f].parent) or f:GetParent()
end

------------------------------------------------------------------------
-- Finding the bars
------------------------------------------------------------------------
function CB:Scan()
    local set = {}
    for name, obj in pairs(_G) do
        if type(name) == "string" and GroupOf(name) and IsFrame(obj) then set[obj] = name end
    end
    for f in pairs(moved) do set[f] = f:GetName() end

    -- the matching frame f belongs to: a matching parent, or a matching anchor
    local function OwnerOf(f)
        local p = RealParent(f)
        while p do
            if set[p] then return p end
            p = RealParent(p)
        end
        for i = 1, (f:GetNumPoints() or 0) do
            local _, rel = f:GetPoint(i)
            if rel and rel ~= f and set[rel] then return rel end
        end
    end
    local function Root(f, depth)
        local o = OwnerOf(f)
        if not o or depth > 8 then return f end
        return Root(o, depth + 1)
    end

    local byRoot = {}
    for f in pairs(set) do
        local r = Root(f, 0)
        byRoot[r] = byRoot[r] or {}
        if r ~= f then table.insert(byRoot[r], f) end
    end

    items, itemOf = {}, {}
    for r, members in pairs(byRoot) do
        local it = { name = set[r], label = Pretty(set[r]), frame = r, members = members }
        table.insert(items, it)
        itemOf[r] = it
        for _, m in ipairs(members) do itemOf[m] = it end
    end
    table.sort(items, function(a, b) return a.name < b.name end)
    scanned = true
    return items
end

function CB:Items(rescan)
    if rescan or not scanned or #items == 0 then self:Scan() end
    return items
end

-- frames to move under the hidden parent: the item itself, plus members that
-- are only anchored to it (members inside it disappear with it anyway)
local function FramesOf(it)
    local list = { it.frame }
    for _, m in ipairs(it.members) do
        local p, inside = RealParent(m), false
        while p do
            if p == it.frame then inside = true break end
            p = RealParent(p)
        end
        if not inside then table.insert(list, m) end
    end
    return list
end

------------------------------------------------------------------------
-- Hiding
------------------------------------------------------------------------
function CB:IsHidden(name)
    local layout = L()
    return layout and layout.custom and layout.custom[name] and true or false
end

local function SetState(f, hide)
    if InCombatLockdown() and f:IsProtected() then return end
    local m = moved[f]
    if hide then
        if not m then
            m = { parent = f:GetParent(), alpha = f:GetAlpha() }
            moved[f] = m
        end
        if ns.unlocked then
            -- unlock mode: back in place, see-through, so it can be clicked
            if f:GetParent() ~= m.parent then f:SetParent(m.parent) end
            f:SetAlpha(0.4)
        else
            if f:GetParent() ~= ns.Groups.hiddenParent then f:SetParent(ns.Groups.hiddenParent) end
            f:SetAlpha(m.alpha or 1)
        end
    elseif m then
        f:SetParent(m.parent)
        f:SetAlpha(m.alpha or 1)
        moved[f] = nil
    end
end

function CB:Apply(layout, rescan)
    layout = layout or L()
    if not layout then return end
    local list = self:Items(rescan)
    local custom = layout.custom
    -- 0.9.0 saved one key for all of them: turn it into one key per bar
    if custom and #list > 0 then
        for old in pairs(OLD_KEYS) do
            if custom[old] then
                custom[old] = nil
                for _, it in ipairs(list) do
                    if it.name:sub(1, #old) == old then custom[it.name] = true end
                end
            end
        end
    end
    for _, it in ipairs(list) do
        local hide = custom and custom[it.name]
        for _, f in ipairs(FramesOf(it)) do SetState(f, hide) end
    end
end

function CB:SetHidden(name, hide)
    if InCombatLockdown() then ns.Print("Cannot change this in combat.") return end
    local layout = L()
    if not layout then return end
    ns.Layout:PushUndo()
    layout.custom = layout.custom or {}
    layout.custom[name] = hide and true or nil
    ns.Layout:Apply()
    ns.Print(Pretty(name) .. (hide and " hidden." or " shown."))
    if ns.OptionsPanel and ns.OptionsPanel:IsShown() then ns.OptionsPanel:refresh() end
end

function CB:Toggle(name)
    self:SetHidden(name, not self:IsHidden(name))
end

-- for the options panel: bars found now, plus hidden ones that are not
-- around at the moment (so they can still be shown again)
function CB:OptionList()
    local list, seen = {}, {}
    for _, it in ipairs(self:Items(true)) do
        table.insert(list, { name = it.name, label = it.label, found = true })
        seen[it.name] = true
    end
    local layout = L()
    for name in pairs((layout and layout.custom) or {}) do
        if not seen[name] and not OLD_KEYS[name] then
            table.insert(list, { name = name, label = Pretty(name), found = false })
        end
    end
    return list
end

------------------------------------------------------------------------
-- 1) "Hide (ZBar)" in the bar's own right-click menu
------------------------------------------------------------------------
local function ItemUnderMouse()
    if not scanned then CB:Scan() end
    local f = GetMouseFocus()
    while f do
        if itemOf[f] then return itemOf[f] end
        f = f.GetParent and f:GetParent()
    end
end

hooksecurefunc("ToggleDropDownMenu", function(level)
    if (level or 1) ~= 1 or not DropDownList1 or not DropDownList1:IsShown() then return end
    if not ns.db then return end
    local it = ItemUnderMouse()
    if not it then return end
    -- own table on purpose: UIDropDownMenu_CreateInfo() hands out one shared
    -- table on 3.3.5, and wiping it could disturb the menu's own entries
    local info = {
        text = "Hide (ZBar)",
        notCheckable = true,
        checked = false,
        func = function()
            CloseDropDownMenus()
            CB:SetHidden(it.name, true)
        end,
    }
    UIDropDownMenu_AddButton(info, 1)
end)

------------------------------------------------------------------------
-- 2) unlock mode: blue box per bar, right-click to hide / show
------------------------------------------------------------------------
local overlays = {}

local function CreateOverlay(name)
    local ov = CreateFrame("Frame", nil, UIParent)
    ov:SetFrameStrata("DIALOG")
    ov:EnableMouse(true)
    ov:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                     edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
                     insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    ov:SetBackdropBorderColor(0.3, 0.7, 1, 0.9)
    ov.text = ov:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ov.text:SetPoint("BOTTOM", ov, "TOP", 0, 1)
    ov.text:SetText(Pretty(name))
    ov:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" and ns.mode == "buttons" then CB:Toggle(name) end
    end)
    ov:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(Pretty(name))
        GameTooltip:AddLine("Right-click: hide / show", 1, 1, 1)
        GameTooltip:AddLine("Moving and scaling stay in the bar's own right-click menu.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    ov:SetScript("OnLeave", function() GameTooltip:Hide() end)
    overlays[name] = ov
    return ov
end

function CB:Refresh()
    local shown = {}
    if ns.unlocked and ns.mode == "buttons" then
        for _, it in ipairs(self:Items(true)) do
            local f = it.frame
            if f:IsVisible() then
                local ov = overlays[it.name] or CreateOverlay(it.name)
                ov:ClearAllPoints()
                ov:SetPoint("TOPLEFT", f, "TOPLEFT", -3, 3)
                ov:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 3, -3)
                if self:IsHidden(it.name) then
                    ov:SetBackdropColor(0.8, 0.1, 0.1, 0.45)
                else
                    ov:SetBackdropColor(0.1, 0.4, 0.9, 0.25)
                end
                ov:Show()
                shown[it.name] = true
            end
        end
    end
    for name, ov in pairs(overlays) do
        if not shown[name] then ov:Hide() end
    end
end

------------------------------------------------------------------------
-- These frames may be created a bit after login: check again a few times
------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function()
    for _, delay in ipairs({ 2, 5, 10 }) do
        ns.After(delay, function()
            if ns.ready then ns.RunOOC("custombars", function() CB:Apply(nil, true) end) end
        end)
    end
end)
