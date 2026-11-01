-- /qol: the settings window. A category list on the left (General, then one row per module
-- with its on/off box), the selected page on the right. Pages are built the first time they
-- are shown. Escape closes the window.

local UI = QOL.UI
local W, LIST_W, PAD = 760, 206, 14
local PANEL_W = W - PAD * 2 - LIST_W - 12
local PAGE_W = PANEL_W - 54   -- room for the scrollbar on the right
local VERSION = "v0.2"

local win = CreateFrame("Frame", "SurvivorQoLOptions", UIParent)
win:SetWidth(W)
win:SetHeight(500)
win:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
win:SetFrameStrata("DIALOG")
win:SetToplevel(true)
UI.Backdrop(win, { 0.07, 0.06, 0.05, 0.97 }, { 0.55, 0.51, 0.44 })
win:SetMovable(true)
win:EnableMouse(true)
win:RegisterForDrag("LeftButton")
win:SetScript("OnDragStart", function() this:StartMoving() end)
win:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
win:Hide()
table.insert(UISpecialFrames, "SurvivorQoLOptions")
QOL.window = win

-- title bar: gear glyph, "Survivor QoL", version, close; a gold rule fading at both ends
local mark = win:CreateTexture(nil, "ARTWORK")
mark:SetTexture(QOL.media .. "g_gear")
mark:SetVertexColor(1, 0.82, 0)
mark:SetWidth(18)
mark:SetHeight(18)
mark:SetPoint("TOPLEFT", win, "TOPLEFT", PAD + 2, -12)
local word = UI.Text(win, "GameFontNormalLarge", "LEFT", 0.91, 0.87, 0.78)
word:SetPoint("LEFT", mark, "RIGHT", 8, 0)
word:SetText("Survivor")
local qol = UI.Text(win, "GameFontNormalLarge")
qol:SetPoint("LEFT", word, "RIGHT", 5, 0)
qol:SetText("QoL")
local ver = UI.Text(win, "GameFontDisableSmall")
ver:SetPoint("BOTTOMLEFT", qol, "BOTTOMRIGHT", 6, 1)
ver:SetText(VERSION)
local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", win, "TOPRIGHT", -4, -4)
-- Move frames sits in the title bar so it works from any page
local move = UI.Button(win, "Move frames", function() QOL.MoveMode(true) end)
move:SetPoint("RIGHT", close, "LEFT", -6, 0)
for i = 0, 1 do
  local rule = win:CreateTexture(nil, "ARTWORK")
  rule:SetTexture("Interface\\Buttons\\WHITE8X8")
  rule:SetHeight(1)
  rule:SetPoint("TOPLEFT", win, "TOPLEFT", PAD + i * (W / 2 - PAD), -40)
  rule:SetWidth(W / 2 - PAD)
  if i == 0 then
    rule:SetGradientAlpha("HORIZONTAL", 0.55, 0.51, 0.44, 0, 0.55, 0.51, 0.44, 1)
  else
    rule:SetGradientAlpha("HORIZONTAL", 0.55, 0.51, 0.44, 1, 0.55, 0.51, 0.44, 0)
  end
end

-- ---------------------------------------------------------------- category list
local list = CreateFrame("Frame", nil, win)
UI.Backdrop(list, { 0, 0, 0, 0.4 }, { 0.37, 0.35, 0.32 })
list:SetWidth(LIST_W)
list:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, -52)
local hint = UI.Text(win, "GameFontHighlightSmall", "LEFT", 0.62, 0.62, 0.62)
hint:SetWidth(LIST_W - 4)
hint:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 4, -8)
hint:SetText("Tick a module to turn it on. Type /qol to open this window.")

local panel = CreateFrame("Frame", nil, win)
UI.Backdrop(panel, { 0, 0, 0, 0.4 }, { 0.37, 0.35, 0.32 })
panel:SetWidth(PANEL_W)
panel:SetPoint("TOPLEFT", list, "TOPRIGHT", 12, 0)

