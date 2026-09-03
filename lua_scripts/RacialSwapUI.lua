--=====================================================================
--  RacialSwapUI  -  Script de servidor (Eluna + AIO)
--  Sirve la UI al cliente via AIO usando 100% elementos nativos de WoW 3.3.5a
--  (No requiere parches MPQ ni archivos externos).
--  Abrir en el juego con:  /raciales  o  /rs  o  /racialswitch
--=====================================================================
local AIO = AIO or require("AIO")
local AIO_NAME = "RacialSwapUI"

-- ===== CONFIG (compartida cliente + servidor) ========================
local CATEGORY_ORDER  = { "utility", "passive", "weapon", "profession" }
local CATEGORY_TITLE  = {
    utility    = "Principal  (1)",
    passive    = "Pasivas  (2)",
    weapon     = "Armas  (1)",
    profession = "Profesion  (1)",
}
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
    for _, id in ipairs(list) do SPELL_TO_CATEGORY[id] = cat end
end

--=====================================================================
--  ===============  LADO SERVIDOR  ==================================
--=====================================================================
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
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    local function GetSavedSelection(player)
        local saved = {}
        local result = CharDBQuery(string.format(
            "SELECT spell FROM character_racial_selection WHERE guid = %u ORDER BY category, spell",
            player:GetGUIDLow()
        ))
        if not result then return nil end

        repeat
            local id = result:GetUInt32(0)
            if SPELL_TO_CATEGORY[id] then saved[#saved + 1] = id end
        until not result:NextRow()
        return saved
    end

    local function SaveSelection(player, wanted)
        local guid = player:GetGUIDLow()
        CharDBExecute(string.format("DELETE FROM character_racial_selection WHERE guid = %u", guid))
        for id in pairs(wanted) do
            CharDBExecute(string.format(
                "INSERT INTO character_racial_selection (guid, spell, category) VALUES (%u, %u, '%s')",
                guid, id, SPELL_TO_CATEGORY[id] or "utility"
            ))
        end
    end

    _G.OpenRacialSwapUI = function(player)
        if not player then return end
        AIO.Handle(player, AIO_NAME, "Show", GetSavedSelection(player) or {})
    end

    function Handlers.Request(player)
        if not player then return end
        _G.OpenRacialSwapUI(player)
    end

    function Handlers.Apply(player, selected)
        if not player or type(selected) ~= "table" then return end
        if player:IsInCombat() then
            player:SendBroadcastMessage("|cFFFF0000No puedes cambiar raciales mientras estas en combate.|r")
            return
        end

        local validated = {}
        local counts = { utility = 0, passive = 0, weapon = 0, profession = 0 }

        for _, spellId in ipairs(selected) do
            local cat = SPELL_TO_CATEGORY[spellId]
            if cat and counts[cat] < CATEGORY_LIMITS[cat] then
                counts[cat] = counts[cat] + 1
                validated[spellId] = true
            end
        end

        for id in pairs(SPELL_TO_CATEGORY) do
            if player:HasSpell(id) and not validated[id] then
                player:RemoveSpell(id)
            end
        end

        for id in pairs(validated) do
            if not player:HasSpell(id) then
                player:LearnSpell(id)
            end
        end

        SaveSelection(player, validated)
        player:SendBroadcastMessage("|cFF00FF00Tus rasgos raciales han sido actualizados con exito.|r")
        AIO.Handle(player, AIO_NAME, "OnApplied")
    end

    local function OnCommand(event, player, command)
        local c = string.lower(command or "")
        if c == "rs" or c == "raciales" or c == "racialswitch" then
            _G.OpenRacialSwapUI(player)
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

--=====================================================================
--  ===============  LADO CLIENTE  (Nativo WoW 3.3.5a via AIO) =======
--=====================================================================
local Handlers = AIO.AddHandlers(AIO_NAME, {})

local isSpanish = GetLocale():find("es")
local TEXT = isSpanish and {
    title = "Rasgos Raciales",
    subtitle = "Elige tus raciales por categoria",
    apply = "Aplicar",
    reset = "Restablecer",
    close = "Cerrar",
    selected = "Seleccionado",
    available = "Puntos restantes",
    utility = "Principal",
    passive = "Pasivas",
    weapon = "Armas",
    profession = "Profesion",
} or {
    title = "Racial Traits",
    subtitle = "Choose your racial abilities by category",
    apply = "Apply",
    reset = "Reset",
    close = "Close",
    selected = "Selected",
    available = "Points remaining",
    utility = "Primary",
    passive = "Passives",
    weapon = "Weapons",
    profession = "Profession",
}

local selectedSpells = {}
local btnList = {}

-- Main Window Frame (Native Blizzard Dialog Frame Style)
local f = CreateFrame("Frame", "RacialSwapMainFrame", UIParent)
f:SetSize(720, 520)
f:SetPoint("CENTER")
f:SetFrameStrata("DIALOG")
f:SetToplevel(true)
f:EnableMouse(true)
f:SetMovable(true)
f:SetClampedToScreen(true)
f:RegisterForDrag("LeftButton")
f:SetScript("OnDragStart", f.StartMoving)
f:SetScript("OnDragStop", f.StopMovingOrSizing)
f:Hide()
tinsert(UISpecialFrames, "RacialSwapMainFrame")

-- Backdrop using standard Blizzard textures
f:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 }
})

