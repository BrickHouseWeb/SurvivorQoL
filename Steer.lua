-- Steer mode (was the SteerLook addon): keeps mouselook on (MouselookStart) so moving the mouse
-- turns the hero the way holding right-click does. It lets go whenever the cursor is needed:
-- card choices, pause, death, victory, the chat box, any open window and while you hold Alt.
-- Once the cursor is free to go it takes hold again as soon as no mouse button is held, after a
-- short pause, so the click that picked a card never lands in the world and chained cards don't
-- flick steering on and off. Steering freezes the hidden cursor where it starts, so after a card
-- pick the cursor comes back on the cards next time. A right-click (or any other key that ends
-- mouselook in the engine) does not turn steering off: it is taken back next frame.
-- The only settings are the aim point's on/off and size: the values below are tested defaults.
-- TurnOrActionStart is protected on this client (Blizzard UI only), so never call it.

local SPOT_Y = 40        -- aim point: UI units above the middle of the 3D view
local RESUME = 0.15      -- seconds after the cursor stops being needed before steering again

local db
local holding = false   -- true while we have called MouselookStart and not Stop
local freedAt           -- GetTime() when the cursor was last needed
local driver = CreateFrame("Frame")

local function Has(name) return type(getglobal(name)) == "function" end

local function Phase()
  if not Has("AZS_GetPhase") then return nil end
  local ok, ph = pcall(AZS_GetPhase)
  if ok then return ph end
end

-- Right-click and other keys can end mouselook on their own; IsMouselooking tells us when.
-- It can answer 0 for "no", which Lua counts as true.
local function Looking()
  if not Has("IsMouselooking") then return holding end
  local ok, on = pcall(IsMouselooking)
  return ok and on and on ~= 0 or false
end

local function Start()
  if not Has("MouselookStart") then return end
  if holding and Looking() then return end
  if pcall(MouselookStart) then
    holding = true
    QOL.steering = true
    if GameTooltip:IsShown() then GameTooltip:Hide() end
  end
end

-- no tooltips while steering: the hidden cursor still mouses over units and frames
local tipOnShow = GameTooltip:GetScript("OnShow")
GameTooltip:SetScript("OnShow", function()
  if tipOnShow then tipOnShow() end
  if QOL.steering then this:Hide() end
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
  if IsAltKeyDown and IsAltKeyDown() then return "alt" end
  if Phase() ~= "playing" then return "cards" end
  if OpenWindow() then return "window" end
end

-- ---------------------------------------------------------------- aim mark
-- A quiet aim point a little above the middle of the game's 3D view (WorldFrame), in front of
-- the hero: a small soft dot inside a faint thin ring, in the Cursor module's color (class color
-- by default) so it matches the cursor trail, without looking like a shooter's crosshair. WorldFrame and not UIParent: the camera keeps the hero in the middle
-- of WorldFrame, and on some setups UIParent does not cover the same area. LOW strata keeps it
-- under every window and menu.
local mark = CreateFrame("Frame", nil, UIParent)
mark:SetFrameStrata("LOW")
mark:EnableMouse(false)
mark:SetPoint("CENTER", WorldFrame, "CENTER", 0, SPOT_Y)
mark:Hide()

local ring = mark:CreateTexture(nil, "ARTWORK")
ring:SetTexture(QOL.media .. "ring2")
ring:SetAllPoints(mark)
local dot = mark:CreateTexture(nil, "OVERLAY")
dot:SetTexture(QOL.media .. "dot")
dot:SetPoint("CENTER", mark, "CENTER", 0, 0)

local function Mark(on)
  if not (on and db.centerMark) then mark:Hide() return end
  if mark.size ~= db.aimSize then
    mark:SetWidth(db.aimSize)
    mark:SetHeight(db.aimSize)
    local d = math.max(3, math.floor(db.aimSize / 4 + 0.5))
    dot:SetWidth(d)
    dot:SetHeight(d)
    mark.size = db.aimSize
  end
  local r, g, b = QOL.CursorColor()
  ring:SetVertexColor(r, g, b, 0.45)
  dot:SetVertexColor(r, g, b, 0.9)
  mark:Show()
end

local function ButtonHeld()
  if not IsMouseButtonDown then return false end
  return IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton") or IsMouseButtonDown("MiddleButton")
end

-- ---------------------------------------------------------------- frame loop
-- Checked every frame, so steering lets go the moment cards or a window come up, and takes the
-- mouse back the frame after a right-click let go of it.
local function Step()
  if CursorNeeded() then
    Stop()
    Mark(false)
    freedAt = GetTime()
    return
  end
  if holding and Looking() then return end
  -- coming back from cards or a window: wait for the click to finish and a short pause
  if freedAt then
    if ButtonHeld() or GetTime() - freedAt < RESUME then return end
    freedAt = nil
  end
  Start()
  Mark(true)
end

local function Tick()
  local ok, err = pcall(Step)
  if not ok then
    Stop()
    QOL.Set(QOL.Module("steer"), false)
    QOL.Print("Steer mode hit an error and turned off: " .. tostring(err))
  end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LEAVING_WORLD")
ev:SetScript("OnEvent", function()
  if db and QOL.IsOn(QOL.Module("steer")) then Stop() end
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
  desc = "Turn with the mouse without holding right-click. It lets go for cards, windows and chat, and nameplates never block turning (hold Shift to click one). Set a key for it in Key Bindings.",
  default = false,
  defaults = { centerMark = true, aimSize = 14 },
  Enable = function(mdb)
    db = mdb
    -- settings that became fixed defaults in 0.3
    for _, k in ipairs({ "pointer", "resume", "resumeDelay", "spotV", "altFree", "noTooltips", "spotX", "spotY", "aimThick" }) do
      db[k] = nil
    end
    -- aimSize used to size the old plus (8-40, default 16); start the new ring at its default
    if not db.aimV then db.aimSize, db.aimV = 14, 1 end
    -- turning it on steers right away
    freedAt = nil
    driver:SetScript("OnUpdate", Tick)
    QOL.PlatePassThrough(true)
  end,
  Disable = function()
    driver:SetScript("OnUpdate", nil)
    Stop()
    mark:Hide()
    QOL.PlatePassThrough(false)
  end,
  Page = function(P)
    local G = P:Group("Steering")
    G:Checks({ { "Show an aim point in front of my character", "centerMark" } })
    G:Sliders({ { "aimSize", function(v) return "Aim point size: " .. v .. " px" end, 8, 30, 1, "Small", "Large" } })
    G:Note("The aim point uses your cursor color (Cursor page). Hold Alt to get the cursor for a moment. Hold Shift to click a nameplate. Steering lets go for cards, windows and chat, and comes back once you have clicked.")
    G:Done()
  end,
})
