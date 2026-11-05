-- ZBar layout: the saved arrangement and the logic that applies it.
--
-- layout = {
--   nextId  = <number>,
--   groups  = { [id] = { x, y, scale, label } },        -- x, y: bottom-left in UIParent units
--   buttons = { [name] = { g = id, x, y, hidden } },     -- x, y: offset inside the group (group units)
-- }
local _, ns = ...
local Layout = {}
ns.Layout = Layout

local function L() return ns.db.layout end

local function BtnSize(name)
    local b = _G[name]
    return b:GetWidth(), b:GetHeight()
end

------------------------------------------------------------------------
-- Capture the current Blizzard positions (first run and after factory reset)
------------------------------------------------------------------------
function Layout:CaptureDefaults()
    local layout = { nextId = 1, groups = {}, buttons = {} }
    local count = 0
    for _, bar in ipairs(ns.Bars.list) do
        if ns.Bars:IsBarEnabled(bar) then
            local rects, minX, minY, scale = {}, nil, nil, nil
            for i = 1, 12 do
                local name = bar.prefix .. i
                local btn = _G[name]
                if btn then
                    local x, y, _, _, s = ns.Bars:GetAbsRect(btn)
                    if x then
                        rects[name] = { x, y }
                        scale = scale or s
                        minX = minX and math.min(minX, x) or x
                        minY = minY and math.min(minY, y) or y
                    end
                end
            end
            if scale then
                local id = layout.nextId
                layout.nextId = id + 1
                layout.groups[id] = { x = ns.Round(minX), y = ns.Round(minY), scale = ns.Round(scale), label = bar.label }
                for name, r in pairs(rects) do
                    layout.buttons[name] = {
                        g = id,
                        x = ns.Round((r[1] - minX) / scale),
                        y = ns.Round((r[2] - minY) / scale),
                    }
                    count = count + 1
                end
            end
        end
    end
    return layout, count
end

------------------------------------------------------------------------
-- Model helpers
------------------------------------------------------------------------
function Layout:Members(id, layout)
    layout = layout or L()
    local list = {}
    for name, b in pairs(layout.buttons) do
        if b.g == id then table.insert(list, name) end
    end
    return list
end

-- absolute rect of a button in UIParent units
function Layout:AbsRect(name, layout)
    layout = layout or L()
    local b = layout.buttons[name]
    local g = layout.groups[b.g]
    local w, h = BtnSize(name)
    return g.x + b.x * g.scale, g.y + b.y * g.scale, w * g.scale, h * g.scale
end

-- move the group origin to the bottom-left of its buttons; drop empty groups
function Layout:Normalize(id)
    local layout = L()
    local g = layout.groups[id]
    if not g then return end
    local minX, minY
    for _, b in pairs(layout.buttons) do
        if b.g == id then
            minX = minX and math.min(minX, b.x) or b.x
            minY = minY and math.min(minY, b.y) or b.y
        end
    end
    if not minX then
        layout.groups[id] = nil
        return
    end
    if minX ~= 0 or minY ~= 0 then
        for _, b in pairs(layout.buttons) do
            if b.g == id then
                b.x = ns.Round(b.x - minX)
                b.y = ns.Round(b.y - minY)
            end
        end
        g.x = ns.Round(g.x + minX * g.scale)
        g.y = ns.Round(g.y + minY * g.scale)
    end
end

-- put the given buttons (all from one group) into a new group at the same spot
function Layout:Detach(names, label)
    local layout = L()
    local src = layout.buttons[names[1]].g
    local sg = layout.groups[src]
    if #self:Members(src) == #names then return src end

    local id = layout.nextId
    layout.nextId = id + 1
    layout.groups[id] = { x = sg.x, y = sg.y, scale = sg.scale, label = label or ("Group " .. id) }
    for _, n in ipairs(names) do layout.buttons[n].g = id end
    self:Normalize(id)
    self:Normalize(src)
    return id
end

local function RectsHit(ax, ay, aw, ah, bx, by, bw, bh)
    return ax < bx + bw - 2 and ax + aw > bx + 2 and ay < by + bh - 2 and ay + ah > by + 2
end

