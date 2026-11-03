-- Time played. The client answers one request per session with two totals (the
-- TIME_PLAYED_MSG payload); after that the glue passes in GetTime() and this adds the
-- seconds that have passed. Nothing here calls the client.

local _, ns = ...

local Played = {}
ns.Played = Played

---@class FootstepsPlayed
---@field total number? seconds played in all, as of `at`
---@field level number? seconds played on the current level, as of `at`
---@field at number? the clock when the two were true
local methods = {}
methods.__index = methods

---@return FootstepsPlayed
function Played.new()
  return setmetatable({}, methods)
end

-- Whether the client has answered yet.
---@return boolean
function methods:known()
  return self.total ~= nil
end

-- Take the client's answer. A later answer replaces what was counted since the last.
---@param total number totalTimePlayed
---@param level number timePlayedThisLevel
---@param now number GetTime()
function methods:seed(total, level, now)
  self.total, self.level, self.at = total, level, now
end

local function elapsed(self, now)
  return math.max(now - self.at, 0)
end

-- Seconds played in all and on this level, as whole seconds; nothing before an answer.
---@param now number GetTime()
---@return number? total
---@return number? level
function methods:read(now)
  if not self:known() then
    return nil
  end
  local passed = elapsed(self, now)
  return math.floor(self.total + passed), math.floor(self.level + passed)
end

-- The character has just levelled: the seconds spent on the level that ended, and the
-- new level starts from zero. Nothing before an answer.
---@param now number GetTime()
---@return number? levelTime
function methods:levelUp(now)
  if not self:known() then
    return nil
  end
  local passed = elapsed(self, now)
  local levelTime = math.floor(self.level + passed)
  self.total, self.level, self.at = self.total + passed, 0, math.max(self.at, now)
  return levelTime
end

-- The one request a session (RequestTimePlayed). The client's chat frames print its
-- answer, so the glue unregisters TIME_PLAYED_MSG on them while the request waits and
-- registers it again once the request is settled: a quiet spell after the last answer,
-- or giving up on one. The quiet spell is there because another request may be out at
-- login, an addon's or a /played typed at once: the first answer may be that one, and
-- Footsteps' own would then print. Settling happens once, so a /played typed later
-- prints as usual; one typed during the quiet spell prints nothing.

---@class FootstepsPlayedRequest
---@field state "idle" | "waiting" | "settled"
---@field quiet number seconds without an answer after which the request is settled
---@field heardAt number? when the last answer came while the request waited
local request = {}
request.__index = request

---@param options { quiet: number? }?
---@return FootstepsPlayedRequest
function Played.newRequest(options)
  options = options or {}
  return setmetatable({ state = "idle", quiet = options.quiet or 1 }, request)
end

-- True the first time: the glue asks the client now.
---@return boolean
function request:ask()
  if self.state ~= "idle" then
    return false
  end
  self.state = "waiting"
  return true
end

-- Whether the request is out and not settled: the answer must stay out of chat.
---@return boolean
function request:waiting()
  return self.state == "waiting"
end

-- TIME_PLAYED_MSG arrived. True while the request waits: the glue asks quietSince(now)
-- `quiet` seconds on.
---@param now number GetTime()
---@return boolean
function request:answered(now)
  if self.state ~= "waiting" then
    return false
  end
  self.heardAt = now
  return true
end

-- A quiet spell is over. `at` is the time of the answer it followed, which names it, so
-- no clock is compared. True when no answer has come since: the request is settled, and
-- the glue gives the chat frames their event back.
---@param at number the GetTime() given to answered()
---@return boolean
function request:quietSince(at)
  if self.state ~= "waiting" or self.heardAt ~= at then
    return false
  end
  self.state = "settled"
  return true
end

-- The glue gave up on the answer. True the first time after asking: the glue gives the
-- chat frames their event back.
---@return boolean
function request:settle()
  if self.state ~= "waiting" then
    return false
  end
  self.state = "settled"
  return true
end
