-- ZBar macro builder: Interface > AddOns > ZBar > Macro Builder
-- Click a macro together (spells, targets, keys, extras) instead of typing
-- the macro language. The result is a normal game macro (works in combat,
-- can go on any button or Ctrl / Shift layer). ZBar keeps how it was built
-- (the "recipe"), so it can be edited here again later.
--
-- Recipes: character macros in ZBarCharDB.macros, account macros in
-- ZBarDB.macros (both keyed by macro name).
-- recipe = { name, perChar, mode = "cast" | "sequence", lines = { line... },
--            icon (nil = changes with the spell, or the name of one of its spells),
--            resetTarget, resetCombat, resetSecs, tooltip, targetmouse, dismount, cancelform,
--            stopcasting, targetenemy, startattack, petattack, trinket1,
--            trinket2, hideerrors }
-- line   = { name, who = "harm" | "help" | nil, mouseover, focus, target, tot,
--            selfnt (no target: cast without a unit, the game's Auto Self Cast
--            puts helpful spells on you), self (always yourself), mod = "alt" | "ctrl" | "shift" | "nomod" | nil,
--            combat = "combat" | "nocombat" | nil }
-- In sequence mode the conditions of line 1 are used for the whole sequence.
local _, ns = ...
local MB = {}
ns.Macros = MB

local MAX_BODY = 255
local MAX_NAME = 16
local MAX_ACCOUNT, MAX_CHARACTER = 36, 18
local MAX_LINES = { cast = 4, sequence = 6 }
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

local function CharStore()
    ns.db.macros = ns.db.macros or {}
    return ns.db.macros
end

local function AccStore()
    ns.adb = ns.adb or {}
    ns.adb.macros = ns.adb.macros or {}
    return ns.adb.macros
end

local function Store(perChar)
    return perChar and CharStore() or AccStore()
end

