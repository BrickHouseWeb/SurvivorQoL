-- The minimap button: left-click opens /qol, right-click opens a small menu to turn modules
-- on or off, drag moves it around the minimap's edge (unless locked in General).

local UI = QOL.UI

local function SquareMinimap()
  if type(GetMinimapShape) == "function" then
    local ok, shape = pcall(GetMinimapShape)
    if ok and shape then return shape == "SQUARE" end
  end
  return DFRL ~= nil   -- SurvivorsDragonUi's minimap is square
end

local btn = CreateFrame("Button", "SurvivorQoLMinimapButton", Minimap)
btn:SetWidth(31)
btn:SetHeight(31)
btn:SetFrameStrata("MEDIUM")
-- above SurvivorsDragonUi's own minimap button (Minimap level + 20), so it is never hidden under it
btn:SetFrameLevel(Minimap:GetFrameLevel() + 25)
btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
local back = btn:CreateTexture(nil, "BACKGROUND")
back:SetTexture(QOL.media .. "dot")
back:SetVertexColor(0.08, 0.07, 0.05)
back:SetWidth(22)
back:SetHeight(22)
back:SetPoint("TOPLEFT", btn, "TOPLEFT", 5, -4)
-- the addon's mark: the game's own Engineering icon, so it looks like every other minimap button
-- (same size and spot as most addons use; the round border hides its corners)
local mark = btn:CreateTexture(nil, "ARTWORK")
mark:SetTexture(QOL.ICON)
mark:SetTexCoord(0.05, 0.95, 0.05, 0.95)
mark:SetWidth(20)
mark:SetHeight(20)
mark:SetPoint("TOPLEFT", btn, "TOPLEFT", 6, -5)
local ring = btn:CreateTexture(nil, "OVERLAY")
ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
ring:SetWidth(53)
ring:SetHeight(53)
ring:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
btn:Hide()

local function PlaceButton()
  local a = math.rad(QOL.db.general.minimapAngle or 220)
  local x, y = math.cos(a), math.sin(a)
  if SquareMinimap() then
    local m = math.max(math.abs(x), math.abs(y))
    x, y = x / m, y / m
  end
  local r = (Minimap:GetWidth() or 140) / 2 + 8
  btn:ClearAllPoints()
  btn:SetPoint("CENTER", Minimap, "CENTER", x * r, y * r)
end

local function Tooltip()
  GameTooltip:SetOwner(btn, "ANCHOR_LEFT")
  GameTooltip:AddLine("Survivor QoL", 1, 1, 1)
  GameTooltip:AddLine("Left-click: open settings", 0, 1, 0)
  GameTooltip:AddLine("Right-click: turn modules on or off", 0, 1, 0)
  if not QOL.db.general.minimapLock then GameTooltip:AddLine("Drag: move this button", 0, 1, 0) end
  GameTooltip:AddLine(" ")
  for i = 1, table.getn(QOL.modules) do
    local m = QOL.modules[i]
    local on = QOL.IsOn(m)
    GameTooltip:AddDoubleLine(m.label, on and "On" or "Off", 1, 0.82, 0, on and 1 or 1, on and 1 or 0.35, on and 1 or 0.35)
  end
  GameTooltip:Show()
end

-- ---------------------------------------------------------------- right-click menu
local menu = CreateFrame("Frame", "SurvivorQoLMenu", UIParent)
menu:SetFrameStrata("FULLSCREEN_DIALOG")
menu:SetWidth(180)
UI.Backdrop(menu, { 0, 0, 0, 0.94 }, { 0.6, 0.6, 0.67 })
menu:EnableMouse(true)
menu:Hide()
table.insert(UISpecialFrames, "SurvivorQoLMenu")
local menuTitle = UI.Text(menu, "GameFontNormalSmall")
menuTitle:SetPoint("TOPLEFT", menu, "TOPLEFT", 12, -10)
menuTitle:SetText("Survivor QoL")
local items = {}

