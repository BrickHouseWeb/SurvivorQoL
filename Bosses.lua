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

-- tries each name starting at `start`; puts the old target back if nothing was found.
-- nearOnly (targeting by itself): a guardian counts within the reach of its lair; anything
-- counts within about 28 yards or while it attacks you.
local function TargetFrom(list, start, nearOnly)
  local n = table.getn(list)
  local before = UnitExists("target") and UnitName("target")
  for k = 0, n - 1 do
    local name = list[math.mod(start - 1 + k, n) + 1].name
    local d = nearOnly and LairDist(name)
    if TryTarget(name) and (not nearOnly or (d and d <= db.reach) or Close() or AttackingMe()) then return true end
  end
  local now = UnitExists("target") and UnitName("target")
  if now ~= before then
    if before and TargetLastTarget then TargetLastTarget()
    elseif not before and ClearTarget then ClearTarget() end
  end
  return false
end

-- the Tab key: the next boss or guardian after the one you have, else the normal Tab
local function Tab()
  if db and db.tab and QOL.IsOn(QOL.Module("bosses")) then
    local list = Targets()
    local n = table.getn(list)
    if n > 0 then
      local i = Index(list, UnitExists("target") and UnitName("target"))
      if TargetFrom(list, i and math.mod(i, n) + 1 or 1, true) then return end
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
  -- nothing close: wait a bit before looking again
  if not TargetFrom(list, 1, true) then nextTry = GetTime() + 1.5 end
end

QOL.Register({
  key = "bosses",
  label = "Boss Targeting",
  glyph = "g_skull",
  desc = "Tab targets the boss or guardian instead of the nearest enemy. It can also target one by itself once it is close enough. When none is up, Tab works as normal.",
  default = true,
  defaults = { tab = true, guardians = true, elites = false, auto = "always", reach = 40 },
  Enable = function(mdb)
    db = mdb
    driver:SetScript("OnUpdate", Tick)
  end,
  Disable = function() driver:SetScript("OnUpdate", nil) end,
  Page = function(P)
    local G = P:Group("Who counts")
    G:Note("Bosses and the final boss always count.")
    G:Checks({ { "Guardians", "guardians" }, { "Elites", "elites" } })
    G:Done()
    G = P:Group("Tab key")
    G:Checks({ { "Tab targets them first", "tab" } })
    G:Note("Only ones near you count (see Guardian reach below). Press Tab again to step to the next one.")
    G:Done()
    G = P:Group("Target by itself")
    G:Radios(nil, "auto", { { "off", "Off" }, { "notarget", "Only if I have no target" }, { "always", "Always" } })
    G:Sliders({ { "reach", function(v) return "Guardian reach: " .. v .. " yd" end, 10, 80, 5, "10 yd", "80 yd" } })
    G:Note("Guardians: once you are this close to their lair, so you can tag them early. Bosses: once they are about 28 yards away or attacking you. Always also switches away from a normal enemy you targeted.")
    G:Done()
  end,
})
