-- Boss Targeting (was the BossTab addon): while a boss or guardian is alive (from the game's
-- AZS_UNITS list), Tab targets it instead of the nearest enemy, final boss first, and steps
-- through them on each press. Optionally it also targets one by itself once it is close enough
-- to target. When none is up or in range, Tab works as normal.

local PHASES = { playing = true, choosing = true, paused = true, victory = true }
local ORDER = { final = 1, boss = 2, guardian = 3, elite = 4 }

local db, nativeTab
local wait = 0
local driver = CreateFrame("Frame")

local function Number(v) return type(v) == "number" and v - v == 0 end

local function Wanted(kind)
  if kind == "final" or kind == "boss" then return true end
  if kind == "guardian" then return db.guardians end
  if kind == "elite" then return db.elites end
  return false
end

-- names of the living bosses and guardians, most important first, each name once
local function Targets()
  local list = {}
  if type(AZS_GetPhase) ~= "function" then return list end
  local ok, phase = pcall(AZS_GetPhase)
  if not ok or not PHASES[phase] or type(AZS_UNITS) ~= "table" then return list end
  local seen = {}
  for i = 1, table.getn(AZS_UNITS) do
    local u = AZS_UNITS[i]
    if type(u) == "table" and ORDER[u.kind] and Wanted(u.kind) and type(u.name) == "string" and u.name ~= ""
      and Number(u.hp) and u.hp > 0 and not seen[u.name] then
      seen[u.name] = true
      table.insert(list, { name = u.name, order = ORDER[u.kind] })
    end
  end
  table.sort(list, function(a, b)
    if a.order ~= b.order then return a.order < b.order end
    return a.name < b.name
  end)
  return list
end

local function TryTarget(name)
  if type(TargetByName) ~= "function" then return false end
  pcall(TargetByName, name, 1)
  return UnitExists("target") and UnitName("target") == name and not UnitIsDead("target")
end

local function Index(list, name)
  for i = 1, table.getn(list) do
    if list[i].name == name then return i end
  end
end

-- TargetByName reaches far past what is on screen, so when targeting by itself a hit is kept
-- only if it is near: CheckInteractDistance 4 is the follow range (about 28 yards).
local function Close()
  if type(CheckInteractDistance) ~= "function" then return false end
  return CheckInteractDistance("target", 4) and true or false
end

local function AttackingMe()
  return UnitExists("targettarget") and UnitIsUnit("targettarget", "player") and true or false
end

-- Yards from the hero to a guardian's lair (AZS_LAIRS and the hero's AZS_RUN px/py share one
-- frame), or nil when unknown. Bosses have no position in the game's data.
local function LairDist(name)
  local run, lairs = AZS_RUN, AZS_LAIRS
  local hx = type(run) == "table" and tonumber(run.px)
  local hy = type(run) == "table" and tonumber(run.py)
  if not hx or not hy or type(lairs) ~= "table" then return nil end
  for i = 1, table.getn(lairs) do
    local l = lairs[i]
    if type(l) == "table" and l.name == name then
      local lx, ly = tonumber(l.x), tonumber(l.y)
      if lx and ly then return math.sqrt((lx - hx) * (lx - hx) + (ly - hy) * (ly - hy)) end
    end
  end
end

-- "Near" is decided without touching your target: a boss or guardian is near when its nameplate
-- is on screen, or (guardians) when you are within reach of its lair. Then it is targeted once.
-- (Trying names one by one with TargetByName and switching back made the target flicker, and
-- TargetLastTarget only goes back one step.)

-- names of enemies whose nameplate is on screen; nil when no enemy plate is shown at all
-- (nameplates turned off), so "near" can't be read from plates
local function PlateNames()
  local names, any = {}, false
  for plate in pairs(QOL.PlateList()) do
    if plate:IsShown() and not QOL.PlateIsFriendly(plate) then
      any = true
      local regions = { plate:GetRegions() }
      for i = 1, table.getn(regions) do
        local r = regions[i]
        if r and r.GetObjectType and r:GetObjectType() == "FontString" then
          local t = r:GetText()
          if t and t ~= "" and not string.find(t, "^%d+$") then names[t] = true end
        end
      end
    end
  end
  return any and names or nil
