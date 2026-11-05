-- ZBar mover: unlock mode, overlays, dragging, hiding and resizing.
local _, ns = ...
local Mover = {}
ns.Mover = Mover

local overlays = {}
local dragging -- id of the group being dragged

local function L() return ns.db.layout end

-- Ends a drag when the mouse button is released, wherever the cursor is.
-- (The frame that started the drag may not get OnDragStop/OnMouseUp.)
local dropWatcher = CreateFrame("Frame")
dropWatcher:Hide()
dropWatcher:SetScript("OnUpdate", function(self)
    if not IsMouseButtonDown("LeftButton") then
        self:Hide()
        Mover:StopGroupDrag()
        ns.Blocks:StopDrag()
    end
end)

function Mover:WatchDrop()
    dropWatcher:Show()
end

local function GetSlot(btn)
    if btn.action then return btn.action end
    if ActionButton_CalculateAction then return ActionButton_CalculateAction(btn, "LeftButton") end
end

------------------------------------------------------------------------
-- Group dragging
------------------------------------------------------------------------
-- backup: layout copy from before the drag (and before any detach), used to cancel a drop
function Mover:StartGroupDrag(id, backup)
    local f = ns.Groups.frames[id]
    if not f or InCombatLockdown() then return end
    dragging = id
    self.backup = backup or ns.DeepCopy(L())
    ns.Layout:PushUndo(self.backup)
    f:StartMoving()
    dropWatcher:Show()
end

function Mover:StopGroupDrag()
    local id = dragging
    if not id then return end
    dragging = nil
    dropWatcher:Hide()
    local f = ns.Groups.frames[id]
    local g = L().groups[id]
    if not f or not g or InCombatLockdown() then return end

    f:StopMovingOrSizing()
    f:SetUserPlaced(false)
    local s = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
    g.x = ns.Round(f:GetLeft() * s)
    g.y = ns.Round(f:GetBottom() * s)

    local backup = self.backup
    self.backup = nil
    if ns.Layout:TrySnap(id) == "blocked" and backup then
        ns.db.layout = backup
        ns.Layout:DropUndo()
        ns.Print("No free spot next to that button - moved back.")
        PlaySound("igQuestFailed")
    end
    ns.Layout:Apply()
end

function Mover:ScaleGroup(id, delta)
    if InCombatLockdown() then return end
    local g = L().groups[id]
    if not g then return end
    ns.Layout:PushUndo(nil, "groupscale" .. id)
    g.scale = math.max(0.5, math.min(2, ns.Round(g.scale + delta * 0.05)))
    ns.Layout:Apply()
end

------------------------------------------------------------------------
-- Button overlays
------------------------------------------------------------------------
local function Overlay_OnEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    if ns.mode == "content" then
        local slot = GetSlot(self.btn)
        if slot and HasAction(slot) then
            GameTooltip:SetAction(slot)
        else
            GameTooltip:SetText("Empty slot")
        end
        GameTooltip:AddLine("Drag: pick up  |  Drop on it: place", 1, 1, 1)
    else
        GameTooltip:SetText(self.info.label)
        GameTooltip:AddLine("Drag: move this button", 1, 1, 1)
        GameTooltip:AddLine("Alt+Drag: move the whole bar", 1, 1, 1)
        GameTooltip:AddLine("Right-click: hide / show", 1, 1, 1)
    end
    GameTooltip:Show()
end

local function Overlay_OnLeave()
    GameTooltip:Hide()
end

local function Overlay_OnDragStart(self)
    if InCombatLockdown() then return end
    if ns.mode == "content" then
        local slot = GetSlot(self.btn)
        if slot then PickupAction(slot) end
        return
    end

    local layout = L()
    local b = layout.buttons[self.name]
    if not b then return end

    local names, label
    if IsAltKeyDown() then
        local bar = self.info.bar
        names, label = {}, bar.label
        for n, o in pairs(layout.buttons) do
            local info = ns.Bars.info[n]
            if o.g == b.g and info and info.bar == bar then table.insert(names, n) end
        end
    else
        names = { self.name }
    end

    local backup = ns.DeepCopy(layout)
    local id = ns.Layout:Detach(names, label)
    ns.Layout:DoApply()
    Mover:StartGroupDrag(id, backup)
end

local function Overlay_OnDragStop()
    Mover:StopGroupDrag()
end

local function Overlay_OnReceiveDrag(self)
    if ns.mode ~= "content" or InCombatLockdown() then return end
    local slot = GetSlot(self.btn)
    if slot and GetCursorInfo() then PlaceAction(slot) end
end

local function Overlay_OnMouseUp(self, button)
    if InCombatLockdown() then return end
    if ns.mode == "content" then
        if button == "LeftButton" then Overlay_OnReceiveDrag(self) end
        return
    end
    if button == "RightButton" then
        local b = L().buttons[self.name]
        if b then
            ns.Layout:PushUndo()
            b.hidden = (not b.hidden) or nil
            ns.Layout:Apply()
        end
    end
end

