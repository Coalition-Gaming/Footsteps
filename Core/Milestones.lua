-- Milestones: what the game reported, plus the moment it happened, turned into a
-- journal entry for one of the ten kinds, or into nothing (DECISION-004, "Milestones").
-- Nothing is an answer: a kind switched off, a fight lost, a guild achievement, a boss
-- or a place seen before, another player's duel, an arena, or a payload without what
-- the entry's sentence needs. Whether something is a first is asked through functions
-- the glue binds to the journal, and only once the entry is otherwise certain, so
-- nothing is marked seen that was not recorded.

local _, ns = ...

local Milestones = {}
ns.Milestones = Milestones

---@class FootstepsMoment
---@field at number time()
---@field level number? UnitLevel("player")
---@field map number? the uiMapID the client reports
---@field zone string? GetZoneText()
---@field sub string? GetSubZoneText()
---@field played number? total seconds played, once the client has answered

---@class FootstepsFirsts
---@field map fun(id: number): boolean Journal.firstMap, bound to the journal
---@field instance fun(id: number): boolean Journal.firstInstance
---@field encounter fun(id: number): boolean Journal.firstEncounter
---@field mount fun(): boolean Journal.firstMount

-- What every entry copies from the moment it was made, when known.
local MOMENT = { "at", "level", "map", "zone", "sub", "played" }

-- ENCOUNTER_END's success is 1 for a kill and 0 for a wipe.
local function won(success)
  return success == 1 or success == true
end

-- PVP_MATCH_COMPLETE's winner: 0 is the Horde and 1 the Alliance, as Memento reads it.
-- Blizzard's results screen reads the same numbering from C_PvP.GetActiveMatchWinner()
-- (probe Q13). Anything else is a draw.
local WINNERS = { [0] = "Horde", [1] = "Alliance" }

---@param winner number?
---@param faction string? UnitFactionGroup("player")
---@return "won" | "lost" | "draw" | nil
local function result(winner, faction)
  local side = WINNERS[winner]
  if side == nil then
    return "draw"
  elseif faction ~= "Horde" and faction ~= "Alliance" then
    return nil
  end
  return side == faction and "won" or "lost"
end

-- One function per kind: the payload as the fields the entry adds, or nil when the
-- kind records nothing for it. A function that asks a first does so last.
local KINDS = {}

function KINDS.start(p)
  if p.empty ~= true then
    return nil
  end
  return { className = p.className, race = p.race }
end

-- While PLAYER_LEVEL_UP is handled UnitLevel can still give the old level, so the
-- event's level wins over the moment's, and without it nothing is recorded: the
-- sentence needs the new level, and the moment's would name the one just left.
function KINDS.level(p)
  if type(p.level) ~= "number" then
    return nil
  end
  return { level = p.level, levelTime = p.levelTime }
end

function KINDS.achievement(p)
  if p.guild or p.name == nil then
    return nil
  end
  return {
    id = p.id,
    name = p.name,
    points = p.points,
    icon = p.icon,
    legacyPoints = p.legacyPoints,
    earnedBefore = p.earnedBefore == true or nil,
  }
end

function KINDS.boss(p, firsts)
  if not won(p.success) or p.name == nil or type(p.id) ~= "number" then
    return nil
  end
  if not firsts.encounter(p.id) then
    return nil
  end
  return { id = p.id, name = p.name, difficulty = p.difficulty, groupSize = p.groupSize, instance = p.instance }
end

function KINDS.visit(p, firsts)
  local place = p.place
  if place == nil or place.name == nil or type(place.id) ~= "number" then
    return nil
  end
  local dungeon = place.dungeon == true
  local first
  if dungeon then
    first = firsts.instance(place.id)
  else
    first = firsts.map(place.id)
  end
  if not first then
    return nil
  end
  -- onTaxi rides along for Shots.policy, which takes no picture of a visit made flying.
  return { id = place.id, name = place.name, dungeon = dungeon, onTaxi = p.onTaxi == true or nil }
end

function KINDS.death()
  return {}
end

-- The payload is Duel.parse's answer, which names an opponent only when the line was a
-- duel result naming the player. Duel.parse gives nil for two other players' duel, and
-- that records nothing. { unread = true } is the glue's fallback from DUEL_FINISHED when
-- it could not read the line at all: the duel is recorded with no opponent and no
-- result (probe Q12).
function KINDS.duel(p)
  if p.opponent ~= nil then
    return { opponent = p.opponent, won = p.won }
  elseif p.unread == true then
    return {}
  end
  return nil
end

-- PVP_MATCH_COMPLETE also ends arenas; isBattleground is C_PvP.IsBattleground().
function KINDS.battleground(p)
  if p.isBattleground ~= true or p.name == nil then
    return nil
  end
  return { name = p.name, duration = p.duration, result = result(p.winner, p.faction) }
end

-- The glue passes both names C_PetJournal.GetPetInfoByPetID gives: the one the player
-- gave the pet, if any, and its species'. The player's wins when it has something in it.
function KINDS.pet(p)
  local name = p.speciesName
  if type(p.customName) == "string" and p.customName ~= "" then
    name = p.customName
  end
  if name == nil then
    return nil
  end
  return { name = name, species = p.species, icon = p.icon }
end

function KINDS.mount(p, firsts)
  if p.name == nil then
    return nil
  end
  return { id = p.id, name = p.name, icon = p.icon, first = firsts.mount() == true or nil }
end

-- The entry for one milestone, or nil when there is none to record. A new table each
-- time: the moment and the kind's own fields, never the payload or the moment itself.
---@param kind string "start" or one of Migrations.kinds
---@param payload table? what the glue read from the event; nil is taken as {}
---@param context FootstepsMoment
---@param settings FootstepsSettings
---@param firsts FootstepsFirsts called with a dot, at most one of them, at most once
---@return FootstepsEntry?
function Milestones.entry(kind, payload, context, settings, firsts)
  local make = KINDS[kind]
  if make == nil then
    return nil
  end
  -- Every kind but the start has a record switch. A kind switched off notes nothing,
  -- so a place first seen while visits are off is still a first once they are on.
  if kind ~= "start" and not settings.record[kind] then
    return nil
  end
  local fields = make(payload or {}, firsts)
  if fields == nil then
    return nil
  end
  local entry = { kind = kind }
  for _, key in ipairs(MOMENT) do
    entry[key] = context[key]
  end
  for key, value in pairs(fields) do
    entry[key] = value
  end
  return entry
end
