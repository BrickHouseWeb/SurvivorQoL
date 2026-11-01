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
  if pcall(MouselookStart) then holding = true; QOL.steering = true end
end

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

local function CursorNeeded()
  if db.altFree and IsAltKeyDown and IsAltKeyDown() then return true end
  if Phase() ~= "playing" then return true end
  return OpenWindow()
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

-- ---------------------------------------------------------------- frame loop
-- Checked every frame, so steering lets go the moment cards or a window come up.
local function Step()
  if CursorNeeded() then
    Stop()
    freedAt, freeX = GetTime(), nil
    return
  end
  if holding then return end
  -- cursor no longer needed: wait the delay, then (optionally) for the mouse to move
  if freedAt then
    if GetTime() - freedAt < db.resumeDelay then return end
    if db.resumeOnMove then
      local x, y = GetCursorPosition()
      if not freeX then freeX, freeY = x, y return end
      if math.abs(x - freeX) + math.abs(y - freeY) < 12 then return end
    end
    freedAt = nil
  end
  Start()
  if QOL.SteerShowMark then QOL.SteerShowMark() end
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

-- While steering, an aim mark in the middle of the screen: the Cursor module draws its own style
-- there when it is on; otherwise this small reticle does.
local mark = CreateFrame("Frame", nil, UIParent)
mark:SetFrameStrata("TOOLTIP")
mark:SetWidth(26)
mark:SetHeight(26)
mark:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
mark:EnableMouse(false)
local markTex = mark:CreateTexture(nil, "OVERLAY")
markTex:SetTexture(QOL.media .. "reticle")
markTex:SetBlendMode("ADD")
markTex:SetVertexColor(1, 0.82, 0, 0.9)
markTex:SetAllPoints(mark)
mark:Hide()
mark:SetScript("OnUpdate", function()
  local cursor = QOL.Module("cursor")
  if not (holding and db and db.centerMark) or (cursor and QOL.IsOn(cursor)) then this:Hide() end
end)

function QOL.SteerCenter() return db and db.centerMark end

function QOL.SteerShowMark()
  local cursor = QOL.Module("cursor")
  if holding and db.centerMark and not (cursor and QOL.IsOn(cursor)) then mark:Show() end
end

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
  defaults = { pointer = true, altFree = true, resumeDelay = 0.3, resumeOnMove = true, centerMark = true },
  Enable = function(mdb)
    db = mdb
    freedAt = GetTime()
    driver:SetScript("OnUpdate", Tick)
  end,
  Disable = function()
    driver:SetScript("OnUpdate", nil)
    Stop()
    pointer:Hide()
  end,
  Apply = function() if not db.pointer then pointer:Hide() end end,
  Page = function(P)
    local G = P:Group("After cards or a window")
    G:Checks({ { "Wait until I move the mouse", "resumeOnMove" } })
    G:Sliders({ { "resumeDelay", function(v) return "Wait at least: " .. v .. " s" end, 0, 1.5, 0.05, "Right away", "1.5 s" } })
    G:Note("Steering comes back only after this, so clicking a card doesn't snap your view.")
    G:Done()
    G = P:Group("Cursor")
    G:Checks({ { "Hold Alt to get the cursor back", "altFree" }, { "Pointer box", "pointer" } })
    G:Checks({ { "Aim mark in the middle of the screen", "centerMark" } })
    G:Note("While steering, a mark sits in the middle of the screen. If the Cursor module is on, it uses your cursor style. Hold Alt to get the normal cursor back.")
    G:Note("Steering hides the cursor. The pointer box shows what it is on: name, level and health. Move it with Move frames.")
    G:Done()
  end,
})