local function Item(i, text, fn, module)
  local b = CreateFrame("Button", nil, menu)
  b:SetHeight(18)
  b:SetPoint("TOPLEFT", menu, "TOPLEFT", 8, -24 - (i - 1) * 18)
  b:SetPoint("RIGHT", menu, "RIGHT", -8, 0)
  b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
  b.tick = b:CreateTexture(nil, "ARTWORK")
  b.tick:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
  b.tick:SetWidth(16)
  b.tick:SetHeight(16)
  b.tick:SetPoint("LEFT", b, "LEFT", 0, 0)
  b.tick:Hide()
  b.text = UI.Text(b, "GameFontHighlightSmall")
  b.text:SetPoint("LEFT", b, "LEFT", 20, 0)
  b.text:SetText(text)
  b.module = module
  b:SetScript("OnClick", fn)
  table.insert(items, b)
  return b
end

local built = false
local function BuildMenu()
  if built then return end
  built = true
  local n = 0
  for i = 1, table.getn(QOL.modules) do
    n = n + 1
    Item(n, QOL.modules[i].label, function() QOL.Set(this.module, not QOL.IsOn(this.module)); this.tick[QOL.IsOn(this.module) and "Show" or "Hide"](this.tick) end, QOL.modules[i])
  end
  n = n + 1
  local sep = menu:CreateTexture(nil, "ARTWORK")
  sep:SetTexture("Interface\\Buttons\\WHITE8X8")
  sep:SetVertexColor(1, 1, 1, 0.2)
  sep:SetHeight(1)
  sep:SetPoint("TOPLEFT", menu, "TOPLEFT", 12, -24 - (n - 1) * 18 + 4)
  sep:SetPoint("RIGHT", menu, "RIGHT", -12, 0)
  n = n + 0.5
  Item(n, "Open settings", function() menu:Hide(); QOL.OpenPage("general") end)
  Item(n + 1, "Move frames", function() menu:Hide(); QOL.MoveMode(true) end)
  menu:SetHeight(24 + (n + 1) * 18 + 10)
end

local idle = 0
menu:SetScript("OnUpdate", function()
  -- close once the mouse has been away from the menu and the button for a moment
  if MouseIsOver(menu) or MouseIsOver(btn) then idle = 0 return end
  idle = idle + arg1
  if idle > 1.5 then this:Hide() end
end)

local function OpenMenu()
  BuildMenu()
  for i = 1, table.getn(items) do
    local b = items[i]
    if b.module then
      if QOL.IsOn(b.module) then b.tick:Show() else b.tick:Hide() end
    end
  end
  menu:ClearAllPoints()
  menu:SetPoint("TOPRIGHT", btn, "BOTTOMLEFT", 8, 4)
  idle = 0
  menu:Show()
end

btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
btn:RegisterForDrag("LeftButton")
btn:SetScript("OnClick", function()
  GameTooltip:Hide()
  if arg1 == "RightButton" then
    if menu:IsShown() then menu:Hide() else OpenMenu() end
  else
    menu:Hide()
    QOL.ToggleWindow()
  end
end)
btn:SetScript("OnDragStart", function()
  if QOL.db.general.minimapLock then return end
  this:SetScript("OnUpdate", function()
    local mx, my = Minimap:GetCenter()
    local s = Minimap:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    QOL.db.general.minimapAngle = math.deg(math.atan2(cy / s - my, cx / s - mx))
    PlaceButton()
  end)
end)
btn:SetScript("OnDragStop", function() this:SetScript("OnUpdate", nil) end)
btn:SetScript("OnEnter", Tooltip)
btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- General page settings take effect here
function QOL.ApplyGeneral()
  local g = QOL.db.general
  if g.minimap then PlaceButton(); btn:Show() else btn:Hide(); menu:Hide() end
end

QOL.OnLoad(QOL.ApplyGeneral)