-- pages scroll inside the panel, so the window never grows past the screen
local scroll = CreateFrame("ScrollFrame", "SurvivorQoLOptionsScroll", panel, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -14)
scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -32, 10)
local scrollBar = getglobal("SurvivorQoLOptionsScrollScrollBar")
scroll:EnableMouseWheel(true)
scroll:SetScript("OnMouseWheel", function()
  if scrollBar:IsShown() then scrollBar:SetValue(scrollBar:GetValue() - arg1 * 40) end
end)

local rows, pages, current = {}, {}, nil
local Show

local function NewRow(i, label, glyph, m)
  local r = CreateFrame("Button", nil, list)
  r:SetWidth(LIST_W - 12)
  r:SetHeight(26)
  r:SetPoint("TOPLEFT", list, "TOPLEFT", 6, -6 - (i - 1) * 27)
  r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
  -- the open page: a solid highlight plus a gold bar on the left, so it reads as "you are here"
  -- and not as one more on/off box
  r.sel = r:CreateTexture(nil, "BACKGROUND")
  r.sel:SetTexture("Interface\\Buttons\\WHITE8X8")
  r.sel:SetGradientAlpha("HORIZONTAL", 0.33, 0.47, 0.78, 0.75, 0.33, 0.47, 0.78, 0.15)
  r.sel:SetAllPoints(r)
  r.sel:Hide()
  r.accent = r:CreateTexture(nil, "ARTWORK")
  r.accent:SetTexture("Interface\\Buttons\\WHITE8X8")
  r.accent:SetVertexColor(1, 0.82, 0)
  r.accent:SetWidth(3)
  r.accent:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0)
  r.accent:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0)
  r.accent:Hide()
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetTexture(QOL.media .. glyph)
  r.icon:SetWidth(16)
  r.icon:SetHeight(16)
  r.icon:SetPoint("LEFT", r, "LEFT", 6, 0)
  r.text = UI.Text(r, "GameFontNormal")
  r.text:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
  r.text:SetText(label)
  if m then
    r.check = CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate")
    r.check:SetWidth(22)
    r.check:SetHeight(22)
    r.check:SetPoint("RIGHT", r, "RIGHT", 0, 0)
    r.check.module = m
    r.check:SetScript("OnClick", function() QOL.Set(this.module, this:GetChecked() and true or false) end)
  end
  r.key = m and m.key or "general"
  r:SetScript("OnClick", function() Show(this.key) end)
  r.Mark = function(self, on)
    if on then
      self.sel:Show(); self.accent:Show(); self.text:SetTextColor(1, 1, 1); self.icon:SetVertexColor(1, 1, 1)
    else
      self.sel:Hide(); self.accent:Hide(); self.text:SetTextColor(1, 0.82, 0); self.icon:SetVertexColor(1, 0.82, 0)
    end
  end
  rows[r.key] = r
  return r
end

-- ---------------------------------------------------------------- pages
local function GeneralPage()
  local g = QOL.db.general
  local P = UI.Page(scroll, PAGE_W, g, function(key) QOL.ApplyGeneral(key) end)
  P:Title("General", "Settings for the whole addon. Your settings and frame positions are saved for your account, so every character shares them.")
  local G = P:Group("Minimap button")
  G:Checks({ { "Show the minimap button", "minimap" }, { "Lock it in place", "minimapLock" } })
  G:Note("Left-click it to open this window, right-click it to turn modules on or off.")
  G:Done()
  G = P:Group("Moving frames")
  G:Note("Use Move frames at the top of this window to drag frames where you want them.")
  G:Buttons({ { "Reset positions", function() QOL.ResetPositions() end } })
  G:Checks({ { "Snap to a grid while moving", "snap" }, { "Say in chat when a module turns on or off", "chat" } })
  G:Done()
  return P
end

local function ModulePage(m)
  local P = UI.Page(scroll, PAGE_W, QOL.db[m.key], function(key, v)
    if QOL.IsOn(m) and m.Apply then m.Apply(QOL.db[m.key], key) end
  end)
  P:Title(m.label, m.desc)
  P:EnableRow("Enable " .. m.label, function() return QOL.IsOn(m) end, function(v) QOL.Set(m, v) end)
  m.Page(P, QOL.db[m.key])
  return P
end

