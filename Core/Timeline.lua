-- The window's content, worked out from the saved journal (DECISION-004, "The window"):
-- rows newest first, the filter by kind and its checkboxes, hidden entries, each row's
-- tooltip, the detail view's fields and button, whether one entry is listed, and the
-- title. The glue only puts these on screen. Words come from functions the glue passes
-- in, bound to Format and the locale table, because Format is another Core module.
-- Nothing here changes an entry.

local _, ns = ...

local Timeline = {}
ns.Timeline = Timeline

---@class FootstepsText
---@field L table<string, string> the locale table
---@field date fun(at: number, full: boolean?): string an entry's date, in a list's form or the detail view's
---@field line fun(entry: FootstepsEntry): string Format.line
---@field place fun(entry: FootstepsEntry): string Format.place
---@field duration fun(seconds: number): string Format.duration
---@field difficulty fun(id: number): string? a difficulty's name, GetDifficultyInfo's first value

---@class FootstepsFilter
---@field kinds table<string, boolean> false leaves a kind out; a kind not named is listed
---@field showHidden boolean

---@class FootstepsRow
---@field index number the entry's index in the journal
---@field kind string
---@field icon string
---@field date string
---@field text string the entry's sentence
---@field level number?
---@field hasPicture boolean
---@field hasNote boolean
---@field hidden boolean

---@class FootstepsDetailLine
---@field label string
---@field value string

---@class FootstepsDetail
---@field index number
---@field kind string
---@field icon string|number the entry's own icon, a file id, or the kind's texture
---@field text string
---@field lines FootstepsDetailLine[]
---@field file string? the picture's file name, to copy
---@field fileHint string? the line under the file name: its time may be a second off
---@field note string "" when there is none
---@field hidden boolean
---@field button string what the button reads: Hide, or Restore for a hidden entry

-- One of the game's own textures per kind; no art is made for the MVP. Each is used by
-- Blizzard's UI code on the forever branch (Gethe/wow-ui-source, commit e3ecc27, build
-- 70205), in a file that loads on Forever unless noted. Probe Q15 checks each draws.
local ICONS = {
  -- Blizzard_ProfessionsBook/Camelot/Blizzard_ProfessionsBook.lua
  start = "Interface\\Icons\\INV_Scroll_04",
  -- Blizzard_FrameXML/Mainline/AlertFrameSystems.lua: the experience reward
  level = "Interface\\Icons\\XP_Icon",
  -- Blizzard_GlueXML/Mainline/CharacterSelect.lua
  achievement = "Interface\\Icons\\Achievement_Quests_Completed_06",
  -- Blizzard_FrameXML/Mainline/AlertFrameSystems.lua: dungeon and raid world quests
  boss = "Interface\\Icons\\INV_Misc_Bone_Skull_02",
  -- Blizzard_Communities/CommunitiesFrame.xml
  visit = "Interface\\Icons\\INV_Misc_Map02",
  -- Blizzard_FrameXML/GhostFrame.xml: the ghost's way back to the graveyard
  death = "Interface\\Icons\\Spell_Holy_GuardianSpirit",
  -- Blizzard_ChallengesUI/Mainline/Blizzard_ChallengesUI.lua, which does not load on
  -- Forever; it is also the Dual Wield skill's icon, a skill Forever's classes learn.
  duel = "Interface\\Icons\\Ability_DualWield",
  -- Blizzard_GlueXML/Mainline/CharacterSelect.lua: a Warsong Gulch flag
  battleground = "Interface\\Icons\\Achievement_BG_ReturnXFlags_Def_WSG",
  -- Blizzard_Collections/Shared/Blizzard_Collections.lua: the pet journal's tab
  pet = "Interface\\Icons\\INV_ArfusPet_Classic",
  -- Blizzard_Collections/Shared/Blizzard_Collections.lua: the mount journal's tab
  mount = "Interface\\Icons\\INV_Horse3Saddle008_Chestnut",
}
-- Blizzard_UIPanels_Game/Camelot/PaperDollFrame.lua: the game's own "no icon" icon
local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

---@param kind string
---@return string texture
function Timeline.icon(kind)
  return ICONS[kind] or UNKNOWN_ICON
end

-- The kinds that hold the game's own icon for what was earned (DECISION-004, "Holds"):
-- the texture file id GetAchievementInfo, C_PetJournal or C_MountJournal gave.
local OWN_ICON = { achievement = true, pet = true, mount = true }

