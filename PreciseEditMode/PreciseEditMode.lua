-- Precise Edit Mode: a panel beside Blizzard's Edit Mode settings dialog with exact X/Y positions and, for action
-- bars, an exact icon size (any percentage, not just the slider's 10% steps).
--
-- The panel copies the dialog's look (translucent dialog border, title and 32px setting rows) and sits against its
-- side. It's a separate frame rather than a child of the dialog, so Blizzard's own layout code never reads our
-- frames (which could taint Edit Mode).
--
-- Positions go through the same steps Blizzard uses for an arrow-key nudge, so they behave like a drag: the layout
-- is marked as changed and saved with Edit Mode's Save button.
--
-- Icon sizes: Blizzard saves Icon Size in a layout as a slider step (50%, 60%, ...), so an exact size can't live in
-- the layout itself. The nearest step is saved there (so the bar is close even without this addon), and the exact
-- size is saved here, per layout and bar, and applied on top whenever Blizzard sets the bar's icon size.
local ADDON = ...

local PAD = 20       -- the dialog's widthPadding / heightPadding (40) halved
local ROW_H = 32     -- Edit Mode setting row height
local ROW_GAP = 2    -- spacing between the dialog's rows
local LABEL_W = 100  -- Edit Mode setting label width
local BOX_W = 70
local GAP = 2        -- space between this panel and the dialog

local ICON_MIN, ICON_MAX, ICON_STEP = 50, 200, 10 -- Blizzard's Icon Size slider

local db -- PreciseEditModeDB

---------------------------------------------------------------------------
-- Positions (center of the element relative to the center of the screen, in UI units)
---------------------------------------------------------------------------
local function ScaleToUI(frame)
    return frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
end

local function GetCenterOffset(frame)
    local left, right, top, bottom = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
    if not (left and right and top and bottom) then return end
    local r = ScaleToUI(frame)
    return (left + right) / 2 * r - UIParent:GetWidth() / 2, (top + bottom) / 2 * r - UIParent:GetHeight() / 2
end

local function MoveTo(frame, x, y)
    if InCombatLockdown() or not frame:CanBeMoved() then return end
    local cx, cy = GetCenterOffset(frame)
    if not cx then return end
    local r = ScaleToUI(frame)
    local dx, dy = (x - cx) / r, (y - cy) / r
    if math.abs(dx) < 0.01 and math.abs(dy) < 0.01 then return end

    -- The same steps as EditModeSystemMixin:ProcessMovementKey (an arrow-key nudge), with our distance
    if frame.isManagedFrame and frame:IsInDefaultPosition() then frame:BreakFromFrameManager() end
    if frame == PlayerCastingBarFrame and Enum.EditModeCastBarSetting then
        EditModeManagerFrame:OnSystemSettingChange(frame, Enum.EditModeCastBarSetting.LockToPlayerFrame, 0)
    end
    frame:ClearFrameSnap()
    frame:StopMovingOrSizing()
    frame:BreakFrameSnap(dx, dy)
end

---------------------------------------------------------------------------
-- Exact icon sizes for action bars
---------------------------------------------------------------------------
local ICON_SIZE = Enum.EditModeActionBarSetting and Enum.EditModeActionBarSetting.IconSize
local scaledByUs = {} -- bar -> true while an exact size is applied
local pending = {}    -- bars to update once combat ends

local function IsActionBar(frame)
    return frame and ICON_SIZE and frame.system == Enum.EditModeSystem.ActionBar and type(frame.actionButtons) == "table"
        and frame.HasSetting and frame:HasSetting(ICON_SIZE)
end

local function LayoutName()
    local info = EditModeManagerFrame:GetActiveLayoutInfo()
    return info and info.layoutName
end

local function GetExactSize(bar)
    local layout = LayoutName()
    local sizes = layout and db.iconSize[layout]
    return sizes and sizes[bar.systemIndex]
end

local function SetExactSize(bar, pct)
    local layout = LayoutName()
    if not layout then return end
    db.iconSize[layout] = db.iconSize[layout] or {}
    db.iconSize[layout][bar.systemIndex] = pct
    if not next(db.iconSize[layout]) then db.iconSize[layout] = nil end
end

-- Scale the bar's buttons to the exact size, or back to Blizzard's when there's none. Mirrors
-- EditModeActionBarSystemMixin:UpdateSystemSettingIconSize.
local function ApplyIconSize(bar)
    if InCombatLockdown() then pending[bar] = true; return end
    local exact = GetExactSize(bar)
    if not exact and not scaledByUs[bar] then return end
    scaledByUs[bar] = exact and true or nil

    local scale = (exact or bar:GetSettingValue(ICON_SIZE)) / 100
    if bar.EditModeSetScale then bar:EditModeSetScale(scale) end
    for _, button in pairs(bar.actionButtons) do
        if button.container then button.container:SetScale(scale) end
    end
    bar:Layout()
    EditModeManagerFrame:UpdateActionBarLayout(bar)
    if bar.MarkBarArtDirty and bar.RefreshBarArt then
        bar:MarkBarArtDirty()
        bar:RefreshBarArt()
    end
end

local function NearestStep(pct)
    local step = math.floor((pct - ICON_MIN) / ICON_STEP + 0.5) * ICON_STEP + ICON_MIN
    return math.max(ICON_MIN, math.min(ICON_MAX, step))
end

local function SetIconSize(bar, pct)
    if InCombatLockdown() then return end
    pct = math.max(ICON_MIN, math.min(ICON_MAX, math.floor(pct + 0.5)))
    local step = NearestStep(pct)
    SetExactSize(bar, pct ~= step and pct or nil)
    if bar:GetSettingValue(ICON_SIZE) ~= step then
        -- Save the nearest step in the layout; marks the layout as changed, like moving the slider
        EditModeManagerFrame:OnSystemSettingChange(bar, ICON_SIZE, step)
    end
    scaledByUs[bar] = true -- re-apply even if the size is now a plain step
    ApplyIconSize(bar)
    EditModeSystemSettingsDialog:UpdateDialog(bar) -- show the new step on Blizzard's slider
end

---------------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------------
local panel = CreateFrame("Frame", "PreciseEditModePanel", UIParent)
panel:SetFrameStrata("DIALOG")
panel:SetFrameLevel(200)
panel:EnableMouse(true)
panel:SetClampedToScreen(true)
panel:SetWidth(PAD * 2 + LABEL_W + 5 + BOX_W + 24)
panel:Hide()

panel.Border = CreateFrame("Frame", nil, panel, "DialogBorderTranslucentTemplate")
panel.Border:SetAllPoints()

panel.Title = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
panel.Title:SetPoint("TOP", 0, -15)

local rows = {}
local attached -- the selected Edit Mode system

local function Tooltip(region, title, text)
    region:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title, 1, 1, 1)
        GameTooltip:AddLine(text, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    region:SetScript("OnLeave", GameTooltip_Hide)
end

-- A setting row like Edit Mode's: label on the left, then an input box and an optional suffix ("%").
local function MakeRow(label, suffix, tip, read, write)
    local row = CreateFrame("Frame", nil, panel)
    row:SetSize(LABEL_W + 5 + BOX_W + 24, ROW_H)
    row:EnableMouse(true)
    Tooltip(row, label, tip)

    row.Label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightMedium")
    row.Label:SetSize(LABEL_W, ROW_H)
    row.Label:SetPoint("LEFT")
    row.Label:SetJustifyH("LEFT")
    row.Label:SetText(label)

    local box = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    box:SetSize(BOX_W, 20)
    box:SetPoint("LEFT", row.Label, "RIGHT", 10, 0) -- InputBoxTemplate's border sits 5px outside the box
    box:SetAutoFocus(false)
    box:SetMaxLetters(8)
    box:SetJustifyH("CENTER")
    row.Box = box

    if suffix then
        row.Suffix = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        row.Suffix:SetPoint("LEFT", box, "RIGHT", 4, 0)
        row.Suffix:SetText(suffix)
    end

    local function Current()
        local value = attached and read()
        return value and tostring(value) or ""
    end

    function row:Refresh()
        if not box:HasFocus() then box:SetText(Current()) end
    end

    -- Apply the typed value when it's a number that differs from the current one
    local function Commit()
        if not attached then return end -- the dialog closed while editing: drop the edit
        local value = tonumber((box:GetText() or ""):match("^%s*(.-)%s*$"))
        if value and tostring(value) ~= Current() then write(value) end
        box:SetText(Current())
    end
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEditFocusLost", Commit)
    box:SetScript("OnEscapePressed", function(self)
        self:SetText(Current()) -- undo the edit; Commit then finds nothing to change
        self:ClearFocus()
    end)
    box:SetScript("OnTabPressed", function(self)
        local visible = {}
        for _, r in ipairs(rows) do if r:IsShown() then visible[#visible + 1] = r end end
        for i, r in ipairs(visible) do
            if r == row then
                local nextRow = visible[(IsShiftKeyDown() and i - 2 or i) % #visible + 1]
                nextRow.Box:SetFocus()
                nextRow.Box:HighlightText()
                return
            end
        end
    end)

    rows[#rows + 1] = row
    return row
end

local function Round(v) return math.floor(v + 0.5) end

MakeRow("X", nil, "Horizontal position of the element's center, from the center of the screen. "
    .. "Type a value and press Enter. Saved with Edit Mode's Save button, like dragging.",
    function()
        local x = attached and GetCenterOffset(attached)
        return x and Round(x)
    end,
    function(value)
        local _, y = GetCenterOffset(attached)
        if y then MoveTo(attached, value, y) end
    end)

MakeRow("Y", nil, "Vertical position of the element's center, from the center of the screen. "
    .. "Type a value and press Enter. Saved with Edit Mode's Save button, like dragging.",
    function()
        local _, y = attached and GetCenterOffset(attached)
        return y and Round(y)
    end,
    function(value)
        local x = GetCenterOffset(attached)
        if x then MoveTo(attached, x, value) end
    end)

local iconRow = MakeRow(HUD_EDIT_MODE_SETTING_ACTION_BAR_ICON_SIZE or "Icon Size", "%",
    "Any size from 50% to 200%, not just Blizzard's 10% steps. The nearest step is saved in the layout "
    .. "(and shown on the slider); the exact size is kept by Precise Edit Mode for this layout. "
    .. "Moving the Icon Size slider goes back to Blizzard's steps.",
    function()
        return attached and (GetExactSize(attached) or attached:GetSettingValue(ICON_SIZE))
    end,
    function(value) SetIconSize(attached, value) end)

-- Stack the shown rows under the title (12px below it, like the dialog's settings) and size the panel to fit
local function LayoutRows()
    local top = 15 + panel.Title:GetStringHeight() + 12
    local previous
    local count = 0
    for _, row in ipairs(rows) do
        if row:IsShown() then
            row:ClearAllPoints()
            if previous then
                row:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -ROW_GAP)
            else
                row:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -top)
            end
            previous = row
            count = count + 1
        end
    end
    panel:SetHeight(top + count * ROW_H + (count - 1) * ROW_GAP + PAD)
end

local anchoredLeft
local function Anchor()
    local dialog = EditModeSystemSettingsDialog
    local right = dialog:GetRight()
    local left = right and dialog:GetLeft()
    if not left then return end
    -- Right of the dialog when there's room, otherwise left of it
    local wantLeft = right + GAP + panel:GetWidth() > UIParent:GetWidth() and left - GAP - panel:GetWidth() >= 0
    if wantLeft == anchoredLeft and panel:GetNumPoints() > 0 then return end
    anchoredLeft = wantLeft
    panel:ClearAllPoints()
    if wantLeft then
        panel:SetPoint("TOPRIGHT", dialog, "TOPLEFT", -GAP, 0)
    else
        panel:SetPoint("TOPLEFT", dialog, "TOPRIGHT", GAP, 0)
    end
end

local function Refresh()
    if not attached then return end
    for _, row in ipairs(rows) do row:Refresh() end
end

local function Attach(systemFrame)
    attached = systemFrame
    local isBar = IsActionBar(systemFrame)
    iconRow:SetShown(isBar)
    panel.Title:SetText(isBar and "Position & Size" or "Position")
    LayoutRows()
    anchoredLeft = nil
    Anchor()
    Refresh()
    panel:Show()
end

-- Follow the dialog (it can be dragged) and keep the values live while the element is dragged or nudged.
panel:SetScript("OnUpdate", function()
    if not EditModeSystemSettingsDialog:IsShown() or EditModeSystemSettingsDialog.attachedToSystem ~= attached then
        panel:Hide()
        return
    end
    Anchor()
    Refresh()
end)
panel:SetScript("OnHide", function()
    attached = nil
    for _, row in ipairs(rows) do row.Box:ClearFocus() end
end)

---------------------------------------------------------------------------
-- Hooks (post-hooks only, so Blizzard's own code runs untouched)
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event, arg)
    if event == "ADDON_LOADED" then
        if arg ~= ADDON then return end
        PreciseEditModeDB = PreciseEditModeDB or {}
        db = PreciseEditModeDB
        db.iconSize = db.iconSize or {}

    elseif event == "PLAYER_LOGIN" then
        hooksecurefunc(EditModeSystemSettingsDialog, "AttachToSystemFrame", function(_, systemFrame) Attach(systemFrame) end)

        -- Moving Blizzard's Icon Size slider goes back to its steps
        hooksecurefunc(EditModeSystemSettingsDialog, "OnSettingValueChanged", function(dialog, setting)
            local bar = dialog.attachedToSystem
            if setting == ICON_SIZE and IsActionBar(bar) and GetExactSize(bar) then
                SetExactSize(bar, nil)
                ApplyIconSize(bar)
            end
        end)

        -- Re-apply exact sizes whenever Blizzard sets a bar's icon size or reloads its settings (layout change,
        -- revert, login)
        for _, systemFrame in ipairs(EditModeManagerFrame.registeredSystemFrames or {}) do
            if IsActionBar(systemFrame) then
                hooksecurefunc(systemFrame, "UpdateSystemSettingIconSize", ApplyIconSize)
                hooksecurefunc(systemFrame, "UpdateSystem", ApplyIconSize)
                ApplyIconSize(systemFrame)
            end
        end

    elseif event == "PLAYER_REGEN_ENABLED" then
        for bar in pairs(pending) do
            pending[bar] = nil
            ApplyIconSize(bar)
        end
    end
end)
