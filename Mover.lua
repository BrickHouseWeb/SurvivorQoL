-- Move frames: every SurvivorQoL frame registers here with QOL.Movable. In move mode each one
-- gets a blue outline and a name tag; drag it, click Done, and its top-left corner is saved
-- in SurvivorQoLDB.pos (UIParent units, shared by every character).

local UI = QOL.UI
local GRID = 16
local movables = {}

local function Place(e)
  local f, pos = e.frame, QOL.db and QOL.db.pos[e.key]
  f:ClearAllPoints()
  if pos then
    local s = f:GetScale()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos[1] / s, pos[2] / s)
  else
    local d = e.default
    f:SetPoint(d[1], UIParent, d[2], d[3], d[4])
  end
end

local function Save(e)
  local f = e.frame
  local s = f:GetScale()
  local x, y = (f:GetLeft() or 0) * s, (f:GetTop() or 0) * s
  if QOL.db.general.snap then
    x = math.floor(x / GRID + 0.5) * GRID
    y = math.floor(y / GRID + 0.5) * GRID
  end
  QOL.db.pos[e.key] = { x, y }
  Place(e)
end

-- default = { point, relativePoint, x, y } against UIParent. module: the module key that owns
-- the frame; move mode only shows frames whose module is on.
function QOL.Movable(frame, key, label, default, module)
  local e = { frame = frame, key = key, label = label, default = default, module = module }
  movables[key] = e
  frame:SetMovable(true)
  frame:SetClampedToScreen(true)
  if QOL.db then Place(e) end
  return e
end

-- call after changing a frame's scale so it stays where it was saved
function QOL.Replace(key)
  if movables[key] then Place(movables[key]) end
end

QOL.OnLoad(function()
  for _, e in pairs(movables) do Place(e) end
end)

function QOL.ResetPositions()
  for k in pairs(QOL.db.pos) do QOL.db.pos[k] = nil end
  for _, e in pairs(movables) do Place(e) end
  QOL.Print("frame positions reset.")
end

-- ---------------------------------------------------------------- move mode
local grid, bar, reopen

local function Grid()
  if grid then return grid end
  grid = CreateFrame("Frame", nil, UIParent)
  grid:SetAllPoints(UIParent)
  grid:SetFrameStrata("BACKGROUND")
  local w, h = UIParent:GetWidth(), UIParent:GetHeight()
  for x = GRID * 4, w, GRID * 4 do
    local t = grid:CreateTexture(nil, "BACKGROUND")
    t:SetTexture("Interface\\Buttons\\WHITE8X8")
    t:SetVertexColor(1, 1, 1, 0.07)
    t:SetWidth(1)
    t:SetPoint("TOPLEFT", grid, "TOPLEFT", x, 0)
    t:SetPoint("BOTTOMLEFT", grid, "BOTTOMLEFT", x, 0)
  end
  for y = GRID * 4, h, GRID * 4 do
    local t = grid:CreateTexture(nil, "BACKGROUND")
    t:SetTexture("Interface\\Buttons\\WHITE8X8")
    t:SetVertexColor(1, 1, 1, 0.07)
    t:SetHeight(1)
    t:SetPoint("TOPLEFT", grid, "TOPLEFT", 0, -y)
    t:SetPoint("TOPRIGHT", grid, "TOPRIGHT", 0, -y)
  end
  return grid
end

local function Overlay(e)
  if e.overlay then return e.overlay end
  local o = CreateFrame("Frame", nil, UIParent)
  o:SetFrameStrata("DIALOG")
  o:SetPoint("TOPLEFT", e.frame, "TOPLEFT", -3, 3)
  o:SetPoint("BOTTOMRIGHT", e.frame, "BOTTOMRIGHT", 3, -3)
  o:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
  o:SetBackdropColor(0.29, 0.47, 0.83, 0.25)
  o:SetBackdropBorderColor(0.5, 0.66, 1, 1)
  o:EnableMouse(true)
  o:RegisterForDrag("LeftButton")
  o.entry = e
  o:SetScript("OnDragStart", function() this.entry.frame:StartMoving() end)
  o:SetScript("OnDragStop", function()
    this.entry.frame:StopMovingOrSizing()
    Save(this.entry)
  end)
  local tag = CreateFrame("Frame", nil, o)
  tag:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
  tag:SetBackdropColor(0.1, 0.16, 0.29, 0.95)
  tag:SetBackdropBorderColor(0.5, 0.66, 1, 1)
  tag:SetHeight(18)
  tag:SetPoint("BOTTOMLEFT", o, "TOPLEFT", 0, 2)
  -- the name tag reads like a title bar, so dragging it moves the frame too
  tag:EnableMouse(true)
  tag:RegisterForDrag("LeftButton")
  tag.entry = e
  tag:SetScript("OnDragStart", o:GetScript("OnDragStart"))
  tag:SetScript("OnDragStop", o:GetScript("OnDragStop"))
  local t = UI.Text(tag, "GameFontHighlightSmall", "LEFT", 0.81, 0.88, 1)
  t:SetPoint("LEFT", tag, "LEFT", 6, 0)
  t:SetText(e.label)
  tag:SetWidth(t:GetStringWidth() + 12)
  e.overlay = o
  return o
end

local function Bar()
  if bar then return bar end
  bar = CreateFrame("Frame", nil, UIParent)
  bar:SetFrameStrata("FULLSCREEN_DIALOG")
  bar:SetWidth(520)
  bar:SetHeight(46)
  bar:SetPoint("TOP", UIParent, "TOP", 0, -24)
  UI.Backdrop(bar, { 0.07, 0.06, 0.05, 0.97 }, { 0.55, 0.51, 0.44 })
  local t = UI.Text(bar, "GameFontNormal")
  t:SetPoint("TOPLEFT", bar, "TOPLEFT", 14, -9)
  t:SetText("Move frames")
  local d = UI.Text(bar, "GameFontHighlightSmall", "LEFT", 0.74, 0.74, 0.74)
  d:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -3)
  d:SetText("Drag any frame. Positions are saved for all your characters.")
  local done = UI.Button(bar, "Done", function() QOL.MoveMode(false) end)
  done:SetPoint("RIGHT", bar, "RIGHT", -12, 0)
  local snap = UI.Check(bar, "Snap", 0, nil)
  snap:SetPoint("RIGHT", done, "LEFT", -48, 0)
  snap:SetScript("OnShow", function() this:SetChecked(QOL.db.general.snap) end)
  snap:SetScript("OnClick", function()
    QOL.db.general.snap = this:GetChecked() and true or false
    if QOL.db.general.snap then Grid():Show() elseif grid then grid:Hide() end
  end)
  return bar
end

function QOL.MoveMode(on)
  if not QOL.db then return end
  QOL.moving = on and true or false
  if on then
    reopen = QOL.window:IsShown()
    QOL.window:Hide()
    Bar():Show()
    if QOL.db.general.snap then Grid():Show() end
    for _, e in pairs(movables) do
      if not e.module or QOL.db.on[e.module] then
        e.frame:Show()
        Overlay(e):Show()
      end
    end
  else
    if bar then bar:Hide() end
    if grid then grid:Hide() end
    for _, e in pairs(movables) do
      if e.overlay then e.overlay:Hide() end
      -- a frame of a module that is off goes away; the others decide on their next tick
      if e.module and not QOL.db.on[e.module] then e.frame:Hide() end
    end
    if reopen then QOL.window:Show() end
  end
end
