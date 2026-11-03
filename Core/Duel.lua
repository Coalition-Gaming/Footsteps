-- Who won a duel. DUEL_FINISHED carries nothing, so the result is read from the system
-- message the client prints, built from two of its format strings (enUS: "%1$s has
-- defeated %2$s in a duel" and "%2$s has fled from %1$s in a duel"). In both, argument
-- 1 is the winner and argument 2 the loser. The glue passes the strings in; probe Q12
-- in DECISION-004 confirms them in the game.

local _, ns = ...

local Duel = {}
ns.Duel = Duel

---@class FootstepsDuelPattern
---@field pattern string a Lua pattern with two captures
---@field order number[] the argument number of each capture, in the order they appear

-- Turn one format string into a pattern, or nothing if it does not name two players.
---@param format string?
---@return FootstepsDuelPattern?
local function compile(format)
  if type(format) ~= "string" then
    return nil
  end
  local parts, order, unnumbered, position = { "^" }, {}, 0, 1
  while true do
    local from, to, number = format:find("%%(%d*)%$?s", position)
    -- Everything outside the placeholders is plain text: escape every punctuation mark.
    parts[#parts + 1] = format:sub(position, (from or 0) - 1):gsub("%p", "%%%0")
    if not from then
      break
    end
    parts[#parts + 1] = "(.+)"
    if number == "" then
      unnumbered = unnumbered + 1
      order[#order + 1] = unnumbered
    else
      order[#order + 1] = tonumber(number)
    end
    position = to + 1
  end
  parts[#parts + 1] = "$"
  if #order ~= 2 then
    return nil
  end
  return { pattern = table.concat(parts), order = order }
end

-- The patterns for the client's knockout and retreat strings; a string the client
-- lacks is left out.
---@param knockout string? DUEL_WINNER_KNOCKOUT
---@param retreat string? DUEL_WINNER_RETREAT
---@return FootstepsDuelPattern[]
function Duel.patterns(knockout, retreat)
  local list = {}
  list[#list + 1] = compile(knockout)
  list[#list + 1] = compile(retreat)
  return list
end

-- The client writes a player from another realm as "Name-Realm", the realm as
-- GetNormalizedRealmName() gives it (Blizzard_UnitPopup/Mainline/UnitPopupUtils.lua,
-- lines 125 to 127, Gethe forever at e3ecc27). A name is unique only within its realm,
-- so the player's name with any other realm is somebody else, and so is any name with a
-- realm while the player's own is unknown.
local function isPlayer(name, player, realm)
  return name == player or (realm ~= nil and name == player .. "-" .. realm)
end

-- Read a system message. Nothing unless it is a duel result that names the player.
---@param message string
---@param patterns FootstepsDuelPattern[]
---@param player string? the player's own name
---@param realm string? the player's own realm, as GetNormalizedRealmName() gives it
---@return { opponent: string, won: boolean }?
function Duel.parse(message, patterns, player, realm)
  if type(player) ~= "string" or player == "" then
    return nil
  end
  if type(realm) ~= "string" or realm == "" then
    realm = nil
  end
  for _, compiled in ipairs(patterns) do
    local first, second = message:match(compiled.pattern)
    if first then
      local names = {}
      names[compiled.order[1]], names[compiled.order[2]] = first, second
      local winner, loser = names[1], names[2]
      if winner and loser then
        if isPlayer(winner, player, realm) then
          return { opponent = loser, won = true }
        elseif isPlayer(loser, player, realm) then
          return { opponent = winner, won = false }
        end
      end
    end
  end
  return nil
end

-- One duel ends with two events, in an order only the game can show (probe Q12): the
-- result line, which Duel.parse reads, and DUEL_FINISHED, which names nobody. The
-- tracker makes them one entry. A line naming the player is recorded at once.
-- DUEL_FINISHED records nothing when that line came moments before; otherwise it waits
-- a moment for it. If instead a system message came that the glue could not read (a
-- secret, or any message while the client lacks the duel strings), that was the line,
-- and the duel is recorded without a result. If no message came at all, no duel was
-- fought: DUEL_FINISHED also ends a challenge that was declined or cancelled, since
-- Blizzard's own handler for it hides the challenge's popup
-- (Blizzard_Game/Shared/EventImplementation.lua, lines 139 to 142, Gethe forever at
-- e3ecc27). Once a duel is recorded, neither event records another for a few seconds:
-- a new duel starts with a three-second countdown, so anything sooner belongs to the
-- duel just recorded.

---@class FootstepsDuelTracker
---@field window number seconds DUEL_FINISHED waits for the line, and how far apart a secret message may be
---@field span number seconds after a duel is recorded during which its events record nothing
---@field recordedAt number? when the last duel was recorded
---@field waitingSince number? when DUEL_FINISHED began waiting for the line
---@field dueAt number? when that wait ends, as finished() gave it to the glue
---@field unreadAt number? when the last system message the glue could not read arrived
local tracker = {}
tracker.__index = tracker

---@param options { window: number?, span: number? }?
---@return FootstepsDuelTracker
function Duel.newTracker(options)
  options = options or {}
  return setmetatable({ window = options.window or 1, span = options.span or 3 }, tracker)
end

local function justRecorded(self, now)
  return self.recordedAt ~= nil and now - self.recordedAt <= self.span
end

-- A readable line naming the player arrived. True when the glue should record it.
---@param now number GetTime()
---@return boolean
function tracker:line(now)
  if justRecorded(self, now) then
    return false
  end
  self.recordedAt, self.waitingSince, self.dueAt = now, nil, nil
  return true
end

-- A system message arrived that the glue could not read: a secret. It may be the line.
---@param now number GetTime()
function tracker:unreadable(now)
  self.unreadAt = now
end

-- DUEL_FINISHED arrived.
--   "done"      the duel is recorded already
--   "wait", t   ask due(t) at t: the line may still come
---@param now number GetTime()
---@return "done" | "wait" action
---@return number? at
function tracker:finished(now)
  if justRecorded(self, now) then
    return "done"
  end
  self.waitingSince, self.dueAt = now, now + self.window
  return "wait", self.dueAt
end

-- The wait after DUEL_FINISHED is over. `at` is the time finished() gave the glue,
-- which names the wait: one a later DUEL_FINISHED replaced does nothing, and no clock is
-- compared, because GetTime() in floating point can wake the timer a hair before `at`.
-- True when no readable line came and an unreadable message came within the window of
-- DUEL_FINISHED, either side: the glue records the duel without a result. False with no
-- message at all.
---@param at number the time finished() gave
---@return boolean
function tracker:due(at)
  local since = self.waitingSince
  if since == nil or self.dueAt ~= at then
    return false
  end
  self.waitingSince, self.dueAt = nil, nil
  local unreadAt = self.unreadAt
  if unreadAt == nil or math.abs(unreadAt - since) > self.window then
    return false
  end
  self.recordedAt, self.unreadAt = at, nil
  return true
end
