-- Stats panel: your main stats read from AZS_STATS the way the character window shows them
-- (same fields ASBuilder's Now column uses). When a stat changes, the difference shows next
-- to it for a few seconds, so you see what a pick gave you.

-- AZS_STATS field, base, factor, unit: shown value = (field - base) * factor
local ROWS = {
  { label = "Damage", field = "dmg", base = 1, factor = 100, unit = "%", sign = true, icon = "INV_Sword_27" },
  { label = "Cooldowns", field = "cd", base = 1, factor = -100, unit = "%", sign = true, icon = "Spell_Nature_TimeStop" },
  { label = "Crit Chance", field = "crit", base = 0, factor = 100, unit = "%", icon = "Ability_CriticalStrike" },
  { label = "Crit Damage", field = "cm", base = 0, factor = 100, unit = "%", icon = "Ability_Rogue_Eviscerate" },
  { label = "Area", field = "area", base = 1, factor = 100, unit = "%", sign = true, icon = "Spell_Nature_Cyclone" },
  { label = "Speed", field = "spd", base = 1, factor = 100, unit = "%", sign = true, icon = "Ability_Rogue_Sprint" },
  { label = "Armor / DR", field = "arm", base = 0, factor = 100, unit = "%", icon = "INV_Shield_06" },
  { label = "Lifesteal", field = "lch", base = 0, factor = 100, unit = "%", icon = "Spell_Shadow_LifeDrain02" },
  { label = "Pickup", field = "pick", base = 0, factor = 1, unit = " yd", icon = "Spell_Frost_Wisp" },
  { label = "Luck", field = "luck", base = 0, factor = 100, unit = "%", icon = "Spell_Holy_ElunesGrace" },
  { label = "Gold", field = "gold", base = 1, factor = 100, unit = "%", sign = true, icon = "Spell_Holy_SealOfSalvation" },
}

local WIDTH, ROW_H, TOP = 160, 18, 30

local db, last
local f = CreateFrame("Frame", "SurvivorQoLStats", UIParent)
f:SetWidth(WIDTH)
f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
f:SetBackdropBorderColor(0.62, 0.52, 0.32, 1)
f:Hide()

local function Text(font, justify)
  local t = f:CreateFontString(nil, "OVERLAY", font)
  t:SetJustifyH(justify or "LEFT")
  return t
end

local title = Text("GameFontNormal")
title:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -10)
title:SetText("Stats")
f.hint = Text("GameFontDisableSmall", "RIGHT")
f.hint:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -12)
local rule = f:CreateTexture(nil, "ARTWORK")
rule:SetTexture("Interface\\Buttons\\WHITE8X8")
rule:SetVertexColor(0.62, 0.52, 0.32, 0.5)
rule:SetHeight(1)
rule:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -TOP + 3)
rule:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -TOP + 3)

-- one row per stat; rows of hidden stats collapse out of the list
f.rows = {}
for n = 1, table.getn(ROWS) do
  local row = CreateFrame("Frame", nil, f)
  row:SetHeight(ROW_H)
  row:SetWidth(WIDTH - 12)
  -- icons in a frame of their own so the level-up cards' veil doesn't darken them (as in LuckyOdds)
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetTexture("Interface\\Icons\\" .. ROWS[n].icon)
  row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  row.icon:SetWidth(14)
  row.icon:SetHeight(14)
  row.icon:SetPoint("LEFT", row, "LEFT", 6, 0)
  row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
  row.name:SetText(ROWS[n].label)
  row.value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.value:SetJustifyH("RIGHT")
  row.value:SetPoint("RIGHT", row, "RIGHT", -6, 0)
  -- a change pops out just past the panel's right edge, so no column is kept free for it
  row.delta = row:CreateFontString(nil, "OVERLAY")
  row.delta:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
  row.delta:SetJustifyH("LEFT")
  row.delta:SetPoint("LEFT", row, "RIGHT", 10, 0)
  f.rows[n] = row
end

local function Layout()
  local shown = 0
  for n = 1, table.getn(ROWS) do
    local row = f.rows[n]
    if db.show[ROWS[n].field] then
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -TOP - shown * ROW_H)
      row:Show()
      shown = shown + 1
    else
      row:Hide()
    end
  end
  f:SetHeight(TOP + shown * ROW_H + 8)
  f:SetBackdropColor(0.04, 0.04, 0.06, db.alpha)
  f:SetScale(db.scale)
  QOL.Replace("stats")
  if AZS_SetOnTopOfScreens then AZS_SetOnTopOfScreens(f, db.top and true or false) end
end

local function Value(s, r)
  local v = s and tonumber(s[r.field])
  if not v then return nil end
  return math.floor((v - r.base) * r.factor * 10 + 0.5) / 10
end

local function Num(v)
  if v == math.floor(v) then return tostring(v) end
  return string.format("%.1f", v)
end

