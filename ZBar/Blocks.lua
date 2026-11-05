-- ZBar blocks: small Blizzard bars that always move as one unit
-- (stance / shapeshift bar, totem bar, XP bar, reputation bar). Their own
-- inner layout is kept; ZBar only moves, resizes or hides the whole bar.
--
-- layout.blocks = { [key] = { x, y, scale, hidden } }   -- x, y: bottom-left in UIParent units
-- A block without an entry is left completely to Blizzard.
--
-- Visible blocks are obstacles: nothing may be dropped on top of them,
-- and they may not be dropped on top of anything else.
local _, ns = ...
local Blocks = {}
ns.Blocks = Blocks

local function L() return ns.db.layout end

local function Range(prefix, n)
    return function()
        local t = {}
        for i = 1, n do t[#t + 1] = _G[prefix .. i] end
        return t
    end
end

Blocks.list = {
    {
        key = "Stance", label = "Stance Bar", frame = "ShapeshiftBarFrame",
        buttons = Range("ShapeshiftButton", NUM_SHAPESHIFT_SLOTS or 10),
    },
    {
        key = "Totem", label = "Totem Bar", frame = "MultiCastActionBarFrame",
        -- its slide-in animation re-anchors the bar every frame (only the
        -- height changes, so it could only move sideways): switch it off
        killScripts = { "OnUpdate", "OnShow", "OnHide" },
        buttons = function()
            return {
                _G.MultiCastSummonSpellButton,
                _G.MultiCastSlotButton1, _G.MultiCastSlotButton2,
                _G.MultiCastSlotButton3, _G.MultiCastSlotButton4,
                _G.MultiCastRecallSpellButton,
            }
        end,
    },
    {
        -- The pet bar frame slides itself into place every time a pet appears,
        -- so instead of moving that frame the 10 pet buttons are moved into
        -- a ZBar holder (they keep their own spacing).
        key = "Pet", label = "Pet Bar", frame = "PetActionBarFrame",
        buttons = Range("PetActionButton", NUM_PET_ACTION_SLOTS or 10),
        reparent = true,
        visibility = "[vehicleui] hide; [pet] show; hide",
        hideArt = { "SlidingActionBarTexture0", "SlidingActionBarTexture1" },
    },
    { key = "XP",  label = "XP Bar",         frame = "MainMenuExpBar" },
    { key = "Rep", label = "Reputation Bar", frame = "ReputationWatchBar" },
}

-- Blizzard functions that re-anchor these bars; after each one we put ours back
local REANCHOR_HOOKS = {
    "UIParent_ManageFramePositions",
    "ReputationWatchBar_Update",
    "MainMenuExpBar_Update",
    "MainMenuBar_UpdateExperienceBars",
}

local byKey = {}
for _, def in ipairs(Blocks.list) do byKey[def.key] = def end

local function Frame(def) return def.holder or _G[def.frame] end

local function CanTouch(f)
    return not (InCombatLockdown() and f:IsProtected())
end

-- Take the bar away from Blizzard's automatic positioning.
-- Only done for bars the user actually touched; a factory reset (reload) gives them back.
-- move the block's buttons into a ZBar holder (secure buttons: out of combat only)
local function MakeHolder(def)
    local btns = def.buttons()
    local b1 = btns[1]
    if not b1 then return nil end
    local x, y, _, _, s = ns.Bars:GetAbsRect(b1)
    if not x then
        local f = _G[def.frame]
        x, y, _, _, s = ns.Bars:GetAbsRect(f)
    end
    x, y, s = x or 300, y or 150, s or 1

    local holder = CreateFrame("Frame", "ZBar" .. def.key .. "Holder", UIParent)
    holder:SetSize(1, 1)
    holder:SetScale(s)
    holder:SetFrameStrata("MEDIUM")
    holder:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x / s, y / s)
    for _, btn in ipairs(btns) do
        if btn then btn:SetParent(holder) end
    end
    b1:ClearAllPoints()
    b1:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 0, 0)
    if def.visibility then RegisterStateDriver(holder, "visibility", def.visibility) end
    for _, n in ipairs(def.hideArt or {}) do
        local t = _G[n]
        if t then t:SetAlpha(0) end
    end
    def.capX, def.capY, def.capS = x, y, s
    def.holder = holder
    return holder
end

-- returns false if it cannot be done right now (combat)
local function Detach(def, f)
    if def.detached then return true end
    if def.reparent then
        if InCombatLockdown() then return false end
        f = MakeHolder(def)
        if not f then return false end
    end
    if UIPARENT_MANAGED_FRAME_POSITIONS then
        UIPARENT_MANAGED_FRAME_POSITIONS[def.frame] = nil
    end
    def.origParent = f:GetParent()
    if def.killScripts then
        for _, script in ipairs(def.killScripts) do f:SetScript(script, nil) end
    end
    f:SetMovable(true)
    def.detached = true
    return true
