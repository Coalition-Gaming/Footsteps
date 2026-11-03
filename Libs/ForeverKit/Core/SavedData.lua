-- Versioned saved tables with migrations (docs/process/production.md, rule 1).
--
--   local db, status, detail = Kit.SavedData.load(MyAddonDB, {
--     version = 2,
--     defaults = { enabled = true, entries = {} },
--     migrations = { [2] = function(db) db.entries = db.log; db.log = nil end },
--   })
--   if Kit.SavedData.writable(status) then MyAddonDB = db else <run on a session copy> end
--
-- status is one of:
--   new       nothing was saved; db is a copy of the defaults
--   reset     the saved value was not a table; db is a copy of the defaults
--   current   saved data was at this version; missing keys filled in place
--   migrated  saved data was older; every step ran on a copy, which is returned
--   failed    a step raised; the saved data is returned untouched; do not write it
--   newer     saved data is from a newer addon version; returned untouched; do not write it
--
-- Data without schemaVersion is version 1. Defaults fill missing keys only (a saved
-- false is kept) and recurse into record tables, not into lists. Unknown keys are kept.

local _, ns = ...
local Kit = ns.Kit or {}
ns.Kit = Kit

local SavedData = {}
Kit.SavedData = SavedData

local function deepCopy(value)
  if type(value) ~= "table" then
    return value
  end
  local copy = {}
  for k, v in pairs(value) do
    copy[k] = deepCopy(v)
  end
  return copy
end

local function isList(t)
  return next(t) == nil or t[1] ~= nil
end

local function fillDefaults(db, defaults)
  for key, default in pairs(defaults) do
    local current = db[key]
    if current == nil then
      db[key] = deepCopy(default)
    elseif type(current) == "table" and type(default) == "table" and not isList(default) then
      fillDefaults(current, default)
    end
  end
  return db
end

local function fresh(schema)
  local db = deepCopy(schema.defaults)
  db.schemaVersion = schema.version
  return db
end

local function validate(schema)
  for step = 2, schema.version do
    if type(schema.migrations[step]) ~= "function" then
      error(string.format("SavedData: schema version %d has no migration step %d", schema.version, step), 3)
    end
  end
end

function SavedData.load(saved, schema)
  validate(schema)
  if saved == nil then
    return fresh(schema), "new"
  end
  if type(saved) ~= "table" then
    return fresh(schema), "reset", "saved value was a " .. type(saved)
  end

  local from = saved.schemaVersion or 1
  if from > schema.version then
    return saved, "newer", string.format("%d > %d", from, schema.version)
  end
  if from == schema.version then
    saved.schemaVersion = from
    return fillDefaults(saved, schema.defaults), "current"
  end

  -- Migrate a copy, so a failing step cannot leave the saved data half-changed.
  local ok, result = pcall(function()
    local db = deepCopy(saved)
    for step = from + 1, schema.version do
      db = schema.migrations[step](db) or db
      db.schemaVersion = step
    end
    return db
  end)
  if not ok then
    return saved, "failed", tostring(result)
  end
  return fillDefaults(result, schema.defaults), "migrated", string.format("%d -> %d", from, schema.version)
end

function SavedData.writable(status)
  return status ~= "failed" and status ~= "newer"
end