local function Show(r, v)
  if not v then return "-" end
  local sign = (r.sign and v > 0) and "+" or ""
  return sign .. Num(v) .. r.unit
end

local function Refresh()
  local s = AZS_STATS
  local fresh = type(s) == "table" and next(s) ~= nil
  if not QOL.moving and ((db.hideOutside and not QOL.InRun()) or not (QOL.InRun() or fresh)) then f:Hide() return end
  f:Show()
  -- the game sends AZS_STATS only now and then: keep the last numbers between sends
  if fresh then
    last = last or {}
    for n = 1, table.getn(ROWS) do
      local v = Value(s, ROWS[n])
      local old = last[n]
      if v and old and v ~= old then
        f.rows[n].change, f.rows[n].changedAt = v - old, GetTime()
      end
      if v then last[n] = v end
    end
  end
  f.hint:SetText(last and "" or "open C once")
  local now = GetTime()
  for n = 1, table.getn(ROWS) do
    local r, row = ROWS[n], f.rows[n]
    local v = last and last[n]
    row.value:SetText(Show(r, v))
    if v and v ~= 0 then row.value:SetTextColor(1, 1, 1) else row.value:SetTextColor(0.55, 0.55, 0.55) end
    if db.flash and row.change and now - row.changedAt < db.flashTime then
      local d = row.change
      -- Cooldowns read as a reduction, so a higher number is still better
      row.delta:SetText((d > 0 and "+" or "") .. Num(d))
      if d > 0 then
        row.delta:SetTextColor(0.35, 1, 0.35); row.value:SetTextColor(0.35, 1, 0.35)
      else
        row.delta:SetTextColor(1, 0.4, 0.3); row.value:SetTextColor(1, 0.4, 0.3)
      end
    else
      row.change = nil
      row.delta:SetText("")
    end
  end
end

-- a hidden frame gets no OnUpdate, so the refresh runs on its own frame
local driver, wait = CreateFrame("Frame"), 0
local function Tick()
  wait = wait + arg1
  if wait < 0.25 then return end
  wait = 0
  Refresh()
end

QOL.Movable(f, "stats", "Stats Panel", { "TOPRIGHT", "TOPRIGHT", -230, -420 }, "stats")

QOL.StatsFields = function()
  if type(AZS_STATS) ~= "table" or not next(AZS_STATS) then
    QOL.Print("no stats from the game yet. Open your character window (C) in a run.")
    return
  end
  for k, v in pairs(AZS_STATS) do QOL.Print(tostring(k) .. " = " .. tostring(v)) end
end

local defaultShow = {}
for n = 1, table.getn(ROWS) do defaultShow[ROWS[n].field] = true end
defaultShow.lch, defaultShow.pick, defaultShow.gold = false, false, false

QOL.Register({
  key = "stats",
  label = "Stats Panel",
  glyph = "g_chart",
  desc = "Your main stats during a run. When a pick changes a stat, the difference shows next to it for a few seconds.",
  default = true,
  defaults = { show = defaultShow, flash = true, flashTime = 5, top = true, hideOutside = true, scale = 1, alpha = 0.9 },
  Enable = function(mdb)
    db = mdb
    Layout()
    driver:SetScript("OnUpdate", Tick)
  end,
  Disable = function()
    driver:SetScript("OnUpdate", nil)
    f:Hide()
  end,
  Apply = function() Layout(); Refresh() end,
  Page = function(P, mdb)
    -- the stat boxes write into db.show, a table of their own
    local G = P:Group("Show these stats")
    local third = math.floor(G.inner / 3)
    for i = 1, table.getn(ROWS), 3 do
      local y = G:Add(22, 6)
      for c = 0, 2 do
        local r = ROWS[i + c]
        if r then
          local cb = QOL.UI.Check(G.box, r.label, 10 + c * third, y)
          cb.field = r.field
          cb:SetScript("OnClick", function()
            mdb.show[this.field] = this:GetChecked() and true or false
            if QOL.IsOn(QOL.Module("stats")) then Layout() end
          end)
          table.insert(P.refresh, function() cb:SetChecked(mdb.show[cb.field]) end)
        end
      end
    end
    G:Done()
    G = P:Group("Panel")
    G:Checks({ { "Show the change next to a stat", "flash" }, { "Keep over the level-up cards", "top" }, { "Hide outside a run", "hideOutside" } })
    G:Sliders({
      { "flashTime", function(v) return "Change shows for: " .. v .. " s" end, 1, 10, 1, "1 s", "10 s" },
      { "scale", function(v) return "Scale: " .. math.floor(v * 100 + 0.5) .. "%" end, 0.5, 1.5, 0.05, "50%", "150%" },
    })
    G:Sliders({
      { "alpha", function(v) return "Background: " .. math.floor(v * 100 + 0.5) .. "%" end, 0, 1, 0.05, "Clear", "Solid" },
    })
    G:Done()
  end,
})