end

------------------------------------------------------------------------
-- Geometry
------------------------------------------------------------------------
-- absolute rect (UIParent units) of what the block shows, or nil if not visible
function Blocks:Rect(def)
    local f = Frame(def)
    if not f or not f:IsVisible() then return nil end
    if not def.buttons then
        local x, y, w, h = ns.Bars:GetAbsRect(f)
        return x, y, w, h
    end
    local l, b, r, t
    for _, btn in ipairs(def.buttons()) do
        if btn and btn:IsVisible() then
            local x, y, w, h = ns.Bars:GetAbsRect(btn)
            if x then
                l = l and math.min(l, x) or x
                b = b and math.min(b, y) or y
                r = r and math.max(r, x + w) or x + w
                t = t and math.max(t, y + h) or y + h
            end
        end
    end
    if not l then return nil end
    return l, b, r - l, t - b
end

-- rects of all visible, not user-hidden blocks except `exceptKey`
function Blocks:Obstacles(exceptKey)
    local list = {}
    local blocks = (ns.db and ns.db.layout and ns.db.layout.blocks) or {}
    for _, def in ipairs(self.list) do
        local e = blocks[def.key]
        if def.key ~= exceptKey and not (e and e.hidden) then
            local x, y, w, h = self:Rect(def)
            if x then table.insert(list, { x, y, w, h }) end
        end
    end
    return list
end

------------------------------------------------------------------------
-- Layout entries and placing
------------------------------------------------------------------------
-- make sure the block has a layout entry (first time the user touches it)
function Blocks:Take(def)
    local layout = L()
    layout.blocks = layout.blocks or {}
    local e = layout.blocks[def.key]
    local f = Frame(def)
    if not f then return nil end
    if not e and not def.reparent then
        local s = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
        e = {
            x = ns.Round((f:GetLeft() or 0) * s),
            y = ns.Round((f:GetBottom() or 0) * s),
            scale = ns.Round(f:GetScale()),
        }
    end
    if not Detach(def, f) then return nil end
    if not e then -- reparented block: start where its first button was
        e = { x = ns.Round(def.capX), y = ns.Round(def.capY), scale = ns.Round(def.capS) }
    end
    layout.blocks[def.key] = e
    return e
end

local function Place(f, e)
    f:ClearAllPoints()
    local k = UIParent:GetEffectiveScale() / f:GetEffectiveScale()
    f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", e.x * k, e.y * k)
end

function Blocks:Apply(layout)
    layout.blocks = layout.blocks or {}
    for _, def in ipairs(self.list) do
        local e = layout.blocks[def.key]
        local f = Frame(def)
        if e and f and CanTouch(f) and def ~= self.dragging and Detach(def, f) then
            f = Frame(def)
            local hide = e.hidden and not ns.unlocked
            local parent = hide and ns.Groups.hiddenParent or def.origParent
            if f:GetParent() ~= parent then f:SetParent(parent) end
            f:SetScale(e.scale)
            Place(f, e)
            f:SetAlpha((e.hidden and ns.unlocked) and 0.4 or 1)
        end
    end
end

-- safety net: if Blizzard moves a bar anyway, put it back (post-hooks, no taint)
local function Reanchor()
    if not ns.ready or not ns.db or not ns.db.layout or not ns.db.layout.blocks then return end
    for _, def in ipairs(Blocks.list) do
        local e = ns.db.layout.blocks[def.key]
        local f = Frame(def)
        if e and f and def.detached and CanTouch(f) and def ~= Blocks.dragging then
            Place(f, e)
        end
    end
end

for _, fn in ipairs(REANCHOR_HOOKS) do
    if type(_G[fn]) == "function" then hooksecurefunc(fn, Reanchor) end
end

------------------------------------------------------------------------
-- Dragging, resizing, hiding
------------------------------------------------------------------------
function Blocks:StartDrag(def)
    if InCombatLockdown() then return end
    local e = self:Take(def)
    if not e then return end
    ns.Layout:PushUndo()
    self:Apply(L())
    self.dragFrom = { x = e.x, y = e.y }
    self.dragging = def
    Frame(def):StartMoving()
    ns.Mover:WatchDrop()
end

