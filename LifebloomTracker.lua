local ADDON_NAME = ...
local RESTO_SPEC_ID = 105
local LIFEBLOOM_SPELL_ID = 33763
local LIFEBLOOM_SPELL_NAME

local L = {}
L.RESET_POS       = "Frame position reset to default"
L.NOT_FOUND       = "Lifebloom not found"
L.SETTINGS_TITLE  = "LifebloomTracker"
L.SOUND_ENABLE    = "Sound Alert"
L.SOUND_ENABLE_TT = "Play a sound when Lifebloom is about to expire"
L.SOUND_CHOICE    = "Alert Sound"
L.SOUND_CHOICE_TT = "Choose a sound (click to preview)"
L.LOCK_FRAME      = "Lock frame"
L.LOCK_FRAME_TT   = "Prevent the frame from being moved with the mouse"
L.ATTACH_CURSOR   = "Attach to cursor"
L.ATTACH_CURSOR_TT = "Make the tracker follow your mouse cursor instead of staying in a fixed position"

local DB_DEFAULTS = {
    soundEnabled  = true,
    soundID       = 232418,
    soundName     = "Sonar Ping",
    soundIsLSM    = false,
    lockFrame     = false,
    attachToCursor = false,
}

local BUILTIN_SOUNDS = {
    { id = 316525, label = "Water Drop Synth" },
    { id = 232418, label = "Sonar Ping"       },
}

local db
local LSM
local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)

local function GetCurrentSoundLabel()
    if not db then return "?" end
    return db.soundName or DB_DEFAULTS.soundName
end

local function PlayAlertSound()
    if not db or not db.soundEnabled then return end
    if db.soundIsLSM and LSM then
        local path = LSM:Fetch("sound", db.soundName)
        if path then
            if type(path) == "number" then
                PlaySound(path, "Master")
            else
                PlaySoundFile(path, "Master")
            end
        end
    else
        PlaySound(db.soundID, "Master")
    end
end

local PLAYER_CLASS = select(2, UnitClass("player"))
local isEligible = false

local function IsRestoDruid()
    if PLAYER_CLASS ~= "DRUID" then return false end
    return PlayerUtil.GetCurrentSpecID() == RESTO_SPEC_ID
end

local frame = CreateFrame("Frame", "LifebloomTrackerFrame", UIParent)
frame:SetSize(60, 60)
frame:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
frame:SetClampedToScreen(true)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

local function ApplyFrameLock(locked)
    if locked then
        frame:SetScript("OnDragStart", nil)
    else
        frame:SetScript("OnDragStart", frame.StartMoving)
    end
end

local iconFrame = CreateFrame("Frame", nil, frame)
iconFrame:SetAllPoints()

local iconTex = iconFrame:CreateTexture(nil, "ARTWORK")
iconTex:SetSize(56, 56)
iconTex:SetPoint("CENTER")
iconTex:SetTexture("Interface\\Icons\\Spell_Nature_Lifebloom")
iconTex:SetTexCoord(0.1, 0.9, 0.1, 0.9)

local blackBorderFrame = CreateFrame("Frame", nil, iconFrame)
blackBorderFrame:SetAllPoints(iconTex)
blackBorderFrame:SetFrameLevel(iconFrame:GetFrameLevel() + 1)
blackBorderFrame:Hide()

local blackBorders = {
    {points = {"TOPLEFT", "TOPRIGHT"}, size = "Height"},
    {points = {"BOTTOMLEFT", "BOTTOMRIGHT"}, size = "Height"},
    {points = {"TOPLEFT", "BOTTOMLEFT"}, size = "Width"},
    {points = {"TOPRIGHT", "BOTTOMRIGHT"}, size = "Width"},
}

for _, borderData in ipairs(blackBorders) do
    local edge = blackBorderFrame:CreateTexture(nil, "OVERLAY")
    edge:SetColorTexture(0, 0, 0, 1)
    edge:SetPoint(borderData.points[1], 0, 0)
    edge:SetPoint(borderData.points[2], 0, 0)
    edge["Set" .. borderData.size](edge, 1)
