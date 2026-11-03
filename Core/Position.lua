-- Where the window opens, and what is kept when the player moves it (DECISION-004, "The
-- window", and its assumption 7). settings.window holds the window's top left corner in
-- UIParent's coordinates, measured from the bottom left of the screen, per character.
-- The glue reads the corner with GetLeft and GetTop when a drag stops, and anchors the
-- window with what anchor gives when it opens.

local _, ns = ...

local Position = {}
ns.Position = Position

-- The window's anchor to UIParent: its top left corner where the player left it, or
-- its middle in the middle of the screen until then. A position with one coordinate,
-- or one that is not a number, counts as none.
---@param saved { x: number?, y: number? }?
---@return string point
---@return string relativePoint
---@return number x
---@return number y
function Position.anchor(saved)
  if saved ~= nil and type(saved.x) == "number" and type(saved.y) == "number" then
    return "TOPLEFT", "BOTTOMLEFT", saved.x, saved.y
  end
  return "CENTER", "CENTER", 0, 0
end

-- Keep where the window's top left corner was left. A corner the client does not know
-- keeps the earlier position. Other keys in the table are left as they are.
---@param saved { x: number?, y: number? }
---@param left number?
---@param top number?
function Position.remember(saved, left, top)
  if type(left) == "number" and type(top) == "number" then
    saved.x, saved.y = left, top
  end
end
