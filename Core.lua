-- SurvivorQoL: quality-of-life modules, each one on or off in /qol. SurvivorQoLDB is a
-- SavedVariables (not per character), so settings and frame positions are shared by every
-- character on the account. WoW 1.12 / Lua 5.0.

QOL = { modules = {}, say = "|cffe8dfc8Survivor|r|cffffd100QoL|r: ", media = "Interface\\AddOns\\SurvivorQoL\\media\\" }

-- m = { key, label, glyph, desc, default, defaults = {}, Enable(db), Disable(db), Apply(db), Page(page, db) }
function QOL.Register(m)
  table.insert(QOL.modules, m)
end

function QOL.Module(key)
  for i = 1, table.getn(QOL.modules) do
    if QOL.modules[i].key == key then return QOL.modules[i] end
  end
end

function QOL.IsOn(m)
  return QOL.db and QOL.db.on[m.key] and true or false
end

function QOL.Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage(QOL.say .. msg)
end

local listeners = {}
-- fn runs whenever a module turns on or off (options window, minimap menu, tooltip)
function QOL.OnToggle(fn) table.insert(listeners, fn) end

function QOL.Set(m, on)
  on = on and true or false
  if QOL.db.on[m.key] == on then return end
  QOL.db.on[m.key] = on
  if on then m.Enable(QOL.db[m.key]) else m.Disable(QOL.db[m.key]) end
  if QOL.db.general.chat then QOL.Print(m.label .. (on and " on." or " off.")) end
  for i = 1, table.getn(listeners) do listeners[i](m) end
end

-- a setting changed: store it and let the module react
function QOL.Change(m, key, value)
  QOL.db[m.key][key] = value
  if QOL.IsOn(m) and m.Apply then m.Apply(QOL.db[m.key]) end
end

-- fn runs once SurvivorQoLDB is ready (after every module has been enabled)
QOL.loaders = {}
function QOL.OnLoad(fn) table.insert(QOL.loaders, fn) end

-- the game's run phases, as SurvivorsDragonUi reads them
local RUN_PHASES = { playing = true, choosing = true, paused = true, victory = true }
function QOL.InRun()
  if type(AZS_GetPhase) ~= "function" then return false end
  local ok, phase = pcall(AZS_GetPhase)
  return ok and RUN_PHASES[phase] or false
end

local function Fill(t, defaults)
  for k, v in pairs(defaults) do
    if type(v) == "table" then
      if type(t[k]) ~= "table" then t[k] = {} end
      Fill(t[k], v)
    elseif t[k] == nil then
      t[k] = v
    end
  end
end

-- 135 degrees: the top-left corner. SurvivorsDragonUi's own button sits at the bottom left.
QOL.generalDefaults = { minimap = true, minimapLock = false, minimapAngle = 135, snap = true, chat = true }

function QOL.ResetModule(m)
  local db = QOL.db[m.key]
  for k in pairs(db) do db[k] = nil end
  Fill(db, m.defaults or {})
  if QOL.IsOn(m) and m.Apply then m.Apply(db) end
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("VARIABLES_LOADED")
boot:SetScript("OnEvent", function()
  if type(SurvivorQoLDB) ~= "table" then SurvivorQoLDB = {} end
  local db = SurvivorQoLDB
  if type(db.on) ~= "table" then db.on = {} end
  if type(db.pos) ~= "table" then db.pos = {} end
  if type(db.general) ~= "table" then db.general = {} end
  Fill(db.general, QOL.generalDefaults)
  QOL.db = db
  -- the old default (220) put the button under SurvivorsDragonUi's own; move it once
  if db.general.minimapAngle == 220 then db.general.minimapAngle = 135 end
  -- 0.1 had separate ring and trail modules: carry their on/off over to Cursor once
  if db.on.cursor == nil and (db.on.ring ~= nil or db.on.trail ~= nil) then
    db.on.cursor = (db.on.ring or db.on.trail) and true or false
  end
  db.on.ring, db.on.trail, db.ring, db.trail = nil, nil, nil, nil
  for i = 1, table.getn(QOL.modules) do
    local m = QOL.modules[i]
    if type(db[m.key]) ~= "table" then db[m.key] = {} end
    Fill(db[m.key], m.defaults or {})
    if db.on[m.key] == nil then db.on[m.key] = m.default and true or false end
    if db.on[m.key] then m.Enable(db[m.key]) end
  end
  for i = 1, table.getn(QOL.loaders) do QOL.loaders[i]() end
end)
