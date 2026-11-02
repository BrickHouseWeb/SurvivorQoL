-- Combat Text: your damage as a short list in one place on screen, newest on top, older lines
-- pushed down. The list never grows past its line count, so a fight with fifty enemies can't
-- run it down the screen: hits from the same spell close together merge into one line
-- ("Blizzard 12.3k x14"), and the oldest line drops off when the list is full.
-- The numbers come from the combat log messages (CHAT_MSG_*), read with the game's own message
-- patterns (COMBATHITSELFOTHER and friends from GlobalStrings), so any client language works.
-- Spell icons come from the spellbook and, when installed, the icon lists that
-- SurvivorsDragonUi and AZSSpellMeter ship.

local MAX_LINES = 15
local HOLD, FADE = 2.2, 0.6      -- seconds a line stays solid, then fades out
local MERGE = 0.6                -- hits from one spell this close together share a line
local WIDTH = 240
local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local MELEE = "Interface\\Icons\\INV_Sword_04"
local SCHOOL_ICON = {
  Physical = "Interface\\Icons\\Ability_MeleeDamage", Holy = "Interface\\Icons\\Spell_Holy_HolyBolt",
  Fire = "Interface\\Icons\\Spell_Fire_FlameBolt", Nature = "Interface\\Icons\\Spell_Nature_Lightning",
  Frost = "Interface\\Icons\\Spell_Frost_FrostBolt02", Shadow = "Interface\\Icons\\Spell_Shadow_ShadowBolt",
  Arcane = "Interface\\Icons\\Spell_Nature_StarFall",
}

local db
local frame = CreateFrame("Frame", "SurvivorQoLCombatText", UIParent)
frame:SetWidth(WIDTH)
frame:SetHeight(20)
frame:EnableMouse(false)
frame:Hide()
-- only seen while moving frames, so the empty list has something to drag
frame.back = frame:CreateTexture(nil, "BACKGROUND")
frame.back:SetTexture("Interface\\Buttons\\WHITE8X8")
frame.back:SetVertexColor(0, 0, 0, 0.35)
frame.back:SetAllPoints(frame)
frame.back:Hide()
QOL.Movable(frame, "combatText", "Combat Text", { "CENTER", "CENTER", 260, 80 }, "combattext")

-- ---------------------------------------------------------------- reading the combat log
-- A GlobalStrings format ("Your %s hits %s for %d.") turned into a Lua pattern, with the order
-- its values come in (some languages number them: "%2$s").
local function Pattern(fmt)
  if type(fmt) ~= "string" then return nil end
  -- order[j]: which of the format's values the j-th capture holds
  local order, n = {}, 0
  local p = string.gsub(fmt, "([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1")
  -- "%s" and "%d" (plain values count from 1), then "%2$s" (its "$" is escaped to "%$" above)
  p = string.gsub(p, "%%([sd])", function(kind)
    n = n + 1
    table.insert(order, n)
    return kind == "d" and "(%d+)" or "(.-)"
  end)
  p = string.gsub(p, "%%(%d)%%%$([sd])", function(i, kind)
    table.insert(order, tonumber(i))
    return kind == "d" and "(%d+)" or "(.-)"
  end)
  return { pat = "^" .. p .. "$", order = order }
end

-- per event, the messages to try (longest first), the fields each value fills, and whether
-- it is a critical hit. Pet events use the OTHEROTHER wording, where the pet's name comes first.
local RULES = {
  CHAT_MSG_COMBAT_SELF_HITS = {
    { "COMBATHITCRITSCHOOLSELFOTHER", { "target", "amount", "school" }, true },
    { "COMBATHITSCHOOLSELFOTHER", { "target", "amount", "school" } },
    { "COMBATHITCRITSELFOTHER", { "target", "amount" }, true },
    { "COMBATHITSELFOTHER", { "target", "amount" } },
  },
  CHAT_MSG_SPELL_SELF_DAMAGE = {
    { "SPELLLOGCRITSCHOOLSELFOTHER", { "spell", "target", "amount", "school" }, true },
    { "SPELLLOGSCHOOLSELFOTHER", { "spell", "target", "amount", "school" } },
    { "SPELLLOGCRITSELFOTHER", { "spell", "target", "amount" }, true },
    { "SPELLLOGSELFOTHER", { "spell", "target", "amount" } },
  },
  CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE = {
    { "PERIODICAURADAMAGESELFOTHER", { "target", "amount", "school", "spell" } },
  },
  CHAT_MSG_COMBAT_PET_HITS = {
    { "COMBATHITCRITOTHEROTHER", { "source", "target", "amount" }, true },
    { "COMBATHITOTHEROTHER", { "source", "target", "amount" } },
  },
  CHAT_MSG_SPELL_PET_DAMAGE = {
    { "SPELLLOGCRITSCHOOLOTHEROTHER", { "source", "spell", "target", "amount", "school" }, true },
    { "SPELLLOGSCHOOLOTHEROTHER", { "source", "spell", "target", "amount", "school" } },
    { "SPELLLOGCRITOTHEROTHER", { "source", "spell", "target", "amount" }, true },
    { "SPELLLOGOTHEROTHER", { "source", "spell", "target", "amount" } },
  },
}
local PET_EVENT = { CHAT_MSG_COMBAT_PET_HITS = true, CHAT_MSG_SPELL_PET_DAMAGE = true }

