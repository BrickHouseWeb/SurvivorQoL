-- WoW-style controls for the settings pages. A page is built top to bottom: QOL.UI.Page
-- returns a builder, Group adds a boxed section, and each control reads and writes one key
-- of the page's store through get/set, so pages never hold their own copy of a setting.

local UI = {}
QOL.UI = UI

local GOLD = { 1, 0.82, 0 }
local count = 0
local function Name(kind)
  count = count + 1
  return "SurvivorQoL" .. kind .. count
end

local function Backdrop(f, bg, border)
  f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
  f:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
  f:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
end
UI.Backdrop = Backdrop

function UI.Text(parent, font, justify, r, g, b)
  local t = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
  t:SetJustifyH(justify or "LEFT")
  if r then t:SetTextColor(r, g, b) end
  return t
end

-- ---------------------------------------------------------------- page
-- store: the table settings live in. onChange(key, value): called after a control writes.
function UI.Page(parent, width, store, onChange)
  local P = { frame = CreateFrame("Frame", nil, parent), width = width, y = 0, store = store,
    onChange = onChange, refresh = {} }
  P.frame:SetWidth(width)
  P.get = function(key) return P.store[key] end
  P.set = function(key, v)
    if P.filling then return end
    P.store[key] = v
    if P.onChange then P.onChange(key, v) end
  end

  function P:Add(h, gap)
    local y = self.y
    self.y = self.y + h + (gap or 10)
    return -y
  end

  function P:Title(text, sub)
    local t = UI.Text(self.frame, "GameFontNormalLarge")
    t:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, self:Add(22, 4))
    t:SetText(text)
    if sub then
      local s = UI.Text(self.frame, "GameFontHighlightSmall", "LEFT", 0.62, 0.62, 0.62)
      s:SetWidth(self.width)
      s:SetText(sub)
      s:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, -self.y)
      self:Add(s:GetHeight() + 2, 10)
    end
  end

  -- the module's own on/off box; everything added after it is "content" and grays out when off
  function P:EnableRow(label, get, set)
    local y = self:Add(26, 8)
    local cb = UI.Check(self.frame, label, 0, y)
    cb.text:SetFontObject(GameFontHighlight)
    cb:SetScript("OnClick", function() set(this:GetChecked() and true or false) end)
    table.insert(self.refresh, function() cb:SetChecked(get()) end)
    self.notice = UI.Text(self.frame, "GameFontNormalSmall", "LEFT", 1, 0.7, 0.35)
    self.notice:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 4, -self.y)
    self.notice:SetText("This module is off. Tick the box above to change its settings.")
    self:Add(12, 8)
    self.contentTop = self.y
  end

  function P:Group(title)
    local G = { page = self, y = 12 }
    local head = UI.Text(self.frame, "GameFontNormal")
    head:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 2, self:Add(14, 4))
    head:SetText(title)
    local box = CreateFrame("Frame", nil, self.frame)
    Backdrop(box, { 0, 0, 0, 0.35 }, { 0.37, 0.35, 0.32 })
    box:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, -self.y)
    box:SetWidth(self.width)
    G.box = box
    G.inner = self.width - 24

    function G:Add(h, gap)
      local y = self.y
      self.y = self.y + h + (gap or 8)
      return -y
    end
    function G:Check(label, key, x, w)
      local cb = UI.Check(self.box, label, 10 + (x or 0), nil)
      cb.key = key
      cb:SetScript("OnClick", function() P.set(this.key, this:GetChecked() and true or false) end)
      table.insert(P.refresh, function() cb:SetChecked(P.get(key)) end)
      return cb
    end
    -- checks in two columns: list = { { label, key }, ... }
    function G:Checks(list)
      local half = math.floor(self.inner / 2)
      for i = 1, table.getn(list), 2 do
        local y = self:Add(22, 6)
        for c = 0, 1 do
          local item = list[i + c]
          if item then
            local cb = self:Check(item[1], item[2], c * half)
            cb:SetPoint("TOPLEFT", self.box, "TOPLEFT", 10 + c * half, y)
          end
        end
      end
    end
    -- a row of radio buttons: options = { { value, text }, ... }
    function G:Radios(label, key, options)
      local y = self:Add(22, 8)
      local x = 12
      if label then
        local t = UI.Text(self.box, "GameFontHighlight")
        t:SetPoint("TOPLEFT", self.box, "TOPLEFT", x, y - 5)
        t:SetText(label)
        x = x + t:GetStringWidth() + 14
      end
      local radios = {}
      for i = 1, table.getn(options) do
        local r = UI.Radio(self.box, options[i][2])
        r:SetPoint("TOPLEFT", self.box, "TOPLEFT", x, y)
        r.value = options[i][1]
        r:SetScript("OnClick", function()
          P.set(key, this.value)
          for j = 1, table.getn(radios) do radios[j]:SetOn(radios[j].value == this.value) end
        end)
        x = x + r:GetWidth() + 4
        table.insert(radios, r)
      end
      table.insert(P.refresh, function()
        local v = P.get(key)
        for j = 1, table.getn(radios) do radios[j]:SetOn(radios[j].value == v) end
      end)
    end
    -- up to two sliders side by side: list = { { key, title(v) -> text, min, max, step, low, high }, ... }
    function G:Sliders(list)
      local y = self:Add(44, 10)
      for i = 1, table.getn(list) do
        local d = list[i]
        local s = UI.Slider(self.box, d[3], d[4], d[5], d[6], d[7])
        s:SetPoint("TOPLEFT", self.box, "TOPLEFT", 14 + (i - 1) * math.floor(self.inner / 2 + 6), y - 14)
        s.key, s.title = d[1], d[2]
        s:SetScript("OnValueChanged", function()
          local step = this.step
          local v = math.floor(this:GetValue() / step + 0.5) * step
          this.label:SetText(this.title(v))
          P.set(this.key, v)
        end)
        table.insert(P.refresh, function()
          local v = P.get(s.key) or d[3]
          s:SetValue(v)
          s.label:SetText(s.title(v))
        end)
      end
    end
    -- color squares; key stores { r, g, b }
    function G:Swatches(label, key, colors)
      local y = self:Add(20, 8)
      local t = UI.Text(self.box, "GameFontHighlight")
      t:SetPoint("TOPLEFT", self.box, "TOPLEFT", 12, y - 3)
      t:SetText(label)
      local x, sw = 12 + t:GetStringWidth() + 12, {}
      for i = 1, table.getn(colors) do
        local c = colors[i]
        local b = CreateFrame("Button", nil, self.box)
        b:SetWidth(18)
        b:SetHeight(18)
        b:SetPoint("TOPLEFT", self.box, "TOPLEFT", x, y)
        b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        b:SetBackdropColor(c[1], c[2], c[3], 1)
        b.color = c
        b:SetScript("OnClick", function()
          P.set(key, { this.color[1], this.color[2], this.color[3] })
          for j = 1, table.getn(sw) do sw[j]:Mark() end
        end)
        b.Mark = function()
          local v = P.get(key)
          local on = v and math.abs(v[1] - b.color[1]) < 0.01 and math.abs(v[2] - b.color[2]) < 0.01 and math.abs(v[3] - b.color[3]) < 0.01
          if on then b:SetBackdropBorderColor(1, 1, 1, 1) else b:SetBackdropBorderColor(0, 0, 0, 1) end
        end
        table.insert(sw, b)
        x = x + 26
      end
      self.swatchEnd = x
      self.swatchY = y
      table.insert(P.refresh, function() for j = 1, table.getn(sw) do sw[j]:Mark() end end)
    end
    function G:Note(text)
      local t = UI.Text(self.box, "GameFontHighlightSmall", "LEFT", 0.62, 0.62, 0.62)
      t:SetWidth(self.inner)
      t:SetText(text)
      t:SetPoint("TOPLEFT", self.box, "TOPLEFT", 12, -self.y)
      self:Add(t:GetHeight(), 8)
    end
    -- buttons = { { text, fn }, ... }
    function G:Buttons(buttons)
      local y, x = self:Add(22, 8), 12
      for i = 1, table.getn(buttons) do
        local b = UI.Button(self.box, buttons[i][1], buttons[i][2])
        b:SetPoint("TOPLEFT", self.box, "TOPLEFT", x, y)
        x = x + b:GetWidth() + 8
      end
    end
    -- picture tiles that act like radios: tiles = { { value, text, draw(tileFrame) }, ... }
    function G:Tiles(key, tiles, perRow, tw, th)
      local gap = math.floor((self.inner - perRow * tw) / (perRow - 1))
      local list = {}
      for i = 1, table.getn(tiles) do
        local col = math.mod(i - 1, perRow)
        if col == 0 then self.rowY = self:Add(th + 18, 10) end
        local t = CreateFrame("Button", nil, self.box)
        t:SetWidth(tw)
        t:SetHeight(th)
        t:SetPoint("TOPLEFT", self.box, "TOPLEFT", 12 + col * (tw + gap), self.rowY)
        t:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        t:SetBackdropColor(0.09, 0.09, 0.09, 1)
        t.value = tiles[i][1]
        -- a thick gold frame just outside the picked tile
        t.pick = CreateFrame("Frame", nil, t)
        t.pick:SetPoint("TOPLEFT", t, "TOPLEFT", -3, 3)
        t.pick:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", 3, -3)
        t.pick:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
        t.pick:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 1)
        t.pick:Hide()
        tiles[i][3](t)
        t.label = UI.Text(self.box, "GameFontHighlightSmall", "CENTER")
        t.label:SetPoint("TOP", t, "BOTTOM", 0, -4)
        t.label:SetText(tiles[i][2])
        t:SetScript("OnClick", function()
          P.set(key, this.value)
          for j = 1, table.getn(list) do list[j]:Mark() end
        end)
        t.Mark = function()
          if P.get(key) == t.value then
            t:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 1)
            t.label:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
            t.pick:Show()
          else
            t:SetBackdropBorderColor(0.24, 0.23, 0.21, 1)
            t.label:SetTextColor(0.75, 0.75, 0.75)
            t.pick:Hide()
          end
        end
        table.insert(list, t)
      end
      table.insert(P.refresh, function() for j = 1, table.getn(list) do list[j]:Mark() end end)
    end
    function G:Done()
      self.box:SetHeight(self.y + 4)
      self.page:Add(self.y + 4, 14)
    end
    return G
  end

  function P:Refresh()
    self.filling = true
    for i = 1, table.getn(self.refresh) do self.refresh[i]() end
    self.filling = false
    self.frame:SetHeight(self.y)
  end

  -- grays out everything under the enable row and blocks clicks on it
  function P:SetEnabled(on)
    if not self.contentTop then return end
    if not self.blocker then
      self.blocker = CreateFrame("Frame", nil, self.frame)
      self.blocker:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, -self.contentTop)
      self.blocker:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", 0, 0)
      self.blocker:EnableMouse(true)
      self.blocker:SetFrameLevel(self.frame:GetFrameLevel() + 20)
      local veil = self.blocker:CreateTexture(nil, "OVERLAY")
      veil:SetTexture("Interface\\Buttons\\WHITE8X8")
      veil:SetVertexColor(0, 0, 0, 0.55)
      veil:SetAllPoints(self.blocker)
    end
    if on then self.blocker:Hide(); self.notice:Hide() else self.blocker:Show(); self.notice:Show() end
  end

  return P