function Blocks:StopDrag()
    local def = self.dragging
    if not def then return end
    self.dragging = nil
    local f = Frame(def)
    local e = L().blocks and L().blocks[def.key]
    if not f or not e or InCombatLockdown() then return end
    f:StopMovingOrSizing()
    f:SetUserPlaced(false)
    local s = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
    e.x = ns.Round(f:GetLeft() * s)
    e.y = ns.Round(f:GetBottom() * s)

    -- dropped on something: slide off it, or go back if there is no room
    local x, y, w, h = self:Rect(def)
    if x then
        local dx, dy = ns.Layout:PushOut({ { x, y, w, h } }, nil, def.key)
        if not dx then
            if self.dragFrom then e.x, e.y = self.dragFrom.x, self.dragFrom.y end
            ns.Layout:DropUndo()
            ns.Print("No free spot there - moved back.")
            PlaySound("igQuestFailed")
        else
            e.x = ns.Round(e.x + dx)
            e.y = ns.Round(e.y + dy)
        end
    end
    self.dragFrom = nil
    ns.Layout:Apply()
end

function Blocks:Scale(def, delta)
    if InCombatLockdown() then return end
    local e = self:Take(def)
    if not e then return end
    ns.Layout:PushUndo(nil, "blockscale" .. def.key)
    e.scale = math.max(0.5, math.min(2, ns.Round(e.scale + delta * 0.05)))
    ns.Layout:Apply()
end

function Blocks:ToggleHidden(def)
    if InCombatLockdown() then return end
    local e = self:Take(def)
    if not e then return end
    ns.Layout:PushUndo()
    e.hidden = (not e.hidden) or nil
    ns.Layout:Apply()
end

------------------------------------------------------------------------
-- Unlock-mode overlays (one per block, covering what it shows)
------------------------------------------------------------------------
local overlays = {}

local function CreateOverlay(def)
    local ov = CreateFrame("Frame", nil, UIParent)
    ov:SetFrameStrata("DIALOG")
    ov:EnableMouse(true)
    ov:EnableMouseWheel(true)
    ov:RegisterForDrag("LeftButton")
    ov:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                     edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
                     insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    ov:SetBackdropBorderColor(0.3, 0.7, 1, 0.9)

    ov.text = ov:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ov.text:SetPoint("BOTTOM", ov, "TOP", 0, 1)

    ov:SetScript("OnDragStart", function()
        if ns.mode == "buttons" then Blocks:StartDrag(def) end
    end)
    ov:SetScript("OnDragStop", function() Blocks:StopDrag() end)
    ov:SetScript("OnMouseWheel", function(_, delta)
        if ns.mode == "buttons" then Blocks:Scale(def, delta) end
    end)
    ov:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" and ns.mode == "buttons" then Blocks:ToggleHidden(def) end
    end)
    ov:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(def.label)
        GameTooltip:AddLine("Drag: move the whole bar", 1, 1, 1)
        GameTooltip:AddLine("Mouse wheel: resize", 1, 1, 1)
        GameTooltip:AddLine("Right-click: hide / show", 1, 1, 1)
        GameTooltip:Show()
    end)
    ov:SetScript("OnLeave", function() GameTooltip:Hide() end)

    overlays[def.key] = ov
    return ov
end

function Blocks:Refresh()
    local blocks = (L() and L().blocks) or {}
    for _, def in ipairs(self.list) do
        local ov = overlays[def.key]
        local f = Frame(def)
        local first, last
        if ns.unlocked and ns.mode == "buttons" and f and f:IsVisible() then
            if def.buttons then
                for _, b in ipairs(def.buttons()) do
                    if b and b:IsShown() then
                        first = first or b
                        last = b
                    end
                end
            else
                first, last = f, f
            end
        end
        if first then
            ov = ov or CreateOverlay(def)
            ov:ClearAllPoints()
            ov:SetPoint("TOPLEFT", first, "TOPLEFT", -3, 3)
            ov:SetPoint("BOTTOMRIGHT", last, "BOTTOMRIGHT", 3, -3)
            local e = blocks[def.key]
            if e and e.hidden then
                ov:SetBackdropColor(0.8, 0.1, 0.1, 0.45)
            else
                ov:SetBackdropColor(0.1, 0.4, 0.9, 0.25)
            end
            ov.text:SetText(string.format("%s  %d%%", def.label, ((e and e.scale) or f:GetScale()) * 100 + 0.5))
            ov:Show()
        elseif ov and def ~= self.dragging then
            ov:Hide()
        end
    end
end

-- restore: keep blocks that are already detached but missing from the snapshot
function Blocks:Merge(new, cur)
    new.blocks = new.blocks or {}
    for key, e in pairs(cur.blocks or {}) do
        if not new.blocks[key] and byKey[key] and byKey[key].detached then
            new.blocks[key] = ns.DeepCopy(e)
        end
    end
end
