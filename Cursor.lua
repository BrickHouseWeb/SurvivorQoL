-- Cursor: ways to keep track of the mouse on a crowded screen. One of six styles around the
-- cursor and an optional trail. Shaking the mouse makes it big for a moment.

local M = QOL.media
local db
local holder = CreateFrame("Frame", nil, UIParent)
holder:SetFrameStrata("TOOLTIP")
holder:SetAllPoints(UIParent)
holder:EnableMouse(false)
holder:Hide()

local function Tex(file, layer, blend)
  local t = holder:CreateTexture(nil, layer or "OVERLAY")
  t:SetTexture(file)
  if blend then t:SetBlendMode(blend) end
  t:Hide()
  return t
end

local function At(t, x, y, w, h)
  t:ClearAllPoints()
  t:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
  t:SetWidth(w)
  t:SetHeight(h or w)
  t:Show()
end

-- turns a square texture by a radians around its middle
local function Turn(t, a)
  local s, c = math.sin(a), math.cos(a)
  local function P(x, y)
    x, y = x - 0.5, y - 0.5
    return 0.5 + x * c - y * s, 0.5 + x * s + y * c
  end
  local ulx, uly = P(0, 0)
  local llx, lly = P(0, 1)
  local urx, ury = P(1, 0)
  local lrx, lry = P(1, 1)
  t:SetTexCoord(ulx, uly, llx, lly, urx, ury, lrx, lry)
end

-- ---------------------------------------------------------------- pieces
local glow = Tex(M .. "glow", "ARTWORK", "ADD")
local ring = Tex(M .. "ring2", "OVERLAY", "ADD")
local reticle = Tex(M .. "reticle", "OVERLAY", "ADD")
local pip = Tex(M .. "dot", "OVERLAY", "ADD")
local lines = {}
for i = 1, 4 do lines[i] = Tex("Interface\\Buttons\\WHITE8X8", "OVERLAY") end
local waves = {}
for i = 1, 3 do waves[i] = Tex(M .. "ring1", "OVERLAY", "ADD") end
local spot = Tex(M .. "spotlight", "BACKGROUND")
local shade = {}
for i = 1, 4 do shade[i] = Tex("Interface\\Buttons\\WHITE8X8", "BACKGROUND") end
local all = { glow, ring, reticle, pip, spot, lines[1], lines[2], lines[3], lines[4], waves[1], waves[2], waves[3],
  shade[1], shade[2], shade[3], shade[4] }

local TRAIL = 30
local dots, nextDot = {}, 1
for i = 1, TRAIL do
  dots[i] = Tex(M .. "dot", "ARTWORK", "ADD")
  dots[i].age = 99
end

local function HideAll()
  for i = 1, table.getn(all) do all[i]:Hide() end
end
local function HideTrail()
  for i = 1, TRAIL do dots[i]:Hide(); dots[i].age = 99 end
end

-- ---------------------------------------------------------------- color
local function Color()
  if db.classColor and RAID_CLASS_COLORS then
    local _, class = UnitClass("player")
    local c = class and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
  end
  return db.color[1], db.color[2], db.color[3]
end

-- ---------------------------------------------------------------- styles
local spin = 0
local DRAW = {}
DRAW.halo = function(x, y, S, r, g, b, a)
  At(glow, x, y, S * 1.7)
  glow:SetVertexColor(r, g, b, a * 0.35)
  At(ring, x, y, S)
  ring:SetVertexColor(r, g, b, a)
end
DRAW.reticle = function(x, y, S, r, g, b, a)
  At(reticle, x, y, S)
  reticle:SetVertexColor(r, g, b, a)
  Turn(reticle, spin * 0.8)
  At(pip, x, y, 5)
  pip:SetVertexColor(r, g, b, a)
end
DRAW.crosshair = function(x, y, S, r, g, b, a)
  local len, gap, w = S * 0.55, S * 0.28, db.thickness + 1
  local spots = { { x - gap - len / 2, y, len, w }, { x + gap + len / 2, y, len, w }, { x, y + gap + len / 2, w, len }, { x, y - gap - len / 2, w, len } }
  for i = 1, 4 do
    At(lines[i], spots[i][1], spots[i][2], spots[i][3], spots[i][4])
    lines[i]:SetVertexColor(r, g, b, a)
  end
end
DRAW.spotlight = function(x, y, S, r, g, b, a)
  -- a clear circle around the mouse, the rest of the screen dimmed
  local D = S * 6
  local W, H = UIParent:GetWidth(), UIParent:GetHeight()
  At(spot, x, y, D)
  spot:SetVertexColor(0, 0, 0, a * 0.65)
  local half = D / 2
  local boxes = { { 0, y + half, W, H }, { 0, 0, W, y - half }, { 0, y - half, x - half, y + half }, { x + half, y - half, W, y + half } }
  for i = 1, 4 do
    local bx = boxes[i]
    local w, h = bx[3] - bx[1], bx[4] - bx[2]
    if w > 0 and h > 0 then
      shade[i]:ClearAllPoints()
      shade[i]:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", bx[1], bx[2])
      shade[i]:SetWidth(w)
      shade[i]:SetHeight(h)
      shade[i]:SetVertexColor(0, 0, 0, a * 0.65)
      shade[i]:Show()
    else
      shade[i]:Hide()
    end
  end
