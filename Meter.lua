-- Damage Meter: bigger text on the game's own damage meter (AZSMeterFrame), which has no setting
-- for it. Every text on the meter keeps its own font; only its size is multiplied. The game can
-- build rows late or reset their fonts, so the meter is walked again every half second.

local db
local wait = 0
local driver = CreateFrame("Frame")
local orig = {}   -- font string -> { font, size, flags } as the game made it

local function Walk(frame, fn, depth)
  local regions = { frame:GetRegions() }
  for i = 1, table.getn(regions) do
    local r = regions[i]
    if r and r.GetObjectType and r:GetObjectType() == "FontString" then fn(r) end
  end
  if depth <= 0 then return end
  local children = { frame:GetChildren() }
  for i = 1, table.getn(children) do Walk(children[i], fn, depth - 1) end
end

local function Size(fs)
  local font, size, flags = fs:GetFont()
  if not font or not size then return end
  local o = orig[fs]
  -- a size we did not set means the game (re)made this text: take it as the new original
  if not o or math.abs(size - o.want) > 0.05 then
    o = { font = font, size = size, flags = flags }
    orig[fs] = o
  end
  o.want = o.size * db.textScale
  if math.abs(size - o.want) > 0.05 then fs:SetFont(o.font, o.want, o.flags) end
end

local function Tick()
  wait = wait + (arg1 or 0)
  if wait < 0.5 then return end
  wait = 0
  local f = getglobal("AZSMeterFrame")
  if f and f.GetRegions then Walk(f, Size, 6) end
end

local function Restore()
  for fs, o in pairs(orig) do
    fs:SetFont(o.font, o.size, o.flags)
    orig[fs] = nil
  end
end

QOL.Register({
  key = "meter",
  label = "Damage Meter",
  glyph = "g_meter",
  desc = "Bigger text on the game's own damage meter. Turn the meter on in the game's settings first.",
  default = true,
  defaults = { textScale = 1.35 },
  Enable = function(mdb) db = mdb; wait = 1; driver:SetScript("OnUpdate", Tick) end,
  Disable = function() driver:SetScript("OnUpdate", nil); Restore() end,
  Apply = function() wait = 1 end,
  Page = function(P)
    local G = P:Group("Text")
    G:Sliders({ { "textScale", function(v) return "Text size: " .. math.floor(v * 100 + 0.5) .. "%" end, 0.8, 2, 0.05, "80%", "200%" } })
    G:Note("Only the text gets bigger; the meter keeps its size. Very large text can get cut off in its rows.")
    G:Done()
  end,
})