-- patterns are built on first use: GlobalStrings are loaded by then
local compiled = {}
local function Rules(event)
  if compiled[event] then return compiled[event] end
  local list = {}
  for _, r in ipairs(RULES[event] or {}) do
    local p = Pattern(getglobal(r[1]))
    if p then table.insert(list, { p = p, fields = r[2], crit = r[3] }) end
  end
  compiled[event] = list
  return list
end

local function Parse(event, msg)
  local list = Rules(event)
  for i = 1, table.getn(list) do
    local r = list[i]
    local caps = { string.find(msg, r.p.pat) }
    if caps[1] then
      -- string.find returns start and end first, then the captures
      local hit = { crit = r.crit }
      for j = 1, table.getn(r.p.order) do
        local field = r.fields[r.p.order[j]]
        if field then hit[field] = caps[2 + j] end
      end
      hit.amount = tonumber(hit.amount)
      if hit.amount and hit.amount > 0 then return hit end
    end
  end
end

-- ---------------------------------------------------------------- spell icons
local iconCache = {}
local function FromSpellbook(name)
  if not GetSpellName or not GetSpellTexture then return nil end
  local i = 1
  while true do
    local n = GetSpellName(i, BOOKTYPE_SPELL or "spell")
    if not n then return nil end
    if n == name then return GetSpellTexture(i, BOOKTYPE_SPELL or "spell") end
    i = i + 1
  end
end

local function FromCatalogs(name)
  local cat = DFRL and DFRL.tools and DFRL.tools.SpellIconCatalog
  if type(cat) == "table" then
    for _, part in ipairs({ "game", "abilities", "effects" }) do
      local t = cat[part]
      if type(t) == "table" and type(t[name]) == "string" then return t[name] end
    end
  end
  local file = type(AZSSpellMeterIcon) == "table" and AZSSpellMeterIcon[name]
  if type(file) == "string" and file ~= "" then
    if string.find(file, "\\", 1, true) then return file end
    return "Interface\\Icons\\" .. file
  end
end

local function IconFor(hit)
  if not hit.spell then return MELEE end
  local tex = iconCache[hit.spell]
  if tex == nil then
    tex = FromSpellbook(hit.spell) or FromCatalogs(hit.spell) or false
    iconCache[hit.spell] = tex
  end
  return tex or SCHOOL_ICON[hit.school or "Physical"] or SCHOOL_ICON.Physical
end

-- ---------------------------------------------------------------- the list
local lines = {}      -- shown lines, newest first: { key, amount, count, crit, pet, icon, at }
local rows = {}       -- MAX_LINES row frames, reused

local function Row(i)
  if rows[i] then return rows[i] end
  local r = CreateFrame("Frame", nil, frame)
  r:EnableMouse(false)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  r.text = r:CreateFontString(nil, "OVERLAY")
  r.text:SetJustifyH("LEFT")
  rows[i] = r
  return r
end

local function Short(n)
  if n >= 1000000 then return string.format("%.1fM", n / 1000000) end
  if n >= 10000 then return string.format("%.1fk", n / 1000) end
  return tostring(n)
end

local function LineHeight() return math.floor(db.textSize * 1.35 + 0.5) end