-- one fixed panel height for every page, so the window never jumps when you switch pages:
-- 600 px, or less on a short screen (window chrome is 98 px, plus a margin). Longer pages scroll.
local function Layout(P)
  local listH = table.getn(QOL.modules) * 27 + 39
  local h = math.max(listH + 60, math.min(600, UIParent:GetHeight() - 98 - 80))
  panel:SetHeight(h)
  list:SetHeight(listH)
  win:SetHeight(52 + h + 46)
  local view = h - 24
  local range = math.max(0, P.y - view + 6)
  scroll:SetVerticalScroll(0)
  scrollBar:SetMinMaxValues(0, range)
  scrollBar:SetValue(0)
  if range > 0 then scrollBar:Show() else scrollBar:Hide() end
end

Show = function(key)
  if current and pages[current] then pages[current].frame:Hide() end
  current = key
  local P = pages[key]
  if not P then
    P = key == "general" and GeneralPage() or ModulePage(QOL.Module(key))
    pages[key] = P
  end
  P:Refresh()
  if key ~= "general" then P:SetEnabled(QOL.IsOn(QOL.Module(key))) end
  scroll:SetScrollChild(P.frame)
  P.frame:Show()
  if scroll.UpdateScrollChildRect then scroll:UpdateScrollChildRect() end
  for k, r in pairs(rows) do r:Mark(k == key) end
  Layout(P)
end

-- footer: Defaults resets the page you are on, Close closes
local defaults = UI.Button(win, "Defaults", function()
  if current == "general" then
    for k, v in pairs(QOL.generalDefaults) do QOL.db.general[k] = v end
    QOL.ApplyGeneral()
  else
    QOL.ResetModule(QOL.Module(current))
  end
  Show(current)
end)
defaults:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", PAD, 12)
local closeBtn = UI.Button(win, "Close", function() win:Hide() end)
closeBtn:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -PAD, 12)

local built = false
local function Build()
  if built then return end
  built = true
  NewRow(1, "General", "g_gear")
  for i = 1, table.getn(QOL.modules) do
    local m = QOL.modules[i]
    NewRow(i + 1, m.label, m.glyph, m)
  end
end

win:SetScript("OnShow", function()
  Build()
  for _, r in pairs(rows) do
    if r.check then r.check:SetChecked(QOL.IsOn(r.check.module)) end
  end
  Show(current or "general")
end)

-- a module switched on or off anywhere: keep the boxes and the gray-out in step
QOL.OnToggle(function(m)
  if not win:IsShown() then return end
  if rows[m.key] then rows[m.key].check:SetChecked(QOL.IsOn(m)) end
  if pages[m.key] then pages[m.key]:Refresh(); pages[m.key]:SetEnabled(QOL.IsOn(m)) end
end)

function QOL.ToggleWindow()
  if not QOL.db then return end
  if win:IsShown() then win:Hide() else win:Show() end
end

function QOL.OpenPage(key)
  if not QOL.db then return end
  current = key
  if win:IsShown() then Show(key) else win:Show() end
end

SLASH_SURVIVORQOL1 = "/qol"
SlashCmdList["SURVIVORQOL"] = function(msg)
  if not QOL.db then return end
  msg = string.lower(msg or "")
  if msg == "move" then QOL.MoveMode(true) return end
  if msg == "stats all" and QOL.StatsFields then QOL.StatsFields() return end
  if msg == "meter" and QOL.MeterInfo then QOL.MeterInfo() return end
  -- /qol find <word>: names of shown frames containing the word, to hook into the game's own UI
  local _, _, word = string.find(msg, "^find%s+(%S+)")
  if word then
    local n = 0
    for name, f in pairs(getfenv(0)) do
      if type(name) == "string" and type(f) == "table" and f.IsShown and f.GetObjectType
        and string.find(string.lower(name), word, 1, true) then
        local ok, shown = pcall(f.IsShown, f)
        if ok and shown and n < 40 then
          n = n + 1
          local ok2, kind = pcall(f.GetObjectType, f)
          QOL.Print(name .. " (" .. tostring(ok2 and kind) .. ")")
        end
      end
    end
    QOL.Print(n == 0 and ("no shown frames with \"" .. word .. "\" in the name.") or (n .. " found."))
    return
  end
  QOL.ToggleWindow()
end
