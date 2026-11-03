-- The journal: whose it is, what has been seen, and what has happened. Entries are
-- never removed or reordered. Three things may change on an entry after it is written:
-- its shot, its note and whether it is hidden (DECISION-004).

local _, ns = ...

local Journal = {}
ns.Journal = Journal

-- The longest note kept, in characters.
Journal.NOTE_LIMIT = 500

-- A new journal's `seen`, in the shape of the journal it follows: an empty set for each
-- set and false for each flag. Kit.SavedData fills the schema's shape (Core/Migrations.lua)
-- into the saved journal at load, so a set added there alone is here too.
---@param seen FootstepsSeen
---@return FootstepsSeen
local function freshSeen(seen)
  local fresh = {}
  for key, value in pairs(seen) do
    if type(value) == "table" then
      fresh[key] = {}
    else
      fresh[key] = false
    end
  end
  return fresh
end

-- Claim the journal for the character logging in. Another character's journal (a
-- deleted character recreated with the same name and realm) moves to the end of
-- `archived` and a fresh one starts; nothing is ever deleted or overwritten.
---@param db FootstepsDB
---@param guid string UnitGUID("player"), checked not secret by the caller
---@return "new" | "same" | "archived"
function Journal.claim(db, guid)
  if type(guid) ~= "string" then
    error("Journal.claim: guid must be a string, got " .. type(guid), 2)
  end
  if db.guid == nil then
    db.guid = guid
    return "new"
  end
  if db.guid == guid then
    return "same"
  end
  db.archived[#db.archived + 1] = { guid = db.guid, entries = db.entries, seen = db.seen }
  db.guid, db.entries, db.seen = guid, {}, freshSeen(db.seen)
  return "archived"
end

---@param db FootstepsDB
---@param entry FootstepsEntry
---@return number index
function Journal.add(db, entry)
  local index = #db.entries + 1
  db.entries[index] = entry
  return index
end

-- One capture can serve several entries, and the capture hands them one shot table.
-- Each entry gets its own copy, and none holds the table passed in.
---@param db FootstepsDB
---@param indexes number[]
---@param shot FootstepsShot
function Journal.attachShot(db, indexes, shot)
  for _, index in ipairs(indexes) do
    local entry = db.entries[index]
    if entry then
      local copy = {}
      for k, v in pairs(shot) do
        copy[k] = v
      end
      entry.shot = copy
    end
  end
end

local function first(set, id, caller)
  if type(id) ~= "number" then
    error(caller .. ": id must be a number, got " .. type(id), 3)
  end
  if set[id] then
    return false
  end
  set[id] = true
  return true
end

-- True the first time a map is asked about, and marks it seen.
---@param db FootstepsDB
---@param mapID number
---@return boolean
function Journal.firstMap(db, mapID)
  return first(db.seen.maps, mapID, "Journal.firstMap")
end

-- True the first time a dungeon or raid is asked about, and marks it seen. Its id is
-- GetInstanceInfo's instance id, a number apart from map ids, so it has its own set.
---@param db FootstepsDB
---@param instanceID number
---@return boolean
function Journal.firstInstance(db, instanceID)
  return first(db.seen.instances, instanceID, "Journal.firstInstance")
end

-- True the first time an encounter is asked about, and marks it seen.
---@param db FootstepsDB
---@param encounterID number
---@return boolean
function Journal.firstEncounter(db, encounterID)
  return first(db.seen.encounters, encounterID, "Journal.firstEncounter")
end

-- True the first time it is asked, for the character's first mount.
---@param db FootstepsDB
---@return boolean
function Journal.firstMount(db)
  if db.seen.mount then
    return false
  end
  db.seen.mount = true
  return true
end

-- Hide an entry: it stays in the journal and leaves every list.
---@param db FootstepsDB
---@param index number
---@return boolean hidden false when there is no such entry
function Journal.hide(db, index)
  local entry = db.entries[index]
  if not entry then
    return false
  end
  entry.hidden = true
  return true
end

---@param db FootstepsDB
---@param index number
---@return boolean restored false when there is no such entry
function Journal.restore(db, index)
  local entry = db.entries[index]
  if not entry then
    return false
  end
  entry.hidden = nil
  return true
end

-- The first `limit` characters of UTF-8 text. A byte from 128 to 191 continues the
-- character before it, so the cut always falls between characters.
local function firstCharacters(text, limit)
  local characters = 0
  for position = 1, #text do
    local byte = text:byte(position)
    if byte < 128 or byte > 191 then
      characters = characters + 1
      if characters > limit then
        return text:sub(1, position - 1)
      end
    end
  end
  return text
end

-- Set, replace or (with nothing but space) remove the player's note on an entry.
---@param db FootstepsDB
---@param index number
---@param text string?
---@return string? note as stored
function Journal.setNote(db, index, text)
  local entry = db.entries[index]
  if not entry then
    return nil
  end
  local note = (text or ""):match("^%s*(.-)%s*$")
  if note == "" then
    entry.note = nil
  else
    entry.note = firstCharacters(note, Journal.NOTE_LIMIT)
  end
  return entry.note
end

-- Up to n entries that are not hidden, newest first.
---@param db FootstepsDB
---@param n number
---@return FootstepsEntry[]
function Journal.latest(db, n)
  local list = {}
  for index = #db.entries, 1, -1 do
    if #list >= n then
      break
    end
    local entry = db.entries[index]
    if not entry.hidden then
      list[#list + 1] = entry
    end
  end
  return list
end
