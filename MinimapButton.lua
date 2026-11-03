-- The minimap button (DECISION-004, "Opening it"; the design's "The minimap button"): a
-- left-click opens or closes the journal window, a right-click opens the settings, and
-- dragging moves it around the minimap. Built by hand, without LibStub, LibDataBroker or
-- LibDBIcon (DECISION-001 embeds no library globally); it does what LibDBIcon does for a
-- round minimap (LibDBIcon-1.0.lua, lines 156 to 174, 195 to 237 and 251 to 291, in
-- arcane-wizard-dev/Library at 459835c). Core/Ring.lua says where it sits; this file puts
-- it there. Minimap is Blizzard's (Blizzard_Minimap/Mainline/Minimap.xml, line 195, Gethe
-- forever at e3ecc27).

local _, ns = ...

local MinimapButton = {}
ns.MinimapButton = MinimapButton

local L = ns.L
local Ring = ns.Ring

-- The button's art is Blizzard's round map button, WorldMapTrackingPinButtonTemplate
-- (Blizzard_WorldMap/Blizzard_WorldMapTemplates.xml, lines 6 to 59, at e3ecc27), which
-- Blizzard_WorldMap_Mainline.toc loads for every game type (line 16): a 32 by 32
-- button, the background (line 18), the icon, the ring (line 43) and the highlight
-- (line 59), each sized and placed as there.
local SIZE = 32
local BACKGROUND = "Interface\\Minimap\\UI-Minimap-Background"
local RING = "Interface\\Minimap\\MiniMap-TrackingBorder"
local HIGHLIGHT = "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight"
-- The TOC's IconTexture, the icon of the Addon Compartment entry too (DECISION-004,
-- assumption 10): the communities window's guild info tab (Blizzard_Communities/
-- CommunitiesFrame.xml, line 421, loaded for every game type).
local ICON = "Interface\\Icons\\inv_misc_scrollunrolled01"
-- The production rule on OnUpdate (docs/process/production.md, section 3): at most 10
-- runs a second.
local FOLLOW_EVERY = 0.1

---@class FootstepsMinimapButton
---@field update fun() shows the button where it was left while settings.minimap.shown is on, and hides it otherwise

---@param saved { shown: boolean, angle: number? } settings.minimap, the saved table
---@param toggle fun() opens or closes the journal window
---@param options fun() opens the settings at Footsteps' category
---@return FootstepsMinimapButton
function MinimapButton.new(saved, toggle, options)
  ---@type Button
  local button
  local dragging = false
  -- Seconds since the button last followed the cursor in this drag.
  local sinceFollow = 0

  -- One point: the button's centre on the ring around the minimap's centre.
  local function place(angle)
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", Ring.offset(angle, Ring.radius(Minimap:GetWidth())))
  end

  -- The cursor's angle around the minimap: nil on its centre, or while the client does
  -- not know where the minimap is.
  local function cursorAngle()
    local x, y = GetCursorPosition()
    return Ring.angle(x, y, Minimap:GetEffectiveScale(), Minimap:GetCenter())
  end

  -- During a drag the button follows the cursor round the ring, ten times a second.
  -- This OnUpdate is set only while the player holds the button and taken off when they
  -- let go, as LibDBIcon does. It adds up the seconds the client gives it each frame and
  -- follows the cursor once a tenth of a second has passed, as the performance budget
  -- asks (docs/process/production.md, section 3). Letting go places the button at the
  -- cursor once more, so it lands where it was dropped. A run reads the cursor and sets
  -- one point, and makes no table.
  ---@param elapsed number seconds since the last frame
  local function follow(_, elapsed)
    sinceFollow = sinceFollow + elapsed
    if sinceFollow < FOLLOW_EVERY then
      return
    end
    sinceFollow = 0
    local angle = cursorAngle()
    if angle then
      place(angle)
    end
  end

  local function startDrag(self)
    dragging = true
    sinceFollow = 0
    if GameTooltip:GetOwner() == self then
      GameTooltip:Hide()
    end
    self:SetScript("OnUpdate", follow)
  end

  -- Letting go keeps the angle the cursor is at, and places the button there, though the
  -- last tenth of a second had not passed; on the minimap's centre, the angle the button
  -- had before. A drag ends the same way if the button is hidden while it is
  -- held, with the minimap or the interface, so no OnUpdate is left to follow the cursor
  -- once it shows again.
  local function stopDrag(self)
    if not dragging then
      return
    end
    dragging = false
    self:SetScript("OnUpdate", nil)
    Ring.remember(saved, cursorAngle())
    place(Ring.saved(saved))
  end

  -- What hovering it says. AddonCompartmentFrame, beside the minimap, puts its tooltip on
  -- the left (Blizzard_Minimap/Mainline/AddonCompartment.lua, line 13).
  local function showTooltip(self)
    if dragging then
      return
    end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip_SetTitle(GameTooltip, "Footsteps")
    GameTooltip_AddNormalLine(GameTooltip, L["Left-click: open or close the journal window"])
    GameTooltip_AddNormalLine(GameTooltip, L["Right-click: open the settings"])
    GameTooltip_AddNormalLine(GameTooltip, L["Drag: move the button around the minimap"])
    GameTooltip:Show()
  end

  local function create()
    local new = CreateFrame("Button", nil, Minimap)
    new:SetSize(SIZE, SIZE)
    -- Above the minimap's own border art, as LibDBIcon puts its buttons (lines 257 to
    -- 260).
    new:SetFrameStrata("MEDIUM")
    new:SetFrameLevel(8)
    local background = new:CreateTexture(nil, "BACKGROUND")
    background:SetTexture(BACKGROUND)
    background:SetSize(25, 25)
    background:SetPoint("TOPLEFT", 3, -4)
    local icon = new:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ICON)
    icon:SetSize(20, 20)
    icon:SetPoint("TOPLEFT", 7, -6)
    local ring = new:CreateTexture(nil, "OVERLAY")
    ring:SetTexture(RING)
    ring:SetSize(54, 54)
    ring:SetPoint("TOPLEFT")
    new:SetHighlightTexture(HIGHLIGHT, "ADD")
    new:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    new:SetScript("OnClick", function(_, mouseButton)
      if mouseButton == "RightButton" then
        options()
      else
        toggle()
      end
    end)
    new:SetScript("OnEnter", showTooltip)
    new:SetScript("OnLeave", function()
      GameTooltip:Hide()
    end)
    new:RegisterForDrag("LeftButton")
    new:SetScript("OnDragStart", startDrag)
    new:SetScript("OnDragStop", stopDrag)
    new:SetScript("OnHide", stopDrag)
    return new
  end

  ---@type FootstepsMinimapButton
  return {
    -- Made the first time it is shown, so a player who hides it never has one.
    update = function()
      if saved.shown then
        button = button or create()
        place(Ring.saved(saved))
        button:Show()
      elseif button then
        button:Hide()
      end
    end,
  }
end
