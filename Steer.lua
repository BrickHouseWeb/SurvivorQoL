-- Steer mode (was the SteerLook addon): keeps mouselook on (MouselookStart) so moving the mouse
-- turns the hero the way holding right-click does. It lets go whenever the cursor is needed:
-- card choices, pause, death, victory, the chat box, any open window and while you hold Alt.
-- After the cursor was needed it waits a moment, and optionally for the mouse to move, before
-- taking hold again, so clicking a card doesn't snap the view straight away.
-- TurnOrActionStart is protected on this client (Blizzard UI only), so never call it.
-- The pointer box shows what the hidden cursor is on, since mouselook hides the real cursor.

local db
local holding = false   -- true while we have called MouselookStart and not Stop
local freedAt           -- GetTime() when the cursor was last needed
local freedFor          -- why: "alt", "cards" or "window" (only cards park the cursor first)
local freeX, freeY      -- cursor position when the cursor stopped being needed
local elapsed = 0
local driver = CreateFrame("Frame")

local function Has(name) return type(getglobal(name)) == "function" end

local function Phase()
  if not Has("AZS_GetPhase") then return nil end
  local ok, ph = pcall(AZS_GetPhase)
  if ok then return ph end
end

-- Right-click and other keys can end mouselook on their own; IsMouselooking tells us when.
local function Looking()
  if not Has("IsMouselooking") then return holding end
  local ok, on = pcall(IsMouselooking)
  return ok and on and true or false
end

local function Start()
  if not Has("MouselookStart") then return end
  if holding and Looking() then return end
  if pcall(MouselookStart) then
    holding = true
    QOL.steering = true
    if db.noTooltips and GameTooltip:IsShown() then GameTooltip:Hide() end
  end
end

-- no tooltips while steering: the hidden cursor still mouses over units and frames
local tipOnShow = GameTooltip:GetScript("OnShow")
GameTooltip:SetScript("OnShow", function()
  if tipOnShow then tipOnShow() end
  if QOL.steering and db and db.noTooltips then this:Hide() end
end)

local function Stop()
  if not holding then return end
  holding = false
  QOL.steering = false
  if Has("MouselookStop") then pcall(MouselookStop) end
end

-- Windows that need the cursor but are not closed with Escape (so not in UISpecialFrames).
local CURSOR_WINDOWS = { "GameMenuFrame", "ChatFrameEditBox", "LootFrame", "MerchantFrame",
  "GossipFrame", "QuestFrame", "StaticPopup1", "StaticPopup2", "ItemTextFrame" }

local function Shown(name)
  local f = getglobal(name)
  return f and f.IsVisible and f:IsVisible()
end

local function OpenWindow()
  for i = 1, table.getn(CURSOR_WINDOWS) do
    if Shown(CURSOR_WINDOWS[i]) then return true end
  end
  for i = 1, 12 do
    if Shown("ContainerFrame" .. i) then return true end
  end
  if type(UISpecialFrames) == "table" then
    for i = 1, table.getn(UISpecialFrames) do
      if Shown(UISpecialFrames[i]) then return true end
    end
  end
  return QOL.moving
end

-- why the cursor is needed right now: "alt", "cards" (any phase but playing), "window", or nil
local function CursorNeeded()
  if db.altFree and IsAltKeyDown and IsAltKeyDown() then return "alt" end
  if Phase() ~= "playing" then return "cards" end
  if OpenWindow() then return "window" end
end

