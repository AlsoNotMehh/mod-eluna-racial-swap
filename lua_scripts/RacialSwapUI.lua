--=====================================================================
--  RacialSwapUI  -  UN SOLO script de servidor (Eluna) que sirve la UI
--  al cliente via AIO.  No requiere addon de cliente (solo AIO).
--  Abrir en el juego con:  /raciales     (o comando de chat  .rs )
--=====================================================================
local AIO = AIO or require("AIO")
local AIO_NAME = "RacialSwapUI"

-- ===== CONFIG (compartida cliente + servidor) ========================
local CATEGORY_ORDER  = { "utility", "passive", "weapon", "profession" }
local CATEGORY_TITLE  = {
    utility    = "Racial principal  (elige 1)",
    passive    = "Pasivas  (elige 2)",
    weapon     = "Especializacion de arma  (elige 1)",
    profession = "Profesion  (elige 1)",
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

    -- Los hechizos se guardan normalmente en character_spell; esta tabla
    -- conserva la configuracion elegida en la interfaz.
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

    local function GetKnownManaged(player)
        local known = {}
        for id in pairs(SPELL_TO_CATEGORY) do
            if player:HasSpell(id) then known[#known + 1] = id end
        end
        return known
    end

    local function GetSavedSelection(player)
        local saved = {}
        local result = CharDBQuery(
            "SELECT spell FROM character_racial_selection WHERE guid = ? ORDER BY category, spell",
            player:GetGUIDLow()
        )
        if not result then return nil end

        repeat
            local id = result:GetUInt32(0)
            if SPELL_TO_CATEGORY[id] then saved[#saved + 1] = id end
        until not result:NextRow()
        return saved
    end

    local function SaveSelection(player, wanted)
        local guid = player:GetGUIDLow()

        -- Cinco filas como maximo; se reemplaza la configuracion completa para
        -- que nunca queden selecciones antiguas o duplicadas.
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
                player:SendBroadcastMessage("|cffff5555Debes gastar todos los puntos raciales.|r")
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
                player:SendBroadcastMessage("|cffff5555Debes gastar todos los puntos raciales.|r")
                return
            end
        end

        -- Aplicar solamente la diferencia. Las raciales que el jugador ya
        -- conserva no se desaprenden ni se vuelven a aprender.
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
    RegisterPlayerEvent(3, OnLogin) -- PLAYER_EVENT_ON_LOGIN

    return
end

--=====================================================================
--  ===============  LADO CLIENTE  (servido por AIO)  ================
--=====================================================================
local Handlers = AIO.AddHandlers(AIO_NAME, {})

local locale = GetLocale()
local isSpanish = locale == "esES" or locale == "esMX"
local TEXT = isSpanish and {
    title = "Raciales",
    available = "PUNTOS RACIALES DISPONIBLES",
    apply = "Aplicar cambios",
    utility = "Principal",
    passive = "Pasivas",
    weapon = "Armas",
    profession = "Profesion",
    choose = "Click izquierdo: seleccionar",
    remove = "Click derecho: retirar",
    full = "Ya elegiste el maximo en esta categoria.",
} or {
    title = "Racials",
    available = "RACIAL POINTS AVAILABLE",
    apply = "Apply Changes",
    utility = "Primary",
    passive = "Passives",
    weapon = "Weapons",
    profession = "Profession",
    choose = "Left click: select",
    remove = "Right click: remove",
    full = "You already selected the maximum in this category.",
}

local selected = {}
local initialSelected = {}
local countSel = {}
for _, cat in ipairs(CATEGORY_ORDER) do
    selected[cat] = {}
    initialSelected[cat] = {}
    countSel[cat] = 0
end

local btnList = {}
local groupCounterFS = {}
local UpdateCounters, RefreshHighlights
local apply, reset

-- ---- Layout moderno sin scroll: cuatro grupos de dos columnas ----
local ICON, GAPX, GAPY = 42, 14, 7
local GROUP_COLS = {
    utility = 2, passive = 2, weapon = 2, profession = 2,
}
local GROUP_GAP = 44
local MARGIN = 20

local groupInfo = {}
local contentW, maxRows = 558, 0
local totalGroupsW = 0
for _, cat in ipairs(CATEGORY_ORDER) do
    local cols  = GROUP_COLS[cat] or 1
    local rows  = math.ceil(#CATEGORY_SPELLS[cat] / cols)
    local width = cols * ICON + (cols - 1) * GAPX
    groupInfo[cat] = { cols = cols, rows = rows, width = width }
    totalGroupsW = totalGroupsW + width
    if rows > maxRows then maxRows = rows end
end
totalGroupsW = totalGroupsW + GROUP_GAP * (#CATEGORY_ORDER - 1)
MARGIN = math.floor((contentW - totalGroupsW) / 2)
local iconAreaH = maxRows * ICON + (maxRows - 1) * GAPY

-- ---- Marco principal compartido con el Spellbook/Talentos modernos ----
local f = CreateFrame(
    "Frame", "RacialSwapFrame", UIParent, "PortraitFrame2X"
)
f:SetSize(640, 625)
f:SetPoint("CENTER")
f:SetFrameStrata("DIALOG")
f:SetToplevel(true)
f:EnableMouse(true)
f:SetMovable(true)
f:SetClampedToScreen(true)
f:RegisterForDrag("LeftButton")
f:SetScript("OnDragStart", f.StartMoving)
f:SetScript("OnDragStop", f.StopMovingOrSizing)
f:SetScript("OnShow", function()
    PlaySound("igTalentScreenOpen")
end)
f:SetScript("OnHide", function()
    PlaySound("igTalentScreenClose")
end)
f:Hide()
tinsert(UISpecialFrames, "RacialSwapFrame")

f.TitleText = f.TitleText or _G.RacialSwapFrameTitleText
if f.TitleText then
    f.TitleText:SetText("")
end
if type(ApplyModernSystemFrameSkin) == "function" then
    ApplyModernSystemFrameSkin(f)
end
if f.MaximizeMinimizeButton then
    f.MaximizeMinimizeButton:Hide()
end
if f.ModernSystemBackground then
    f.ModernSystemBackground:Hide()
end
if f.ModernSystemTopBar then
    f.ModernSystemTopBar:SetDrawLayer("ARTWORK", -1)
end
if f.TitleText then
    f.TitleText:SetText("")
    f.TitleText:Hide()
end

local portrait = f.portrait or
    (f.PortraitFrame and
        (f.PortraitFrame.Portrait or f.PortraitFrame.portrait)) or
    _G.RacialSwapFramePortrait
local capturedNpcPortrait

local function CopyGossipPortrait()
    local source = _G.GossipFramePortrait
    if not portrait or not source or not source.GetTexture then
        return false
    end
    local texture = source:GetTexture()
    if not texture then return false end
    portrait:SetTexture(texture)
    portrait:SetTexCoord(source:GetTexCoord())
    capturedNpcPortrait = true
    return true
end

local function UpdateNpcPortrait()
    if not portrait then return end
    portrait:SetTexCoord(0, 1, 0, 1)
    if UnitExists("npc") then
        SetPortraitTexture(portrait, "npc")
        capturedNpcPortrait = true
    elseif CopyGossipPortrait() then
        return
    elseif UnitExists("target") and not UnitIsPlayer("target") then
        SetPortraitTexture(portrait, "target")
        capturedNpcPortrait = true
    elseif not capturedNpcPortrait then
        portrait:SetTexture("Interface\\LFGFrame\\UI-LFG-PORTRAIT")
    end
end
UpdateNpcPortrait()

-- Pergamino usado por el buscador de Mazmorra aleatoria de WoW.
local contentBackground = f:CreateTexture(nil, "BACKGROUND")
contentBackground:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
contentBackground:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
contentBackground:SetTexture(
    "Interface\\LFGFrame\\UI-LFG-BACKGROUND-QUESTPAPER"
)
-- El BLP mide 512x256, pero el pergamino visible termina en x=326.
-- Recortar el tramo transparente permite cubrir todo el panel sin huecos.
contentBackground:SetTexCoord(0, 0.63671875, 0, 1)
contentBackground:SetVertexColor(1, 1, 1, 1)

local npcPortraitWatcher = CreateFrame("Frame", nil, f)
npcPortraitWatcher:RegisterEvent("GOSSIP_SHOW")
npcPortraitWatcher:SetScript("OnEvent", function()
    UpdateNpcPortrait()
end)

local availableTitle = f:CreateFontString(
    nil, "OVERLAY", "GameFontHighlight"
)
availableTitle:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
availableTitle:SetPoint("TOP", f, "TOP", 0, -40)
availableTitle:SetText(TEXT.available)
availableTitle:SetTextColor(0.82, 0.85, 0.88)

local iconContainer = CreateFrame("Frame", nil, f)
iconContainer:SetSize(contentW, iconAreaH + 8)
iconContainer:SetPoint("TOP", f, "TOP", 0, -115)

-- Boton Aplicar de Retail construido por segmentos para no deformar bordes.
apply = CreateFrame("Button", nil, f)
apply:SetSize(164, 22)
apply:SetPoint("BOTTOM", f, "BOTTOM", 0, 33)
local RETAIL_BUTTON = "Interface\\CustomTalents\\Buttons\\apply-"
apply.slices = {}

local applyLeft = apply:CreateTexture(nil, "ARTWORK")
applyLeft:SetWidth(12)
applyLeft:SetPoint("TOPLEFT")
applyLeft:SetPoint("BOTTOMLEFT")
applyLeft:SetTexCoord(0, 0.09375, 0, 0.6875)
apply.slices[1] = applyLeft

local applyRight = apply:CreateTexture(nil, "ARTWORK")
applyRight:SetWidth(12)
applyRight:SetPoint("TOPRIGHT")
applyRight:SetPoint("BOTTOMRIGHT")
applyRight:SetTexCoord(0.53125, 0.625, 0, 0.6875)
apply.slices[2] = applyRight

local applyMiddle = apply:CreateTexture(nil, "ARTWORK")
applyMiddle:SetPoint("TOPLEFT", applyLeft, "TOPRIGHT")
applyMiddle:SetPoint("BOTTOMRIGHT", applyRight, "BOTTOMLEFT")
applyMiddle:SetTexCoord(0.09375, 0.53125, 0, 0.6875)
apply.slices[3] = applyMiddle

apply.Text = apply:CreateFontString(nil, "OVERLAY", "GameFontNormal")
apply.Text:SetPoint("CENTER", 0, 1)
apply.Text:SetText(TEXT.apply)

local function SetApplyVisual(state)
    local texturePath = RETAIL_BUTTON .. state .. ".blp"
    for _, texture in ipairs(apply.slices) do
        texture:SetTexture(texturePath)
    end
    if state == "disabled" then
        apply.Text:SetTextColor(0.5, 0.5, 0.5)
    elseif state == "highlight" then
        apply.Text:SetTextColor(1, 1, 1)
    else
        apply.Text:SetTextColor(1, 0.82, 0)
    end
end
apply:SetScript("OnEnable", function() SetApplyVisual("up") end)
apply:SetScript("OnDisable", function() SetApplyVisual("disabled") end)
apply:SetScript("OnEnter", function(self)
    if self:IsEnabled() == 1 then SetApplyVisual("highlight") end
end)
apply:SetScript("OnLeave", function(self)
    SetApplyVisual(self:IsEnabled() == 1 and "up" or "disabled")
end)
apply:SetScript("OnMouseDown", function(self)
    if self:IsEnabled() == 1 then SetApplyVisual("down") end
end)
apply:SetScript("OnMouseUp", function(self)
    if self:IsEnabled() == 1 then
        SetApplyVisual(self:IsMouseOver() and "highlight" or "up")
    end
end)
SetApplyVisual("disabled")

reset = CreateFrame("Button", nil, f)
reset:SetSize(25, 25)
reset:SetPoint("LEFT", apply, "RIGHT", 14, 0)
reset:SetNormalTexture(
    "Interface\\CustomTalents\\Buttons\\undo.tga"
)
reset:SetPushedTexture(
    "Interface\\CustomTalents\\Buttons\\undo.tga"
)
reset:SetDisabledTexture(
    "Interface\\CustomTalents\\Buttons\\undo.tga"
)
reset:GetDisabledTexture():SetVertexColor(0.35, 0.35, 0.35)
reset:SetHighlightTexture(
    "Interface\\CustomTalents\\Buttons\\undo.tga", "ADD"
)

-- ---- Logica ----
local function HasSelectionChanged()
    for _, cat in ipairs(CATEGORY_ORDER) do
        for id in pairs(selected[cat]) do
            if not initialSelected[cat][id] then return true end
        end
        for id in pairs(initialSelected[cat]) do
            if not selected[cat][id] then return true end
        end
    end
    return false
end

function UpdateCounters()
    local allPointsSpent = true
    for _, cat in ipairs(CATEGORY_ORDER) do
        local limit = CATEGORY_LIMITS[cat] or 0
        local available = math.max(0, limit - countSel[cat])
        if available > 0 then allPointsSpent = false end

        local cfs = groupCounterFS[cat]
        if cfs then
            cfs:SetText(available)
            if available > 0 then
                cfs:SetTextColor(0.3, 1.0, 0.3)
            else
                cfs:SetTextColor(0.55, 0.55, 0.55)
            end
        end
    end
    local changed = HasSelectionChanged()
    if allPointsSpent and changed then
        apply:Enable()
    else
        apply:Disable()
    end
    if changed then reset:Enable() else reset:Disable() end
end

function RefreshHighlights()
    for _, b in ipairs(btnList) do
        if selected[b.cat][b.spellId] then
            b.tex:SetDesaturated(false)
            b.selectionBorder:Show()
        elseif countSel[b.cat] < (CATEGORY_LIMITS[b.cat] or 0) then
            b.tex:SetDesaturated(false)
            b.selectionBorder:Hide()
        else
            b.tex:SetDesaturated(true)
            b.selectionBorder:Hide()
        end
    end
    UpdateCounters()
end

-- click izq = seleccionar ; click der = deseleccionar
local function OnIconClick(self, mouseButton)
    local sel = selected[self.cat]
    if mouseButton == "RightButton" then
        if sel[self.spellId] then
            sel[self.spellId] = nil
            countSel[self.cat] = countSel[self.cat] - 1
            PlaySound("igTalentScreenUndoChanges")
            RefreshHighlights()
        end
    else
        if not sel[self.spellId] then
            if countSel[self.cat] >= (CATEGORY_LIMITS[self.cat] or 0) then
                UIErrorsFrame:AddMessage(TEXT.full, 1, 0.2, 0.2)
                return
            end
            sel[self.spellId] = true
            countSel[self.cat] = countSel[self.cat] + 1
            PlaySound("igTalentScreenSpendPoint")
            RefreshHighlights()
        end
    end
end

-- ---- Construir iconos redondos y contadores por categoria ----
local xCursor = MARGIN
for gi, cat in ipairs(CATEGORY_ORDER) do
    local info = groupInfo[cat]
    local centerX = xCursor + info.width / 2

    local categoryLabel = f:CreateFontString(
        nil, "OVERLAY", "GameFontNormalSmall"
    )
    categoryLabel:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
    categoryLabel:SetPoint(
        "TOP", f, "TOPLEFT", 41 + centerX, -67
    )
    categoryLabel:SetText(TEXT[cat])

    local cnt = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    cnt:SetFont("Fonts\\FRIZQT__.TTF", 20, "OUTLINE")
    cnt:SetPoint(
        "TOP", f, "TOPLEFT", 41 + centerX, -86
    )
    groupCounterFS[cat] = cnt

    local vi = 0
    for _, spellId in ipairs(CATEGORY_SPELLS[cat]) do
        local name, _, icon = GetSpellInfo(spellId)
        if name and icon then
            local col = math.floor(vi / info.rows)
            local row = vi % info.rows

            local btn = CreateFrame("Button", nil, iconContainer)
            btn:SetSize(ICON, ICON)
            btn:SetPoint(
                "TOPLEFT", iconContainer, "TOPLEFT",
                xCursor + col * (ICON + GAPX),
                -row * (ICON + GAPY)
            )
            btn.cat, btn.spellId = cat, spellId
            btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

            local bg = btn:CreateTexture(nil, "BACKGROUND")
            bg:SetSize(40, 40)
            bg:SetPoint("CENTER")
            bg:SetTexture(0.01, 0.01, 0.01, 0.95)

            local tex = btn:CreateTexture(nil, "ARTWORK")
            tex:SetSize(37, 37)
            tex:SetPoint("CENTER")
            tex:SetTexture(icon)
            tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            tex:SetDesaturated(true)
            btn.tex = tex

            local silverBorder = CreateFrame(
                "Frame", nil, btn,
                BackdropTemplateMixin and "BackdropTemplate"
            )
            silverBorder:SetPoint("TOPLEFT", btn, "TOPLEFT", -2, 2)
            silverBorder:SetPoint(
                "BOTTOMRIGHT", btn, "BOTTOMRIGHT", 2, -2
            )
            silverBorder:SetBackdrop({
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                edgeSize = 11,
            })
            silverBorder:SetBackdropBorderColor(
                0.76, 0.78, 0.82, 1
            )
            silverBorder:SetFrameLevel(btn:GetFrameLevel() + 1)
            btn.silverBorder = silverBorder

            local selectionBorder = CreateFrame(
                "Frame", nil, btn,
                BackdropTemplateMixin and "BackdropTemplate"
            )
            selectionBorder:SetPoint(
                "TOPLEFT", btn, "TOPLEFT", -5, 5
            )
            selectionBorder:SetPoint(
                "BOTTOMRIGHT", btn, "BOTTOMRIGHT", 5, -5
            )
            selectionBorder:SetBackdrop({
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                edgeSize = 14,
            })
            selectionBorder:SetBackdropBorderColor(
                1.0, 0.82, 0.0, 1
            )
            selectionBorder:SetFrameLevel(btn:GetFrameLevel() + 2)
            selectionBorder:Hide()
            btn.selectionBorder = selectionBorder

            btn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink("spell:"..self.spellId)
                GameTooltip:AddLine(" ")
                if selected[self.cat][self.spellId] then
                    GameTooltip:AddLine(TEXT.remove, 1.0, 0.25, 0.2)
                else
                    GameTooltip:AddLine(TEXT.choose, 0.2, 1.0, 0.2)
                end
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function(self)
                GameTooltip:Hide()
            end)
            btn:SetScript("OnClick", OnIconClick)

            tinsert(btnList, btn)
            vi = vi + 1
        end
    end

    -- separador vertical sutil entre grupos
    if gi < #CATEGORY_ORDER then
        local sep = iconContainer:CreateTexture(nil, "ARTWORK")
        sep:SetTexture(1, 1, 1)
        sep:SetAlpha(0.10)
        sep:SetSize(1, iconAreaH)
        sep:SetPoint(
            "TOPLEFT", iconContainer, "TOPLEFT",
            xCursor + info.width + GROUP_GAP / 2, 0
        )
    end

    xCursor = xCursor + info.width + GROUP_GAP
end

reset:SetScript("OnClick", function()
    for _, cat in ipairs(CATEGORY_ORDER) do
        selected[cat] = {}
        countSel[cat] = 0
        for id in pairs(initialSelected[cat]) do
            selected[cat][id] = true
            countSel[cat] = countSel[cat] + 1
        end
    end
    PlaySound("igTalentScreenUndoChanges")
    RefreshHighlights()
end)

apply:SetScript("OnClick", function()
    for _, cat in ipairs(CATEGORY_ORDER) do
        if countSel[cat] < (CATEGORY_LIMITS[cat] or 0) then
            return
        end
    end

    PlaySound("igTalentScreenApplyChanges")
    local data = {}
    for _, cat in ipairs(CATEGORY_ORDER) do
        data[cat] = {}
        for id in pairs(selected[cat]) do tinsert(data[cat], id) end
    end
    AIO.Handle(AIO_NAME, "Apply", data)
    f:Hide()
end)

function Handlers.Show(_, known)
    for _, cat in ipairs(CATEGORY_ORDER) do
        selected[cat] = {}
        initialSelected[cat] = {}
        countSel[cat] = 0
    end
    if type(known) == "table" then
        for _, id in ipairs(known) do
            local cat = SPELL_TO_CATEGORY[id]
            if cat and countSel[cat] < (CATEGORY_LIMITS[cat] or 0) then
                selected[cat][id] = true
                initialSelected[cat][id] = true
                countSel[cat] = countSel[cat] + 1
            end
        end
    end
    UpdateNpcPortrait()
    RefreshHighlights()
    f:Show()
end

function Handlers.Applied()
end

SLASH_RACIALSWAP1 = "/raciales"
SLASH_RACIALSWAP2 = "/racials"
SlashCmdList["RACIALSWAP"] = function()
    if f:IsShown() then
        f:Hide()
    else
        AIO.Handle(AIO_NAME, "Request")
    end
end