-- would the moving buttons, shifted by dx, dy inside group `target`, cover any
-- other button or a bar block (stance, totem, XP, reputation)?
local function Overlaps(layout, moving, target, dx, dy)
    local tg = layout.groups[target]
    local movingSet = {}
    for _, mn in ipairs(moving) do movingSet[mn] = true end
    local obstacles = ns.Blocks:Obstacles()

    for _, mn in ipairs(moving) do
        local m = layout.buttons[mn]
        local mw, mh = BtnSize(mn)
        local mx, my = m.x + dx, m.y + dy
        local ax, ay = tg.x + mx * tg.scale, tg.y + my * tg.scale
        for _, o in ipairs(obstacles) do
            if RectsHit(ax, ay, mw * tg.scale, mh * tg.scale, o[1], o[2], o[3], o[4]) then return true end
        end
        for tn, t in pairs(layout.buttons) do
            if not movingSet[tn] and layout.groups[t.g] then
                local tw, th = BtnSize(tn)
                if t.g == target then
                    if RectsHit(mx, my, mw, mh, t.x, t.y, tw, th) then return true end
                else
                    local bx, by, bw, bh = Layout:AbsRect(tn, layout)
                    if RectsHit(ax, ay, mw * tg.scale, mh * tg.scale, bx, by, bw, bh) then return true end
                end
            end
        end
    end
    return false
end

-- Everything a dropped thing must not cover: buttons of other groups and visible
-- bar blocks. ignoreGroup / ignoreBlock: the thing being moved.
local function ObstacleRects(layout, ignoreGroup, ignoreBlock)
    local list = ns.Blocks:Obstacles(ignoreBlock)
    for tn, t in pairs(layout.buttons) do
        if t.g ~= ignoreGroup and layout.groups[t.g] and ns.Bars.info[tn] then
            local x, y, w, h = Layout:AbsRect(tn, layout)
            table.insert(list, { x, y, w, h })
        end
    end
    return list
end

local function HitsAny(rects, dx, dy, obstacles)
    for _, r in ipairs(rects) do
        for _, o in ipairs(obstacles) do
            if RectsHit(r[1] + dx, r[2] + dy, r[3], r[4], o[1], o[2], o[3], o[4]) then return o end
        end
    end
end

-- rects: absolute rects of the thing that was just dropped.
-- Returns the smallest shift (dx, dy) that moves it off whatever it covers,
-- 0, 0 if it covers nothing, or nil if there is no free spot next to it.
function Layout:PushOut(rects, ignoreGroup, ignoreBlock)
    local layout = L()
    local obstacles = ObstacleRects(layout, ignoreGroup, ignoreBlock)
    if not HitsAny(rects, 0, 0, obstacles) then return 0, 0 end

    local l, b, r, t
    for _, x in ipairs(rects) do
        l = l and math.min(l, x[1]) or x[1]
        b = b and math.min(b, x[2]) or x[2]
        r = r and math.max(r, x[1] + x[3]) or x[1] + x[3]
        t = t and math.max(t, x[2] + x[4]) or x[2] + x[4]
    end

    local pad = ns.PAD
    local cands = {}
    for _, o in ipairs(obstacles) do
        if HitsAny(rects, 0, 0, { o }) then
            table.insert(cands, { o[1] + o[3] + pad - l, 0 }) -- push right
            table.insert(cands, { o[1] - pad - r, 0 })        -- push left
            table.insert(cands, { 0, o[2] + o[4] + pad - b }) -- push up
            table.insert(cands, { 0, o[2] - pad - t })        -- push down
        end
    end
    table.sort(cands, function(p, q) return math.abs(p[1]) + math.abs(p[2]) < math.abs(q[1]) + math.abs(q[2]) end)
    for _, c in ipairs(cands) do
        if not HitsAny(rects, c[1], c[2], obstacles) then return c[1], c[2] end
    end
    return nil
end

-- buttons of other groups that group `id` is lying on top of (nil if none)
local function CoveredButtons(layout, id, moving)
    local hit
    for _, mn in ipairs(moving) do
        local ax, ay, aw, ah = Layout:AbsRect(mn, layout)
        for tn, t in pairs(layout.buttons) do
            if t.g ~= id and layout.groups[t.g] then
                local bx, by, bw, bh = Layout:AbsRect(tn, layout)
                if RectsHit(ax, ay, aw, ah, bx, by, bw, bh) then
                    hit = hit or {}
                    hit[tn] = true
                end
            end
        end
    end
    return hit
