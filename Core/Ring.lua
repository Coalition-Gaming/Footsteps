-- Where the minimap button sits (DECISION-004, "Opening it"): on a ring around the
-- minimap, at an angle the player sets by dragging it, kept per character in
-- settings.minimap.angle. Angles are in degrees as math.atan2 measures them: 0 is to the
-- right of the minimap's centre, 90 above it, 180 to its left and 270 below. A kept angle
-- is from 0 to under 360. The glue reads the cursor, the minimap's effective scale and
-- its centre, as Blizzard's MinimapMixin:OnClick does (Blizzard_Minimap/Mainline/
-- Minimap.lua, lines 123 to 134, Gethe forever at e3ecc27), and anchors the button's
-- centre to the minimap's centre at the offset given here. This is what LibDBIcon does
-- for a round minimap (LibDBIcon-1.0.lua, lines 156 to 174 and 195 to 209, in
-- arcane-wizard-dev/Library at 459835c), without the library.

local _, ns = ...

local Ring = {}
ns.Ring = Ring

-- Where the button starts: the minimap's bottom left, where LibDBIcon starts its buttons.
Ring.DEFAULT = 225

-- How far beyond the minimap's edge the button's centre sits: LibDBIcon's lib.radius.
local BEYOND = 5

-- A number that is neither infinite nor NaN. Plain Lua 5.1 has no math.huge in Core's
-- list, and NaN is the one value not equal to itself.
local function finite(value)
  return type(value) == "number" and value == value and value - value == 0
end

-- The cursor's angle from the minimap's centre. The cursor is in the screen's pixels,
-- which the minimap's effective scale turns into its own units; the centre is in those
-- units already. Nothing when a value is not known, the scale is not positive, or the
-- cursor is on the centre itself, which has no direction.
---@param cursorX number? from GetCursorPosition
---@param cursorY number?
---@param scale number? the minimap's effective scale
---@param centreX number? the minimap's centre, from its GetCenter
---@param centreY number?
---@return number? angle from 0 to under 360
function Ring.angle(cursorX, cursorY, scale, centreX, centreY)
  if not (finite(cursorX) and finite(cursorY) and finite(scale) and finite(centreX) and finite(centreY)) then
    return nil
  end
  ---@cast cursorX number
  ---@cast cursorY number
  ---@cast scale number
  ---@cast centreX number
  ---@cast centreY number
  if scale <= 0 then
    return nil
  end
  local dx, dy = cursorX / scale - centreX, cursorY / scale - centreY
  if dx == 0 and dy == 0 then
    return nil
  end
  return math.deg(math.atan2(dy, dx)) % 360
end

-- The ring's radius for a minimap of this width: its edge, and a little beyond.
---@param width number
---@return number
function Ring.radius(width)
  return width / 2 + BEYOND
end

-- The button's centre from the minimap's centre, for an angle on a ring of this radius.
---@param angle number degrees
---@param radius number
---@return number x
---@return number y
function Ring.offset(angle, radius)
  local radians = math.rad(angle)
  return math.cos(radians) * radius, math.sin(radians) * radius
end

-- The angle the player left the button at, brought round to 0 to under 360, or the
-- bottom left until there is one. A saved angle that is not a finite number counts as
-- none.
---@param minimap { angle: number? }? settings.minimap
---@return number
function Ring.saved(minimap)
  if type(minimap) == "table" and finite(minimap.angle) then
    return minimap.angle % 360
  end
  return Ring.DEFAULT
end

-- Keep the angle the button was let go at. No angle, or one that is not a finite number,
-- keeps the earlier one. Other keys in the table are left as they are.
---@param minimap { angle: number? } settings.minimap
---@param angle number?
function Ring.remember(minimap, angle)
  if finite(angle) then
    minimap.angle = angle
  end
end
