-- Screenshots: which kinds take one and how (the policy), what the client will call the
-- file, and the state machine that lets milestones arriving together share one picture
-- while it waits to be taken (DECISION-002, "Screenshots"; the design review of
-- 2026-09-25; #103). The glue owns the timers, the interface and Screenshot(); it asks
-- this what to do and tells it what the client said.

local _, ns = ...

local Shots = {}
ns.Shots = Shots

---@class FootstepsShotPolicy
---@field delay number seconds between the milestone and the picture
---@field hideUI boolean whether the interface is hidden for it

-- The delay lets the moment settle: the level-up glow, the toast, the loot, a loading
-- screen. A level-up, an achievement and a battleground keep the interface, because
-- what says the moment is in it: the level-up toast and the portrait's new level, the
-- achievement's toast, the scoreboard.
local RULES = {
  level = { delay = 1.0, hideUI = false },
  achievement = { delay = 1.5, hideUI = false },
  boss = { delay = 1.5, hideUI = true },
  visit = { delay = 3.0, hideUI = true },
  death = { delay = 0.5, hideUI = true },
  duel = { delay = 1.0, hideUI = true },
  battleground = { delay = 3.0, hideUI = false },
  pet = { delay = 1.5, hideUI = true },
  mount = { delay = 1.5, hideUI = true },
}

-- How to take the picture for one milestone, or nothing if it takes none. The entry the
-- milestone made can rule its picture out: an achievement the account already had, or a
-- first visit made from a flight path.
---@param kind string
---@param settings FootstepsSettings
---@param entry FootstepsEntry? the entry the picture is for
---@return FootstepsShotPolicy?
function Shots.policy(kind, settings, entry)
  local rule = RULES[kind]
  if not rule or not settings.record[kind] or not settings.shots[kind] then
    return nil
  end
  if entry ~= nil then
    if kind == "achievement" and entry.earnedBefore then
      return nil
    end
    if kind == "visit" and entry.onTaxi then
      return nil
    end
  end
  return { delay = rule.delay, hideUI = rule.hideUI and settings.hideUI }
end

local EXTENSIONS = { jpeg = "jpg", jpg = "jpg", png = "png", tga = "tga" }

-- The name the client gives a screenshot. An addon cannot list files, so the name is
-- predicted and can be a second off (probe Q3 in DECISION-002).
---@param stamp string date("%m%d%y_%H%M%S") when the screenshot started
---@param format string? the screenshotFormat cvar
---@return string
function Shots.fileName(stamp, format)
  local extension = EXTENSIONS[(format or ""):lower()] or "jpg"
  return "WoWScrnShot_" .. stamp .. "." .. extension
end

---@class FootstepsCapture
---@field timeout number seconds of silence after which a picture counts as lost
---@field state "idle" | "scheduled" | "capturing"
---@field indexes number[] the entries the pending picture serves
---@field fireAt number? when the scheduled picture is due
---@field hideUI boolean? whether the pending picture hides the interface
---@field firedAt number? when Screenshot() was called
---@field stamp string? the date stamp for the file name
---@field begun boolean? the client said the pending picture started
---@field queued { at: number, index: number, policy: FootstepsShotPolicy }[] requests kept for the next picture
---@field late { indexes: number[], stamp: string }? a picture settled as lost that the client may still save
local capture = {}
capture.__index = capture

---@param options { timeout: number? }?
---@return FootstepsCapture
function Shots.newCapture(options)
  options = options or {}
  return setmetatable({
    timeout = options.timeout or 5,
    state = "idle",
    indexes = {},
    queued = {},
  }, capture)
end

-- A milestone wants a picture. It shares one only while the picture waits to be taken:
-- once Screenshot() is called the picture may already be on screen, from a moment before
-- the milestone and perhaps without the interface it wants, so a milestone that comes
-- then waits for the next picture (#103).
--   "schedule", fireAt   nothing was pending: set a timer for fireAt
--   "join", fireAt       it shares the scheduled picture, now due at fireAt. Set no timer:
--                        the one already set wakes no later, and if fireAt moved out, due
--                        answers "wait" with it
--   "queue"              a picture is being taken: the entry waits for the next one. Set
--                        no timer: finished or expire hands back its fire time
---@param now number GetTime()
---@param index number the entry's index in the journal
---@param policy FootstepsShotPolicy
---@return "schedule" | "join" | "queue" action
---@return number? fireAt
function capture:request(now, index, policy)
  if self.state == "capturing" then
    self.queued[#self.queued + 1] = { at = now, index = index, policy = policy }
    return "queue"
  end
  self.indexes[#self.indexes + 1] = index
  local fireAt = now + policy.delay
  if self.state == "scheduled" then
    -- The latest time asked for wins, and so does any milestone that wants the interface.
    self.fireAt = math.max(self.fireAt, fireAt)
    self.hideUI = self.hideUI and policy.hideUI
    return "join", self.fireAt
  end
  self.state, self.fireAt, self.hideUI = "scheduled", fireAt, policy.hideUI
  return "schedule", fireAt
end

-- The picture being taken is settled. The requests made while it was taken are made
-- again, in order and with the time each came, so they share the next picture as if it
-- had been free: it is due at the latest of their times plus delays, and it hides the
-- interface only if all of them want it hidden. Returns when that picture is due, which
-- may have passed already, or nothing if no request came.
---@param self FootstepsCapture
---@return number? fireAt
local function settled(self)
  local queued = self.queued
  self.state, self.indexes, self.queued = "idle", {}, {}
  self.fireAt, self.hideUI, self.firedAt, self.stamp, self.begun = nil, nil, nil, nil, nil
  for _, request in ipairs(queued) do
    self:request(request.at, request.index, request.policy)
  end
  return self.fireAt
end

-- A timer woke.
--   "fire", hideUI   take the picture now
--   "wait", fireAt   too early: a milestone that joined moved it out; set a timer for fireAt
--   "idle"           nothing is scheduled
---@param now number GetTime()
---@param stamp string the date stamp now, used if the client never reports a start
---@return "fire" | "wait" | "idle" action
---@return (boolean | number)? detail
function capture:due(now, stamp)
  if self.state ~= "scheduled" then
    return "idle"
  end
  if now < self.fireAt then
    return "wait", self.fireAt
  end
  -- A picture that was lost and is still unsaved can no longer be told from this one.
  self.late = nil
  self.state, self.firedAt, self.stamp = "capturing", now, stamp
  return "fire", self.hideUI
end

-- SCREENSHOT_STARTED. True when the screenshot is this capture's and not the player's.
-- Either way the client has begun a new file, and the next SCREENSHOT_SUCCEEDED is taken
-- to be that file's, so a picture that was lost is forgotten.
---@param stamp string the date stamp now
---@return boolean ours
function capture:started(stamp)
  self.late = nil
  if self.state ~= "capturing" then
    return false
  end
  self.stamp, self.begun = stamp, true
  return true
end

-- SCREENSHOT_SUCCEEDED or SCREENSHOT_FAILED. The entries the picture served and the
-- shot to attach to them, or nothing if no picture of ours was being taken; the shot is
-- one table, and Journal.attachShot gives each entry its own copy. If milestones came
-- while the picture was being taken, the fourth value is when theirs is due: the glue
-- sets a timer for it, to wake at once if that time has passed. A success with no
-- picture being taken is a lost picture's, saved late, if one is remembered: its entries
-- get their file, and `late` is true, because the interface came back and each entry was
-- said when it was lost. A failure forgets it.
---@param ok boolean
---@param format string? the screenshotFormat cvar
---@return number[]? indexes
---@return FootstepsShot? shot
---@return boolean? late
---@return number? fireAt when the next picture is due
function capture:finished(ok, format)
  if self.state ~= "capturing" then
    local late = self.late
    self.late = nil
    if late == nil or not ok then
      return nil
    end
    return late.indexes, { file = Shots.fileName(late.stamp, format) }, true
  end
  local indexes = self.indexes
  local shot = ok and { file = Shots.fileName(self.stamp, format) } or { failed = true }
  return indexes, shot, nil, settled(self)
end

-- The timer the glue set as a picture fired, `timeout` seconds on, has woken. If that
-- picture is still being taken, the client never reported back: the entries it was for
-- and a shot marked lost. The timer names its picture by when it fired, so a timer left
-- from an earlier picture does nothing to a later one. No clock is compared: GetTime()
-- counts milliseconds in floating point, and firedAt + timeout - firedAt can come out a
-- hair under timeout, which would leave the picture pending and the interface hidden.
-- A picture the client said it had started may only be slow to save, a large PNG or TGA
-- on a slow disk, so it is remembered as late: the next SCREENSHOT_SUCCEEDED gives its
-- entries their file, unless a SCREENSHOT_FAILED, another SCREENSHOT_STARTED or the next
-- picture firing comes first. One whose start never came is not remembered: nothing
-- says the client is writing it. Milestones that came while it was being taken get the
-- next picture, as finished's do; `late` is never true here, and is there so that both
-- hand the glue the same values.
---@param firedAt number GetTime() when the picture the timer was set for fired
---@return number[]? indexes
---@return FootstepsShot? shot
---@return nil late
---@return number? fireAt when the next picture is due
function capture:expire(firedAt)
  if self.state ~= "capturing" or self.firedAt ~= firedAt then
    return nil
  end
  local indexes, stamp, begun = self.indexes, self.stamp, self.begun
  local fireAt = settled(self)
  if begun then
    self.late = { indexes = indexes, stamp = stamp }
  end
  return indexes, { lost = true }, nil, fireAt
end