end
DRAW.sonar = function(x, y, S, r, g, b, a)
  for i = 1, 3 do
    local t = math.mod(spin * 0.7 + (i - 1) / 3, 1)
    At(waves[i], x, y, S * (0.4 + t * 1.1))
    waves[i]:SetVertexColor(r, g, b, a * (1 - t))
  end
end
DRAW.laser = function(x, y, S, r, g, b, a)
  local W, H, w = UIParent:GetWidth(), UIParent:GetHeight(), db.thickness
  lines[1]:ClearAllPoints()
  lines[1]:SetPoint("LEFT", UIParent, "BOTTOMLEFT", 0, y)
  lines[1]:SetWidth(W)
  lines[1]:SetHeight(w)
  lines[1]:SetVertexColor(r, g, b, a * 0.7)
  lines[1]:Show()
  lines[2]:ClearAllPoints()
  lines[2]:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", x, 0)
  lines[2]:SetWidth(w)
  lines[2]:SetHeight(H)
  lines[2]:SetVertexColor(r, g, b, a * 0.7)
  lines[2]:Show()
  At(ring, x, y, S * 0.45)
  ring:SetVertexColor(r, g, b, a)
end

-- ---------------------------------------------------------------- shake to find
local lastX, lastDir, flips, flipT, boost = nil, 0, 0, 0, 0
local function Shake(x, dt)
  if lastX then
    local dx = x - lastX
    if math.abs(dx) > 6 then
      local dir = dx > 0 and 1 or -1
      if dir ~= lastDir then
        flips = flips + 1
        lastDir = dir
        flipT = 0
      end
    end
  end
  flipT = flipT + dt
  if flipT > 0.25 then flips = 0 end
  if flips >= 5 then boost = 1; flips = 0 end
  boost = math.max(0, boost - dt * 0.8)
end

-- ---------------------------------------------------------------- frame loop
local trailX, trailY = nil, nil
local function Tick()
  local dt = arg1 or 0
  spin = spin + dt
  local s = UIParent:GetEffectiveScale()
  local cx, cy = GetCursorPosition()
  local x, y = cx / s, cy / s
  local turning = db.hideTurning and IsMouseButtonDown and IsMouseButtonDown("RightButton")
  -- while Steer Mode (or any mouselook) has the mouse, the cursor is hidden and frozen in place,
  -- so a ring drawn there would just sit where you last clicked
  local looking = QOL.steering or (IsMouselooking and IsMouselooking())
  if turning or looking or (db.onlyRun and not QOL.InRun()) then
    HideAll(); HideTrail()
    trailX = nil
    return
  end
  if db.shake then Shake(x, dt) end
  lastX = x
  local r, g, b = Color()
  local a = db.opacity
  local S = db.size * (1 + boost * 1.6)
  if db.combatBig and UnitAffectingCombat("player") then S = S * 1.25 end

  HideAll()
  local draw = DRAW[db.style] or DRAW.halo
  draw(x, y, S, r, g, b, a)

  -- trail: evenly spaced dots along the path since last frame, fading out
  if db.trail ~= "off" then
    local step = db.trail == "sparkles" and 9 or 5
    if trailX then
      local dx, dy = x - trailX, y - trailY
      local dist = math.sqrt(dx * dx + dy * dy)
      if dist >= step then
        local n = math.min(TRAIL, math.floor(dist / step))
        for i = 1, n do
          local d = dots[nextDot]
          nextDot = math.mod(nextDot, TRAIL) + 1
          d.age = 0
          d.x, d.y = trailX + dx * i / n, trailY + dy * i / n
          if db.trail == "sparkles" then
            d.x, d.y = d.x + math.random(-6, 6), d.y + math.random(-6, 6)
          end
        end
        trailX, trailY = x, y
      end
    else
      trailX, trailY = x, y
    end
    local life = db.trailLen
    for i = 1, TRAIL do
      local d = dots[i]
      if d.age < life then
        d.age = d.age + dt
        local left = 1 - d.age / life
        if left <= 0 then
          d:Hide()
        else
          local w = db.trailWidth * (db.trail == "comet" and left or (0.45 + 0.55 * left))
          At(d, d.x, d.y, w)
          d:SetVertexColor(r, g, b, a * (db.trail == "comet" and left or 0.7 * left))
        end
      end
    end
  end

end

-- textures that depend on settings
local function Apply()
  local file = M .. "ring" .. db.thickness
  ring:SetTexture(file)
  for i = 1, 3 do waves[i]:SetTexture(file) end
  for i = 1, TRAIL do dots[i]:SetTexture(db.trail == "sparkles" and M .. "sparkle" or M .. "dot") end
  if db.trail == "off" then HideTrail() end