-- Header Banner Plate
local header = f:CreateTexture(nil, "ARTWORK")
header:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
header:SetWidth(320)
header:SetHeight(64)
header:SetPoint("TOP", f, "TOP", 0, 12)

local headerText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
headerText:SetPoint("TOP", header, "TOP", 0, -14)
headerText:SetText(TEXT.title)
headerText:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")

-- Close 'X' Button
local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)

-- Column layout for 4 categories
local colWidth = 165
local colStartX = 25
local startY = -65

local colIcons = {
    utility = "Interface\\Icons\\Spell_Holy_MagicalSentry",
    passive = "Interface\\Icons\\Spell_Holy_DevotionAura",
    weapon = "Interface\\Icons\\INV_Sword_04",
    profession = "Interface\\Icons\\Trade_Engineering",
}

local categoryCounters = {}

for idx, cat in ipairs(CATEGORY_ORDER) do
    local colX = colStartX + (idx - 1) * colWidth

    -- Category Header Icon + Text
    local catIcon = f:CreateTexture(nil, "ARTWORK")
    catIcon:SetSize(22, 22)
    catIcon:SetPoint("TOPLEFT", f, "TOPLEFT", colX, startY)
    catIcon:SetTexture(colIcons[cat] or "Interface\\Icons\\INV_Misc_QuestionMark")

    local catTitle = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    catTitle:SetPoint("LEFT", catIcon, "RIGHT", 6, 0)
    catTitle:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    catTitle:SetText(CATEGORY_TITLE[cat])

    -- Counter text
    local counter = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    counter:SetPoint("TOPLEFT", catIcon, "BOTTOMLEFT", 0, -4)
    counter:SetTextColor(0, 1, 0)
    categoryCounters[cat] = counter

    -- Vertical list of spells in 3 mini columns per category
    local spells = CATEGORY_SPELLS[cat] or {}
    for sIdx, spellId in ipairs(spells) do
        local subCol = (sIdx - 1) % 3
        local subRow = math.floor((sIdx - 1) / 3)

        local btnX = colX + subCol * 48
        local btnY = (startY - 35) - subRow * 48

        local btn = CreateFrame("Button", nil, f)
        btn:SetSize(40, 40)
        btn:SetPoint("TOPLEFT", f, "TOPLEFT", btnX, btnY)

        local icon = btn:CreateTexture(nil, "BACKGROUND")
        icon:SetAllPoints()
        local name, _, spellIcon = GetSpellInfo(spellId)
        icon:SetTexture(spellIcon or "Interface\\Icons\\INV_Misc_QuestionMark")
        btn.icon = icon
        btn.spellId = spellId
        btn.category = cat

        -- Blizzard Slot Border Texture
        local border = btn:CreateTexture(nil, "OVERLAY")
        border:SetSize(58, 58)
        border:SetPoint("CENTER")
        border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
        btn.border = border

        -- Selected Green Glow
        local glow = btn:CreateTexture(nil, "OVERLAY")
        glow:SetSize(46, 46)
        glow:SetPoint("CENTER")
        glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
        glow:SetBlendMode("ADD")
        glow:SetVertexColor(0, 1, 0, 1)
        glow:Hide()
        btn.glow = glow

        -- Rank counter in corner (like talent rank)
        local rankText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        rankText:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
        rankText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
        rankText:SetText("0")
        rankText:SetTextColor(0.5, 0.5, 0.5)
        btn.rankText = rankText

        -- Tooltip
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink("spell:" .. self.spellId)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        -- Click handler (Left click toggle)
        btn:SetScript("OnClick", function(self)
            local spell = self.spellId
            local c = self.category
            if selectedSpells[spell] then
                selectedSpells[spell] = nil
                PlaySound("igMainMenuOptionCheckBoxOff")
            else
                local currentCount = 0
                for s in pairs(selectedSpells) do
                    if SPELL_TO_CATEGORY[s] == c then
                        currentCount = currentCount + 1
                    end
                end

                if currentCount < CATEGORY_LIMITS[c] then
                    selectedSpells[spell] = true
                    PlaySound("igMainMenuOptionCheckBoxOn")
                else
                    PlaySound("TellMessage")
                end
            end
            _G.UpdateRacialDisplay()
        end)

        btnList[#btnList + 1] = btn
    end
end

function _G.UpdateRacialDisplay()
    for _, btn in ipairs(btnList) do
        local isSel = selectedSpells[btn.spellId]
        if isSel then
            btn.glow:Show()
            btn.icon:SetDesaturated(false)
            btn.rankText:SetText("1")
            btn.rankText:SetTextColor(0, 1, 0)
        else
            btn.glow:Hide()
            btn.icon:SetDesaturated(false)
            btn.rankText:SetText("0")
            btn.rankText:SetTextColor(0.5, 0.5, 0.5)
        end
    end

    for _, cat in ipairs(CATEGORY_ORDER) do
        local count = 0
        for s in pairs(selectedSpells) do
            if SPELL_TO_CATEGORY[s] == cat then
                count = count + 1
            end
        end
        local limit = CATEGORY_LIMITS[cat]
        categoryCounters[cat]:SetText(string.format("%d / %d", count, limit))
        if count == limit then
            categoryCounters[cat]:SetTextColor(0, 1, 0)
        else
            categoryCounters[cat]:SetTextColor(1, 0.82, 0)
        end
    end
end

-- Bottom Action Buttons (Blizzard Button Template)
local applyBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
applyBtn:SetSize(130, 26)
applyBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -25, 20)
applyBtn:SetText(TEXT.apply)
applyBtn:SetScript("OnClick", function()
    local list = {}
    for id in pairs(selectedSpells) do
        list[#list + 1] = id
    end
    AIO.Handle(AIO_NAME, "Apply", list)
end)

local resetBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
resetBtn:SetSize(130, 26)
resetBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 25, 20)
resetBtn:SetText(TEXT.reset)
resetBtn:SetScript("OnClick", function()
    selectedSpells = {}
    _G.UpdateRacialDisplay()
    PlaySound("igMainMenuOptionCheckBoxOff")
end)

function Handlers.Show(player, saved)
    selectedSpells = {}
    if type(saved) == "table" then
        for _, id in ipairs(saved) do
            selectedSpells[id] = true
        end
    end
    _G.UpdateRacialDisplay()
    f:Show()
    PlaySound("igTalentScreenOpen")
end

function Handlers.OnApplied()
    PlaySound("SPELL_MAGIC_AURA_END")
end
