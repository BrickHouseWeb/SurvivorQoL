-- Boss Targeting (was the BossTab addon): while a boss or guardian is alive (from the game's
-- AZS_UNITS list), Tab targets it instead of the nearest enemy, final boss first, and steps
-- through them on each press. Optionally it also targets one by itself once it is close enough
-- to target. When none is up or in Tab's reach, Tab works as normal.

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

-- Only what you could target anyway: a boss or guardian counts as near only when the game's own
-- Tab can reach it. Tab is stepped through a number of times in one go (nothing is drawn in
-- between, so you never see it), the bosses and guardians it lands on are noted, and your target
-- is put back. (TargetByName alone reaches far past what Tab can, and nameplates only show
-- within about 20 yards.)
local SCAN = 12

-- your target as it was (a dead one is let go, Tab never lands on it again)
local function Snap()
  if not UnitExists("target") or UnitIsDead("target") then return nil end
  local max = UnitHealthMax("target") or 0
  return { name = UnitName("target"), frac = max > 0 and (UnitHealth("target") or 0) / max or 0 }
end

local function Same(snap)
  local max = UnitHealthMax("target") or 0
  local frac = max > 0 and (UnitHealth("target") or 0) / max or 0
  return UnitExists("target") and UnitName("target") == snap.name and math.abs(frac - snap.frac) < 0.01
end

-- back to the target you had before the scan
local function Restore(snap)
  if not snap then
    if UnitExists("target") and ClearTarget then ClearTarget() end
    return
  end
  for i = 1, SCAN do
    if Same(snap) then return end
    nativeTab()
  end
  if not Same(snap) then TryTarget(snap.name) end
end

-- names of the wanted units that Tab reaches right now
local function Reach(list)
  local seen = {}
  if not nativeTab then return seen end
  local wanted = {}
  for i = 1, table.getn(list) do wanted[list[i].name] = true end
  local snap = Snap()
  for i = 1, SCAN do
    nativeTab()
    if not UnitExists("target") then break end
    local n = UnitName("target")
    if wanted[n] and not UnitIsDead("target") then seen[n] = true end
  end
  Restore(snap)
  return seen
end

-- the bosses and guardians within Tab's reach, most important first
local function Near(list)
  local reach, near = Reach(list), {}
  for i = 1, table.getn(list) do
    if reach[list[i].name] then table.insert(near, list[i]) end
  end
  return near
end

-- targets one name once; if it didn't take, goes back to what you had
local function Pick(name)
  local before = UnitExists("target") and UnitName("target")
  if TryTarget(name) then return true end
  local now = UnitExists("target") and UnitName("target")
  if now ~= before then
    if before and TargetLastTarget then TargetLastTarget()
    elseif not before and ClearTarget then ClearTarget() end
  end
  return false
end

-- the near one to target next: the first, or the one after `after`
local function Best(list, after)
  local near = Near(list)
  local n = table.getn(near)
  if n == 0 then return nil end
  local i = Index(near, after)
  return near[i and math.mod(i, n) + 1 or 1].name
end

-- the Tab key: the next near boss or guardian after the one you have, else the normal Tab
local function Tab()
  if db and db.tab and QOL.IsOn(QOL.Module("bosses")) then
    local list = Targets()
    if table.getn(list) > 0 then
      local current = UnitExists("target") and not UnitIsDead("target") and UnitName("target")
      local name = Best(list, current)
      -- already on the only one near: stay on it
      if name and name == current then return end
      if name and Pick(name) then return end
    end
  end
  if nativeTab then nativeTab() end
end

-- Take over the global the Tab binding calls. Keep the original for when none is up.
if type(TargetNearestEnemy) == "function" then
  nativeTab = TargetNearestEnemy
  TargetNearestEnemy = Tab
end

-- each look steps through Tab, so look once a second at most
local nextTry = 0
local function Tick()
  wait = wait + (arg1 or 0)
  if wait < 1 then return end
  wait = 0
  if db.auto == "off" or GetTime() < nextTry then return end
  local list = Targets()
  if table.getn(list) == 0 then return end
  local has = UnitExists("target") and not UnitIsDead("target")
  if has and Index(list, UnitName("target")) then return end
  if db.auto == "notarget" and has then return end
  local name = Best(list, nil)
  -- nothing near, or it didn't stick: wait a bit before looking again
  if not name or not Pick(name) then nextTry = GetTime() + 2 end
end

QOL.Register({
  key = "bosses",
  label = "Boss Targeting",
  glyph = "g_skull",
  desc = "Tab grabs the boss or guardian near you instead of the nearest enemy. When none is near, Tab works as normal.",
  default = true,
  defaults = { tab = true, guardians = true, elites = false, auto = "always" },
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
    G:Note("Only bosses and guardians that Tab could reach are ever targeted.")
    G:Done()
  end,
})