end

-- ---------------------------------------------------------------- single controls
function UI.Check(parent, label, x, y)
  local name = Name("Check")
  local cb = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
  cb:SetWidth(24)
  cb:SetHeight(24)
  if y then cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y) end
  cb.text = getglobal(name .. "Text")
  cb.text:SetFontObject(GameFontHighlight)
  cb.text:SetText(label)
  return cb
end

-- one choice of several, drawn as a button: the picked one has a deep gold fill, a bright gold
-- edge and white text, the others are dark with grey text, so the choice reads at a glance.
-- (Dark text on bright gold smeared: the game's font renderer draws a dark edge around text.)
function UI.Radio(parent, label)
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(22)
  b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetTexture("Interface\\Buttons\\WHITE8X8")
  hl:SetVertexColor(1, 1, 1, 0.08)
  hl:SetAllPoints(b)
  local t = UI.Text(b, "GameFontHighlightSmall", "CENTER")
  t:SetPoint("CENTER", b, "CENTER", 0, 0)
  t:SetText(label)
  b:SetWidth(t:GetStringWidth() + 22)
  b.SetOn = function(self, v)
    if v then
      self:SetBackdropColor(0.45, 0.33, 0.04, 0.95)
      self:SetBackdropBorderColor(1, 0.82, 0, 1)
      t:SetTextColor(1, 1, 1)
    else
      self:SetBackdropColor(0.12, 0.11, 0.1, 0.95)
      self:SetBackdropBorderColor(0.37, 0.35, 0.32, 1)
      t:SetTextColor(0.75, 0.75, 0.75)
    end
  end
  b:SetOn(false)
  return b
end

function UI.Slider(parent, min, max, step, low, high)
  local name = Name("Slider")
  local s = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
  s:SetWidth(200)
  s:SetMinMaxValues(min, max)
  s:SetValueStep(step)
  s.step = step
  s.label = getglobal(name .. "Text")
  getglobal(name .. "Low"):SetText(low or "")
  getglobal(name .. "High"):SetText(high or "")
  return s
end

function UI.Button(parent, text, fn)
  local b = CreateFrame("Button", Name("Button"), parent, "UIPanelButtonTemplate")
  b:SetText(text)
  b:SetWidth(math.max(90, (b.GetTextWidth and b:GetTextWidth() or 60) + 28))
  b:SetHeight(22)
  b:SetScript("OnClick", fn)
  return b
end