local function Layout()
  local h = LineHeight()
  frame:SetHeight(h * db.lines)
  local shown = math.min(table.getn(lines), db.lines)
  for i = 1, MAX_LINES do
    local r = Row(i)
    local l = i <= shown and lines[i]
    if l then
      local size = l.crit and math.floor(db.textSize * 1.25 + 0.5) or db.textSize
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -(i - 1) * h)
      r:SetWidth(WIDTH)
      r:SetHeight(h)
      local x = 0
      if db.icons then
        r.icon:SetTexture(l.icon)
        r.icon:SetWidth(h - 2)
        r.icon:SetHeight(h - 2)
        r.icon:ClearAllPoints()
        r.icon:SetPoint("LEFT", r, "LEFT", 0, 0)
        r.icon:Show()
        x = h + 3
      else
        r.icon:Hide()
      end
      r.text:SetFont(FONT, size, "OUTLINE")
      r.text:ClearAllPoints()
      r.text:SetPoint("LEFT", r, "LEFT", x, 0)
      local text = Short(l.amount)
      if l.count > 1 then text = text .. " |cffaaaaaax" .. l.count .. "|r" end
      r.text:SetText(text)
      if l.crit then r.text:SetTextColor(1, 0.82, 0)
      elseif l.pet then r.text:SetTextColor(0.75, 0.85, 1)
      else r.text:SetTextColor(1, 1, 1) end
      r:SetAlpha(1)
      r:Show()
    else
      r:Hide()
    end
  end
end

local function Add(hit, pet)
  local key = (pet and "pet:" or "") .. (hit.spell or "melee")
  local now = GetTime()
  if db.merge then
    for i = 1, table.getn(lines) do
      local l = lines[i]
      if l.key == key and now - l.at <= MERGE then
        l.amount, l.count, l.at = l.amount + hit.amount, l.count + 1, now
        l.crit = l.crit or hit.crit
        -- the line just hit moves back to the top
        table.remove(lines, i)
        table.insert(lines, 1, l)
        Layout()
        return
      end
    end
  end
  table.insert(lines, 1, { key = key, amount = hit.amount, count = 1, crit = hit.crit, pet = pet, icon = IconFor(hit), at = now })
  while table.getn(lines) > db.lines do table.remove(lines) end
  Layout()
end

-- fading: each line goes solid for HOLD seconds after its last hit, then fades and drops off
local function Tick()
  if QOL.moving then
    frame.back:Show()
    return
  end
  frame.back:Hide()
  local now, changed = GetTime(), false
  for i = table.getn(lines), 1, -1 do
    local age = now - lines[i].at
    if age > HOLD + FADE then
      table.remove(lines, i)
      changed = true
    elseif rows[i] then
      rows[i]:SetAlpha(age > HOLD and 1 - (age - HOLD) / FADE or 1)
    end
  end
  if changed then Layout() end
end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function()
  if event == "SPELLS_CHANGED" then
    -- learned or upgraded spells: look their icons up again
    for k, v in pairs(iconCache) do if v == false then iconCache[k] = nil end end
    return
  end
  local hit = Parse(event, arg1 or "")
  if hit then Add(hit, PET_EVENT[event]) end
end)

-- /qol and move mode: a few sample lines so the size and spot can be judged
function QOL.CombatTextSample()
  if not db then return end
  local samples = { { "Frostbolt", 1840, true }, { "Blizzard", 12330 }, { nil, 412 } }
  for _, s in ipairs(samples) do
    Add({ spell = s[1], amount = s[2], crit = s[3], school = "Frost" })
  end
end

QOL.Register({
  key = "combattext",
  label = "Combat Text",
  glyph = "g_alert",
  desc = "Your damage as a short list in one spot, newest on top. Hits from one spell merge into one line, so it never runs down the screen.",
  default = false,
  defaults = { icons = true, merge = true, lines = 8, textSize = 14 },
  Enable = function(mdb)
    db = mdb
    for e in pairs(RULES) do ev:RegisterEvent(e) end
    ev:RegisterEvent("SPELLS_CHANGED")
    frame:Show()
    frame:SetScript("OnUpdate", Tick)
    Layout()
  end,
  Disable = function()
    ev:UnregisterAllEvents()
    frame:SetScript("OnUpdate", nil)
    for i = table.getn(lines), 1, -1 do table.remove(lines, i) end
    frame:Hide()
  end,
  Apply = function() Layout() end,
  Page = function(P)
    local G = P:Group("Look")
    G:Checks({ { "Show spell icons", "icons" }, { "Merge hits from the same spell", "merge" } })
    G:Sliders({
      { "lines", function(v) return "Most lines: " .. v end, 3, MAX_LINES, 1, "3", tostring(MAX_LINES) },
      { "textSize", function(v) return "Text size: " .. v end, 10, 24, 1, "Small", "Large" },
    })
    G:Buttons({ { "Show a sample", function() QOL.CombatTextSample() end } })
    G:Note("Use Move frames at the top of this window to place it. Crits are gold, your pet's hits are blue.")
    G:Done()
  end,
})