local function CreateOverlay(info)
    local ov = CreateFrame("Frame", nil, UIParent)
    ov:SetFrameStrata("DIALOG")
    ov:EnableMouse(true)
    ov:RegisterForDrag("LeftButton")
    ov.info, ov.btn, ov.name = info, info.btn, info.name

    ov.bg = ov:CreateTexture(nil, "BACKGROUND")
    ov.bg:SetAllPoints()

    ov.text = ov:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ov.text:SetPoint("CENTER")
    ov.text:SetText(info.index)

    ov:SetScript("OnEnter", Overlay_OnEnter)
    ov:SetScript("OnLeave", Overlay_OnLeave)
    ov:SetScript("OnDragStart", Overlay_OnDragStart)
    ov:SetScript("OnDragStop", Overlay_OnDragStop)
    ov:SetScript("OnReceiveDrag", Overlay_OnReceiveDrag)
    ov:SetScript("OnMouseUp", Overlay_OnMouseUp)

    overlays[info.name] = ov
    return ov
end

------------------------------------------------------------------------
-- Group handles (border + header)
------------------------------------------------------------------------
local function CreateHandle(f)
    local h = CreateFrame("Frame", nil, f)
    h:SetFrameStrata("DIALOG")
    h:SetPoint("TOPLEFT", f, "TOPLEFT", -3, 3)
    h:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 3, -3)
    h:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12 })
    h:SetBackdropBorderColor(1, 0.82, 0, 0.9)
    h:EnableMouse(false)

    local head = CreateFrame("Frame", nil, h)
    head:SetHeight(16)
    head:SetPoint("BOTTOMLEFT", h, "TOPLEFT", 0, 0)
    head:SetPoint("BOTTOMRIGHT", h, "TOPRIGHT", 0, 0)
    head:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background" })
    head:SetBackdropColor(0, 0, 0, 0.8)
    head:EnableMouse(true)
    head:EnableMouseWheel(true)
    head:RegisterForDrag("LeftButton")

    local text = head:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("LEFT", 3, 0)
    text:SetPoint("RIGHT", -3, 0)
    h.label = text

    head:SetScript("OnDragStart", function()
        if ns.mode == "buttons" then Mover:StartGroupDrag(f.zbarId) end
    end)
    head:SetScript("OnDragStop", function() Mover:StopGroupDrag() end)
    head:SetScript("OnMouseWheel", function(_, delta) Mover:ScaleGroup(f.zbarId, delta) end)
    head:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(h.label:GetText() or "Group")
        GameTooltip:AddLine("Drag: move the whole group", 1, 1, 1)
        GameTooltip:AddLine("Mouse wheel: resize", 1, 1, 1)
        GameTooltip:Show()
    end)
    head:SetScript("OnLeave", Overlay_OnLeave)

    f.zbarHandle = h
    return h
end

------------------------------------------------------------------------
-- Refresh visuals, unlock / lock
------------------------------------------------------------------------
-- Only frames that are really gone get hidden: hiding and re-showing the
-- frame under the cursor would cancel a drag that is just starting.
function Mover:Refresh()
    local layout = L()
    local showOv, showHandle = {}, {}
    if ns.unlocked then
        for name in pairs(layout.buttons) do
            local info = ns.Bars.info[name]
            if info and info.managed then showOv[name] = true end
        end
        for id in pairs(layout.groups) do
            local f = ns.Groups.frames[id]
            if f and f.zbarActive then showHandle[f] = true end
        end
    end
    for name, ov in pairs(overlays) do
        if not showOv[name] then ov:Hide() end
    end
    for _, f in pairs(ns.Groups.frames) do
        if f.zbarHandle and not showHandle[f] then f.zbarHandle:Hide() end
    end
    ns.Blocks:Refresh()
    ns.CustomBars:Refresh()
    if not ns.unlocked then return end

    for name, b in pairs(layout.buttons) do
        local info = ns.Bars.info[name]
        if info and info.managed then
            local ov = overlays[name] or CreateOverlay(info)
            ov:ClearAllPoints()
            ov:SetAllPoints(info.btn)
            if ns.mode == "content" then
                ov.bg:SetTexture(0.2, 0.4, 1, 0.2)
                ov.text:SetText("")
            elseif b.hidden then
                ov.bg:SetTexture(0.8, 0.1, 0.1, 0.45)
                ov.text:SetText(info.index)
            else
                ov.bg:SetTexture(0.1, 0.8, 0.2, 0.25)
                ov.text:SetText(info.index)
            end
            ov:Show()
        end
    end

    for id, g in pairs(layout.groups) do
        local f = ns.Groups.frames[id]
        if f and f.zbarActive then
            local h = f.zbarHandle or CreateHandle(f)
            h.label:SetText(string.format("%s  %d%%", g.label or ("Group " .. id), g.scale * 100 + 0.5))
            h:Show()
        end
    end
end

function Mover:Unlock()
    if not ns.ready then return end
    if InCombatLockdown() then ns.Print("Cannot unlock in combat.") return end
    ns.unlocked = true
    ns.mode = "buttons"
    ns.Layout:Apply()
    ns.Toolbar:Open()
end

function Mover:Lock(fromCombat)
    if dragging then self:StopGroupDrag() end
    ns.Blocks:StopDrag()
    ns.unlocked = false
    ns.mode = "buttons"
    ns.Toolbar:Hide()
    GameTooltip:Hide()
    ns.Layout:Apply()
    self:Refresh()
    if fromCombat then ns.Print("Locked because combat started.") end
end

function Mover:Toggle()
    if ns.unlocked then self:Lock() else self:Unlock() end
end