-- The detail view's icon: the entry's own when its kind holds one and it has one, and
-- the kind's otherwise. The list keeps the kind's, so a row says what kind it is.
---@param entry FootstepsEntry
---@return string|number texture
local function detailIcon(entry)
  if OWN_ICON[entry.kind] and type(entry.icon) == "number" then
    return entry.icon
  end
  return Timeline.icon(entry.kind)
end

-- Each kind's name in the filter, as a key of the locale table. The start has no
-- checkbox, so it has no name.
local KIND_NAMES = {
  level = "Levels",
  achievement = "Achievements",
  boss = "Bosses",
  visit = "First visits",
  death = "Deaths",
  duel = "Duels",
  battleground = "Battlegrounds",
  pet = "Pets",
  mount = "Mounts",
}

-- A kind's name for the player; a kind this does not know is its own word.
---@param kind string
---@param L table<string, string> the locale table
---@return string
function Timeline.kindName(kind, L)
  local key = KIND_NAMES[kind]
  if key == nil then
    return kind
  end
  return L[key]
end

-- Every kind given ticked, hidden entries left out: how the window starts each session.
---@param kinds string[]
---@return FootstepsFilter
function Timeline.newFilter(kinds)
  local ticked = {}
  for _, kind in ipairs(kinds) do
    ticked[kind] = true
  end
  return { kinds = ticked, showHidden = false }
end

-- Whether a kind's checkbox is ticked. A kind the filter does not name is listed, so
-- it counts as ticked.
---@param filter FootstepsFilter
---@param kind string
---@return boolean
function Timeline.ticked(filter, kind)
  return filter.kinds[kind] ~= false
end

-- A click on a kind's checkbox.
---@param filter FootstepsFilter
---@param kind string
function Timeline.toggle(filter, kind)
  filter.kinds[kind] = not Timeline.ticked(filter, kind)
end

-- A click on "Show hidden".
---@param filter FootstepsFilter
function Timeline.toggleHidden(filter)
  filter.showHidden = not filter.showHidden
end

---@param shot FootstepsShot?
---@return boolean
local function failed(shot)
  return shot ~= nil and (shot.failed == true or shot.lost == true)
end

-- Whether the filter lets an entry of `kind` through.
---@param filter FootstepsFilter
---@param kind string
---@param hidden boolean
---@return boolean
local function listedBy(filter, kind, hidden)
  return filter.kinds[kind] ~= false and (filter.showHidden or not hidden)
end

-- The rows the filter lets through, newest first. One pass over the journal, reading
-- each entry a handful of times, and the words only for the rows listed: a journey from
-- 1 to 60 is about 500 entries.
---@param entries FootstepsEntry[] oldest first
---@param filter FootstepsFilter
---@param text FootstepsText
---@return FootstepsRow[]
function Timeline.rows(entries, filter, text)
  local rows = {}
  for index = #entries, 1, -1 do
    local entry = entries[index]
    local kind = entry.kind
    local hidden = entry.hidden and true or false
    if listedBy(filter, kind, hidden) then
      local shot = entry.shot
      rows[#rows + 1] = {
        index = index,
        kind = kind,
        icon = Timeline.icon(kind),
        date = text.date(entry.at),
        text = text.line(entry),
        level = entry.level,
        hasPicture = shot ~= nil and shot.file ~= nil,
        hasNote = entry.note ~= nil,
        hidden = hidden,
      }
    end
  end
  return rows
end

-- Whether rows lists one entry: it is of a kind the filter does not untick, and not
-- hidden unless hidden entries are shown. The detail view's selection follows this, so
-- the view closes when its entry leaves the list.
---@param entries FootstepsEntry[]
---@param filter FootstepsFilter
---@param index number
---@return boolean
function Timeline.listed(entries, filter, index)
  local entry = entries[index]
  if entry == nil then
    return false
  end
  return listedBy(filter, entry.kind, entry.hidden and true or false)
end