end

-- the bosses and guardians near you, most important first. useLair: guardians also count within
-- reach of their lair (auto-target only; Tab never reaches past what you could normally target)
local function Near(list, useLair)
  local plates, near = PlateNames(), {}
  for i = 1, table.getn(list) do
    local name = list[i].name
    local d = LairDist(name)
    if (plates and plates[name]) or (useLair and d and d <= db.reach) then table.insert(near, list[i]) end
  end
  return near, plates
end

-- targets one name once; keeps it only if it worked (and, with check, if it is close or
-- attacking you), otherwise goes back to what you had
local function Pick(name, check)
  local before = UnitExists("target") and UnitName("target")
  if TryTarget(name) and (not check or Close() or AttackingMe()) then return true end
  local now = UnitExists("target") and UnitName("target")
  if now ~= before then
    if before and TargetLastTarget then TargetLastTarget()
    elseif not before and ClearTarget then ClearTarget() end
  end
  return false
end

-- the best thing to target right now: the first near one, or with nameplates off, the most
-- important one if it turns out to be close
local function Best(list, after, useLair)
  local near, plates = Near(list, useLair)
  local n = table.getn(near)
  if n > 0 then
    local i = Index(near, after)
    return near[i and math.mod(i, n) + 1 or 1].name, false
  end
  if not plates and list[1] then return list[1].name, true end
end

-- the Tab key: the next near boss or guardian after the one you have, else the normal Tab
local function Tab()
  if db and db.tab and QOL.IsOn(QOL.Module("bosses")) then
    local list = Targets()
    if table.getn(list) > 0 then
      local current = UnitExists("target") and not UnitIsDead("target") and UnitName("target")
      local name, check = Best(list, current)
      -- already on the only one near: stay on it
      if name and name == current then return end
      if name and Pick(name, check) then return end
    end
  end
  if nativeTab then nativeTab() end
end

-- Take over the global the Tab binding calls. Keep the original for when none is up.
if type(TargetNearestEnemy) == "function" then
  nativeTab = TargetNearestEnemy
  TargetNearestEnemy = Tab
end

local nextTry = 0
local function Tick()
  wait = wait + (arg1 or 0)
  if wait < 0.4 then return end
  wait = 0
  if db.auto == "off" or GetTime() < nextTry then return end
  local list = Targets()
  if table.getn(list) == 0 then return end
  local has = UnitExists("target") and not UnitIsDead("target")
  if has and Index(list, UnitName("target")) then return end
  if db.auto == "notarget" and has then return end
  local name, check = Best(list, nil, true)
  -- nothing near, or it didn't stick: wait a bit before looking again
  if not name or not Pick(name, check) then nextTry = GetTime() + 1 end
end

QOL.Register({
  key = "bosses",
  label = "Boss Targeting",
  glyph = "g_skull",
  desc = "Tab grabs the boss or guardian near you instead of the nearest enemy. When none is near, Tab works as normal.",
  default = true,
  defaults = { tab = true, guardians = true, elites = false, auto = "always", reach = 40 },
  Enable = function(mdb)
    db = mdb
    driver:SetScript("OnUpdate", Tick)
  end,
  Disable = function() driver:SetScript("OnUpdate", nil) end,
  Page = function(P)
    local G = P:Group("Tab key")
    G:Checks({ { "Tab targets nearby bosses and guardians first", "tab" } })
    G:Checks({ { "Elites count too", "elites" } })
    G:Done()
    G = P:Group("Target by itself")
    G:Radios(nil, "auto", { { "off", "Off" }, { "notarget", "When I have no target" }, { "always", "Always" } })
    G:Sliders({ { "reach", function(v) return "Guardian reach: " .. v .. " yd" end, 10, 80, 5, "10 yd", "80 yd" } })
    G:Note("A boss or guardian counts once its nameplate is on screen. Guardians also count once you are within reach of their lair, so you can tag them early.")
    G:Done()
  end,
})