end

-- ---------------------------------------------------------------- settings page previews
local POINT = "Interface\\Cursor\\Point"
local function Preview(tile, parts)
  local function T(file, w, h, ox, oy, r, g, b, a, blend)
    local t = tile:CreateTexture(nil, "ARTWORK")
    t:SetTexture(file)
    if blend then t:SetBlendMode(blend) end
    t:SetWidth(w)
    t:SetHeight(h or w)
    t:SetPoint("CENTER", tile, "CENTER", ox or 0, oy or 0)
    t:SetVertexColor(r or 1, g or 0.82, b or 0, a or 1)
    return t
  end
  parts(T)
  local p = tile:CreateTexture(nil, "OVERLAY")
  p:SetTexture(POINT)
  p:SetWidth(18)
  p:SetHeight(18)
  p:SetPoint("TOPLEFT", tile, "CENTER", -3, 3)
end

local TILES = {
  { "halo", "Halo", function(t) Preview(t, function(T) T(M .. "glow", 64, nil, 0, 0, 1, 0.82, 0, 0.35, "ADD"); T(M .. "ring2", 38) end) end },
  { "reticle", "Reticle", function(t) Preview(t, function(T) T(M .. "reticle", 42); T(M .. "dot", 5) end) end },
  { "crosshair", "Crosshair", function(t) Preview(t, function(T)
    T("Interface\\Buttons\\WHITE8X8", 24, 2, -28, 0); T("Interface\\Buttons\\WHITE8X8", 24, 2, 28, 0)
    T("Interface\\Buttons\\WHITE8X8", 2, 18, 0, 22); T("Interface\\Buttons\\WHITE8X8", 2, 18, 0, -22) end) end },
  -- cropped top and bottom so the dark edge stays inside the tile
  { "spotlight", "Spotlight", function(t) Preview(t, function(T) T(M .. "spotlight", 136, 76, 0, 0, 0, 0, 0, 0.85):SetTexCoord(0, 1, 0.22, 0.78) end) end },
  { "sonar", "Sonar", function(t) Preview(t, function(T) T(M .. "ring1", 22); T(M .. "ring1", 40, nil, 0, 0, 1, 0.82, 0, 0.6); T(M .. "ring1", 58, nil, 0, 0, 1, 0.82, 0, 0.3) end) end },
  { "laser", "Laser lines", function(t) Preview(t, function(T)
    T("Interface\\Buttons\\WHITE8X8", 134, 1, 0, 0, 1, 0.3, 0.3, 0.7); T("Interface\\Buttons\\WHITE8X8", 1, 74, 0, 0, 1, 0.3, 0.3, 0.7)
    T(M .. "ring2", 16, nil, 0, 0, 1, 0.3, 0.3) end) end },
}

QOL.Register({
  key = "cursor",
  label = "Cursor",
  glyph = "g_cross",
  desc = "Ways to keep track of your mouse when the screen is full. Pick a style and add a trail.",
  default = true,
  defaults = { style = "halo", size = 22, thickness = 2, opacity = 0.9, color = { 0.7, 0.42, 1 }, classColor = true,
    trail = "glow", trailLen = 0.4, trailWidth = 14,
    shake = false, hideTurning = true, combatBig = false, onlyRun = false },
  Enable = function(mdb)
    db = mdb
    Apply()
    holder:Show()
    holder:SetScript("OnUpdate", Tick)
  end,
  Disable = function()
    holder:SetScript("OnUpdate", nil)
    HideAll(); HideTrail()
    holder:Hide()
  end,
  Apply = Apply,
  Page = function(P)
    local G = P:Group("Style")
    G:Tiles("style", TILES, 3, 136, 76)
    G:Done()
    G = P:Group("Look")
    G:Sliders({
      { "size", function(v) return "Size: " .. v .. " px" end, 20, 120, 2, "Small", "Large" },
      { "thickness", function(v) return "Thickness: " .. ({ "Thin", "Medium", "Thick" })[v] end, 1, 3, 1, "Thin", "Thick" },
    })
    G:Swatches("Color", "color", { { 1, 0.82, 0 }, { 1, 1, 1 }, { 1, 0.3, 0.3 }, { 0.25, 0.83, 0.42 }, { 0.3, 0.65, 1 }, { 0.7, 0.42, 1 } })
    local cc = G:Check("Use my class color", "classColor")
    cc:SetPoint("TOPLEFT", G.box, "TOPLEFT", G.swatchEnd + 8, G.swatchY + 3)
    G:Done()
    G = P:Group("Trail")
    G:Radios(nil, "trail", { { "off", "Off" }, { "glow", "Glow" }, { "comet", "Comet" }, { "sparkles", "Sparkles" } })
    G:Done()
    G = P:Group("Extras")
    G:Checks({ { "Shake the mouse to find it", "shake" }, { "Hide while turning", "hideTurning" } })
    G:Done()
  end,
})
