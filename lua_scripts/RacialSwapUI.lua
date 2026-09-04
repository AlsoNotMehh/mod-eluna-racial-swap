local AIO = AIO or require("AIO")
local AIO_NAME = "RacialSwapUI"

local CATEGORY_ORDER  = { "utility", "passive", "weapon", "profession" }
local CATEGORY_LIMITS = { utility = 1, passive = 2, weapon = 1, profession = 1 }
local CATEGORY_SPELLS = {
    utility    = { 59752, 20572, 20594, 58984, 20549, 7744, 20577, 26297, 28730, 59542, 2481, 20589 },
    passive    = { 20592, 20596, 20579, 20551, 822, 20573, 65222, 20555, 58943,
                   20550, 20591, 5227, 6562, 20582, 20585, 58985, 20599, 20598 },
    weapon     = { 26290, 20595, 59224, 20597, 20558 },
    profession = { 20593, 20552, 28877 },
}

local SPELL_TO_CATEGORY = {}
for cat, list in pairs(CATEGORY_SPELLS) do
    for _, id in ipairs(list) do
        SPELL_TO_CATEGORY[id] = cat
    end
end

-- ============================================================================
-- Server Side
-- ============================================================================
if AIO.AddAddon() then
    local Handlers = AIO.AddHandlers(AIO_NAME, {})

    CharDBExecute([[
    CREATE TABLE IF NOT EXISTS `character_racial_selection` (
        `guid` INT UNSIGNED NOT NULL,
        `spell` INT UNSIGNED NOT NULL,
        `category` VARCHAR(16) NOT NULL,
        `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (`guid`, `spell`),
        KEY `idx_character_racial_selection_category` (`guid`, `category`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    local function GetSavedSelection(player)
        local saved = {}
        local result = CharDBQuery(
            "SELECT spell FROM character_racial_selection WHERE guid = ? ORDER BY category, spell",
            player:GetGUIDLow()
        )
        if not result then return nil end

        repeat
            local id = result:GetUInt32(0)
            if SPELL_TO_CATEGORY[id] then
                saved[#saved + 1] = id
            end
        until not result:NextRow()
        return saved
    end

    local function SaveSelection(player, wanted)
        local guid = player:GetGUIDLow()
        CharDBExecute("DELETE FROM character_racial_selection WHERE guid = ?", guid)
        for id in pairs(wanted) do
            CharDBExecute(
                "INSERT INTO character_racial_selection (guid, spell, category) VALUES (?, ?, ?)",
                guid, id, SPELL_TO_CATEGORY[id]
            )
        end
    end

    _G.OpenRacialSwapUI = function(player)
        if not player then return end
        AIO.Handle(player, AIO_NAME, "Show", GetSavedSelection(player) or {})
    end

    function Handlers.Request(player)
        if not player then return end
        if player:GetGMRank() == 0 then return end
        _G.OpenRacialSwapUI(player)
    end

    function Handlers.Apply(player, selected)
        if not player or type(selected) ~= "table" then return end

        if player:IsInCombat() then
            player:SendBroadcastMessage("|cffff5555No puedes cambiar raciales en combate.|r")
            AIO.Handle(player, AIO_NAME, "Show", GetSavedSelection(player) or {})
            return
        end

        local toLearn = {}
        for _, cat in ipairs(CATEGORY_ORDER) do
            local list = selected[cat]
            if type(list) ~= "table" then
                player:SendBroadcastMessage("|cffff5555Debes seleccionar todos los puntos raciales requeridos.|r")
                return
            end

            local n = 0
            for _, id in ipairs(list) do
                if SPELL_TO_CATEGORY[id] == cat then
                    n = n + 1
                    toLearn[#toLearn + 1] = id
                else
                    return
                end
            end
            if n ~= (CATEGORY_LIMITS[cat] or 0) then
                player:SendBroadcastMessage("|cffff5555Debes seleccionar todos los puntos raciales requeridos.|r")
                return
            end
        end

        local wanted = {}
        for _, id in ipairs(toLearn) do wanted[id] = true end

        for id in pairs(SPELL_TO_CATEGORY) do
            if player:HasSpell(id) and not wanted[id] then
                player:RemoveSpell(id)
            end
        end
        for id in pairs(wanted) do
            if not player:HasSpell(id) then
                player:LearnSpell(id)
            end
        end

        SaveSelection(player, wanted)
        player:SaveToDB()
        AIO.Handle(player, AIO_NAME, "Applied")
    end

    local function OnCommand(event, player, command)
        local c = string.lower(command or "")
        if c == "rs" or c == "raciales" then
            if player:GetGMRank() > 0 then
                _G.OpenRacialSwapUI(player)
            end
            return false
        end
    end
    RegisterPlayerEvent(42, OnCommand)

    local function OnLogin(event, player)
        local saved = GetSavedSelection(player)
        if saved and #saved > 0 then
            local wanted = {}
            for _, id in ipairs(saved) do wanted[id] = true end

            for id in pairs(SPELL_TO_CATEGORY) do
                if player:HasSpell(id) and not wanted[id] then
                    player:RemoveSpell(id)
                end
            end
            for id in pairs(wanted) do
                if not player:HasSpell(id) then
                    player:LearnSpell(id)
                end
            end
        end
    end
    RegisterPlayerEvent(3, OnLogin)

    return
end

-- ============================================================================
-- Client Side (AIO)
-- ============================================================================
local Handlers = AIO.AddHandlers(AIO_NAME, {})

local locale = GetLocale()
local isSpanish = locale == "esES" or locale == "esMX"
local TEXT = isSpanish and {
    title = "Cambio de Raciales",
    apply = "Aplicar cambios",
    maxExceeded = "Ya has seleccionado el maximo en esta categoria.",
    needAll = "Debes gastar todos los puntos raciales.",
} or {
    title = "Racial Swap",
    apply = "Apply Changes",
    maxExceeded = "You have already selected the maximum in this category.",
    needAll = "You must spend all racial points.",
}

local selected = {}
local countSel = {}
for _, cat in ipairs(CATEGORY_ORDER) do
    selected[cat] = {}
    countSel[cat] = 0
end

local btnList = {}
local groupCounterFS = {}

local f = CreateFrame("Frame", "RacialSwapFrame", UIParent)
f:SetWidth(470)
f:SetHeight(360)
f:SetPoint("CENTER")
f:SetFrameStrata("DIALOG")
f:SetToplevel(true)
f:EnableMouse(true)
f:SetMovable(true)
f:SetClampedToScreen(true)
f:RegisterForDrag("LeftButton")
f:SetScript("OnDragStart", f.StartMoving)
f:SetScript("OnDragStop", f.StopMovingOrSizing)
f:SetScript("OnShow", function() PlaySound("igTalentScreenOpen") end)
f:SetScript("OnHide", function() PlaySound("igTalentScreenClose") end)
f:Hide()
tinsert(UISpecialFrames, "RacialSwapFrame")

f:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 32, edgeSize = 16,
    insets = { left = 5, right = 5, top = 5, bottom = 5 }
})
f:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)

local titleText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
titleText:SetPoint("TOP", f, "TOP", 0, -15)
titleText:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
titleText:SetText(TEXT.title)
titleText:SetTextColor(1.0, 0.82, 0.0)

local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
closeBtn:SetWidth(28)
closeBtn:SetHeight(28)
closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)

local GROUP_CONFIG = {
    utility    = { cols = 2, xOffset = 25 },
    passive    = { cols = 3, xOffset = 115 },
    weapon     = { cols = 2, xOffset = 245 },
    profession = { cols = 2, xOffset = 345 },
}

local ICON_SIZE = 34
local GAP_X = 6
local GAP_Y = 6
local START_Y = -68

for _, cat in ipairs(CATEGORY_ORDER) do
    local cfg = GROUP_CONFIG[cat]
    local spells = CATEGORY_SPELLS[cat]
    local groupWidth = cfg.cols * ICON_SIZE + (cfg.cols - 1) * GAP_X

    local counter = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    counter:SetPoint("TOPLEFT", f, "TOPLEFT", cfg.xOffset, -42)
    counter:SetWidth(groupWidth)
    counter:SetJustifyH("CENTER")
    counter:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
    counter:SetText("0")
    counter:SetTextColor(0.8, 0.8, 0.8)
    groupCounterFS[cat] = counter

    for idx, spellId in ipairs(spells) do
        local col = (idx - 1) % cfg.cols
        local row = math.floor((idx - 1) / cfg.cols)

        local btnX = cfg.xOffset + col * (ICON_SIZE + GAP_X)
        local btnY = START_Y - row * (ICON_SIZE + GAP_Y)

        local btn = CreateFrame("Button", nil, f)
        btn:SetWidth(ICON_SIZE)
        btn:SetHeight(ICON_SIZE)
        btn:SetPoint("TOPLEFT", f, "TOPLEFT", btnX, btnY)
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

        local icon = btn:CreateTexture(nil, "BACKGROUND")
        icon:SetAllPoints()
        local _, _, spellIcon = GetSpellInfo(spellId)
        icon:SetTexture(spellIcon or "Interface\\Icons\\INV_Misc_QuestionMark")
        btn.icon = icon
        btn.spellId = spellId
        btn.category = cat

        local border = btn:CreateTexture(nil, "OVERLAY")
        border:SetWidth(ICON_SIZE + 14)
        border:SetHeight(ICON_SIZE + 14)
        border:SetPoint("CENTER")
        border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
        btn.border = border

        local glow = btn:CreateTexture(nil, "OVERLAY")
        glow:SetWidth(ICON_SIZE + 6)
        glow:SetHeight(ICON_SIZE + 6)
        glow:SetPoint("CENTER")
        glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
        glow:SetBlendMode("ADD")
        glow:SetVertexColor(0, 1, 0, 1)
        glow:Hide()
        btn.glow = glow

        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink("spell:" .. self.spellId)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        btn:SetScript("OnClick", function(self, button)
            local spell = self.spellId
            local c = self.category

            if button == "RightButton" then
                if selected[c][spell] then
                    selected[c][spell] = nil
                    countSel[c] = math.max(0, countSel[c] - 1)
                    PlaySound("igMainMenuOptionCheckBoxOff")
                end
            else
                if selected[c][spell] then
                    selected[c][spell] = nil
                    countSel[c] = math.max(0, countSel[c] - 1)
                    PlaySound("igMainMenuOptionCheckBoxOff")
                else
                    if countSel[c] < CATEGORY_LIMITS[c] then
                        selected[c][spell] = true
                        countSel[c] = countSel[c] + 1
                        PlaySound("igMainMenuOptionCheckBoxOn")
                    else
                        UIErrorsFrame:AddMessage(TEXT.maxExceeded, 1.0, 0.1, 0.1, 1.0)
                        PlaySound("TellMessage")
                    end
                end
            end
            _G.RefreshRacialUI()
        end)

        btnList[#btnList + 1] = btn
    end
end

local applyBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
applyBtn:SetWidth(140)
applyBtn:SetHeight(24)
applyBtn:SetPoint("BOTTOM", f, "BOTTOM", 0, 16)
applyBtn:SetText(TEXT.apply)

applyBtn:SetScript("OnClick", function()
    local payload = {}
    for _, cat in ipairs(CATEGORY_ORDER) do
        payload[cat] = {}
        for id in pairs(selected[cat]) do
            table.insert(payload[cat], id)
        end
        if #payload[cat] ~= CATEGORY_LIMITS[cat] then
            UIErrorsFrame:AddMessage(TEXT.needAll, 1.0, 0.1, 0.1, 1.0)
            PlaySound("TellMessage")
            return
        end
    end
    PlaySound("igQuestListComplete")
    AIO.Handle(AIO_NAME, "Apply", payload)
end)

function _G.RefreshRacialUI()
    for _, btn in ipairs(btnList) do
        local isSel = selected[btn.category][btn.spellId]
        if isSel then
            btn.glow:Show()
            btn.icon:SetDesaturated(false)
        else
            btn.glow:Hide()
            btn.icon:SetDesaturated(false)
        end
    end

    local allFilled = true
    for _, cat in ipairs(CATEGORY_ORDER) do
        local count = countSel[cat] or 0
        local limit = CATEGORY_LIMITS[cat]
        groupCounterFS[cat]:SetText(tostring(count))
        if count > 0 then
            groupCounterFS[cat]:SetTextColor(0.1, 1.0, 0.1)
        else
            groupCounterFS[cat]:SetTextColor(0.8, 0.8, 0.8)
        end
        if count ~= limit then
            allFilled = false
        end
    end

    if allFilled then
        applyBtn:Enable()
    else
        applyBtn:Disable()
    end
end

function Handlers.Show(player, saved)
    if type(player) == "table" and not player.Add and saved == nil then
        saved = player
    end

    for _, cat in ipairs(CATEGORY_ORDER) do
        selected[cat] = {}
        countSel[cat] = 0
    end

    if type(saved) == "table" then
        for _, id in ipairs(saved) do
            local cat = SPELL_TO_CATEGORY[id]
            if cat and (countSel[cat] < CATEGORY_LIMITS[cat]) then
                selected[cat][id] = true
                countSel[cat] = countSel[cat] + 1
            end
        end
    end

    _G.RefreshRacialUI()
    f:Show()
end

function Handlers.Applied()
    PlaySound("SPELL_MAGIC_AURA_END")
    f:Hide()
end
