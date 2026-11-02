-- Plate pass-through, part of Steer Mode: native nameplates are mouse-enabled frames on
-- WorldFrame, so a right-click that lands on one never starts turning. Empty each plate's mouse
-- area (same trick SurvivorsDragonUi uses for hidden plates) so clicks reach the world. Holding
-- Shift gives plates their clicks back, to target one. Works with any nameplate addon.

local BORDER = "Interface\\Tooltips\\Nameplate-Border"
local EMPTY = 1000000

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

local function Tick()
  elapsedSince = elapsedSince + arg1
  if elapsedSince < 0.1 then return end
  elapsedSince = 0
  if not WorldFrame then return end
  Discover()
  local pass = not IsShiftKeyDown()
  -- Re-apply every tick: another addon restoring its saved insets would undo ours.
  for plate in pairs(plates) do
    if plate:IsShown() then
      if pass then Each(plate, Empty) else Each(plate, Restore) end
    end
  end
end

-- Steer Mode turns this on and off with itself
function QOL.PlatePassThrough(on)
  if on then
    driver:SetScript("OnUpdate", Tick)
  else
    driver:SetScript("OnUpdate", nil)
    for frame in pairs(orig) do Restore(frame) end
  end
end