-- ---------------------------------------------------------------- pointer box
-- cursor icon, portrait, level, name and health of the unit under the hidden cursor
local pointer = CreateFrame("Frame", "SurvivorQoLSteerPointer", UIParent)
pointer:SetWidth(190)
pointer:SetHeight(46)
pointer:SetFrameStrata("MEDIUM")
pointer:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
pointer:SetBackdropColor(0, 0, 0, 0.75)
pointer:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
pointer:Hide()
pointer.cursor = pointer:CreateTexture(nil, "OVERLAY")
pointer.cursor:SetTexture("Interface\\Cursor\\Point")
pointer.cursor:SetWidth(22)
pointer.cursor:SetHeight(22)
pointer.cursor:SetPoint("LEFT", pointer, "LEFT", 6, 0)
pointer.portrait = pointer:CreateTexture(nil, "ARTWORK")
pointer.portrait:SetWidth(32)
pointer.portrait:SetHeight(32)
pointer.portrait:SetPoint("LEFT", pointer.cursor, "RIGHT", 2, 0)
pointer.name = pointer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
pointer.name:SetPoint("TOPLEFT", pointer.portrait, "TOPRIGHT", 6, -2)
pointer.name:SetPoint("RIGHT", pointer, "RIGHT", -8, 0)
pointer.name:SetJustifyH("LEFT")
pointer.bar = CreateFrame("StatusBar", nil, pointer)
pointer.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
pointer.bar:SetHeight(10)
pointer.bar:SetPoint("BOTTOMLEFT", pointer.portrait, "BOTTOMRIGHT", 6, 2)
pointer.bar:SetPoint("RIGHT", pointer, "RIGHT", -8, 0)
pointer.bar:SetMinMaxValues(0, 1)
pointer.hp = pointer.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
pointer.hp:SetPoint("CENTER", pointer.bar, "CENTER", 0, 0)
QOL.Movable(pointer, "steerPointer", "Steer Pointer", { "LEFT", "LEFT", 20, 0 }, "steer")

local function LevelText(unit)
  local level = UnitLevel(unit)
  local text = (level and level > 0) and tostring(level) or "??"
  local class = UnitClassification and UnitClassification(unit)
  if class == "worldboss" then return "Boss" end
  if class == "elite" or class == "rareelite" then return text .. "+" end
  return text
end

local function UpdatePointer()
  if QOL.moving then pointer:Show() return end
  if not db.pointer or Phase() ~= "playing" then pointer:Hide() return end
  pointer:Show()
  if not UnitExists("mouseover") then
    pointer.unitName = nil
    pointer.portrait:SetTexture(nil)
    pointer.name:SetText("Nothing")
    pointer.name:SetTextColor(0.6, 0.6, 0.6)
    pointer.bar:Hide()
    pointer:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    return
  end
  local name = UnitName("mouseover") or "?"
  if pointer.unitName ~= name then
    pointer.unitName = name
    pcall(SetPortraitTexture, pointer.portrait, "mouseover")
  end
  pointer.name:SetText(LevelText("mouseover") .. "  " .. name)
  local r, g, b = 1, 0.82, 0
  if UnitCanAttack("player", "mouseover") then r, g, b = 1, 0.25, 0.2
  elseif UnitIsFriend("player", "mouseover") then r, g, b = 0.3, 1, 0.3 end
  pointer.name:SetTextColor(r, g, b)
  pointer:SetBackdropBorderColor(r, g, b, 1)
  local hp, maxHp = UnitHealth("mouseover") or 0, UnitHealthMax("mouseover") or 0
  if maxHp > 0 then
    pointer.bar:SetMinMaxValues(0, maxHp)
    pointer.bar:SetValue(hp)
    pointer.bar:SetStatusBarColor(r, g, b)
    pointer.hp:SetText(math.floor(hp / maxHp * 100 + 0.5) .. "%")
    pointer.bar:Show()
  else
    pointer.bar:Hide()
  end
end

-- ---------------------------------------------------------------- middle of the screen
-- Mouselook freezes the hidden cursor where steering started, and the cursor comes back there
-- when cards show up. Starting steering only once the cursor is at the aim spot keeps it there,
-- next to the cards. Like action-camera games, the spot is a small plus a little above the
-- middle of the screen, in front of the hero. While we wait for the cursor, a faint ring
-- marks the spot.
local CENTER_REACH = 70
local WAIT_MAX = 2   -- seconds: after this, steer again even if the cursor never reached the spot
local mark = CreateFrame("Frame", nil, UIParent)
mark:SetFrameStrata("TOOLTIP")
mark:SetWidth(64)
mark:SetHeight(64)
mark:EnableMouse(false)
mark:Hide()

-- the plus: four gold arms over slightly bigger black ones (an outline that reads on anything)
local arms = {}
local function Arm(layer, r, g, b)
  local t = mark:CreateTexture(nil, layer)
  t:SetTexture("Interface\\Buttons\\WHITE8X8")
  t:SetVertexColor(r, g, b, 1)
  table.insert(arms, t)
  return t
end
local plus = { outline = {}, fill = {} }
for i = 1, 4 do
  plus.outline[i] = Arm("ARTWORK", 0, 0, 0)
  plus.fill[i] = Arm("OVERLAY", 1, 0.82, 0)
