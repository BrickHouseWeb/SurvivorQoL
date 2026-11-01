-- Nameplates: native nameplates are mouse-enabled frames on WorldFrame, so a right-click that
-- lands on one never starts turning. Empty each plate's mouse area (same trick
-- SurvivorsDragonUi uses for hidden plates) so clicks reach the world.

local BORDER = "Interface\\Tooltips\\Nameplate-Border"
local EMPTY = 1000000

local db
local plates = {}
local orig = {}   -- frame -> its insets before we emptied them, for giving clicks back
local seenChildren = 0
local elapsedSince = 0
local driver = CreateFrame("Frame")

local function IsPlate(frame)
  if not frame or not frame.GetRegions then return false end
  local regions = { frame:GetRegions() }
  for i = 1, table.getn(regions) do
    local r = regions[i]
    if r and r.GetObjectType and r:GetObjectType() == "Texture" and r:GetTexture() == BORDER then
      return true
    end
  end
  return false
end

-- green or blue health bar: a friendly plate (Shift-V)
local function IsFriendly(plate)
  local children = { plate:GetChildren() }
  for i = 1, table.getn(children) do
    local c = children[i]
    if c.GetObjectType and c:GetObjectType() == "StatusBar" then
      local r, g, b = c:GetStatusBarColor()
      return (g > r + 0.1 and g > b + 0.1) or (b > r + 0.1 and b > g + 0.1)
    end
  end
  return false
end

local function Empty(frame)
  if not frame.GetHitRectInsets or not frame.SetHitRectInsets then return end
  local l, r, t, b = frame:GetHitRectInsets()
  if l and l >= EMPTY then return end
  if not orig[frame] then orig[frame] = { l or 0, r or 0, t or 0, b or 0 } end
  frame:SetHitRectInsets(EMPTY, EMPTY, EMPTY, EMPTY)
end

local function Restore(frame)
  local i = orig[frame]
  if not i then return end
  frame:SetHitRectInsets(i[1], i[2], i[3], i[4])
  orig[frame] = nil
end

-- The plate and any mouse-enabled child (the health bar, if the client enables it).
local function Each(plate, fn)
  fn(plate)
  local children = { plate:GetChildren() }
  for i = 1, table.getn(children) do
    local c = children[i]
    if orig[c] or (c.IsMouseEnabled and c:IsMouseEnabled()) then fn(c) end
  end
end

local function Discover()
  local count = WorldFrame:GetNumChildren() or 0
  if count < seenChildren then seenChildren = 0 end
  if count == seenChildren then return end
  local children = { WorldFrame:GetChildren() }
  for i = seenChildren + 1, count do
    local f = children[i]
    if not plates[f] and IsPlate(f) then plates[f] = true end
  end
  seenChildren = count
end

-- shared with Calm Crowds: the native plates found so far (plate -> true)
function QOL.PlateList()
  if WorldFrame then Discover() end
  return plates
end
QOL.PlateIsFriendly = IsFriendly

local function Tick()
  elapsedSince = elapsedSince + arg1
  if elapsedSince < 0.1 then return end
  elapsedSince = 0
  if not WorldFrame then return end
  Discover()
  -- Holding Shift, or outside a run when "only during a run" is on: plates click as normal.
  local pass = not (db.shift and IsShiftKeyDown()) and not (db.onlyRun and not QOL.InRun())
  -- Re-apply every tick: another addon restoring its saved insets would undo ours.
  for plate in pairs(plates) do
    if plate:IsShown() then
      if pass and (db.friendly or not IsFriendly(plate)) then Each(plate, Empty) else Each(plate, Restore) end
    end
  end
end

QOL.Register({
  key = "plates",
  label = "Plate Pass-Through",
  glyph = "g_plate",
  desc = "Right-click turning works even with your mouse on a nameplate. Doesn't change how nameplates look, and works with any nameplate addon.",
  default = true,
  defaults = { shift = true, onlyRun = false, friendly = true },
  Enable = function(mdb) db = mdb; driver:SetScript("OnUpdate", Tick) end,
  Disable = function()
    driver:SetScript("OnUpdate", nil)
    for frame in pairs(orig) do Restore(frame) end
  end,
  Page = function(P)
    local G = P:Group("Clicking a nameplate")
    G:Checks({ { "Hold Shift to click a nameplate", "shift" } })
    G:Note("Hold Shift when you want to click a nameplate to target that enemy.")
    G:Done()
  end,
})