-- What hovering a row shows beyond the row: the place, time played, the picture and
-- the note, each only when the entry has it. The picture's file name is predicted from
-- the clock, not read, so it can be a second off (DECISION-002, "Linking the file"),
-- and the line says so.
---@param entries FootstepsEntry[]
---@param index number
---@param text FootstepsText
---@return string[]?
function Timeline.tooltip(entries, index, text)
  local entry = entries[index]
  if entry == nil then
    return nil
  end
  local L = text.L
  local lines = {}
  local place = text.place(entry)
  if place ~= "" then
    lines[#lines + 1] = place
  end
  if entry.played then
    lines[#lines + 1] = L["Time played: %s"]:format(text.duration(entry.played))
  end
  local shot = entry.shot
  if shot and shot.file then
    lines[#lines + 1] = L["Screenshot: %s, give or take a second"]:format(shot.file)
  elseif failed(shot) then
    lines[#lines + 1] = L["Screenshot failed"]
  end
  if entry.note then
    lines[#lines + 1] = entry.note
  end
  return lines
end

-- What a kind holds that its sentence does not say, each as a label and a value: an
-- achievement's points, a boss's difficulty and group size, a battleground's length.
-- Ids are left out; they mean nothing to the player as numbers. An icon is drawn, not
-- written (detailIcon above).
---@param entry FootstepsEntry
---@param text FootstepsText
---@param add fun(label: string, value: string)
local function addKindFacts(entry, text, add)
  local L, kind = text.L, entry.kind
  if kind == "achievement" and entry.points then
    add(L["Achievement points"], tostring(entry.points))
  elseif kind == "boss" then
    -- A difficulty the client has no name for is left out.
    local difficulty = entry.difficulty and text.difficulty(entry.difficulty)
    if type(difficulty) == "string" and difficulty ~= "" then
      add(L["Difficulty"], difficulty)
    end
    if entry.groupSize then
      add(L["Group size"], tostring(entry.groupSize))
    end
  elseif kind == "battleground" and entry.duration then
    add(L["Duration"], text.duration(entry.duration))
  end
end

-- What the detail view shows for one entry: its icon and sentence, its facts as label
-- and value, the picture's file name to copy with a line saying it can be a second off,
-- the note to edit and whether it is hidden. The file name itself stays bare, so the
-- player can copy it.
---@param entries FootstepsEntry[]
---@param index number
---@param text FootstepsText
---@return FootstepsDetail?
function Timeline.detail(entries, index, text)
  local entry = entries[index]
  if entry == nil then
    return nil
  end
  local L = text.L
  local lines = {}
  local function add(label, value)
    lines[#lines + 1] = { label = label, value = value }
  end
  if entry.at then
    -- Always with the year and the time, where a row has one or the other.
    add(L["Date"], text.date(entry.at, true))
  end
  if entry.level then
    add(L["Level"], tostring(entry.level))
  end
  local place = text.place(entry)
  if place ~= "" then
    add(L["Place"], place)
  end
  if entry.played then
    add(L["Time played"], text.duration(entry.played))
  end
  addKindFacts(entry, text, add)
  local shot = entry.shot
  if failed(shot) then
    add(L["Screenshot"], L["Failed"])
  end
  local hidden = entry.hidden and true or false
  local file = shot and shot.file
  return {
    index = index,
    kind = entry.kind,
    icon = detailIcon(entry),
    text = text.line(entry),
    lines = lines,
    file = file,
    fileHint = file and L["The time in this name may be a second off."] or nil,
    note = entry.note or "",
    hidden = hidden,
    -- Hiding needs no confirmation because the same button undoes it (assumption 9).
    button = hidden and L["Restore"] or L["Hide"],
  }
end

-- The window's title: how many entries are not hidden, whatever the filter, and the
-- time played. Until the client has answered, the time played is the newest entry's
-- that knows it, hidden or not.
---@param entries FootstepsEntry[]
---@param played number? from Played, when the client has answered
---@return { count: number, played: number? }
function Timeline.title(entries, played)
  local count = 0
  for index = 1, #entries do
    if not entries[index].hidden then
      count = count + 1
    end
  end
  if played == nil then
    for index = #entries, 1, -1 do
      played = entries[index].played
      if played ~= nil then
        break
      end
    end
  end
  return { count = count, played = played }
end

-- The title as the player reads it: the character's name, then title's count and time
-- played. Without a name, the addon's own, which is not translated.
---@param entries FootstepsEntry[]
---@param played number? from Played, when the client has answered
---@param name string? the character's name
---@param text FootstepsText
---@return string
function Timeline.titleText(entries, played, name, text)
  local L = text.L
  local title = Timeline.title(entries, played)
  if type(name) ~= "string" or name == "" then
    name = "Footsteps"
  end
  if title.played == nil then
    if title.count == 1 then
      return L["%s · 1 entry"]:format(name)
    end
    return L["%s · %d entries"]:format(name, title.count)
  end
  local duration = text.duration(title.played)
  if title.count == 1 then
    return L["%s · 1 entry · %s played"]:format(name, duration)
  end
  return L["%s · %d entries · %s played"]:format(name, title.count, duration)
end
