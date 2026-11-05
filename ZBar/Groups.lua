-- ZBar groups: container frames that hold the rearranged buttons.
local _, ns = ...
local Groups = {}
ns.Groups = Groups

Groups.frames = {}

local hidden = CreateFrame("Frame", "ZBarHiddenParent", UIParent)
hidden:Hide()
Groups.hiddenParent = hidden

function Groups:Acquire(id)
    local f = self.frames[id]
    if not f then
        f = CreateFrame("Frame", "ZBarGroup" .. id, UIParent)
        f:SetFrameStrata("MEDIUM")
        f:SetFrameLevel(ns.BASE_LEVEL)
        f:SetMovable(true)
        f:SetClampedToScreen(true)
        f:SetSize(1, 1)
        f.zbarId = id
        self.frames[id] = f
    end
    if not f.zbarActive then
        f.zbarActive = true
        f:Show()
        -- hide like the default bars do while in a vehicle
        RegisterStateDriver(f, "visibility", "[vehicleui] hide; show")
    end
    return f
end

function Groups:Release(id)
    local f = self.frames[id]
    if f and f.zbarActive then
        f.zbarActive = nil
        UnregisterStateDriver(f, "visibility")
        f:Hide()
        if f.zbarHandle then f.zbarHandle:Hide() end
    end
end