end

local redBorderFrame = CreateFrame("Frame", nil, iconFrame)
redBorderFrame:SetPoint("TOPLEFT", iconTex, "TOPLEFT", -3, 3)
redBorderFrame:SetPoint("BOTTOMRIGHT", iconTex, "BOTTOMRIGHT", 3, -3)
redBorderFrame:SetFrameLevel(iconFrame:GetFrameLevel() + 2)
redBorderFrame:Hide()

local redBorders = {}
local redBorderData = {
    {points = {"TOPLEFT", "TOPRIGHT"}, size = "Height"},
    {points = {"BOTTOMLEFT", "BOTTOMRIGHT"}, size = "Height"},
    {points = {"TOPLEFT", "BOTTOMLEFT"}, size = "Width"},
    {points = {"TOPRIGHT", "BOTTOMRIGHT"}, size = "Width"},
}

for _, borderData in ipairs(redBorderData) do
    local edge = redBorderFrame:CreateTexture(nil, "OVERLAY")
    edge:SetColorTexture(0.9, 0.1, 0.1, 0)
    edge:SetPoint(borderData.points[1], 0, 0)
    edge:SetPoint(borderData.points[2], 0, 0)
    edge["Set" .. borderData.size](edge, 3)
    redBorders[#redBorders + 1] = edge
end

iconFrame.redBorders = redBorders

local function SetRedBorderAlpha(alpha)
    for _, edge in ipairs(iconFrame.redBorders) do
        edge:SetAlpha(alpha)
    end
end

local stackText = iconFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
stackText:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", -2, 4)
stackText:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
stackText:SetShadowColor(0, 0, 0, 0)
stackText:SetTextColor(1, 1, 0)
stackText:SetText("")

local timerText = iconFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
timerText:SetPoint("CENTER", iconFrame, "CENTER", 0, 0)
timerText:SetFont("Fonts\\FRIZQT__.TTF", 20, "OUTLINE")
timerText:SetShadowColor(0, 0, 0, 0)
timerText:SetTextColor(1, 1, 1)
timerText:SetText("")

local warnOverlay = frame:CreateTexture(nil, "OVERLAY")
warnOverlay:SetAllPoints()
warnOverlay:SetColorTexture(1, 0, 0, 0)

local warnAlpha, warnDir = 0, 1
local warnSoundPlayed = false

local function ApplyFrameSize(isSmall)
    if isSmall then
        frame:SetSize(40, 40)
        iconTex:SetSize(36, 36)
        stackText:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
        timerText:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    else
        frame:SetSize(60, 60)
        iconTex:SetSize(56, 56)
        stackText:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
        timerText:SetFont("Fonts\\FRIZQT__.TTF", 20, "OUTLINE")
    end
end

local cachedUnits = { "player", "target", "focus", "mouseover" }
local LIFEBLOOM_BASE_DURATION = 15

local function RebuildUnitsCache()
    cachedUnits = { "player", "target", "focus", "mouseover" }
    if IsInRaid() then
        for i = 1, 40 do cachedUnits[#cachedUnits + 1] = "raid" .. i end
    elseif IsInGroup() then
        for i = 1, 4 do cachedUnits[#cachedUnits + 1] = "party" .. i end
    end
end

local function FindMyLifebloom()
    for _, unit in ipairs(cachedUnits) do
        if UnitExists(unit) then
            local aura = C_UnitAuras.GetAuraDataBySpellName(unit, LIFEBLOOM_SPELL_NAME, "HELPFUL")
            if aura and aura.sourceUnit == "player" then
                return {
                    name   = UnitName(unit) or unit,
                    unit   = unit,
                    stacks = math.max(aura.applications or 0, 1),
                    expire = aura.expirationTime or 0,
                    dur    = aura.duration or LIFEBLOOM_BASE_DURATION,
                    icon   = aura.icon,
                }
            end
        end
    end
    return nil
end

local function UpdateVisibility()
    if isEligible then
        frame:Show()
    else
        frame:Hide()
    end
end

-- Full rescan + UI reset — used when toggling settings
local function RefreshDisplay()
    currentData = FindMyLifebloom()
    if currentData then
        local d = currentData
        if d.icon then iconTex:SetTexture(d.icon) end
        iconTex:SetDesaturated(false)
        blackBorderFrame:Show()
        redBorderFrame:Show()
        stackText:SetText(tostring(d.stacks))
        if d.stacks == 1 then     stackText:SetTextColor(0.8, 0.251, 0.251)
        elseif d.stacks == 2 then stackText:SetTextColor(1, 0.933, 0.373)
        else                      stackText:SetTextColor(0.286, 0.686, 0.298) end
    else
        iconTex:SetDesaturated(true)
        blackBorderFrame:Show()
        redBorderFrame:Hide()
        stackText:SetText("")
        timerText:SetText("")
        SetRedBorderAlpha(0)
        warnOverlay:SetColorTexture(1, 0, 0, 0)
        if LCG then
            LCG.ProcGlow_Start(iconFrame)
        end
    end
    UpdateVisibility()
end

local currentData = nil
local scanTick = 0
local uiTick = 0

frame:SetScript("OnUpdate", function(self, elapsed)
    if not isEligible then return end

    if db and db.attachToCursor then
        local scale = UIParent:GetEffectiveScale()
        local x, y = GetCursorPosition()
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale + 25, y / scale + 25)
    end

    scanTick = scanTick + elapsed
    if scanTick >= 0.25 then
        scanTick = 0
        local newData = FindMyLifebloom()
        local hadBuff = currentData ~= nil
        local hasBuff = newData ~= nil

        -- update icon/stacks only when something actually changed
        if newData then
            if not currentData
                or newData.unit   ~= currentData.unit
                or newData.stacks ~= currentData.stacks then
                if newData.icon then iconTex:SetTexture(newData.icon) end
                iconTex:SetDesaturated(false)
                blackBorderFrame:Show()
                redBorderFrame:Show()
                if LCG then
                    LCG.ProcGlow_Stop(iconFrame)
                end
                stackText:SetText(tostring(newData.stacks))
                if newData.stacks == 1 then     stackText:SetTextColor(0.8, 0.251, 0.251)
                elseif newData.stacks == 2 then stackText:SetTextColor(1, 0.933, 0.373)
                else                            stackText:SetTextColor(0.286, 0.686, 0.298) end
            end
        elseif hadBuff then
            -- buff just disappeared, reset static elements once
            iconTex:SetDesaturated(true)
            blackBorderFrame:Show()
            redBorderFrame:Hide()
            stackText:SetText("")
            SetRedBorderAlpha(0)
            if LCG then
                LCG.ProcGlow_Start(iconFrame)
            end
        end

        currentData = newData

        -- update frame visibility when buff appears or disappears
        if hasBuff ~= hadBuff then
            UpdateVisibility()
        end
    end

    local now = GetTime()
    local d = currentData
    local warnSecs = 3.5 -- pandemic range + extra time to account for human response i suppose

    if d then
        local rem = d.expire - now

        -- fast-path expiry check: when under 1s, verify the aura every frame
        -- so the frame disappears the moment the buff actually drops
        if rem <= 1 then
            local live = FindMyLifebloom()
            -- Only clear if: no live buff AND the scan hasn't already
            -- replaced d with fresh data (i.e. currentData still == d).
            if not live and currentData == d then
                currentData = nil
                iconTex:SetDesaturated(true)
                iconTex:SetVertexColor(1, 1, 1)
                blackBorderFrame:Show()
                redBorderFrame:Hide()
                timerText:SetText("")
                warnSoundPlayed = false
                warnAlpha = 0; warnDir = 1
                warnOverlay:SetColorTexture(1, 0, 0, 0)
                SetRedBorderAlpha(0)
                stackText:SetText("")
                if LCG then
                    LCG.ProcGlow_Start(iconFrame)
                end
                UpdateVisibility()
                return
            end
        end

        if rem > 0 then
            if LCG then
                LCG.ProcGlow_Stop(iconFrame)
            end

            if rem <= warnSecs then
                if not warnSoundPlayed then
                    PlayAlertSound()
                    warnSoundPlayed = true
                end
                warnAlpha = warnAlpha + elapsed * 2.5 * warnDir
                if warnAlpha >= 0.85 then warnDir = -1
                elseif warnAlpha <= 0  then warnDir = 1 end
                warnOverlay:SetColorTexture(1, 0, 0, warnAlpha)
                local redTint = 1 - (warnAlpha * 0.6)
                iconTex:SetVertexColor(1, redTint, redTint)
                SetRedBorderAlpha(1)
            else
                warnSoundPlayed = false
                warnAlpha = 0; warnDir = 1
                warnOverlay:SetColorTexture(1, 0, 0, 0)
                iconTex:SetVertexColor(1, 1, 1)
                SetRedBorderAlpha(0)
            end

            uiTick = uiTick + elapsed
            if uiTick >= 0.1 then
                uiTick = 0
                local ratio = rem / LIFEBLOOM_BASE_DURATION

                if ratio <= 0.25 then
                    timerText:SetText(string.format("%.1f", rem))
                    timerText:SetTextColor(0.8, 0.251, 0.251)
                elseif ratio > 0.5 then
                    timerText:SetText(string.format("%.0f", rem))
                    timerText:SetTextColor(0.9, 0.9, 0.9)
                else
                    timerText:SetText(string.format("%.0f", rem))
                    timerText:SetTextColor(1, 0.933, 0.373)
                end
            end
        else
            -- Timer hit zero. Only clear if the scan also sees no buff —
            -- avoids wiping a freshly-recast Lifebloom that the scan
            -- already picked up while our stale snapshot says rem<=0.
            if not currentData or currentData == d then
                currentData = nil
                iconTex:SetDesaturated(true)
                iconTex:SetVertexColor(1, 1, 1)
                blackBorderFrame:Show()
                redBorderFrame:Hide()
                timerText:SetText("")
                warnSoundPlayed = false
                warnAlpha = 0; warnDir = 1
                warnOverlay:SetColorTexture(1, 0, 0, 0)
                SetRedBorderAlpha(0)
                stackText:SetText("")
                if LCG then
                    LCG.ProcGlow_Start(iconFrame)
                end
                UpdateVisibility()
            end
        end
    else
        warnSoundPlayed = false
        timerText:SetText("")
        warnAlpha = 0; warnDir = 1
        warnOverlay:SetColorTexture(1, 0, 0, 0)
        iconTex:SetVertexColor(1, 1, 1)
    end
end)

local settingsCategory
local soundPickerBtn

local function BuildSoundPicker(onSelect)
    local function StripColors(s)
        return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
    end

    local DDW = 205
    local ddFrame = CreateFrame("Frame", "LBTSoundDD", UIParent)
    ddFrame:SetSize(DDW, 32)
    ddFrame:Hide()

    local ddLeft = ddFrame:CreateTexture(nil, "ARTWORK")
    ddLeft:SetTexture("Interface\\Glues\\CharacterCreate\\CharacterCreate-LabelFrame")
    ddLeft:SetSize(25, 64)
    ddLeft:SetPoint("LEFT", ddFrame, "LEFT", 0, 0)
    ddLeft:SetTexCoord(0, 0.1953125, 0, 1)

    local ddMid = ddFrame:CreateTexture(nil, "ARTWORK")
    ddMid:SetTexture("Interface\\Glues\\CharacterCreate\\CharacterCreate-LabelFrame")
    ddMid:SetPoint("LEFT", ddLeft, "RIGHT", 0, 0)
    ddMid:SetPoint("RIGHT", ddFrame, "RIGHT", -25, 0)
    ddMid:SetHeight(64)
    ddMid:SetTexCoord(0.1953125, 0.8046875, 0, 1)

    local ddRight = ddFrame:CreateTexture(nil, "ARTWORK")
    ddRight:SetTexture("Interface\\Glues\\CharacterCreate\\CharacterCreate-LabelFrame")
    ddRight:SetSize(25, 64)
    ddRight:SetPoint("RIGHT", ddFrame, "RIGHT", 0, 0)
    ddRight:SetTexCoord(0.8046875, 1, 0, 1)

    local ddText = ddFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ddText:SetPoint("LEFT",  ddFrame, "LEFT",  27, 2)
    ddText:SetPoint("RIGHT", ddFrame, "RIGHT", -43, 2)
    ddText:SetJustifyH("LEFT")
    ddText:SetText(StripColors(GetCurrentSoundLabel()))

    local ddBtn = CreateFrame("Button", nil, ddFrame)
    ddBtn:SetSize(24, 24)
    ddBtn:SetPoint("RIGHT", ddFrame, "RIGHT", -16, 0)
    local ddArrow = ddBtn:CreateTexture(nil, "ARTWORK")
    ddArrow:SetAllPoints()
    ddArrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    ddFrame:EnableMouse(true)

    local POPUP_W        = DDW + 10
    local ROW_H          = 16
    local MAX_POPUP_H    = 280
    local MIN_POPUP_H    = 60
    local VISIBLE_ROWS   = math.floor(MAX_POPUP_H / ROW_H)

    local popup = CreateFrame("Frame", "LBTSoundPopup", UIParent, "BackdropTemplate")
    popup:SetSize(POPUP_W, MAX_POPUP_H)
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetFrameLevel(200)
    popup:SetClampedToScreen(true)
    popup:Hide()
    popup:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    popup:SetBackdropColor(0.04, 0.04, 0.04, 1)
    popup:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)

    local clickCatcher = CreateFrame("Frame", nil, UIParent)
    clickCatcher:SetAllPoints(UIParent)
    clickCatcher:SetFrameStrata("FULLSCREEN_DIALOG")
    clickCatcher:SetFrameLevel(199)
    clickCatcher:EnableMouse(true)
    clickCatcher:Hide()
    clickCatcher:SetScript("OnMouseDown", function()
        popup:Hide()
        clickCatcher:Hide()
    end)
    popup:SetScript("OnHide", function() clickCatcher:Hide() end)

    popup:SetPropagateKeyboardInput(false)
    popup:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            popup:Hide()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)

    local clipFrame = CreateFrame("Frame", nil, popup)
    clipFrame:SetPoint("TOPLEFT",     popup, "TOPLEFT",      5,  -5)
    clipFrame:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -14,  5)

    local SCROLL_W     = POPUP_W - 20
    local scrollOffset = 0
    local entries      = {}
    local rowBtns      = {}

    local function BuildEntryList()
        local list = {}
        list[#list+1] = { isHeader = true, text = "Built-in Sounds" }
        for _, s in ipairs(BUILTIN_SOUNDS) do
            list[#list+1] = { isLSM = false, id = s.id, text = s.label, display = s.label }
        end
        if LSM then
            local names = LSM:List("sound")
            if names then
                local sorted = {}
                for _, n in ipairs(names) do sorted[#sorted+1] = n end
                table.sort(sorted, function(a, b)
                    return StripColors(a):lower() < StripColors(b):lower()
                end)
                list[#list+1] = { isHeader = true, text = "SharedMedia" }
                for _, name in ipairs(sorted) do
                    list[#list+1] = { isLSM = true, text = name, display = StripColors(name) }
                end
            end
        end
        return list
    end

    local function RefreshRows()
        for i = 1, VISIBLE_ROWS do
            local ei  = scrollOffset + i
            local e   = entries[ei]
            local btn = rowBtns[i]
            if not e then
                btn:Hide()
            elseif e.isHeader then
                btn:Show()
                btn:EnableMouse(false)
                btn.label:SetText(e.text)
                btn.label:SetFontObject("GameFontDisableSmall")
                btn.bg:SetColorTexture(0, 0, 0, 0)
            else
                btn:Show()
                btn:EnableMouse(true)
                btn.label:SetText(e.display)
                btn.label:SetFontObject("GameFontHighlightSmall")
                btn.bg:SetColorTexture(0, 0, 0, 0)
                btn:SetScript("OnClick", function()
                    if e.isLSM then
                        db.soundIsLSM = true
                        db.soundName  = e.text
                        local path = LSM:Fetch("sound", e.text)
                        if path then
                            if type(path) == "number" then
                                PlaySound(path, "Master")
                            else
                                PlaySoundFile(path, "Master")
                            end
                        end
                    else
                        db.soundIsLSM = false
                        db.soundID    = e.id
                        db.soundName  = e.display
                        PlayAlertSound()
                    end
                    ddText:SetText(StripColors(GetCurrentSoundLabel()))
                    if onSelect then onSelect(StripColors(GetCurrentSoundLabel())) end
                    popup:Hide()
                    RefreshRows()
                end)
            end
        end
        for i = #entries + 1, #rowBtns do rowBtns[i]:Hide() end
    end

    for i = 1, VISIBLE_ROWS do
        local btn = CreateFrame("Button", nil, clipFrame)
        btn:SetSize(SCROLL_W, ROW_H)
        btn:SetPoint("TOPLEFT", clipFrame, "TOPLEFT", 0, -(i-1)*ROW_H)

        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0)
        btn.bg = bg

        local hl = btn:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.08)

        local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("LEFT",  btn, "LEFT",  6, 0)
        lbl:SetPoint("RIGHT", btn, "RIGHT", -2, 0)
        lbl:SetJustifyH("LEFT")
        btn.label = lbl

        rowBtns[i] = btn
    end

    local sbW      = 8
    local sbTrackH = MAX_POPUP_H - 10

    local scrollbar = CreateFrame("Frame", nil, popup)
    scrollbar:SetSize(sbW, sbTrackH)
    scrollbar:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -3, -5)

    local sbBg = scrollbar:CreateTexture(nil, "BACKGROUND")
    sbBg:SetAllPoints()
    sbBg:SetColorTexture(0, 0, 0, 0.4)

    local thumb = CreateFrame("Button", nil, scrollbar)
    thumb:SetWidth(sbW - 2)
    local thumbTex = thumb:CreateTexture(nil, "ARTWORK")
    thumbTex:SetAllPoints()
    thumbTex:SetColorTexture(0.6, 0.6, 0.6, 0.7)

    local function UpdateScrollbar()
        local total  = #entries
        local maxOff = math.max(0, total - VISIBLE_ROWS)
        if maxOff == 0 then thumb:Hide() return end
        thumb:Show()
        local thumbH   = math.max(20, math.floor(sbTrackH * VISIBLE_ROWS / total))
        local thumbTop = scrollOffset / maxOff * (sbTrackH - thumbH)
        thumb:SetSize(sbW - 2, thumbH)
        thumb:SetPoint("TOP", scrollbar, "TOP", 0, -thumbTop)
    end

    local function ScrollBy(delta)
        local maxOff = math.max(0, #entries - VISIBLE_ROWS)
        scrollOffset = math.max(0, math.min(maxOff, scrollOffset + delta))
        RefreshRows()
        UpdateScrollbar()
    end

    popup:EnableMouseWheel(true)
    popup:SetScript("OnMouseWheel", function(_, d) ScrollBy(-d * 3) end)
    clipFrame:EnableMouseWheel(true)
    clipFrame:SetScript("OnMouseWheel", function(_, d) ScrollBy(-d * 3) end)

    local isDragging, dragStartY, dragStartOff = false, 0, 0
    thumb:SetScript("OnMouseDown", function(_, b)
        if b == "LeftButton" then
            isDragging   = true
            dragStartY   = select(2, GetCursorPosition()) / UIParent:GetEffectiveScale()
            dragStartOff = scrollOffset
        end
    end)
    thumb:SetScript("OnMouseUp",  function() isDragging = false end)
    thumb:SetScript("OnUpdate", function()
        if not isDragging then return end
        local cy     = select(2, GetCursorPosition()) / UIParent:GetEffectiveScale()
        local maxOff = math.max(0, #entries - VISIBLE_ROWS)
        if maxOff == 0 then return end
        local newOff = math.floor(dragStartOff + (dragStartY - cy) / (sbTrackH - thumb:GetHeight()) * maxOff + 0.5)
        newOff = math.max(0, math.min(maxOff, newOff))
        if newOff ~= scrollOffset then
            scrollOffset = newOff
            RefreshRows()
            UpdateScrollbar()
        end
    end)

    local function ResizePopup()
        local rowCount  = #entries
        local fitH      = rowCount * ROW_H + 10
        local newH      = math.max(MIN_POPUP_H, math.min(MAX_POPUP_H, fitH))
        local newVis    = math.floor((newH - 10) / ROW_H)
        popup:SetHeight(newH)
        clipFrame:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -14, 5)
        sbTrackH = newH - 10
        scrollbar:SetHeight(sbTrackH)
        return newVis
    end

    local function OpenPicker(anchor)
        entries      = BuildEntryList()
        scrollOffset = 0
        local visRows = ResizePopup()
        local maxOff  = math.max(0, #entries - VISIBLE_ROWS)
        for idx, e in ipairs(entries) do
            local isSel = not e.isHeader and (
                (e.isLSM  and db.soundIsLSM and db.soundName == e.text) or
                (not e.isLSM and not db.soundIsLSM and db.soundID == e.id)
            )
            if isSel then
                scrollOffset = math.max(0, math.min(maxOff, idx - 1 - math.floor(visRows/2)))
                break
            end
        end
        RefreshRows()
        UpdateScrollbar()
        popup:ClearAllPoints()
        popup:SetPoint("TOPLEFT", anchor or soundPickerBtn, "BOTTOMLEFT", 0, 0)
        popup:Show()
        popup:EnableKeyboard(true)
        clickCatcher:Show()
    end

    ddBtn:SetScript("OnClick",       function() if popup:IsShown() then popup:Hide() else OpenPicker(ddFrame) end end)
    ddFrame:SetScript("OnMouseDown", function() if popup:IsShown() then popup:Hide() else OpenPicker(ddFrame) end end)

    return OpenPicker, ddText, StripColors
end

local function BuildSettingsPanel()
    local OpenPicker, ddText, StripColors = BuildSoundPicker(function(label)
        if soundPickerBtn then
            soundPickerBtn:SetText(label)
        end
    end)

    local category, layout = Settings.RegisterVerticalLayoutCategory(L.SETTINGS_TITLE)
    settingsCategory = category

    local soundSetting = Settings.RegisterAddOnSetting(category,
        "soundEnabled", "soundEnabled", LifebloomTrackerDB, Settings.VarType.Boolean, L.SOUND_ENABLE, DB_DEFAULTS.soundEnabled)
    Settings.CreateCheckbox(category, soundSetting, L.SOUND_ENABLE_TT)

    local soundNameSetting = Settings.RegisterAddOnSetting(category,
        "soundName", "soundName", LifebloomTrackerDB, Settings.VarType.String, L.SOUND_CHOICE, DB_DEFAULTS.soundName)
    soundNameSetting:SetValueChangedCallback(function(_, value)
        db.soundName  = value
        db.soundID    = DB_DEFAULTS.soundID
        db.soundIsLSM = DB_DEFAULTS.soundIsLSM
        if soundPickerBtn then
            soundPickerBtn:SetText(StripColors(value))
        end
    end)

    local soundChoiceInitializer = CreateSettingsButtonInitializer(
        L.SOUND_CHOICE,
        GetCurrentSoundLabel(),
        function(button)
            soundPickerBtn = button
            button:SetText(StripColors(GetCurrentSoundLabel()))
            OpenPicker(button)
        end,
        L.SOUND_CHOICE_TT,
        true
    )
    layout:AddInitializer(soundChoiceInitializer)

    hooksecurefunc(SettingsPanel, "DisplayCategory", function(_, cat)
        if cat ~= settingsCategory then return end
        C_Timer.After(0.05, function()
            -- Walk scroll frames to find our sound button
            local scrollBox = SettingsPanel.Container and SettingsPanel.Container.SettingsList and SettingsPanel.Container.SettingsList.ScrollBox
            if not scrollBox then return end
            scrollBox:ForEachFrame(function(frame)
                if frame.Button and frame.data and frame.data.buttonText then
                    soundPickerBtn = frame.Button
                    soundPickerBtn:SetText(StripColors(GetCurrentSoundLabel()))
                end
            end)
        end)
    end)

    local lockSetting = Settings.RegisterAddOnSetting(category,
        "lockFrame", "lockFrame", LifebloomTrackerDB, Settings.VarType.Boolean, L.LOCK_FRAME, DB_DEFAULTS.lockFrame)
    Settings.CreateCheckbox(category, lockSetting, L.LOCK_FRAME_TT)
    lockSetting:SetValueChangedCallback(function(setting, value)
        db.lockFrame = value
        ApplyFrameLock(value)
    end)

    local attachSetting = Settings.RegisterAddOnSetting(category,
        "attachToCursor", "attachToCursor", LifebloomTrackerDB, Settings.VarType.Boolean, L.ATTACH_CURSOR, DB_DEFAULTS.attachToCursor)
    Settings.CreateCheckbox(category, attachSetting, L.ATTACH_CURSOR_TT)
    attachSetting:SetValueChangedCallback(function(setting, value)
        db.attachToCursor = value        ApplyFrameSize(value)        if not value then
            frame:ClearAllPoints()
            frame:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
        end
    end)

    Settings.RegisterAddOnCategory(category)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
ev:RegisterEvent("CHARACTER_POINTS_CHANGED")

ev:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then

        if type(LifebloomTrackerDB) ~= "table" then
            LifebloomTrackerDB = {}
        end
        db = LifebloomTrackerDB
        for k, v in pairs(DB_DEFAULTS) do
            if db[k] == nil then db[k] = v end
        end

        BuildSettingsPanel()
        ApplyFrameLock(db.lockFrame or false)
        ApplyFrameSize(db.attachToCursor or false)
        self:UnregisterEvent("ADDON_LOADED")

    elseif event == "PLAYER_ENTERING_WORLD"
        or event == "PLAYER_SPECIALIZATION_CHANGED"
        or event == "CHARACTER_POINTS_CHANGED" then

        if not LSM and LibStub then
            LSM = LibStub("LibSharedMedia-3.0", true)
        end

        if not LIFEBLOOM_SPELL_NAME then
            LIFEBLOOM_SPELL_NAME = C_Spell.GetSpellName(LIFEBLOOM_SPELL_ID)
        end

        local wasEligible = isEligible
        isEligible = IsRestoDruid()
        
        if isEligible and not wasEligible then
            ev:RegisterEvent("GROUP_ROSTER_UPDATE")
            RebuildUnitsCache()
        elseif not isEligible and wasEligible then
            ev:UnregisterEvent("GROUP_ROSTER_UPDATE")
        end
        
        UpdateVisibility()

    elseif event == "GROUP_ROSTER_UPDATE" then
        RebuildUnitsCache()
    end
end)

SLASH_LIFEBLOOMTRACKER1 = "/lbt"
SlashCmdList["LIFEBLOOMTRACKER"] = function(_)
    if settingsCategory then
        Settings.OpenToCategory(settingsCategory.ID)
    end
end

frame:Show()
