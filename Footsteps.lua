-- Footsteps' glue: it loads the journal, claims it for the character, listens to the
-- game and turns each event into a call to Core (the design's "Layout"). What makes an
-- entry, when a picture is taken and what is said are Core's decisions. This file reads
-- the client, leaves out every value that arrives secret (production rule 2), and
-- passes the rest in. The capture runner is in Capture.lua, the slash command in
-- Slash.lua, the window in Window.lua, the settings panel in Options.lua, the minimap
-- button in MinimapButton.lua and the guard for secret values in Secrets.lua.

local ADDON_NAME, ns = ...

local L = ns.L
local Kit, Journal, Migrations, Milestones = ns.Kit, ns.Journal, ns.Migrations, ns.Milestones
local Maps, Played, Duel, Shots, Format = ns.Maps, ns.Played, ns.Duel, ns.Shots, ns.Format
local readable = ns.Secrets.readable

local PREFIX = "|cff33ff99Footsteps|r: "

-- Seconds to wait for the answer to the played-time request before the chat frames get
-- TIME_PLAYED_MSG back without it.
local PLAYED_TIMEOUT = 10

---@type FootstepsDB the journal, once loaded and writable
local db
---@type string? why Footsteps is off for the session, once it is
local off
---@type string? Kit.SavedData's answer at ADDON_LOADED
local status
---@type FootstepsCaptureRunner
local capture
---@type FootstepsWindow the journal window, once the journal is loaded
local window
---@type FootstepsOptions the settings panel, once the journal is loaded
local options
---@type FootstepsMinimapButton
local button

local events = Kit.Events.new()
local played = Played.new()
local request = Played.newRequest()
local duels = Duel.newTracker()
-- The client's duel-result strings, read once. Either may be missing (probe Q12), and
-- then there are fewer patterns, or none.
local duelPatterns = Duel.patterns(DUEL_WINNER_KNOCKOUT, DUEL_WINNER_RETREAT)

---@param text string
local function chat(text)
  print(PREFIX .. text)
end

local function anySecret(...)
  for i = 1, select("#", ...) do
    if issecretvalue((select(i, ...))) then
      return true
    end
  end
  return false
end

-- --------------------------------------------------------------- entries

-- What every entry carries from the moment it was made.
---@return FootstepsMoment
local function moment()
  return {
    at = time(),
    level = readable(UnitLevel("player")),
    map = readable(C_Map.GetBestMapForUnit("player")),
    zone = readable(GetZoneText()),
    sub = readable(GetSubZoneText()),
    played = (played:read(GetTime())),
  }
end

---@type FootstepsFirsts
local firsts = {
  map = function(id)
    return Journal.firstMap(db, id)
  end,
  instance = function(id)
    return Journal.firstInstance(db, id)
  end,
  encounter = function(id)
    return Journal.firstEncounter(db, id)
  end,
  mount = function()
    return Journal.firstMount(db)
  end,
}

-- The chat line for an entry, while the player wants them.
---@param entry FootstepsEntry
local function say(entry)
  if db.settings.announce then
    chat(Format.announce(entry, L))
  end
end

-- One milestone: the entry, then its picture, then its chat line, then the window if
-- it is open. The start entry is neither pictured nor said.
---@param kind string
---@param payload table?
local function record(kind, payload)
  local entry = Milestones.entry(kind, payload, moment(), db.settings, firsts)
  if entry == nil then
    return
  end
  local index = Journal.add(db, entry)
  if kind ~= "start" then
    local policy = Shots.policy(kind, db.settings, entry)
    if policy then
      capture.request(index, policy)
    else
      say(entry)
    end
  end
  window.refresh()
end

-- --------------------------------------------------------------- the kinds

local function onLevelUp(_, level)
  -- The level's clock restarts whatever becomes of the entry, so the next level counts
  -- from now even while levels are not recorded.
  local levelTime = played:levelUp(GetTime())
  if issecretvalue(level) then
    return
  end
  record("level", { level = level, levelTime = levelTime })
end

-- An achievement's Legacy points, read as Blizzard_LegacyChallenges.lua reads them
-- (line 306, Gethe forever at e3ecc27). Probe Q1 confirms it in game; until then a
-- failure here costs the points, never the entry.
local function legacyPoints(id)
  local consts = Constants.LegacyConsts
  if consts == nil then
    return nil
  end
  local ok, points = pcall(C_Traits.GetTraitCurrencyForAchievement, consts.LEGACY_POINTS_TRAIT_CURRENCY_ID, id)
  if not ok or issecretvalue(points) or type(points) ~= "number" then
    return nil
  end
  return points
end

local function onAchievement(_, id, alreadyEarned)
  if anySecret(id, alreadyEarned) then
    return
  end
  local _, name, points, _, _, _, _, _, _, icon, _, isGuild = GetAchievementInfo(id)
  if anySecret(name, points, icon, isGuild) then
    return
  end
  record("achievement", {
    id = id,
    name = name,
    points = points,
    icon = icon,
    legacyPoints = legacyPoints(id),
    earnedBefore = alreadyEarned,
    guild = isGuild,
  })
end

local function onEncounterEnd(_, id, name, difficulty, groupSize, success)
  if anySecret(id, name, difficulty, groupSize, success) then
    return
  end
  local instance, instanceType = GetInstanceInfo()
  record("boss", {
    id = id,
    name = name,
    difficulty = difficulty,
    groupSize = groupSize,
    success = success,
    instance = Maps.dungeonName({ name = readable(instance), type = readable(instanceType) }),
  })
end

-- What Maps reads of C_Map.GetMapInfo, each field nil when it arrives secret, or nothing
-- for a map the client does not know.
---@param mapID number
---@return FootstepsMapInfo?
local function mapInfo(mapID)
  local info = readable(C_Map.GetMapInfo(mapID))
  if info == nil then
    return nil
  end
  return { name = readable(info.name), mapType = readable(info.mapType), parentMapID = readable(info.parentMapID) }
end

-- A first visit, from the zone the map belongs to or the dungeon the player is in.
local function onArea()
  local name, instanceType, _, _, _, _, _, instanceID = GetInstanceInfo()
  local place = Maps.place(
    readable(C_Map.GetBestMapForUnit("player")),
    mapInfo,
    Enum.UIMapType,
    { name = readable(name), type = readable(instanceType), id = readable(instanceID) }
  )
  record("visit", { place = place, onTaxi = readable(UnitOnTaxi("player")) })
end

local function onDeath()
  record("death")
end

-- A duel is read from the game's line when it can be, and recorded from DUEL_FINISHED
-- without a result when the line came secret, or when the client lacks the strings to
-- read it with. Core/Duel.lua's tracker makes the two one entry.
local function onSystemMessage(_, message)
  if issecretvalue(message) or #duelPatterns == 0 then
    duels:unreadable(GetTime())
    return
  end
  if type(message) ~= "string" then
    return
  end
  local result = Duel.parse(message, duelPatterns, readable(UnitName("player")), readable(GetNormalizedRealmName()))
  if result and duels:line(GetTime()) then
    record("duel", result)
  end
end

local function onDuelFinished()
  local action, at = duels:finished(GetTime())
  if action == "wait" then
    ---@cast at number
    C_Timer.After(at - GetTime(), function()
      if duels:due(at) then
        record("duel", { unread = true })
      end
    end)
  end
end

local function onMatchComplete(_, winner, duration)
  if anySecret(winner, duration) then
    return
  end
  record("battleground", {
    winner = winner,
    duration = duration,
    name = readable((GetInstanceInfo())),
    faction = readable((UnitFactionGroup("player"))),
    isBattleground = readable(C_PvP.IsBattleground()),
  })
end

local function onPetAdded(_, guid)
  if issecretvalue(guid) then
    return
  end
  local species, customName, _, _, _, _, _, speciesName, icon = C_PetJournal.GetPetInfoByPetID(guid)
  if anySecret(species, customName, speciesName, icon) then
    return
  end
  record("pet", { customName = customName, speciesName = speciesName, species = species, icon = icon })
end

local function onMountAdded(_, id)
  if issecretvalue(id) then
    return
  end
  local name, _, icon = C_MountJournal.GetMountInfoByID(id)
  if anySecret(name, icon) then
    return
  end
  record("mount", { id = id, name = name, icon = icon })
end

-- --------------------------------------------------------------- time played

-- The chat frames print the answer to RequestTimePlayed, because their system message
-- group includes TIME_PLAYED_MSG. While the one request a session waits, Footsteps
-- takes that one event off each chat frame that has it and remembers which; once the
-- request is settled it gives the event back to exactly those (probe Q11). Settled is a
-- quiet second after the last answer, or ten seconds after asking.
---@type table<table, true>
local muted = {}

local function mute()
  ChatFrameUtil.ForEachChatFrame(function(frame)
    if frame:IsEventRegistered("TIME_PLAYED_MSG") then
      frame:UnregisterEvent("TIME_PLAYED_MSG")
      muted[frame] = true
    end
  end)
end

local function unmute()
  for frame in pairs(muted) do
    frame:RegisterEvent("TIME_PLAYED_MSG")
  end
  muted = {}
end

-- The chat frames register their message groups again on UPDATE_CHAT_WINDOWS
-- (Blizzard_ChatFrameBase/Mainline/ChatFrameOverrides.lua, lines 118 to 129, Gethe
-- forever at e3ecc27), which can come after the request. While it waits, the event is
-- taken off them again: now, for frames that heard UPDATE_CHAT_WINDOWS first, and on
-- the next frame, for any that hear it after Footsteps. Frames that no longer show
-- system messages are forgotten, so they are not given the event back.
local function onChatWindows()
  muted = {}
  mute()
  C_Timer.After(0, function()
    if request:waiting() then
      mute()
    end
  end)
end

-- The request is settled: the chat frames get the event back, and the chat windows are
-- left alone.
local function givePlayedBack()
  events:Off("UPDATE_CHAT_WINDOWS", onChatWindows)
  unmute()
end

local function askPlayed()
  if not request:ask() then
    return
  end
  -- The way back is set first, so nothing below can keep the event from the frames.
  C_Timer.After(PLAYED_TIMEOUT, function()
    if request:settle() then
      givePlayedBack()
    end
  end)
  events:On("UPDATE_CHAT_WINDOWS", onChatWindows)
  mute()
  -- A request the client refuses brings no answer: the event goes back at once.
  if not pcall(RequestTimePlayed) and request:settle() then
    givePlayedBack()
  end
end

-- The answer to Footsteps' request, to another made at login, or to a /played the
-- player typed later. While the request waits, the frames get the event back a quiet
-- second after the last answer, so neither Footsteps' answer nor another's prints.
-- An open window's title takes the new time played.
local function onTimePlayed(_, total, level)
  local now = GetTime()
  if not anySecret(total, level) and type(total) == "number" and type(level) == "number" then
    played:seed(total, level, now)
    window.refreshTitle()
  end
  if request:answered(now) then
    C_Timer.After(request.quiet, function()
      if request:quietSince(now) then
        givePlayedBack()
      end
    end)
  end
end

-- --------------------------------------------------------------- logging in

local function onEnteringWorld()
  onArea()
  askPlayed()
end

-- What Footsteps listens to once the journal is claimed.
local function listen()
  capture = ns.Capture.new(events, db, say, window.refresh)
  events:On("PLAYER_LEVEL_UP", onLevelUp)
  events:On("ACHIEVEMENT_EARNED", onAchievement)
  events:On("ENCOUNTER_END", onEncounterEnd)
  events:On("PLAYER_ENTERING_WORLD", onEnteringWorld)
  events:On("ZONE_CHANGED_NEW_AREA", onArea)
  events:On("PLAYER_DEAD", onDeath)
  events:On("CHAT_MSG_SYSTEM", onSystemMessage)
  events:On("DUEL_FINISHED", onDuelFinished)
  events:On("PVP_MATCH_COMPLETE", onMatchComplete)
  events:On("NEW_PET_ADDED", onPetAdded)
  events:On("NEW_MOUNT_ADDED", onMountAdded)
  events:On("TIME_PLAYED_MSG", onTimePlayed)
end

-- The saved journal is readable only now. One Footsteps must not change (a newer
-- version's, or one an upgrade failed on) is left as it is and never assigned.
local function onAddonLoaded(_, name)
  if name ~= ADDON_NAME then
    return
  end
  events:Off("ADDON_LOADED", onAddonLoaded)
  local loaded, detail
  loaded, status, detail = Kit.SavedData.load(FootstepsCharDB, Migrations.schema)
  if Kit.SavedData.writable(status) then
    FootstepsCharDB = loaded
    db = loaded
    window = ns.Window.new(db, played)
    -- The settings panel's rows are bound to the saved table now, once; the minimap
    -- button follows its box. The two are built apart, so that either failing leaves the
    -- other (probes Q16 and Q17 are not yet confirmed in game): a panel the client will
    -- not build leaves a stand-in, so options is always set, and a button that cannot be
    -- made is reported through the client's error handler here, after the panel. The
    -- journal, the window and the slash command need neither.
    options = ns.Options.new(db, events, chat, function()
      button.update()
    end)
    button = ns.MinimapButton.new(db.settings.minimap, window.toggle, options.open)
    securecallfunction(button.update)
  elseif status == "newer" then
    off = L["The saved journal is from a newer version of Footsteps, so it is kept as it is and nothing is recorded."]
  else
    off = L["The saved journal could not be upgraded, so it is kept as it is and nothing is recorded."]
    -- The error of the step that raised goes to the client's error handler, as an event
    -- handler's does (ForeverKit's Events), so an upgrade that fails in the wild comes
    -- with something to work from. The player is told in chat at login.
    geterrorhandler()("Footsteps could not upgrade the saved journal: " .. detail)
  end
end

local function onLogin()
  if off then
    chat(off)
    return
  end
  if status == "reset" then
    chat(L["The saved journal could not be read, so a new one was started."])
  end
  local guid = UnitGUID("player")
  if issecretvalue(guid) or type(guid) ~= "string" then
    chat(L["This character could not be identified, so nothing is recorded this session."])
    return
  end
  if Journal.claim(db, guid) == "archived" then
    db.welcomed = false -- a new character's journal: it gets its first-run line
  end
  listen()
  record("start", {
    empty = #db.entries == 0,
    className = readable((UnitClass("player"))),
    race = readable((UnitRace("player"))),
  })
  if not db.welcomed then
    chat(L["Recording this character's journey. Type /footsteps to see the journal."])
    db.welcomed = true
  end
end

events:On("ADDON_LOADED", onAddonLoaded)
events:Once("PLAYER_LOGIN", onLogin)

SLASH_FOOTSTEPS1 = "/footsteps"
SLASH_FOOTSTEPS2 = "/steps"
SlashCmdList.FOOTSTEPS = function(message)
  if off then
    chat(off)
  elseif db then
    ns.Slash.run(db, message, chat, window, options)
  end
end

-- The Addon Compartment, the game's addon menu by the minimap, lists Footsteps because
-- the TOC names this function (AddonCompartmentFunc), which is why it is global. The
-- client calls it with the addon's name and the mouse button (Blizzard_Minimap/Mainline/
-- AddonCompartment.lua, lines 77 to 104, Gethe forever at e3ecc27). A click does what a
-- click on the minimap button does.
function Footsteps_OnAddonCompartmentClick(_, mouseButton)
  if off then
    chat(off)
  elseif db then
    if mouseButton == "RightButton" then
      options.open()
    else
      window.toggle()
    end
  end
end
