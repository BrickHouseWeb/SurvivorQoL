-- Nameplates: our own enemy nameplates, sized by how much the enemy matters. Bosses and
-- guardians (from the game's AZS_UNITS) are big, your target gets a gold border and glow, and
-- once many enemies are on screen the ordinary ones shrink and fade. Like the old QuietPlates,
-- it hides the native plate (and any other addon's skin on it) and draws its own bar on the
-- plate; the plate itself keeps its position, clicks and health. Friendly plates are left alone.

local M = QOL.media
local BORDER = "Interface\\Tooltips\\Nameplate-Border"
local BAR = "Interface\\TargetingFrame\\UI-StatusBar"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
-- name color per tier
local TINT = { final = { 1, 0.5, 0 }, boss = { 1, 0.5, 0 }, guardian = { 0.78, 0.5, 1 }, elite = { 1, 0.82, 0 }, normal = { 1, 1, 1 } }

local db
local states = {}       -- plate -> state
local wait = 0
local driver = CreateFrame("Frame")

local function Learn(plate)
  if states[plate] then return states[plate] end
  local regions = { plate:GetRegions() }
  local name, level
  for i = 1, table.getn(regions) do
    local r = regions[i]
    if r and r.GetObjectType and r:GetObjectType() == "FontString" then
      local t = r:GetText()
      if not name and t and t ~= "" and t ~= "??" and not string.find(t, "^%d+$") then name = r else level = level or r end
    end
  end
  local bar
  local children = { plate:GetChildren() }
  for i = 1, table.getn(children) do
    if children[i].GetObjectType and children[i]:GetObjectType() == "StatusBar" then bar = children[i] break end
  end
  if not name or not bar then return nil end
  local st = { plate = plate, name = name, level = level, bar = bar, regions = regions, others = {}, childCount = -1 }
  states[plate] = st
  return st
end

-- every frame on the plate that is not the native bar or ours: other addons' skins
local function ListOthers(st)
  local n = st.plate:GetNumChildren() or 0
  if n == st.childCount then return end
  st.childCount = n
  for i = table.getn(st.others), 1, -1 do table.remove(st.others, i) end
  local children = { st.plate:GetChildren() }
  for i = 1, n do
    local c = children[i]
    if c and c ~= st.bar and c ~= st.own and c.SetAlpha then table.insert(st.others, c) end
  end
end

local function Blank(st)
  st.bar:SetAlpha(0)
  for i = 1, table.getn(st.regions) do
    local r = st.regions[i]
    if r and r.SetAlpha then r:SetAlpha(0) end
  end
  ListOthers(st)
  for i = 1, table.getn(st.others) do st.others[i]:SetAlpha(0) end
  st.blanked = true
end

local function Unblank(st)
  if st.own then st.own:Hide() end
  if not st.blanked then return end
  st.bar:SetAlpha(1)
  for i = 1, table.getn(st.regions) do
    local r = st.regions[i]
    if r and r.SetAlpha then r:SetAlpha(1) end
  end
  for i = 1, table.getn(st.others) do st.others[i]:SetAlpha(1) end
  st.blanked = nil
end

local function Build(st)
  local own = CreateFrame("Frame", nil, st.plate)
  own:EnableMouse(false)
  own:SetPoint("CENTER", st.plate, "CENTER", 0, 0)
  own.glow = own:CreateTexture(nil, "BACKGROUND")
  own.glow:SetTexture(M .. "glow")
  own.glow:SetBlendMode("ADD")
  own.glow:SetVertexColor(1, 0.82, 0, 0.55)
  own.glow:SetPoint("TOPLEFT", own, "TOPLEFT", -18, 14)
  own.glow:SetPoint("BOTTOMRIGHT", own, "BOTTOMRIGHT", 18, -14)
  own.edge = own:CreateTexture(nil, "BORDER")
  own.edge:SetTexture(WHITE)
  own.back = own:CreateTexture(nil, "ARTWORK")
  own.back:SetTexture(WHITE)
  own.back:SetVertexColor(0, 0, 0, 0.8)
  own.back:SetAllPoints(own)
  own.health = CreateFrame("StatusBar", nil, own)
  own.health:EnableMouse(false)
  own.health:SetAllPoints(own)
  own.health:SetStatusBarTexture(BAR)
  own.label = own:CreateFontString(nil, "OVERLAY")
  own.label:SetPoint("BOTTOM", own, "TOP", 0, 3)
  own.pct = own.health:CreateFontString(nil, "OVERLAY")
  own.pct:SetPoint("RIGHT", own.health, "RIGHT", -2, 0)
  st.own = own
  st.childCount = -1
end

-- hostile red, neutral yellow, tapped/grey as the game colors it, softened a little
local function BarColor(r, g, b)
  if r > 0.9 and g < 0.2 and b < 0.2 then return 0.75, 0.18, 0.1 end
  if r > 0.9 and g > 0.9 and b < 0.2 then return 0.9, 0.75, 0 end
  return r, g, b
end

-- the game's bosses, guardians and elites by name -> kind
local function Kinds()
  local k = {}
  if type(AZS_UNITS) ~= "table" then return k end
  for i = 1, table.getn(AZS_UNITS) do
    local u = AZS_UNITS[i]
    if type(u) == "table" and type(u.name) == "string" and type(u.kind) == "string" then
      if not k[u.name] or u.kind == "final" or u.kind == "boss" then k[u.name] = u.kind end
    end
  end
  return k
end

local function Paint(st, kind, isTarget, calm)
  if not st.own then Build(st) end
  Blank(st)
  local own = st.own
  local scale, alpha = 1, 1
  if kind == "final" or kind == "boss" then scale = db.bossSize
  elseif kind == "guardian" then scale = db.guardianSize
  elseif kind == "elite" then scale = db.eliteSize
  elseif calm then scale, alpha = db.trashSize, db.trashAlpha end
  if isTarget then scale, alpha = math.max(scale, 1) * db.targetBoost, 1 end
  if own.scale ~= scale then own:SetScale(scale); own.scale = scale end
  if own.alpha ~= alpha then own:SetAlpha(alpha); own.alpha = alpha end
  if own.w ~= db.width or own.h ~= db.height then
    own:SetWidth(db.width); own:SetHeight(db.height); own.w, own.h = db.width, db.height
  end
  if own.fs ~= db.fontSize then
    own.label:SetFont(FONT, db.fontSize, "OUTLINE")
    own.pct:SetFont(FONT, db.fontSize - 1, "OUTLINE")
    own.fs = db.fontSize
  end
  -- the target: thick gold edge and a glow; everything else: thin black edge
  local e = isTarget and 2 or 1
  if own.edgeSize ~= e then
    own.edge:ClearAllPoints()
    own.edge:SetPoint("TOPLEFT", own, "TOPLEFT", -e, e)
    own.edge:SetPoint("BOTTOMRIGHT", own, "BOTTOMRIGHT", e, -e)
    own.edgeSize = e
  end
  if isTarget then own.edge:SetVertexColor(1, 0.82, 0, 1) else own.edge:SetVertexColor(0, 0, 0, 1) end
  if isTarget and db.targetGlow then own.glow:Show() else own.glow:Hide() end
  local low, high = st.bar:GetMinMaxValues()
  own.health:SetMinMaxValues(low, high)
  own.health:SetValue(st.bar:GetValue())
  own.health:SetStatusBarColor(BarColor(st.bar:GetStatusBarColor()))
  local t = TINT[kind] or TINT.normal
  local text = ""
  if db.showName and (db.calmNames or kind ~= "normal" or not calm or isTarget) then text = st.name:GetText() or "" end
  own.label:SetText(text)
  own.label:SetTextColor(t[1], t[2], t[3])
  local pct = ""
  if db.showPercent and high and high > low then pct = math.floor((st.bar:GetValue() - low) / (high - low) * 100 + 0.5) .. "%" end
  own.pct:SetText((kind ~= "normal" or not calm or isTarget) and pct or "")
  own:Show()
end

local function Tick()
  wait = wait + (arg1 or 0)
  if wait < 0.05 then return end
  wait = 0
  local plates = QOL.PlateList()
  local kinds = Kinds()
  local tName = UnitExists("target") and UnitName("target")
  local shown = 0
  for plate in pairs(plates) do
    if plate:IsShown() and not QOL.PlateIsFriendly(plate) then shown = shown + 1 end
  end
  local calm = db.calm and shown >= db.threshold
  for plate in pairs(plates) do
    local st = states[plate] or Learn(plate)
    if st then
      if plate:IsShown() and not QOL.PlateIsFriendly(plate) then
        local name = st.name:GetText()
        Paint(st, kinds[name or ""] or "normal", tName and name == tName, calm)
      else
        Unblank(st)
      end
    end
  end
end

QOL.Register({
  key = "nameplates",
  label = "Nameplates",
  glyph = "g_crowd",
  desc = "Our own enemy nameplates. Bosses and guardians are bigger, your target gets a gold border, and when lots of enemies are on screen the ordinary ones shrink and fade so the important ones stand out.",
  default = true,
  defaults = { width = 110, height = 9, fontSize = 10, showName = true, showPercent = true,
    bossSize = 1.4, guardianSize = 1.25, eliteSize = 1.05, targetBoost = 1.15, targetGlow = true,
    calm = true, threshold = 12, trashSize = 0.6, trashAlpha = 0.45, calmNames = true },
  Enable = function(mdb) db = mdb; driver:SetScript("OnUpdate", Tick) end,
  Disable = function()
    driver:SetScript("OnUpdate", nil)
    for _, st in pairs(states) do Unblank(st) end
  end,
  Page = function(P)
    local G = P:Group("Bar")
    G:Sliders({
      { "width", function(v) return "Width: " .. v .. " px" end, 60, 200, 5, "Narrow", "Wide" },
      { "height", function(v) return "Height: " .. v .. " px" end, 4, 20, 1, "Thin", "Tall" },
    })
    G:Sliders({ { "fontSize", function(v) return "Text size: " .. v end, 7, 16, 1, "Small", "Large" } })
    G:Checks({ { "Show the name", "showName" }, { "Show health percent", "showPercent" } })
    G:Done()
    G = P:Group("Size by enemy")
    G:Sliders({
      { "bossSize", function(v) return "Bosses: " .. math.floor(v * 100 + 0.5) .. "%" end, 0.8, 2, 0.05, "80%", "200%" },
      { "guardianSize", function(v) return "Guardians: " .. math.floor(v * 100 + 0.5) .. "%" end, 0.8, 2, 0.05, "80%", "200%" },
    })
    G:Sliders({ { "eliteSize", function(v) return "Elites: " .. math.floor(v * 100 + 0.5) .. "%" end, 0.5, 1.6, 0.05, "50%", "160%" } })
    G:Done()
    G = P:Group("Your target")
    G:Checks({ { "Glow around my target", "targetGlow" } })
    G:Sliders({ { "targetBoost", function(v) return "Target size: +" .. math.floor((v - 1) * 100 + 0.5) .. "%" end, 1, 1.5, 0.05, "Same", "+50%" } })
    G:Note("Your target always gets a thick gold border and stays fully visible.")
    G:Done()
    G = P:Group("Calm crowds")
    G:Checks({ { "Shrink ordinary enemies when it gets busy", "calm" } })
    G:Sliders({ { "threshold", function(v) return v == 0 and "Always" or ("Start at " .. v .. " enemies on screen") end, 0, 50, 1, "Always", "50" } })
    G:Sliders({
      { "trashSize", function(v) return "Their size: " .. math.floor(v * 100 + 0.5) .. "%" end, 0.3, 1, 0.05, "Tiny", "Normal" },
      { "trashAlpha", function(v) return "Visible: " .. math.floor(v * 100 + 0.5) .. "%" end, 0.1, 1, 0.05, "Faint", "Solid" },
    })
    G:Checks({ { "Keep names on ordinary enemies", "calmNames" } })
    G:Note("While it is busy, ordinary enemies hide their health percent (and their name if the box above is off). Bosses, guardians, elites and your target never shrink.")
    G:Done()
  end,
})