end

-- If a button of group `id` was dropped next to (or on top of) a button of
-- another group, line it up beside that button and merge the two groups.
-- Returns true (snapped), false (left where dropped) or "blocked"
-- (dropped on buttons that have no free spot beside them: caller cancels the drop).
function Layout:TrySnap(id)
    local layout = L()
    local moving = self:Members(id)
    local pad = ns.PAD
    local cands = {}
    -- dropped onto other buttons: pop out to the nearest free spot beside
    -- one of THOSE buttons, however far; otherwise snap only when close
    local covered = CoveredButtons(layout, id, moving)
    local maxDist = covered and math.huge or ns.SNAP

    -- not on a button, but on a bar block (stance, totem, XP...): slide off it
    if not covered then
        local rects = {}
        for _, n in ipairs(moving) do
            local x, y, w, h = self:AbsRect(n, layout)
            table.insert(rects, { x, y, w, h })
        end
        local dx, dy = self:PushOut(rects, id, nil)
        if not dx then return "blocked" end
        if dx ~= 0 or dy ~= 0 then
            local g = layout.groups[id]
            g.x = ns.Round(g.x + dx)
            g.y = ns.Round(g.y + dy)
            return true
        end
    end

    for _, an in ipairs(moving) do
        local a = layout.buttons[an]
        local ax, ay = self:AbsRect(an)
        local aw, ah = BtnSize(an)
        for tn, t in pairs(layout.buttons) do
            if t.g ~= id and layout.groups[t.g] and (not covered or covered[tn]) then
                local tg = layout.groups[t.g]
                local tw, th = BtnSize(tn)
                local spots = {
                    { t.x + tw + pad, t.y },  -- right of target
                    { t.x - aw - pad, t.y },  -- left
                    { t.x, t.y + th + pad },  -- above
                    { t.x, t.y - ah - pad },  -- below
                }
                for pri, s in ipairs(spots) do
                    local cx, cy = tg.x + s[1] * tg.scale, tg.y + s[2] * tg.scale
                    local d = math.sqrt((cx - ax) ^ 2 + (cy - ay) ^ 2)
                    if d <= maxDist then
                        table.insert(cands, { d = d, pri = pri, target = t.g, dx = s[1] - a.x, dy = s[2] - a.y })
                    end
                end
            end
        end
    end

    -- equal distance: prefer right, left, above, below (bars are rows)
    table.sort(cands, function(p, q)
        if math.abs(p.d - q.d) > 0.5 then return p.d < q.d end
        return p.pri < q.pri
    end)
    for _, c in ipairs(cands) do
        if not Overlaps(layout, moving, c.target, c.dx, c.dy) then
            for _, n in ipairs(moving) do
                local b = layout.buttons[n]
                b.g = c.target
                b.x = ns.Round(b.x + c.dx)
                b.y = ns.Round(b.y + c.dy)
            end
            layout.groups[id] = nil
            self:Normalize(c.target)
            return true
        end
    end
    return covered and "blocked" or false
end

------------------------------------------------------------------------
-- Apply the layout to the real frames
------------------------------------------------------------------------
function Layout:Apply()
    if not ns.ready then return end
    ns.RunOOC("apply", function() Layout:DoApply() end)
end

