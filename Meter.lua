-- Damage Meter: bigger text on the game's own damage meter (AZSMeterFrame), which has no setting
-- for it. The game sets its fonts again as it updates, so a one-off SetFont is undone at once.
-- Instead each text's own SetFont / SetFontObject is wrapped: whatever size the game asks for
-- is multiplied before it lands. The meter is walked every half second for new rows.

local db
local wait = 0
local driver = CreateFrame("Frame")
local wrapped = {}   -- font string -> { SetFont, SetFontObject, font, size, flags }

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

local function Factor() return (db and QOL.IsOn(QOL.Module("meter"))) and db.textScale or 1 end

local function Wrap(fs)
  if wrapped[fs] then return end
  local font, size, flags = fs:GetFont()
  if not font or not size then return end
  local w = { SetFont = fs.SetFont, SetFontObject = fs.SetFontObject, font = font, size = size, flags = flags }
  wrapped[fs] = w
  fs.SetFont = function(self, f, s, fl)
    w.font, w.size, w.flags = f, s, fl
    return w.SetFont(self, f, (s or 12) * Factor(), fl)
  end
  if w.SetFontObject then
    fs.SetFontObject = function(self, obj)
      w.SetFontObject(self, obj)
      local f, s, fl = self:GetFont()
      if f and s then
        w.font, w.size, w.flags = f, s, fl
        w.SetFont(self, f, s * Factor(), fl)
      end
    end
  end
  w.SetFont(fs, font, size * Factor(), flags)
end

-- puts every wrapped text at its game size times the current factor
local function Resize()
  for fs, w in pairs(wrapped) do w.SetFont(fs, w.font, w.size * Factor(), w.flags) end
end

local function Tick()
  wait = wait + (arg1 or 0)
  if wait < 0.5 then return end
  wait = 0
  local f = getglobal("AZSMeterFrame")
  if f and f.GetRegions then Walk(f, Wrap, 8) end
end

-- /qol meter: what the module sees, for when the text does not change
function QOL.MeterInfo()
  local f = getglobal("AZSMeterFrame")
  if not f then QOL.Print("AZSMeterFrame is not there. Turn the meter on in the game first.") return end
  local n, sample = 0, nil
  Walk(f, function(fs) n = n + 1; sample = sample or fs end, 8)
  QOL.Print("meter texts found: " .. n .. ", shown: " .. tostring(f:IsShown()))
  if sample then
    local font, size = sample:GetFont()
    QOL.Print("first text: \"" .. tostring(sample:GetText()) .. "\" size " .. tostring(size) .. " font " .. tostring(font))
  end
end

QOL.Register({
  key = "meter",
  label = "Damage Meter",
  glyph = "g_meter",
  desc = "Bigger text on the game's own damage meter. Turn the meter on in the game's settings first.",
  default = true,
  defaults = { textScale = 1.7 },
  Enable = function(mdb) db = mdb; wait = 1; driver:SetScript("OnUpdate", Tick); Resize() end,
  Disable = function() driver:SetScript("OnUpdate", nil); Resize() end,
  Apply = function() Resize() end,
  Page = function(P)
    local G = P:Group("Text")
    G:Sliders({ { "textScale", function(v) return "Text size: " .. math.floor(v * 100 + 0.5) .. "%" end, 1, 3, 0.05, "100%", "300%" } })
    G:Note("Only the text gets bigger; the meter keeps its size. Very large text can get cut off in its rows. Type /qol meter if nothing changes.")
    G:Done()
  end,
})
