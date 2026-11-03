-- The interface around a picture: whether Footsteps may hide it, and when it owes it
-- back (DECISION-002, "Screenshots"). The glue reads InCombatLockdown(),
-- UIParent:IsShown() and what the player has open, and does the hiding and showing;
-- this keeps what was decided. Four rules: never touch the interface in combat, because
-- UIParent holds protected frames; never hide it while hiding would close what the
-- player is doing; never show an interface the player hid; and give back every interface
-- Footsteps hid, at once, as combat starts, or when combat ends.

local _, ns = ...

local Interface = {}
ns.Interface = Interface

---@class FootstepsInterface
---@field hidden boolean Footsteps hid the interface and has not shown it again
---@field owed boolean the picture is settled, and showing the interface waits for combat to end
local methods = {}
methods.__index = methods

---@return FootstepsInterface
function Interface.new()
  return setmetatable({ hidden = false, owed = false }, methods)
end

-- Just before a picture. True when the glue should hide the interface now: the picture
-- wants it hidden, combat has not locked it, the player has not hidden it already, and
-- the player is not busy. Busy is a window open that ends its interaction when hidden
-- (an NPC's, loot, a trade, the mail, the bank), a popup up that ends what it asks
-- about when hidden (a group invite), or typing in a box: hiding the interface hides
-- those too.
---@param wanted boolean the capture's hideUI
---@param inCombat boolean InCombatLockdown()
---@param shown boolean UIParent:IsShown()
---@param busy boolean? such a window or popup is shown, or a box has the keyboard
---@return boolean
function methods:hide(wanted, inCombat, shown, busy)
  if wanted and not inCombat and shown and not busy then
    self.hidden = true
    return true
  end
  return false
end

-- The picture is settled: taken, failed or lost. True when the glue should show the
-- interface now. In combat it is left hidden and owed until combat ends.
---@param inCombat boolean InCombatLockdown()
---@return boolean
function methods:restore(inCombat)
  if not self.hidden then
    return false
  end
  if inCombat then
    self.owed = true
    return false
  end
  self.hidden, self.owed = false, false
  return true
end

-- PLAYER_REGEN_DISABLED. True when the glue should show the interface now: Footsteps
-- has it hidden, and combat lockdown has not begun yet, so the player does not fight
-- without it. A picture still being taken goes on; settling it then shows nothing. Once
-- lockdown has begun the interface waits for the end of combat.
---@param inCombat boolean InCombatLockdown()
---@return boolean
function methods:combatStarting(inCombat)
  if not self.hidden or inCombat then
    return false
  end
  self.hidden, self.owed = false, false
  return true
end

-- PLAYER_REGEN_ENABLED. True when the glue should show an interface owed since a
-- picture settled in combat. One whose picture is still being taken waits for it.
---@return boolean
function methods:combatEnded()
  if not self.owed then
    return false
  end
  self.hidden, self.owed = false, false
  return true
end