function Layout:DoApply()
    local layout = L()
    local Bars, Groups = ns.Bars, ns.Groups

    for id in pairs(Groups.frames) do
        if not layout.groups[id] then Groups:Release(id) end
    end

    local bw, bh = {}, {}
    for name, b in pairs(layout.buttons) do
        if Bars.info[name] then
            local w, h = BtnSize(name)
            bw[b.g] = math.max(bw[b.g] or 1, b.x + w)
            bh[b.g] = math.max(bh[b.g] or 1, b.y + h)
        end
    end

    for id, g in pairs(layout.groups) do
        local f = Groups:Acquire(id)
        f:SetScale(g.scale)
        f:ClearAllPoints()
        f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", g.x / g.scale, g.y / g.scale)
        f:SetSize(bw[id] or 1, bh[id] or 1)
    end

    for name, b in pairs(layout.buttons) do
        local info = Bars.info[name]
        local f = Groups.frames[b.g]
        if info and f and layout.groups[b.g] then
            Bars:Prepare(info)
            local btn = info.btn
            local hide = b.hidden and not ns.unlocked
            btn:SetParent(hide and Groups.hiddenParent or f)
            btn:ClearAllPoints()
            btn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", b.x, b.y)
            btn:SetAlpha((b.hidden and ns.unlocked) and 0.4 or 1)
            info.managed = true
        end
    end

    Bars:SyncBonus(layout)
    Bars:SyncMainArt(layout)
    ns.Blocks:Apply(layout)
    ns.CustomBars:Apply(layout)
    if ns.Mover then ns.Mover:Refresh() end
end

------------------------------------------------------------------------
-- Save / restore / factory reset
------------------------------------------------------------------------
function Layout:Save()
    ns.db.saved = ns.DeepCopy(L())
    ns.db.savedAt = date("%Y-%m-%d %H:%M")
    ns.Print("Layout saved (positions only - bar contents are saved per role).")
end

function Layout:Restore()
    local saved = ns.db.saved
    if not saved then ns.Print("No layout-only save yet. Use Save Layout Only first.") return end
    if InCombatLockdown() then ns.Print("Cannot restore in combat.") return end

    local cur = L()
    self:PushUndo()
    local new = ns.DeepCopy(saved)
    local maxId = 0
    for id in pairs(new.groups) do maxId = math.max(maxId, id) end
    new.nextId = math.max(new.nextId or 1, maxId + 1)

    -- buttons managed now but missing from the snapshot keep their current spot
    for name, b in pairs(cur.buttons) do
        if not new.buttons[name] and cur.groups[b.g] and ns.Bars.info[name] then
            local x, y = self:AbsRect(name, cur)
            local id = new.nextId
            new.nextId = id + 1
            new.groups[id] = { x = ns.Round(x), y = ns.Round(y), scale = cur.groups[b.g].scale, label = "Group " .. id }
            new.buttons[name] = { g = id, x = 0, y = 0, hidden = b.hidden }
        end
    end

    ns.Blocks:Merge(new, cur)
    ns.db.layout = new
    self:Apply()
    ns.Print("Layout restored (positions only" .. (ns.db.savedAt and (", saved " .. ns.db.savedAt) or "") .. ").")
end

function Layout:FactoryReset()
    -- the reload puts every button back where Blizzard keeps it, then we capture again
    ns.db.layout = nil
    ReloadUI()
end

------------------------------------------------------------------------
-- Undo (kept for this session only)
------------------------------------------------------------------------
local UNDO_MAX = 15
local undo = {}
local lastTag, lastTime = nil, 0

-- snapshot: layout copy from before the change (default: the current layout).
-- tag: changes with the same tag less than 2 s apart (mouse wheel resizing)
-- count as one undo step.
-- note: optional text shown when this step is undone
function Layout:PushUndo(snapshot, tag, note)
    local now = GetTime()
    if tag and tag == lastTag and now - lastTime < 2 then
        lastTime = now
        return
    end
    lastTag, lastTime = tag, now
    table.insert(undo, { layout = snapshot or ns.DeepCopy(L()), note = note })
    if #undo > UNDO_MAX then table.remove(undo, 1) end
    ns.Toolbar:UpdateUndo()
end

-- the change that was just pushed got cancelled (e.g. a blocked drop)
function Layout:DropUndo()
    table.remove(undo)
    lastTag = nil
    ns.Toolbar:UpdateUndo()
end

function Layout:UndoCount()
    return #undo
end

function Layout:Undo()
    if InCombatLockdown() then ns.Print("Cannot undo in combat.") return end
    local step = table.remove(undo)
    if not step then ns.Print("Nothing to undo.") return end
    local snap = step.layout
    lastTag = nil
    ns.Blocks:Merge(snap, L())
    ns.db.layout = snap
    self:Apply()
    ns.Toolbar:UpdateUndo()
    ns.Print(string.format("Undone. %d more step(s) can be undone.", #undo))
    if step.note then ns.Print(step.note) end
end
