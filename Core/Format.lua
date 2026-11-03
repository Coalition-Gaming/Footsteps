-- An entry turned into words. Every string comes from the locale table the glue passes
-- in (production rule 4), and whole sentences are format strings, never fragments
-- joined together.

local _, ns = ...

local Format = {}
ns.Format = Format

-- Days and hours, hours and minutes, or minutes: "1d 4h", "1h 32m", "32m".
---@param seconds number
---@param L table<string, string>
---@return string
function Format.duration(seconds, L)
  local minutes = math.floor(seconds / 60)
  local hours = math.floor(minutes / 60)
  local days = math.floor(hours / 24)
  if days > 0 then
    return L["%dd %dh"]:format(days, hours % 24)
  elseif hours > 0 then
    return L["%dh %dm"]:format(hours, minutes % 60)
  elseif minutes > 0 then
    return L["%dm"]:format(minutes)
  end
  return L["under a minute"]
end

local sentences = {}

function sentences.start(entry, L)
  local known = entry.race and entry.className
  if (entry.level or 1) > 1 then
    if known then
      return L["Journal begins at level %d · %s %s"]:format(entry.level, entry.race, entry.className)
    end
    return L["Journal begins at level %d"]:format(entry.level)
  elseif known then
    return L["Journey began · %s %s"]:format(entry.race, entry.className)
  end
  return L["Journey began"]
end

function sentences.level(entry, L)
  if entry.levelTime then
    return L["Reached level %d after %s"]:format(entry.level, Format.duration(entry.levelTime, L))
  end
  return L["Reached level %d"]:format(entry.level)
end

function sentences.achievement(entry, L)
  local points = entry.legacyPoints or 0
  if entry.earnedBefore then
    return L["Earned %s (already earned on this account)"]:format(entry.name)
  elseif points == 1 then
    return L["Earned %s · 1 Legacy point"]:format(entry.name)
  elseif points > 1 then
    return L["Earned %s · %d Legacy points"]:format(entry.name, points)
  end
  return L["Earned %s"]:format(entry.name)
end

function sentences.boss(entry, L)
  if entry.instance then
    return L["Defeated %s in %s"]:format(entry.name, entry.instance)
  end
  return L["Defeated %s"]:format(entry.name)
end

function sentences.visit(entry, L)
  if entry.dungeon then
    return L["Entered %s for the first time"]:format(entry.name)
  end
  return L["First visit to %s"]:format(entry.name)
end

function sentences.death(_, L)
  return L["Died"]
end

function sentences.duel(entry, L)
  if not entry.opponent then
    return L["Fought a duel"]
  elseif entry.won then
    return L["Won a duel against %s"]:format(entry.opponent)
  end
  return L["Lost a duel to %s"]:format(entry.opponent)
end

function sentences.battleground(entry, L)
  if entry.result == "won" then
    return L["Won in %s"]:format(entry.name)
  elseif entry.result == "lost" then
    return L["Lost in %s"]:format(entry.name)
  elseif entry.result == "draw" then
    return L["Drew in %s"]:format(entry.name)
  end
  return L["Fought in %s"]:format(entry.name)
end

function sentences.pet(entry, L)
  return L["New pet: %s"]:format(entry.name)
end

function sentences.mount(entry, L)
  if entry.first then
    return L["First mount: %s"]:format(entry.name)
  end
  return L["New mount: %s"]:format(entry.name)
end

-- The sentence for an entry: "Reached level 10 after 1h 32m".
---@param entry FootstepsEntry
---@param L table<string, string>
---@return string
function Format.line(entry, L)
  local sentence = sentences[entry.kind]
  if not sentence then
    return tostring(entry.kind)
  end
  return sentence(entry, L)
end

-- Where an entry happened: "Goldshire, Elwynn Forest", "Elwynn Forest", or "".
---@param entry FootstepsEntry
---@param L table<string, string>
---@return string
function Format.place(entry, L)
  local zone, sub = entry.zone or "", entry.sub or ""
  if zone == "" then
    return sub
  elseif sub == "" or sub == zone then
    return zone
  end
  return L["%s, %s"]:format(sub, zone)
end

-- The format an entry's date is written in by the client's date(), which Core may not
-- call. In a list, a row of the window or a line of the chat list, an entry from this
-- year has the day and the time, "Nov 04 16:53", and one from another year the day and
-- the year, "Nov 04 2025": the year takes the time's place, so a row's date column keeps
-- its width. The detail view always has the year and the time, "Nov 04 2025 16:53".
---@param year string the entry's year, date("%Y", at)
---@param thisYear string this year, date("%Y")
---@param L table<string, string>
---@param full boolean? the detail view's form
---@return string
function Format.dateFormat(year, thisYear, L, full)
  if full then
    return L["%b %d %Y %H:%M"]
  elseif year == thisYear then
    return L["%b %d %H:%M"]
  end
  return L["%b %d %Y"]
end

-- What is said in chat when an entry is recorded, once its picture, if any, is settled.
---@param entry FootstepsEntry
---@param L table<string, string>
---@return string
function Format.announce(entry, L)
  local sentence = Format.line(entry, L)
  if not entry.shot then
    return sentence
  elseif entry.shot.file then
    return L["%s · screenshot taken"]:format(sentence)
  end
  return L["%s · screenshot failed"]:format(sentence)
end

-- Whether an entry's sentence already names the place: a first visit's and a
-- battleground's always do, a boss's only when it names the dungeon.
---@param entry FootstepsEntry
---@return boolean
local function namesPlace(entry)
  if entry.kind == "boss" then
    return entry.instance ~= nil
  end
  return entry.kind == "visit" or entry.kind == "battleground"
end

-- One line of the chat list: when, what, where, and a mark when it has its picture.
---@param entry FootstepsEntry
---@param L table<string, string>
---@param when string the entry's date and time, formatted by the glue
---@return string
function Format.listLine(entry, L, when)
  local text = Format.line(entry, L)
  local place = Format.place(entry, L)
  if place ~= "" and not namesPlace(entry) then
    text = L["%s · %s"]:format(text, place)
  end
  if entry.shot and entry.shot.file then
    return L["%s  %s  [screenshot]"]:format(when, text)
  end
  return L["%s  %s"]:format(when, text)
end

-- The caption a picture carries (Caption.lua): the sentence of each entry it serves, one
-- a line, then who, at what level, where and when, on one line. The level is left out
-- when a level-up's sentence says it, the place when a sentence names it, and anything
-- that is not known.
---@param entries FootstepsEntry[] the entries the picture serves, at least one
---@param L table<string, string>
---@param name string? the character's name
---@param when string the first entry's date and time, formatted by the glue
---@return string title
---@return string detail
function Format.caption(entries, L, name, when)
  local lines, saysLevel, saysPlace = {}, false, false
  for i, entry in ipairs(entries) do
    lines[i] = Format.line(entry, L)
    saysLevel = saysLevel or entry.kind == "level"
    saysPlace = saysPlace or namesPlace(entry)
  end
  local first = entries[1]
  local parts = {}
  if name ~= nil and name ~= "" then
    parts[#parts + 1] = name
  end
  if first.level ~= nil and not saysLevel then
    parts[#parts + 1] = L["Level %d"]:format(first.level)
  end
  local place = Format.place(first, L)
  if place ~= "" and not saysPlace then
    parts[#parts + 1] = place
  end
  local detail = when
  for i = #parts, 1, -1 do
    detail = L["%s · %s"]:format(parts[i], detail)
  end
  return table.concat(lines, "\n"), detail
end
