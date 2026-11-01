-- Damage Meter: makes the game's own damage meter (AZSMeterFrame) bigger or smaller. Its text
-- is small and the game has no setting for it, so this scales the whole frame. A frame's anchor
-- offsets are in its own scaled units, so they are divided by the scale to keep the meter in
-- the spot the game put it. The game may build the frame late, so it is looked up every tick.

local db
local wait = 0
local driver = CreateFrame("Frame")
local applied, home   -- scale we set; the frame's own anchor before we touched it

local function Frame() return getglobal("AZSMeterFrame") end

local function Apply(scale)
  local f = Frame()
  if not f or not f.SetScale then return end
  if not home and f:GetNumPoints() == 1 then
    local p, rel, rp, x, y = f:GetPoint(1)
    home = { p, rel, rp, x or 0, y or 0 }
  end
  if applied == scale then return end
  f:SetScale(scale)
  if home then
    f:ClearAllPoints()
    f:SetPoint(home[1], home[2] or UIParent, home[3], home[4] / scale, home[5] / scale)
  end
  applied = scale
end

local function Tick()
  wait = wait + (arg1 or 0)
  if wait < 0.5 then return end
  wait = 0
  Apply(db.scale)
end

QOL.Register({
  key = "meter",
  label = "Damage Meter",
  glyph = "g_meter",
  desc = "Makes the game's own damage meter bigger, text and all. Turn the meter on in the game's settings first.",
  default = true,
  defaults = { scale = 1.3 },
  Enable = function(mdb) db = mdb; applied = nil; driver:SetScript("OnUpdate", Tick) end,
  Disable = function()
    driver:SetScript("OnUpdate", nil)
    Apply(1)
    applied = nil
  end,
  Apply = function() Apply(db.scale) end,
  Page = function(P)
    local G = P:Group("Size")
    G:Sliders({ { "scale", function(v) return "Meter size: " .. math.floor(v * 100 + 0.5) .. "%" end, 0.6, 2.5, 0.05, "60%", "250%" } })
    G:Note("Scales the whole meter, so the text and bars grow together.")
    G:Done()
  end,
})