------------------------------------------------------------------------
-- Building the macro text
------------------------------------------------------------------------
-- the condition brackets of one line, e.g. "[@mouseover,help,nodead][help,nodead][@player]"
function MB:Clauses(c)
    local extra = {}
    if c.mod == "nomod" then
        extra[#extra + 1] = "nomod"
    elseif c.mod then
        extra[#extra + 1] = "mod:" .. c.mod
    end
    if c.combat then extra[#extra + 1] = c.combat end
    local rel = (c.who == "harm" or c.who == "help") and c.who or nil
    local out = {}
    local function Add(unit, isSelf)
        local p = {}
        if unit then p[#p + 1] = "@" .. unit end
        if rel and not isSelf then p[#p + 1] = rel end
        if not isSelf and (unit or rel) then p[#p + 1] = "nodead" end
        for _, e in ipairs(extra) do p[#p + 1] = e end
        out[#out + 1] = "[" .. table.concat(p, ",") .. "]"
    end
    if c.mouseover then Add("mouseover") end
    if c.focus then Add("focus") end
    if c.target then Add(nil) end
    if c.tot then Add("targettarget") end
    if c.selfnt then
        -- [noexists] checks the target; the spell goes out without a unit, so
        -- the game's Auto Self Cast (on by default) puts it on you. An enemy
        -- target does not match, so it is never cast on you by accident.
        local q = { "noexists" }
        for _, e in ipairs(extra) do q[#q + 1] = e end
        out[#out + 1] = "[" .. table.concat(q, ",") .. "]"
    end
    if c.self then Add("player", true) end
    if #out == 0 and (rel or #extra > 0) then Add(nil) end
    local s = table.concat(out)
    if s == "[]" then s = "" end -- "any target, any time": no brackets needed
    return s
end

local function Spells(r)
    local list = {}
    for _, line in ipairs(r.lines or {}) do
        if line.name and line.name ~= "" then list[#list + 1] = line end
    end
    return list
end

-- extras: key, the line it adds, label, help
MB.EXTRAS = {
    { "tooltip", "#showtooltip", "Show tooltip", "The button shows the icon and tooltip of the spell the macro would cast now." },
    { "targetmouse", "/target [@mouseover,exists,nodead]", "Target mouse", "Targets whatever is under your mouse first "
        .. "(also on unit frames), so the spell goes there and it stays your target. Point and press - attack or heal. Turns off Auto target." },
    { "dismount", "/dismount [mounted]", "Dismount", "Gets off your mount first." },
    { "cancelform", "/cancelform", "Cancel form", "Leaves your shapeshift form first." },
    { "stopcasting", "/stopcasting", "Stop casting", "Stops the spell you are casting, so this one goes out right away." },
    { "targetenemy", "/targetenemy [noharm][dead]", "Auto target", "No enemy target (or it is dead): targets the nearest enemy first. Turns off Target mouse." },
    { "startattack", "/startattack [harm,nodead]", "Start attack", "Starts your auto attack on an enemy target." },
    { "petattack", "/petattack [harm,nodead]", "Pet attack", "Sends your pet at an enemy target." },
    { "trinket1", "/use 13", "Trinket 1", "Uses your upper trinket too." },
    { "trinket2", "/use 14", "Trinket 2", "Uses your lower trinket too." },
    { "hideerrors", "/script UIErrorsFrame:Clear()", "Hide errors", "Clears the red error text (\"Not ready yet\", ...) after the macro." },
}

-- the chosen icon spell, if it is still one of the macro's spells
function MB:IconSpell(r)
    if not r.icon then return nil end
    for _, line in ipairs(Spells(r)) do
        if line.name == r.icon then return r.icon end
    end
end

function MB:Build(r)
    local out = {}
    local function Add(s) out[#out + 1] = s end
    local iconSpell = self:IconSpell(r)
    if iconSpell then
        -- fixed icon: "#show" shows that spell's icon (and tooltip with #showtooltip)
        Add((r.tooltip and "#showtooltip " or "#show ") .. iconSpell)
    elseif r.tooltip then
        Add("#showtooltip")
    end
    for _, x in ipairs(self.EXTRAS) do
        if x[1] ~= "hideerrors" and x[1] ~= "tooltip" and r[x[1]] then Add(x[2]) end
    end
    local spells = Spells(r)
    if #spells > 0 then
        if r.mode == "sequence" then
            local cond = self:Clauses(r.lines[1])
            local reset = {}
            local secs = tonumber(r.resetSecs)
            if secs and secs > 0 then reset[#reset + 1] = tostring(math.floor(secs)) end
            if r.resetTarget then reset[#reset + 1] = "target" end
            if r.resetCombat then reset[#reset + 1] = "combat" end
            local names = {}
            for _, line in ipairs(spells) do names[#names + 1] = line.name end
            Add("/castsequence" .. (cond ~= "" and (" " .. cond) or "")
                .. (#reset > 0 and (" reset=" .. table.concat(reset, "/")) or "")
                .. " " .. table.concat(names, ", "))
        else
            local parts = {}
            for _, line in ipairs(spells) do parts[#parts + 1] = self:Clauses(line) .. line.name end
            Add("/cast " .. table.concat(parts, "; "))
        end
    end
    if r.hideerrors then Add(self.EXTRAS[#self.EXTRAS][2]) end
    return table.concat(out, "\n"), #spells
end

function MB:NewRecipe()
    return { name = "", perChar = true, mode = "cast", lines = {}, tooltip = true }
end

function MB:NewLine(name)
    return { name = name or "", target = true }
end

------------------------------------------------------------------------
-- Game macros
------------------------------------------------------------------------
-- index of a macro by name in one bank (account: 1-36, character: 37-54)
function MB:Find(name, perChar)
    if not name or name == "" then return nil end
    local numAcc, numChar = GetNumMacros()
    local first, last
    if perChar then
        first, last = MAX_ACCOUNT + 1, MAX_ACCOUNT + (numChar or 0)
    else
        first, last = 1, numAcc or 0
    end
    for i = first, last do
        if GetMacroInfo(i) == name then return i end
    end
end

local function Updated()
    if MacroFrame and MacroFrame:IsShown() and MacroFrame_Update then MacroFrame_Update() end
end

-- the macro's own icon (as an index of the game's macro icon list): the chosen
-- spell's icon if the list has it, else the question mark (which shows the
-- spell picked by #showtooltip / #show on the button anyway)
function MB:IconIndex(r)
    local spell = self:IconSpell(r)
    local tex = spell and self:Icon(spell)
    if not (tex and GetNumMacroIcons and GetMacroIconInfo) then return 1 end
    tex = tex:lower():gsub("/", "\\")
    for i = 1, GetNumMacroIcons() do
        local t = GetMacroIconInfo(i)
        if t then
            t = t:lower():gsub("/", "\\")
            if t == tex or ("interface\\icons\\" .. t) == tex then return i end
        end
    end
    return 1
end

local function Create(name, body, perChar, icon)
    icon = icon or 1
    local before = MB:Find(name, not perChar) -- a macro of the same name in the other bank is not ours
    if not pcall(CreateMacro, name, icon, body, perChar and 1 or nil) then
        pcall(CreateMacro, name, "INV_Misc_QuestionMark", body, perChar and 1 or nil)
    end
    local found = MB:Find(name, perChar)
    if not found then
        -- older argument order (name, icon, body, local, perCharacter): it went to the other bank
        local other = MB:Find(name, not perChar)
        if other and other ~= before then
            DeleteMacro(other)
            pcall(CreateMacro, name, icon, body, nil, perChar and 1 or nil)
            found = MB:Find(name, perChar)
        end
    end
    return found
end

local function Edit(index, name, body, icon)
    if not pcall(EditMacro, index, name, icon or 1, body) then
        pcall(EditMacro, index, name, nil, body)
    end
end

-- orig: { name, perChar } of the recipe as it was saved before (nil = new)
-- returns ok, message
function MB:Save(r, orig)
    if InCombatLockdown() then return false, "Macros cannot be saved in combat." end
    local name = (r.name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return false, "Give the macro a name." end
    if #name > MAX_NAME then return false, "The name can be at most " .. MAX_NAME .. " characters." end
    local body, nSpells = self:Build(r)
    if nSpells == 0 then return false, "Add at least one spell or item." end
    if #body > MAX_BODY then
        return false, "The macro is " .. #body .. " characters long, the game allows " .. MAX_BODY .. ". Turn something off."
    end
    r.name = name
    local perChar = r.perChar and true or false
    local origIndex = orig and self:Find(orig.name, orig.perChar)

    -- a macro with this name that ZBar did not make is never overwritten
    local same = self:Find(name, perChar)
    local isOrig = orig and orig.name == name and (orig.perChar and true or false) == perChar
    if same and not isOrig then
        if Store(perChar)[name] then
            return false, "There is already a ZBar macro named \"" .. name .. "\" - pick it in the Macro list to change it, or use another name."
        end
        return false, "There is already a macro named \"" .. name .. "\" (not made by ZBar). Pick another name."
    end

    local index
    if same then
        Edit(same, name, body, self:IconIndex(r))
        index = same
    elseif origIndex and (orig.perChar and true or false) == perChar then
        Edit(origIndex, name, body, self:IconIndex(r)) -- renamed in the same bank
        origIndex = nil
        index = self:Find(name, perChar)
    else
        local numAcc, numChar = GetNumMacros()
        if perChar and (numChar or 0) >= MAX_CHARACTER then
            return false, "No free character macro slot (" .. MAX_CHARACTER .. " used). Delete one or save it as an account macro."
        elseif not perChar and (numAcc or 0) >= MAX_ACCOUNT then
            return false, "No free account macro slot (" .. MAX_ACCOUNT .. " used). Delete one or save it as a character macro."
        end
        index = Create(name, body, perChar, self:IconIndex(r))
        if not index then return false, "The game did not create the macro." end
    end
    -- the old one (renamed, or moved to the other bank)
    if orig and not isOrig then
        if origIndex and self:Find(orig.name, orig.perChar) == origIndex then DeleteMacro(origIndex) end
        Store(orig.perChar)[orig.name] = nil
    end
    local saved = ns.DeepCopy(r)
    saved.savedAt = date("%Y-%m-%d %H:%M")
    Store(perChar)[name] = saved
    Updated()
    return true, "Saved: " .. name .. (perChar and " (character macro)" or " (account macro)") .. ", " .. #body .. "/" .. MAX_BODY .. " characters."
end

function MB:Delete(name, perChar)
    if InCombatLockdown() then return false, "Macros cannot be deleted in combat." end
    local index = self:Find(name, perChar)
    if index then DeleteMacro(index) end
    Store(perChar)[name] = nil
    Updated()
    return true, "Deleted: " .. name .. "."
end

function MB:Pickup(name, perChar)
    local index = self:Find(name, perChar)
    if not index then return false end
    PickupMacro(index)
    return true
end

-- every recipe this character can edit: { name, perChar }, sorted
function MB:List()
    local list = {}
    if not ns.db then return list end
    for name in pairs(CharStore()) do list[#list + 1] = { name = name, perChar = true } end
    for name in pairs(AccStore()) do list[#list + 1] = { name = name, perChar = false } end
    table.sort(list, function(a, b)
        if a.perChar ~= b.perChar then return a.perChar end
        return a.name < b.name
    end)
    return list
end

function MB:Get(name, perChar)
    return ns.db and Store(perChar)[name]
end

------------------------------------------------------------------------
-- Spell / item icons
------------------------------------------------------------------------
function MB:Icon(name)
    if not name or name == "" then return nil end
    local tex = GetSpellTexture(name)
    if tex then return tex end
    local _, _, _, _, _, _, _, _, _, itex = GetItemInfo(name)
    return itex
end

-- what is on the cursor, as a name (spell, pet spell or item)
local function CursorName()
    local t, a, b = GetCursorInfo()
    if t == "spell" then
        return GetSpellName(a, b or BOOKTYPE_SPELL)
    elseif t == "item" then
        return (GetItemInfo(a))
    end
end

------------------------------------------------------------------------
-- The picker (works like the one in WeakAuras Simple Remastered):
-- category, search, a list with icons, left click picks.
------------------------------------------------------------------------
local CATEGORY_NAMES = {
    cooldown = "Spells with cooldown",
    spell = "Other spells",
    item = "Usable items (trinkets, potions)",
}
local CATEGORY_ORDER = { "cooldown", "spell", "item" }

local scanTip
local function HasCooldown(index, book)
    if not scanTip then
        scanTip = CreateFrame("GameTooltip", "ZBarScanTooltip", nil, "GameTooltipTemplate")
    end
    scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
    scanTip:ClearLines()
    scanTip:SetSpell(index, book)
    for i = 1, scanTip:NumLines() do
        for _, side in ipairs({ "Left", "Right" }) do
            local fs = _G["ZBarScanTooltipText" .. side .. i]
            local text = fs and fs:GetText()
            if text and text:lower():find("cooldown") then return true, text end
        end
    end
    return false
end

local function ScanSpells()
    local result, seen = {}, {}
    local books = { { BOOKTYPE_SPELL or "spell" } }
    if HasPetSpells and HasPetSpells() then books[2] = { BOOKTYPE_PET or "pet", HasPetSpells() } end
    local total = 0
    for t = 1, GetNumSpellTabs() do
        local _, _, offset, num = GetSpellTabInfo(t)
        total = math.max(total, (offset or 0) + (num or 0))
    end
    for _, book in ipairs(books) do
        local bt = book[1]
        local isPet = bt ~= (BOOKTYPE_SPELL or "spell")
        local count = isPet and (book[2] or 0) or total
        for i = 1, count do
            local name = GetSpellName(i, bt)
            if not name then break end
            if not IsPassiveSpell(i, bt) and not seen[name] then
                seen[name] = true
                local cd, cdText = HasCooldown(i, bt)
                result[#result + 1] = {
                    name = name, icon = GetSpellTexture(i, bt),
                    kind = cd and "cooldown" or "spell",
                    info = (isPet and "pet" or nil), cdText = cdText,
                }
            end
        end
    end
    table.sort(result, function(a, b) return a.name < b.name end)
    return result
end

local function ScanItems()
    local result, seen = {}, {}
    local function Add(link)
        if not link then return end
        local id = tonumber(link:match("item:(%d+)"))
        if not id or seen[id] or not GetItemSpell(link) then return end
        seen[id] = true
        local name, _, _, _, _, _, _, _, _, icon = GetItemInfo(link)
        if name then result[#result + 1] = { name = name, icon = icon, kind = "item" } end
    end
    for slot = 1, 19 do Add(GetInventoryItemLink("player", slot)) end
    for bag = 0, 4 do
        for slot = 1, (GetContainerNumSlots(bag) or 0) do Add(GetContainerItemLink(bag, slot)) end
    end
    table.sort(result, function(a, b) return a.name < b.name end)
    return result
end

local picker
local NROWS, ROWH = 14, 22

local function CreatePicker()
    local f = CreateFrame("Frame", "ZBarPicker", UIParent)
    f:SetSize(420, 470)
    f:SetPoint("CENTER", 120, 0)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", 11, -11)
    bg:SetPoint("BOTTOMRIGHT", -11, 11)
    bg:SetTexture(0.05, 0.05, 0.05, 1)
    tinsert(UISpecialFrames, "ZBarPicker") -- Esc closes it

    f.title = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    f.title:SetPoint("TOP", 0, -18)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    local showLabel = f:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    showLabel:SetPoint("TOPLEFT", 22, -44)
    showLabel:SetText("Show")
    local cat = CreateFrame("Frame", "ZBarPickerCategory", f, "UIDropDownMenuTemplate")
    cat:SetPoint("TOPLEFT", 4, -56)
    UIDropDownMenu_SetWidth(cat, 170)

    local searchLabel = f:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    searchLabel:SetPoint("TOPLEFT", 230, -44)
    searchLabel:SetText("Search")
    local search = CreateFrame("EditBox", "ZBarPickerSearch", f, "InputBoxTemplate")
    search:SetSize(160, 20)
    search:SetPoint("TOPLEFT", 236, -60)
    search:SetAutoFocus(false)

    f.info = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    f.info:SetPoint("TOPLEFT", 22, -92)
    f.info:SetWidth(376)
    f.info:SetJustifyH("LEFT")
    f.info:SetText("|cffffd100Read from your spellbook (and your pet's) right now.|r")

    local scroll = CreateFrame("ScrollFrame", "ZBarPickerScroll", f, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 20, -110)
    scroll:SetSize(356, NROWS * ROWH)

    f.rows = {}
    for i = 1, NROWS do
        local row = CreateFrame("Button", nil, f)
        row:SetSize(356, ROWH)
        row:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, -(i - 1) * ROWH)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(20, 20)
        row.icon:SetPoint("LEFT", 2, 0)
        row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        row.text:SetPoint("RIGHT", -2, 0)
        row.text:SetJustifyH("LEFT")
        row:SetScript("OnClick", function(self)
            local entry = self.entry
            if not entry then return end
            f:Hide()
            if f.onPick then f.onPick(entry) end
        end)
        row:SetScript("OnEnter", function(self)
            if not self.entry then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if self.entry.kind == "item" then
                local _, link = GetItemInfo(self.entry.name)
                if link then GameTooltip:SetHyperlink(link) else GameTooltip:SetText(self.entry.name) end
            else
                local link = GetSpellLink(self.entry.name)
                if link then GameTooltip:SetHyperlink(link) else GameTooltip:SetText(self.entry.name) end
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f.rows[i] = row
    end

    f.status = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    f.status:SetPoint("BOTTOMLEFT", 22, 20)
    f.status:SetText("Left click: choose.  Or drag a spell from your spellbook onto the icon slot.")

    local filtered = {}
    function f:Update()
        local all = self.entries or {}
        wipe(filtered)
        local s = (search:GetText() or ""):lower()
        for _, e in ipairs(all) do
            if (self.category == "item" and e.kind == "item") or e.kind == self.category then
                if s == "" or e.name:lower():find(s, 1, true) then filtered[#filtered + 1] = e end
            end
        end
        FauxScrollFrame_Update(scroll, #filtered, NROWS, ROWH)
        local offset = FauxScrollFrame_GetOffset(scroll)
        for i = 1, NROWS do
            local row, e = self.rows[i], filtered[offset + i]
            row.entry = e
            if e then
                row.icon:SetTexture(e.icon or QUESTION)
                local extra = {}
                if e.info then extra[#extra + 1] = e.info end
                if e.cdText then extra[#extra + 1] = e.cdText end
                row.text:SetText(e.name .. (#extra > 0 and ("  |cff999999(" .. table.concat(extra, ", ") .. ")|r") or ""))
                row:Show()
            elseif i == 1 then
                row.icon:SetTexture(nil)
                row.text:SetText("|cff999999Nothing found.|r")
                row:Show()
            else
                row:Hide()
            end
        end
    end

    scroll:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, ROWH, function() f:Update() end)
    end)
    search:SetScript("OnTextChanged", function() f:Update() end)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    UIDropDownMenu_Initialize(cat, function()
        for _, key in ipairs(CATEGORY_ORDER) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = CATEGORY_NAMES[key]
            info.checked = f.category == key
            info.func = function()
                f.category = key
                UIDropDownMenu_SetText(cat, CATEGORY_NAMES[key])
                f.info:SetText(key == "item" and "|cffffd100Read from your bags and equipment right now.|r"
                    or "|cffffd100Read from your spellbook (and your pet's) right now.|r")
                f:Update()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    function f:Open(onPick, title)
        self.onPick = onPick
        self.title:SetText(title or "Choose")
        self.entries = ScanSpells()
        for _, e in ipairs(ScanItems()) do self.entries[#self.entries + 1] = e end
        self.category = "cooldown"
        UIDropDownMenu_SetText(cat, CATEGORY_NAMES.cooldown)
        self.info:SetText("|cffffd100Read from your spellbook (and your pet's) right now.|r")
        search:SetText("")
        FauxScrollFrame_SetOffset(scroll, 0)
        scroll:SetVerticalScroll(0)
        self:Show()
        self:Update()
    end
    f:Hide()
    return f
end

function MB:OpenPicker(onPick, title)
    picker = picker or CreatePicker()
    picker:Open(onPick, title)
end

------------------------------------------------------------------------
-- Sub-panel: Interface > AddOns > ZBar > Macro Builder
------------------------------------------------------------------------
local p = CreateFrame("Frame", "ZBarMacroPanel", UIParent)
p.name = "Macro Builder"
p.parent = "ZBar"
p:Hide()

local cur = MB:NewRecipe() -- the recipe being edited (a copy)
local orig                 -- { name, perChar } of its saved version, nil = new
local sel = 1              -- selected spell line
local Refresh              -- forward

local function Text(text, x, y, font, width)
    local fs = p:CreateFontString(nil, "ARTWORK", font or "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetJustifyH("LEFT")
    if width then fs:SetWidth(width) end
    fs:SetText(text or "")
    return fs
end

local function Btn(text, w, x, y, onClick, parent)
    local b = CreateFrame("Button", nil, parent or p, "UIPanelButtonTemplate")
    b:SetSize(w, 22)
    b:SetPoint("TOPLEFT", x, y)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

local function Tip(frame, title, text)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:SetText(title)
        if text then GameTooltip:AddLine(text, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local checkN = 0
local function Check(label, x, y, onClick, tipTitle, tipText)
    checkN = checkN + 1
    local cb = CreateFrame("CheckButton", "ZBarMBCheck" .. checkN, p, "UICheckButtonTemplate")
    cb:SetSize(22, 22)
    cb:SetPoint("TOPLEFT", x, y)
    _G[cb:GetName() .. "Text"]:SetText(label)
    _G[cb:GetName() .. "Text"]:SetFontObject("GameFontHighlightSmall")
    cb:SetScript("OnClick", function(self) onClick(self:GetChecked() and true or false) Refresh() end)
    if tipTitle then Tip(cb, tipTitle, tipText) end
    return cb
end

local radioN = 0
local function Radio(label, x, y, onClick)
    radioN = radioN + 1
    local rb = CreateFrame("CheckButton", "ZBarMBRadio" .. radioN, p, "UIRadioButtonTemplate")
    rb:SetPoint("TOPLEFT", x, y)
    _G[rb:GetName() .. "Text"]:SetText(label)
    rb:SetScript("OnClick", function() onClick() Refresh() end)
    return rb
end

local function Drop(name, x, y, width, items, get, set)
    local dd = CreateFrame("Frame", name, p, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", x - 16, y)
    UIDropDownMenu_SetWidth(dd, width)
    UIDropDownMenu_Initialize(dd, function()
        local now = get()
        for _, it in ipairs(items) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = it[2]
            info.checked = now == it[1]
            info.func = function() set(it[1]) Refresh() end
            UIDropDownMenu_AddButton(info)
        end
    end)
    dd.items = items
    dd.get = get
    return dd
end

local function DropText(dd)
    local now = dd.get()
    for _, it in ipairs(dd.items) do
        if it[1] == now then UIDropDownMenu_SetText(dd, it[2]) return end
    end
end

local function Status(text, r, g, b)
    p.status:SetText(text or "")
    p.status:SetTextColor(r or 1, g or 0.82, b or 0)
end

local function Lines() return cur.lines end
local function Cond() -- the line whose targets / keys are edited
    if cur.mode == "sequence" then return cur.lines[1] end
    return cur.lines[sel]
end

Text("ZBar - Macro Builder", 16, -16, "GameFontNormalLarge")
Text("Click a macro together. It becomes a normal game macro (works in combat, goes on any button or "
    .. "Ctrl / Shift layer). ZBar remembers how it was built, so you can change it here later.", 16, -38, nil, 570)

-- macro choice, name, character / account
Text("Macro:", 16, -70, "GameFontNormalSmall")
local pick = CreateFrame("Frame", "ZBarMBMacroPick", p, "UIDropDownMenuTemplate")
pick:SetPoint("TOPLEFT", 40, -62)
UIDropDownMenu_SetWidth(pick, 130)

local function Load(name, perChar)
    local r = name and MB:Get(name, perChar)
    if r then
        cur = ns.DeepCopy(r)
        cur.savedAt = nil
        orig = { name = name, perChar = perChar }
    else
        cur = MB:NewRecipe()
        orig = nil
    end
    sel = 1
    Status("")
    Refresh()
end

UIDropDownMenu_Initialize(pick, function()
    local info = UIDropDownMenu_CreateInfo()
    info.text = "|cff8af559New macro|r"
    info.checked = orig == nil
    info.func = function() Load(nil) end
    UIDropDownMenu_AddButton(info)
    for _, m in ipairs(MB:List()) do
        info = UIDropDownMenu_CreateInfo()
        info.text = m.name .. (m.perChar and "" or "  |cff999999(account)|r")
            .. (MB:Find(m.name, m.perChar) and "" or "  |cffff4040(deleted)|r")
        info.checked = orig and orig.name == m.name and orig.perChar == m.perChar
        info.func = function() Load(m.name, m.perChar) end
        UIDropDownMenu_AddButton(info)
    end
end)

Text("Name:", 222, -70, "GameFontNormalSmall")
local nameBox = CreateFrame("EditBox", "ZBarMBName", p, "InputBoxTemplate")
nameBox:SetSize(116, 20)
nameBox:SetPoint("TOPLEFT", 262, -65)
nameBox:SetAutoFocus(false)
nameBox:SetMaxLetters(MAX_NAME)
nameBox:SetScript("OnTextChanged", function(self, user)
    if user then cur.name = self:GetText() end
end)
nameBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

local charRadio = Radio("Character", 392, -64, function() cur.perChar = true end)
local accRadio = Radio("Account", 482, -64, function() cur.perChar = false end)
Tip(charRadio, "Character macro", "Only this character has it (" .. MAX_CHARACTER .. " slots).")
Tip(accRadio, "Account macro", "Every character on this account has it (" .. MAX_ACCOUNT .. " slots).")

-- mode
local castRadio = Radio("Cast: the first spell that fits", 16, -94, function() cur.mode = "cast" end)
local seqRadio = Radio("Cast sequence", 224, -94, function() cur.mode = "sequence" end)
Tip(castRadio, "Cast", "Each press casts the first spell in the list whose conditions fit "
    .. "(e.g. enemy target: the attack, friendly target: the heal).")
Tip(seqRadio, "Cast sequence", "Each press casts the next spell of the list. The targets and keys of the "
    .. "first spell are used for the whole sequence.")
local resetText = Text("Reset:", 340, -98, "GameFontNormalSmall")
local resetTarget = Check("new target", 378, -94, function(v) cur.resetTarget = v end,
    "Reset on new target", "The sequence starts over when you change target.")
local resetCombat = Check("combat", 462, -94, function(v) cur.resetCombat = v end,
    "Reset after combat", "The sequence starts over when combat ends.")
local resetSecs = CreateFrame("EditBox", "ZBarMBResetSecs", p, "InputBoxTemplate")
resetSecs:SetSize(26, 20)
resetSecs:SetPoint("TOPLEFT", 534, -95)
resetSecs:SetAutoFocus(false)
resetSecs:SetNumeric(true)
resetSecs:SetMaxLetters(3)
resetSecs:SetScript("OnTextChanged", function(self, user)
    if user then cur.resetSecs = tonumber(self:GetText()) Refresh() end
end)
resetSecs:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
local resetSecsText = Text("s", 564, -99, "GameFontNormalSmall")
Tip(resetSecs, "Reset after seconds", "The sequence starts over when you have not pressed it for this long (empty: never).")

-- spell list
local listTitle = Text("", 16, -124, "GameFontNormal")
local addButton = Btn("Add Spell", 100, 480, -120, function()
    local max = MAX_LINES[cur.mode] or 4
    if #cur.lines >= max then return end
    cur.lines[#cur.lines + 1] = MB:NewLine()
    sel = #cur.lines
    Refresh()
end)

local rows = {}
for i = 1, 6 do
    local row = CreateFrame("Button", nil, p)
    row:SetSize(570, 20)
    row:SetPoint("TOPLEFT", 16, -144 - (i - 1) * 20)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row.sel = row:CreateTexture(nil, "BACKGROUND")
    row.sel:SetAllPoints()
    row.sel:SetTexture(1, 0.82, 0, 0.15)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(18, 18)
    row.icon:SetPoint("LEFT", 2, 0)
    row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.text:SetPoint("RIGHT", -74, 0)
    row.text:SetJustifyH("LEFT")
    row:SetScript("OnClick", function() sel = i Refresh() end)
    local function Small(text, x, fn, tip)
        local b = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        b:SetSize(22, 18)
        b:SetPoint("RIGHT", x, 0)
        b:SetText(text)
        b:SetScript("OnClick", fn)
        Tip(b, tip)
        return b
    end
    row.up = Small("^", -50, function()
        local l = cur.lines
        if i > 1 then l[i], l[i - 1] = l[i - 1], l[i] sel = i - 1 Refresh() end
    end, "Move up (tried earlier)")
    row.down = Small("v", -26, function()
        local l = cur.lines
        if i < #l then l[i], l[i + 1] = l[i + 1], l[i] sel = i + 1 Refresh() end
    end, "Move down (tried later)")
    row.del = Small("x", -2, function()
        table.remove(cur.lines, i)
        if sel > #cur.lines then sel = math.max(1, #cur.lines) end
        Refresh()
    end, "Remove")
    rows[i] = row
end
local emptyText = Text("No spells yet: click Add Spell.", 22, -148, "GameFontDisableSmall")

-- editor of the selected line
local edY = -272
local slot = CreateFrame("Button", "ZBarMBSlot", p)
slot:SetSize(26, 26)
slot:SetPoint("TOPLEFT", 16, edY)
slot.icon = slot:CreateTexture(nil, "ARTWORK")
slot.icon:SetAllPoints()
slot:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
local slotBorder = slot:CreateTexture(nil, "OVERLAY")
slotBorder:SetTexture("Interface\\Buttons\\UI-Quickslot2")
slotBorder:SetSize(46, 46)
slotBorder:SetPoint("CENTER")

local spellBox = CreateFrame("EditBox", "ZBarMBSpell", p, "InputBoxTemplate")
spellBox:SetSize(128, 20)
spellBox:SetPoint("TOPLEFT", 52, edY - 3)
spellBox:SetAutoFocus(false)

local function SetSpell(name)
    local line = cur.lines[sel]
    if not line then
        if #cur.lines >= (MAX_LINES[cur.mode] or 4) then return end
        cur.lines[#cur.lines + 1] = MB:NewLine()
        sel = #cur.lines
        line = cur.lines[sel]
    end
    line.name = name or ""
    Refresh()
end

local function DropOnSlot()
    local name = CursorName()
    if name then
        ClearCursor()
        SetSpell(name)
    end
end
slot:SetScript("OnReceiveDrag", DropOnSlot)
slot:SetScript("OnClick", function()
    if GetCursorInfo() then DropOnSlot() return end
    MB:OpenPicker(function(entry) SetSpell(entry.name) end, "Choose a spell or item")
end)
Tip(slot, "Spell", "Click: choose from a list. Or drag a spell from your spellbook (or an item) here.")
spellBox:SetScript("OnReceiveDrag", DropOnSlot)
spellBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
spellBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
spellBox:SetScript("OnTextChanged", function(self, user)
    if user and cur.lines[sel] then
        cur.lines[sel].name = self:GetText()
        Refresh(true)
    end
end)

local chooseButton = Btn("Choose...", 70, 186, edY - 2, function()
    MB:OpenPicker(function(entry) SetSpell(entry.name) end, "Choose a spell or item")
end)

local whoDrop = Drop("ZBarMBWho", 266, edY, 76,
    { { "any", "Any target" }, { "harm", "Enemy" }, { "help", "Friendly" } },
    function() local c = Cond() return c and (c.who or "any") or "any" end,
    function(v) local c = Cond() if c then c.who = (v ~= "any") and v or nil end end)
local modDrop = Drop("ZBarMBMod", 380, edY, 64,
    { { "none", "Any key" }, { "alt", "Alt held" }, { "ctrl", "Ctrl held" }, { "shift", "Shift held" }, { "nomod", "No key held" } },
    function() local c = Cond() return c and (c.mod or "none") or "none" end,
    function(v) local c = Cond() if c then c.mod = (v ~= "none") and v or nil end end)
local combatDrop = Drop("ZBarMBCombat", 482, edY, 80,
    { { "any", "Any time" }, { "combat", "In combat" }, { "nocombat", "Out of combat" } },
    function() local c = Cond() return c and (c.combat or "any") or "any" end,
    function(v) local c = Cond() if c then c.combat = (v ~= "any") and v or nil end end)

local tryText = Text("Try on:", 16, edY - 38, "GameFontNormalSmall")
local targetChecks = {}
local TARGETS = {
    { "mouseover", "Mouseover", 58, "The unit under your mouse (also on unit frames), if there is one." },
    { "focus", "Focus", 138, "Your focus, if you have one." },
    { "target", "Target", 194, "Your current target." },
    { "tot", "Target's target", 256, "Whoever your target is targeting (e.g. heal the tank your enemy hits)." },
    { "selfnt", "Me if no target", 372, "You have no target: the spell goes on you (like the game's Auto Self Cast). "
        .. "With an enemy target it is not cast on you." },
    { "self", "Me as fallback", 480, "Casts on you when nothing before it fits - also when your target is an enemy "
        .. "(only for spells that can go on you)." },
}
for _, t in ipairs(TARGETS) do
    targetChecks[t[1]] = Check(t[2], t[3], edY - 34, function(v)
        local c = Cond()
        if c then c[t[1]] = v or nil end
    end, t[2], t[4] .. " Checked ones are tried from left to right.")
end
local seqNote = Text("", 16, edY - 58, "GameFontDisableSmall", 570)

-- extras
local exY = -350
Text("Extras", 16, exY, "GameFontNormal")
local extraChecks = {}
local EXCLUSIVE = { targetmouse = "targetenemy", targetenemy = "targetmouse" }
local LABEL = {}
for _, x in ipairs(MB.EXTRAS) do LABEL[x[1]] = x[3] end
for i, x in ipairs(MB.EXTRAS) do
    local col, rowN = (i - 1) % 6, math.floor((i - 1) / 6)
    extraChecks[x[1]] = Check(x[3], 16 + col * 96, exY - 16 - rowN * 22, function(v)
        cur[x[1]] = v or nil
        -- Target mouse and Auto target fight each other: one turns the other off
        local other = EXCLUSIVE[x[1]]
        if v and other and cur[other] then
            cur[other] = nil
            Status("\"" .. LABEL[other] .. "\" turned off: it does not work together with \"" .. x[3] .. "\".")
        end
    end,
        x[3], x[4] .. "\n|cffaaaaaaAdds: " .. x[2] .. "|r")
end

-- preview
local pvY = -414
Text("Macro text", 16, pvY, "GameFontNormal")
local counter = Text("", 470, pvY, "GameFontNormal")
Text("Icon:", 120, pvY + 1, "GameFontNormalSmall")
local iconDrop = CreateFrame("Frame", "ZBarMBIcon", p, "UIDropDownMenuTemplate")
iconDrop:SetPoint("TOPLEFT", 136, pvY + 8)
UIDropDownMenu_SetWidth(iconDrop, 150)
UIDropDownMenu_Initialize(iconDrop, function()
    local info = UIDropDownMenu_CreateInfo()
    info.text = "Automatic (follows the spell)"
    info.checked = not MB:IconSpell(cur)
    info.func = function() cur.icon = nil Refresh() end
    UIDropDownMenu_AddButton(info)
    local seen = {}
    for _, line in ipairs(cur.lines) do
        local n = line.name
        if n and n ~= "" and not seen[n] then
            seen[n] = true
            info = UIDropDownMenu_CreateInfo()
            info.text = n
            info.icon = MB:Icon(n) or QUESTION
            info.checked = cur.icon == n
            info.func = function() cur.icon = n Refresh() end
            UIDropDownMenu_AddButton(info)
        end
    end
end)
Tip(iconDrop, "Macro icon", "Automatic: the button shows the spell the macro would cast now. "
    .. "Or pick one of its spells: the button always shows that icon (adds the spell's name to the first line).")
local box = CreateFrame("Frame", nil, p)
box:SetPoint("TOPLEFT", 16, pvY - 16)
box:SetSize(570, 76)
box:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
})
box:SetBackdropColor(0, 0, 0, 0.8)
box:SetBackdropBorderColor(0.5, 0.5, 0.5)
local preview = box:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
preview:SetPoint("TOPLEFT", 8, -7)
preview:SetPoint("BOTTOMRIGHT", -8, 6)
preview:SetJustifyH("LEFT")
preview:SetJustifyV("TOP")
p.preview = preview

-- buttons
local btY = -514
local saveButton = Btn("Save Macro", 110, 16, btY, function()
    local ok, msg = MB:Save(cur, orig)
    if ok then
        orig = { name = cur.name, perChar = cur.perChar and true or false }
        Status(msg, 0.54, 0.96, 0.35)
    else
        Status(msg, 1, 0.25, 0.25)
    end
    Refresh()
end)
local pickupButton = Btn("Pick Up", 90, 132, btY, function()
    if orig and MB:Pickup(orig.name, orig.perChar) then
        Status("Drop it on a button (hold Ctrl or Shift in Mode: Modifiers for a layer).")
    end
end)
Tip(pickupButton, "Pick Up", "Puts the saved macro on your cursor, so you can drop it on a button.")
local deleteButton = Btn("Delete", 80, 228, btY, function()
    if orig then StaticPopup_Show("ZBAR_DELETE_MACRO", orig.name) end
end)
Btn("New", 70, 314, btY, function() Load(nil) end)
p.status = Text("", 16, btY - 28, "GameFontNormalSmall", 570)

StaticPopupDialogs["ZBAR_DELETE_MACRO"] = {
    text = "ZBar: delete the macro \"%s\"? It is removed from the game's macros too.",
    button1 = DELETE or "Delete",
    button2 = CANCEL,
    OnShow = function(self) if ns.SolidPopupOn then ns.SolidPopupOn(self) end end,
    OnHide = function(self) if ns.SolidPopupOff then ns.SolidPopupOff(self) end end,
    OnAccept = function()
        if not orig then return end
        local ok, msg = MB:Delete(orig.name, orig.perChar)
        if ok then
            cur, orig, sel = MB:NewRecipe(), nil, 1
        end
        Status(msg, ok and 0.54 or 1, ok and 0.96 or 0.25, ok and 0.35 or 0.25)
        Refresh()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

local function Summary(line, i)
    local c = (cur.mode == "sequence") and cur.lines[1] or line
    local parts = {}
    if cur.mode ~= "sequence" or i == 1 then
        local who = c.who == "harm" and "Enemy" or c.who == "help" and "Friendly" or nil
        local on = {}
        for _, t in ipairs(TARGETS) do
            if c[t[1]] then
                on[#on + 1] = (t[1] == "self") and "me" or (t[1] == "selfnt") and "me if no target" or t[2]
            end
        end
        if who then parts[#parts + 1] = who end
        if #on > 0 then parts[#parts + 1] = table.concat(on, " > ") end
        if c.mod then parts[#parts + 1] = c.mod == "nomod" and "no key" or (c.mod:sub(1, 1):upper() .. c.mod:sub(2)) end
        if c.combat then parts[#parts + 1] = c.combat == "combat" and "in combat" or "out of combat" end
    end
    return table.concat(parts, " | ")
end

Refresh = function(keepSpellBox)
    if not ns.db then return end
    local max = MAX_LINES[cur.mode] or 4
    while #cur.lines > max do table.remove(cur.lines) end
    if sel > #cur.lines then sel = math.max(1, #cur.lines) end

    UIDropDownMenu_SetText(pick, orig and (orig.name .. (orig.perChar and "" or " (account)")) or "New macro")
    if not nameBox:HasFocus() then nameBox:SetText(cur.name or "") end
    charRadio:SetChecked(cur.perChar and true or false)
    accRadio:SetChecked(not cur.perChar)
    castRadio:SetChecked(cur.mode ~= "sequence")
    seqRadio:SetChecked(cur.mode == "sequence")
    local seq = cur.mode == "sequence"
    for _, w in ipairs({ resetText, resetTarget, resetCombat, resetSecs, resetSecsText }) do
        if seq then w:Show() else w:Hide() end
    end
    resetTarget:SetChecked(cur.resetTarget)
    resetCombat:SetChecked(cur.resetCombat)
    if not resetSecs:HasFocus() then resetSecs:SetText(cur.resetSecs and tostring(cur.resetSecs) or "") end

    listTitle:SetText(seq and ("Spells - one after the other (" .. #cur.lines .. "/" .. max .. ")")
        or ("Spells - top to bottom, the first that fits is cast (" .. #cur.lines .. "/" .. max .. ")"))
    if #cur.lines >= max then addButton:Disable() else addButton:Enable() end
    for i, row in ipairs(rows) do
        local line = cur.lines[i]
        if line then
            row.icon:SetTexture(MB:Icon(line.name) or QUESTION)
            local nm = (line.name ~= "" and line.name) or "|cff888888(choose a spell)|r"
            local sum = Summary(line, i)
            row.text:SetText(i .. ". " .. nm .. (sum ~= "" and ("   |cffaaaaaa" .. sum .. "|r") or ""))
            if i == sel then row.sel:Show() else row.sel:Hide() end
            if i > 1 then row.up:Enable() else row.up:Disable() end
            if i < #cur.lines then row.down:Enable() else row.down:Disable() end
            row:Show()
        else
            row:Hide()
        end
    end
    if #cur.lines == 0 then emptyText:Show() else emptyText:Hide() end

    -- editor
    local line = cur.lines[sel]
    local c = Cond()
    slot.icon:SetTexture((line and MB:Icon(line.name)) or QUESTION)
    if not keepSpellBox and not spellBox:HasFocus() then spellBox:SetText(line and line.name or "") end
    for _, dd in ipairs({ whoDrop, modDrop, combatDrop }) do
        DropText(dd)
        if c then UIDropDownMenu_EnableDropDown(dd) else UIDropDownMenu_DisableDropDown(dd) end
    end
    for key, cb in pairs(targetChecks) do
        cb:SetChecked(c and c[key])
        if c then cb:Enable() else cb:Disable() end
    end
    if seq then
        seqNote:SetText("Cast sequence: the targets and keys above are for the whole sequence.")
    elseif line and line.name ~= "" and not MB:Icon(line.name) then
        seqNote:SetText("|cffff4040\"" .. line.name .. "\" is not in your spellbook or bags - check the name, or use Choose...|r")
    else
        seqNote:SetText("")
    end

    for key, cb in pairs(extraChecks) do cb:SetChecked(cur[key]) end

    if cur.icon and not MB:IconSpell(cur) then cur.icon = nil end
    local iconSpell = MB:IconSpell(cur)
    UIDropDownMenu_SetText(iconDrop, iconSpell or "Automatic")
    local body = MB:Build(cur)
    preview:SetText(body ~= "" and body or "|cff888888(empty)|r")
    local n = #body
    counter:SetText((n > MAX_BODY and "|cffff4040" or (n > MAX_BODY - 20) and "|cffffd100" or "|cff8af559")
        .. n .. " / " .. MAX_BODY .. " characters|r")
    if n > MAX_BODY then saveButton:Disable() else saveButton:Enable() end
    if orig and MB:Find(orig.name, orig.perChar) then pickupButton:Enable() else pickupButton:Disable() end
    if orig then deleteButton:Enable() else deleteButton:Disable() end
end

function p:refresh() Refresh() end
p:SetScript("OnShow", function() Refresh() end)
p:SetScript("OnHide", function() if picker then picker:Hide() end end)
InterfaceOptions_AddCategory(p)
ns.MacroPanel = p

-- open a sub-panel (the first call may only expand ZBar in the list on 3.3.5)
function ns.OpenSubPanel(panel)
    InterfaceOptionsFrame_OpenToCategory(panel)
    InterfaceOptionsFrame_OpenToCategory(panel)
end
