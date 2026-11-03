-- Footsteps' saved-data schema, handed to Kit.SavedData.load (production rule 1).
-- Nothing has been released, so version 1 is still being shaped (DECISION-004). From
-- the first release on, every change to the shape below adds a step here, never an
-- edit to a released one, and a spec in spec/Footsteps/Core/Migrations_spec.lua with
-- the old shape as fixture.

local _, ns = ...

---@class FootstepsShot
---@field file string? the predicted screenshot file name
---@field failed true? the client reported SCREENSHOT_FAILED
---@field lost true? the client never reported back

---@class FootstepsEntry
---@field at number time() when the entry was made
---@field kind string "start" or one of Migrations.kinds
---@field level number? the character's level
---@field map number? uiMapID
---@field zone string?
---@field sub string?
---@field played number? total seconds played when the entry was made
---@field levelTime number? level entries: seconds spent on the level just finished
---@field className string? start: the character's class
---@field race string? start
---@field id number? achievement, boss (encounter), visit (map or instance), mount
---@field name string? achievement, boss, visit, battleground, pet, mount
---@field points number? achievement
---@field icon number? achievement, pet, mount: a texture file id
---@field legacyPoints number? achievement: Legacy points, 0 for an ordinary one
---@field earnedBefore true? achievement: the account had it already
---@field difficulty number? boss
---@field groupSize number? boss
---@field instance string? boss: the dungeon's name
---@field dungeon boolean? visit: a dungeon or raid, not a zone
---@field onTaxi true? visit: made from a flight path
---@field opponent string? duel: nil when the game's line could not be read
---@field won boolean? duel
---@field result "won" | "lost" | "draw" | nil battleground
---@field duration number? battleground: seconds it ran
---@field species number? pet
---@field first true? mount: the character's first
---@field shot FootstepsShot?
---@field note string? written by the player
---@field hidden true? the player hid the entry; it is never removed

---@class FootstepsSeen
---@field maps table<number, true> zones, by uiMapID
---@field instances table<number, true> dungeons and raids, by instance id (not a map id)
---@field encounters table<number, true> bosses, by encounter id
---@field mount boolean a mount has been recorded

---@class FootstepsArchive
---@field guid string the earlier owner
---@field entries FootstepsEntry[]
---@field seen FootstepsSeen

---@class FootstepsSettings
---@field hideUI boolean hide the interface for pictures
---@field caption boolean put a caption in each picture: what happened, who, where and when
---@field announce boolean say in chat when a milestone is recorded
---@field record table<string, boolean> by kind: whether it is recorded at all
---@field shots table<string, boolean> by kind: whether it takes a picture
---@field minimap { shown: boolean, angle: number } the minimap button
---@field window { x: number?, y: number? } where the player left the window

---@class FootstepsDB
---@field schemaVersion number
---@field guid string? the character this journal belongs to
---@field welcomed boolean the first-run line has been shown
---@field settings FootstepsSettings
---@field seen FootstepsSeen
---@field entries FootstepsEntry[] oldest first; never removed or reordered
---@field archived FootstepsArchive[] journals of earlier owners, oldest first

local Migrations = {}
ns.Migrations = Migrations

-- The kinds of entry a player can switch, in the order settings and help show them.
-- "start" is not here: a journal always has its first entry.
Migrations.kinds = { "level", "achievement", "boss", "visit", "death", "duel", "battleground", "pet", "mount" }

local function switches(off)
  local set = {}
  for _, kind in ipairs(Migrations.kinds) do
    set[kind] = kind ~= off
  end
  return set
end

Migrations.schema = {
  version = 1,
  defaults = {
    welcomed = false,
    settings = {
      hideUI = true,
      caption = true,
      announce = true,
      record = switches(),
      -- Deaths take no picture until the player turns it on (design review, 2026-09-25).
      shots = switches("death"),
      minimap = { shown = true, angle = 225 },
      window = {},
    },
    seen = { maps = {}, instances = {}, encounters = {}, mount = false },
    entries = {},
    archived = {},
  },
  migrations = {},
}
