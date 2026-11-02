-- Nameplates: our own enemy nameplates. Bosses, guardians (from the game's AZS_UNITS) and your
-- current target get a full plate with name, health percent and, on your target, its debuffs.
-- Every other enemy gets a tiny health bar, so a crowded screen stays readable. Your target
-- gets a gold edge and sits on top. Like the old QuietPlates, it hides the native plate (and any
-- other addon's skin on it) and draws its own bar on the plate; the plate itself keeps its
-- position, clicks and health. Friendly plates are left alone.

local BAR = "Interface\\TargetingFrame\\UI-StatusBar"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
-- edge color per tier
local TINT = { final = { 1, 0.5, 0 }, boss = { 1, 0.5, 0 }, guardian = { 0.78, 0.5, 1 } }
local BIG = { final = 1.15, boss = 1.15, guardian = 1 }   -- kinds that always get a full plate, and its scale
local DEBUFFS = 8

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
  own.edge = own:CreateTexture(nil, "BORDER")
  own.edge:SetTexture(WHITE)
  own.edge:SetPoint("TOPLEFT", own, "TOPLEFT", -1, 1)
  own.edge:SetPoint("BOTTOMRIGHT", own, "BOTTOMRIGHT", 1, -1)
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
  -- debuff icons in a row under the bar
  own.auras = CreateFrame("Frame", nil, own)
  own.auras:EnableMouse(false)
  own.auras:SetPoint("TOPLEFT", own, "BOTTOMLEFT", 0, -3)
  own.auras:SetWidth(1)
  own.auras:SetHeight(1)
  own.icons = {}
  st.own = own
  st.childCount = -1
end

local function Icon(own, i)
  local ic = own.icons[i]
  if ic then return ic end
  ic = CreateFrame("Frame", nil, own.auras)
  ic:EnableMouse(false)
  ic:SetFrameLevel(own.auras:GetFrameLevel())
  ic.tex = ic:CreateTexture(nil, "ARTWORK")
  ic.tex:SetAllPoints(ic)
  ic.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  ic.border = ic:CreateTexture(nil, "BACKGROUND")
  ic.border:SetTexture(WHITE)
  ic.border:SetVertexColor(0, 0, 0, 1)
  ic.border:SetPoint("TOPLEFT", ic, "TOPLEFT", -1, 1)
  ic.border:SetPoint("BOTTOMRIGHT", ic, "BOTTOMRIGHT", 1, -1)
  ic.count = ic:CreateFontString(nil, "OVERLAY")
  ic.count:SetFont(FONT, 9, "OUTLINE")
  ic.count:SetPoint("BOTTOMRIGHT", ic, "BOTTOMRIGHT", 2, -1)
  own.icons[i] = ic
  return ic
end

-- the target's debuffs (only the target can be asked: plates have no unit of their own)
local function Debuffs(own, show)
  local n = 0
  if show then
    local size = math.max(10, math.floor(own.h * 1.6 + 0.5))
    for i = 1, DEBUFFS do
      local tex, count = UnitDebuff("target", i)
      if not tex then break end
      n = i
      local ic = Icon(own, i)
      ic:SetWidth(size)
      ic:SetHeight(size)
      ic:ClearAllPoints()
      ic:SetPoint("TOPLEFT", own.auras, "TOPLEFT", (i - 1) * (size + 3), 0)
      ic.tex:SetTexture(tex)
      ic.count:SetText((count and count > 1) and count or "")
      ic:Show()
    end
  end
  for i = n + 1, table.getn(own.icons) do own.icons[i]:Hide() end
end

-- hostile red, neutral yellow, tapped/grey as the game colors it, softened a little
local function BarColor(r, g, b)
  if r > 0.9 and g < 0.2 and b < 0.2 then return 0.75, 0.18, 0.1 end
  if r > 0.9 and g > 0.9 and b < 0.2 then return 0.9, 0.75, 0 end
  return r, g, b
end

-- the game's bosses and guardians by name -> kind
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

local function Paint(st, kind, isTarget)
  if not st.own then Build(st) end
  Blank(st)
  local own = st.own
  local full = BIG[kind] or isTarget
  local scale, alpha, w, h
  if full then
    scale, alpha = BIG[kind] or 1, 1
    w, h = db.width * db.plateScale, db.height * db.plateScale
  else
    scale, alpha = 1, db.smallAlpha
    w, h = db.smallWidth * db.smallScale, 3 * db.smallScale
  end
  w, h = math.floor(w + 0.5), math.max(2, math.floor(h + 0.5))
  if own.scale ~= scale then own:SetScale(scale); own.scale = scale end
  if own.alpha ~= alpha then own:SetAlpha(alpha); own.alpha = alpha end
  if own.w ~= w or own.h ~= h then
    own:SetWidth(w); own:SetHeight(h); own.w, own.h = w, h
  end
  -- the target draws over the plates around it. Child frames keep their own level when the
  -- parent's changes, so the bar and icons are lifted with it (or the black back hides them).
  if own.isTarget ~= isTarget then
    local level = st.plate:GetFrameLevel() + (isTarget and 30 or 1)
    own:SetFrameLevel(level)
    own.health:SetFrameLevel(level + 1)
    own.auras:SetFrameLevel(level + 2)
    for i = 1, table.getn(own.icons) do own.icons[i]:SetFrameLevel(level + 2) end
    own.isTarget = isTarget
  end
  if own.fs ~= db.fontSize then
    own.label:SetFont(FONT, db.fontSize, "OUTLINE")
    own.pct:SetFont(FONT, db.fontSize - 1, "OUTLINE")
    own.fs = db.fontSize
  end
  -- 1 px edge: gold on your target, tier color on bosses and guardians, black otherwise
  local tint = TINT[kind]
  if isTarget then own.edge:SetVertexColor(1, 0.82, 0, 1)
  elseif tint then own.edge:SetVertexColor(tint[1], tint[2], tint[3], 1)
  else own.edge:SetVertexColor(0, 0, 0, 1) end
  local low, high = st.bar:GetMinMaxValues()
  own.health:SetMinMaxValues(low, high)
  own.health:SetValue(st.bar:GetValue())
  own.health:SetStatusBarColor(BarColor(st.bar:GetStatusBarColor()))
  own.label:SetText(full and (st.name:GetText() or "") or "")
  own.label:SetTextColor(1, 1, 1)
  local pct = ""
  if full and db.showPercent and high and high > low then
    pct = math.floor((st.bar:GetValue() - low) / (high - low) * 100 + 0.5) .. "%"
  end
  own.pct:SetText(pct)
  Debuffs(own, isTarget and db.debuffs)
  own:Show()
end

-- The one plate that is your target. A plate only knows its name and health bar, so several
-- enemies with your target's name all look alike: keep those whose health matches the target's
-- too, stay on the plate picked last time while it still matches, and otherwise take the one
-- nearest the middle of the screen (where your hero is, and where Tab looks first).
local lastTarget
local targetEvents = CreateFrame("Frame")
targetEvents:RegisterEvent("PLAYER_TARGET_CHANGED")
targetEvents:SetScript("OnEvent", function() lastTarget = nil end)

local function TargetPlate(plates)
  if not UnitExists("target") or UnitIsDead("target") then lastTarget = nil return nil end
  local tName = UnitName("target")
  local tMax = UnitHealthMax("target") or 0
  local tFrac = tMax > 0 and (UnitHealth("target") or 0) / tMax or nil
  local cx, cy = WorldFrame:GetCenter()
  local best, bestDist
  for plate in pairs(plates) do
    local st = states[plate]
    if st and plate:IsShown() and st.name:GetText() == tName then
      local low, high = st.bar:GetMinMaxValues()
      local match = true
      if tFrac and high and high > low then
        match = math.abs((st.bar:GetValue() - low) / (high - low) - tFrac) < 0.02
      end
      if match then
        if plate == lastTarget then return plate end
        local px, py = plate:GetCenter()
        local dist = px and ((px - cx) * (px - cx) + (py - cy) * (py - cy)) or 1e12
        if not best or dist < bestDist then best, bestDist = plate, dist end
      end
    end
  end
  lastTarget = best
  return best
end

local function Tick()
  wait = wait + (arg1 or 0)
  if wait < 0.05 then return end
  wait = 0
  local plates = QOL.PlateList()
  local kinds = Kinds()
  local targetPlate = TargetPlate(plates)
  for plate in pairs(plates) do
    local st = states[plate] or Learn(plate)
    if st then
      if plate:IsShown() and not QOL.PlateIsFriendly(plate) then
        Paint(st, kinds[st.name:GetText() or ""] or "normal", plate == targetPlate)
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
  desc = "Ordinary enemies get a tiny health bar. Bosses, guardians and your target get a full nameplate, and your target shows its debuffs.",
  default = true,
  defaults = { width = 110, height = 9, fontSize = 10, showPercent = true, debuffs = true, plateScale = 1,
    smallWidth = 36, smallScale = 1, smallAlpha = 0.7 },
  Enable = function(mdb)
    db = mdb
    -- settings from 0.2 that are gone: busy-fight shrinking and per-tier sizes
    db.calm, db.threshold, db.trashSize, db.trashAlpha, db.calmNames, db.otherAlpha = nil, nil, nil, nil, nil, nil
    db.bossSize, db.guardianSize, db.eliteSize, db.targetBoost, db.showName = nil, nil, nil, nil, nil
    driver:SetScript("OnUpdate", Tick)
  end,
  Disable = function()
    driver:SetScript("OnUpdate", nil)
    for _, st in pairs(states) do Unblank(st) end
  end,
  Page = function(P)
    local G = P:Group("Bosses, guardians and your target")
    G:Sliders({
      { "plateScale", function(v) return "Plate size: " .. math.floor(v * 100 + 0.5) .. "%" end, 0.6, 1.6, 0.05, "Small", "Large" },
      { "fontSize", function(v) return "Text size: " .. v end, 7, 16, 1, "Small", "Large" },
    })
    G:Checks({ { "Show health percent", "showPercent" }, { "Show my target's debuffs", "debuffs" } })
    G:Done()
    G = P:Group("Other enemies")
    G:Sliders({
      { "smallScale", function(v) return "Bar size: " .. math.floor(v * 100 + 0.5) .. "%" end, 0.5, 2, 0.05, "Small", "Large" },
      { "smallAlpha", function(v) return "Opacity: " .. math.floor(v * 100 + 0.5) .. "%" end, 0.2, 1, 0.05, "Faint", "Solid" },
    })
    G:Note("A tiny health bar with no name. Works with the game's own nameplates; turn off other nameplate addons so they don't fight.")
    G:Done()
  end,
})
