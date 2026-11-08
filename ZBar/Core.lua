-- ZBar core: settings, saved variables, combat queue, timers, startup.
local ADDON, ns = ...
_G.ZBar = ns

ns.VERSION    = "0.12.3"
ns.SNAP       = 16   -- snap distance in screen pixels
ns.PAD        = 6    -- gap between snapped buttons (Blizzard default spacing)
ns.BASE_LEVEL = 10   -- frame level of ZBar groups (above the main bar art)
ns.unlocked   = false
ns.mode       = "buttons" -- "buttons" = move buttons, "content" = drag spells/macros

function ns.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99ZBar|r: " .. tostring(msg))
end

function ns.DeepCopy(t)
    if type(t) ~= "table" then return t end
    local c = {}
    for k, v in pairs(t) do c[k] = ns.DeepCopy(v) end
    return c
end

function ns.Round(v)
    return math.floor(v * 100 + 0.5) / 100
end

------------------------------------------------------------------------
-- Simple timers (3.3.5 has no C_Timer)
------------------------------------------------------------------------
local timers = {}
local timerFrame = CreateFrame("Frame")
timerFrame:SetScript("OnUpdate", function(_, elapsed)
    for i = #timers, 1, -1 do
        local t = timers[i]
        t.left = t.left - elapsed
        if t.left <= 0 then
            table.remove(timers, i)
            t.func()
        end
    end
end)

function ns.After(delay, func)
    table.insert(timers, { left = delay, func = func })
end

------------------------------------------------------------------------
-- Out-of-combat queue: secure frames cannot be changed in combat
------------------------------------------------------------------------
local queue, queueOrder = {}, {}

function ns.RunOOC(key, func)
    if InCombatLockdown() then
        if not queue[key] then table.insert(queueOrder, key) end
        queue[key] = func
        return false
    end
    func()
    return true
end

local function FlushQueue()
    local order = queueOrder
    queueOrder = {}
    for _, key in ipairs(order) do
        local func = queue[key]
        queue[key] = nil
        if func then func() end
    end
end

------------------------------------------------------------------------
-- Startup
------------------------------------------------------------------------
function ns.Setup()
    if ns.ready then return end
    ns.Bars:Init()
    local layout = ns.db.layout
    if not layout or not layout.groups or not layout.buttons then
        local count
        ns.db.layout, count = ns.Layout:CaptureDefaults()
        ns.Print(string.format("Default bar layout captured (%d buttons). Type /zbar to rearrange.", count))
    end
    ns.ready = true
    ns.Layout:Apply()
    if ns.Modifiers then ns.Modifiers:Init() end
    if ns.Roles then ns.Roles:OnReady() end
    if ns.Minimap then ns.Minimap:Create() end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        ZBarCharDB = ZBarCharDB or {}
        ns.db = ZBarCharDB
        ZBarDB = ZBarDB or {} -- account-wide (account macros of the macro builder)
        ns.adb = ZBarDB
        ns.db.version = 1
    elseif event == "PLAYER_ENTERING_WORLD" then
        if not ns.setupScheduled then
            ns.setupScheduled = true
            -- give Blizzard time to place its bars before we capture them
            ns.After(1, function() ns.RunOOC("setup", ns.Setup) end)
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        if ns.unlocked and ns.Mover then ns.Mover:Lock(true) end
    elseif event == "PLAYER_REGEN_ENABLED" then
        FlushQueue()
    end
end)