end
local function DrawPlus(size, w)
  local len, gap = math.floor(size * 0.38 + 0.5), math.max(2, math.floor(size * 0.12 + 0.5))
  -- arm i: left, right, up, down from the middle
  local dirs = { { -1, 0 }, { 1, 0 }, { 0, 1 }, { 0, -1 } }
  for i = 1, 4 do
    local dx, dy = dirs[i][1], dirs[i][2]
    local cx, cy = dx * (gap + len / 2), dy * (gap + len / 2)
    local aw, ah = dx ~= 0 and len or w, dy ~= 0 and len or w
    for _, t in ipairs({ plus.outline[i], plus.fill[i] }) do
      local pad = t == plus.outline[i] and 1 or 0
      t:ClearAllPoints()
      t:SetPoint("CENTER", mark, "CENTER", cx, cy)
      t:SetWidth(aw + pad * 2)
      t:SetHeight(ah + pad * 2)
    end
  end
end

local spot = mark:CreateTexture(nil, "OVERLAY")
spot:SetTexture(QOL.media .. "ring2")
spot:SetBlendMode("ADD")
spot:SetVertexColor(1, 0.82, 0, 0.75)
spot:SetWidth(CENTER_REACH)
spot:SetHeight(CENTER_REACH)
spot:SetPoint("CENTER", mark, "CENTER", 0, 0)
spot:Hide()

-- The aim spot is measured from WorldFrame, the game's 3D view, not UIParent: the camera keeps
-- the hero in the middle of WorldFrame, and on some setups UIParent does not cover the same area.
-- It sits a little above that middle, nudged by the sliders (in UI units).
local function SpotPixels()
  local wx, wy = WorldFrame:GetCenter()
  local ws, us = WorldFrame:GetEffectiveScale(), UIParent:GetEffectiveScale()
  return wx * ws + db.spotX * us, wy * ws + db.spotY * us
end

-- "on": steering, "wait": waiting for the cursor to reach the spot, "off": neither
local function Mark(state)
  if mark.x ~= db.spotX or mark.y ~= db.spotY then
    mark:ClearAllPoints()
    mark:SetPoint("CENTER", WorldFrame, "CENTER", db.spotX, db.spotY)
    mark.x, mark.y = db.spotX, db.spotY
  end
  if mark.size ~= db.aimSize or mark.thick ~= db.aimThick then
    DrawPlus(db.aimSize, db.aimThick)
    mark.size, mark.thick = db.aimSize, db.aimThick
  end
  local showPlus = state == "on" and db.centerMark
  for i = 1, table.getn(arms) do
    if showPlus then arms[i]:Show() else arms[i]:Hide() end
  end
  if state == "wait" then spot:Show() else spot:Hide() end
  if showPlus or state == "wait" then mark:Show() else mark:Hide() end
end

local function NearMiddle()
  local x, y = GetCursorPosition()
  local cx, cy = SpotPixels()
  local reach = CENTER_REACH * UIParent:GetEffectiveScale()
  return (x - cx) * (x - cx) + (y - cy) * (y - cy) <= reach * reach
end

-- ---------------------------------------------------------------- frame loop
-- Checked every frame, so steering lets go the moment cards or a window come up.
local function Step()
  local why = CursorNeeded()
  if why then
    Stop()
    Mark("off")
    freedAt, freedFor, freeX = GetTime(), why, nil
    return
  end
  if holding then return end
  -- After Alt: steer again at once. After a window: after the short delay. After cards: after the
  -- delay, then once the cursor is back at the aim spot (or has moved), at most 2 s later.
  if freedAt and freedFor ~= "alt" then
    if GetTime() - freedAt < db.resumeDelay then Mark("off") return end
    if freedFor == "cards" then
      if db.resume == "center" then
        if not NearMiddle() and GetTime() - freedAt < db.resumeDelay + WAIT_MAX then Mark("wait") return end
      elseif db.resume == "move" then
        local x, y = GetCursorPosition()
        if not freeX then freeX, freeY = x, y return end
        if math.abs(x - freeX) + math.abs(y - freeY) < 12 then return end
      end
    end
  end
  freedAt, freedFor = nil, nil
  Start()
  Mark("on")
end

local function Tick()
  local ok, err = pcall(Step)
  elapsed = elapsed + (arg1 or 0)
  if ok and elapsed >= 0.1 then
    elapsed = 0
    ok, err = pcall(UpdatePointer)
  end
  if not ok then
    Stop()
    QOL.Set(QOL.Module("steer"), false)
    QOL.Print("Steer mode hit an error and turned off: " .. tostring(err))
  end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
ev:RegisterEvent("PLAYER_LEAVING_WORLD")
ev:SetScript("OnEvent", function()
  if not db or not QOL.IsOn(QOL.Module("steer")) then return end
  if event == "PLAYER_LEAVING_WORLD" then Stop() else pcall(UpdatePointer) end
end)

-- key binding (Bindings.xml): turn Steer mode on or off
BINDING_HEADER_SURVIVORQOL = "Survivor QoL"
BINDING_NAME_SURVIVORQOL_STEER = "Turn Steer mode on or off"
function QOL.ToggleSteer()
  local m = QOL.Module("steer")
  if m and QOL.db then QOL.Set(m, not QOL.IsOn(m)) end
end

QOL.Register({
  key = "steer",
  label = "Steer Mode",
  glyph = "g_steer",
  desc = "Your hero turns with the mouse without holding right-click. It lets go when you pick cards, open a window, chat or hold Alt. You can set a key for it in Key Bindings.",
  default = false,
  defaults = { pointer = false, altFree = true, resumeDelay = 0.3, resume = "center", centerMark = true, spotX = 0, spotY = 40, aimSize = 16, aimThick = 1, noTooltips = true },
  Enable = function(mdb)
    db = mdb
    -- the first aim spot sat dead center; move it up in front of the hero once
    if not db.spotV then
      if db.spotX == 0 and db.spotY == 0 then db.spotY = 60 end
      db.spotV = 2
    end
    -- the hover info box used to be on by default; turn it off once
    if db.spotV < 3 then db.pointer = false; db.spotV = 3 end
    -- the default spot moved down from 60 to 40
    if db.spotV < 4 then
      if db.spotY == 60 then db.spotY = 40 end
      db.spotV = 4
    end
    -- turning it on steers right away; only cards and windows make it wait
    freedAt = nil
    driver:SetScript("OnUpdate", Tick)
  end,
  Disable = function()
    driver:SetScript("OnUpdate", nil)
    Stop()
    pointer:Hide()
    mark:Hide()
  end,
  Apply = function() if not db.pointer then pointer:Hide() end end,
  Page = function(P)
    local G = P:Group("After cards or a window")
    G:Radios("Steer again", "resume", { { "center", "When the cursor reaches the middle" }, { "move", "When I move the mouse" } })
    G:Note("Middle is the smoothest: the cursor stays parked at the aim mark while you steer, so when cards pop up it is right there. A gold ring shows where to bring it back; after 2 seconds it steers again anyway.")
    G:Sliders({ { "resumeDelay", function(v) return "Wait at least: " .. v .. " s" end, 0, 1.5, 0.05, "Right away", "1.5 s" } })
    G:Done()
    G = P:Group("Cursor")
    G:Checks({ { "Hold Alt to get the cursor back", "altFree" }, { "Show what I'm aiming at", "pointer" } })
    G:Checks({ { "No tooltips while steering", "noTooltips" } })
    G:Checks({ { "Aim mark while steering", "centerMark" } })
    G:Sliders({
      { "aimSize", function(v) return "Aim mark size: " .. v .. " px" end, 8, 40, 1, "Small", "Large" },
      { "aimThick", function(v) return "Line thickness: " .. v .. " px" end, 1, 4, 1, "Thin", "Thick" },
    })
    G:Sliders({
      { "spotX", function(v) return "Aim spot left / right: " .. v end, -400, 400, 5, "Left", "Right" },
      { "spotY", function(v) return "Aim spot down / up: " .. v end, -300, 300, 5, "Down", "Up" },
    })
    G:Note("While steering, a small plus sits a little above the middle of the screen, in front of your character, like in action-camera games. Your cursor ring hides while you steer. Hold Alt to get the normal cursor back.")
    G:Note("Show what I'm aiming at: a small box with the name, level and health of whatever the hidden cursor is on. Move it with Move frames.")
    G:Done()
  end,
})
