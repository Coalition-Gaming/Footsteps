-- Every player-facing string Footsteps shows (production rule 4). enUS is the base
-- and the fallback; a string is added here in the same change as the code showing it.
-- Core runs on plain Lua 5.1, whose format has no numbered arguments, so a translation
-- keeps each string's arguments in this order.

local _, ns = ...

ns.L = ns.Kit.Locale.new(GetLocale(), {
  -- Core/Format.lua: the sentence for each kind of entry.
  ["Journey began"] = true,
  ["Journey began · %s %s"] = true, -- race, class
  ["Journal begins at level %d"] = true,
  ["Journal begins at level %d · %s %s"] = true, -- level, race, class
  ["Reached level %d"] = true,
  ["Reached level %d after %s"] = true, -- level, time spent on the level before
  ["Earned %s"] = true,
  ["Earned %s · 1 Legacy point"] = true,
  ["Earned %s · %d Legacy points"] = true,
  ["Earned %s (already earned on this account)"] = true,
  ["Defeated %s"] = true,
  ["Defeated %s in %s"] = true, -- boss, instance
  ["First visit to %s"] = true,
  ["Entered %s for the first time"] = true,
  ["Died"] = true,
  ["Won a duel against %s"] = true,
  ["Lost a duel to %s"] = true,
  ["Fought a duel"] = true,
  ["Won in %s"] = true, -- battleground
  ["Lost in %s"] = true,
  ["Drew in %s"] = true,
  ["Fought in %s"] = true,
  ["New pet: %s"] = true,
  ["New mount: %s"] = true,
  ["First mount: %s"] = true,

  -- Core/Format.lua: durations.
  ["%dd %dh"] = true,
  ["%dh %dm"] = true,
  ["%dm"] = true,
  ["under a minute"] = true,

  -- Core/Format.lua: an entry's date, as formats for the client's date(). A row of the
  -- window and a line of the chat list have the time for an entry from this year and the
  -- year in its place for one from another; the detail view has both.
  ["%b %d %H:%M"] = true, -- this year's: Nov 04 16:53
  ["%b %d %Y"] = true, -- another year's: Nov 04 2025
  ["%b %d %Y %H:%M"] = true, -- the detail view's: Nov 04 2025 16:53

  -- Core/Format.lua: places and the lines built around a sentence.
  ["%s, %s"] = true, -- subzone, zone
  ["%s · %s"] = true, -- sentence, place; also each part of a picture's caption, then the rest
  ["%s · screenshot taken"] = true,
  ["%s · screenshot failed"] = true,
  ["%s  %s"] = true, -- when, what
  ["%s  %s  [screenshot]"] = true,
  -- The line under a picture's caption: the character's name, this, the place, the date.
  ["Level %d"] = true,

  -- Core/Timeline.lua: a row's tooltip.
  ["Time played: %s"] = true,
  -- The picture's file name. Footsteps predicts it from the clock, so its time may be a
  -- second off (DECISION-002, "Linking the file").
  ["Screenshot: %s, give or take a second"] = true,
  ["Screenshot failed"] = true,

  -- Core/Timeline.lua: the detail view's labels and values.
  ["Date"] = true,
  ["Level"] = true,
  ["Place"] = true,
  ["Time played"] = true,
  ["Achievement points"] = true,
  ["Difficulty"] = true, -- a boss's; the value is the client's own name for it
  ["Group size"] = true,
  ["Duration"] = true, -- how long a battleground ran
  ["Screenshot"] = true,
  ["The time in this name may be a second off."] = true, -- under the file name, as above
  ["Failed"] = true, -- the screenshot
  ["Hide"] = true, -- the button that hides the open entry
  ["Restore"] = true, -- the same button, for a hidden entry

  -- Core/Timeline.lua: the window's title.
  ["%s · 1 entry"] = true, -- the character's name
  ["%s · %d entries"] = true, -- name, how many
  ["%s · 1 entry · %s played"] = true, -- name, time played
  ["%s · %d entries · %s played"] = true, -- name, how many, time played

  -- Core/Timeline.lua: each kind's name in the filter.
  ["Levels"] = true,
  ["Achievements"] = true,
  ["Bosses"] = true,
  ["First visits"] = true,
  ["Deaths"] = true,
  ["Duels"] = true,
  ["Battlegrounds"] = true,
  ["Pets"] = true,
  ["Mounts"] = true,

  -- Window.lua: the filter.
  ["Filter"] = true,
  ["Show hidden"] = true,

  -- Window.lua and Detail.lua: the detail view. "Screenshot" above labels its file name.
  ["Click an entry to open it here."] = true,
  ["Note"] = true, -- the player's own note on an entry

  -- Options.lua: the settings panel. Each kind's name above heads its two boxes.
  ["Hide the interface for pictures"] = true,
  ["Add a caption to pictures"] = true,
  ["Say in chat when a milestone is recorded"] = true,
  ["Show the minimap button"] = true,
  ["Record"] = true, -- whether a kind is recorded
  ["Take a picture"] = true, -- whether a kind takes a screenshot
  ["The settings open when combat ends."] = true, -- asked for in combat
  -- Said instead of opening the panel when the client would not build it. The commands
  -- are what the player types, so they stay in English.
  ["The settings panel could not be built. /footsteps record, shots, hideui and caption still work."] = true,

  -- MinimapButton.lua: the button's tooltip, under the addon's name.
  ["Left-click: open or close the journal window"] = true,
  ["Right-click: open the settings"] = true,
  ["Drag: move the button around the minimap"] = true,

  -- Footsteps.lua: loading the journal and logging in.
  ["Recording this character's journey. Type /footsteps to see the journal."] = true,
  ["The saved journal could not be read, so a new one was started."] = true,
  ["The saved journal is from a newer version of Footsteps, so it is kept as it is and nothing is recorded."] = true,
  ["The saved journal could not be upgraded, so it is kept as it is and nothing is recorded."] = true,
  ["This character could not be identified, so nothing is recorded this session."] = true,

  -- Slash.lua: the chat list.
  ["The journal has no entries yet."] = true,
  -- The window's "Show hidden" checkbox, then its "Filter" button, both as above.
  ["No entries to show: every entry is hidden. The window lists them with %s ticked under %s."] = true,

  -- Slash.lua: the switches. "on" and "off" are also what the player types after
  -- record, shots, hideui and caption, which takes them in English whatever the language.
  ["on"] = true,
  ["off"] = true,
  ["Record %s: %s"] = true, -- kind, on or off
  ["Pictures for %s: %s"] = true, -- kind, on or off
  ["Pictures hide the interface: %s"] = true, -- on or off
  ["Pictures have a caption: %s"] = true, -- on or off
  ["Recorded, by kind:"] = true,
  ["Pictures, by kind:"] = true,
  ["%s: %s"] = true, -- kind, on or off

  -- Slash.lua: help.
  ["Not understood: %s"] = true, -- the word typed
  ["Commands:"] = true,
  ["/footsteps or /steps: open or close the journal window"] = true,
  ["/footsteps list [n]: the last n entries, 10 unless given, up to 50"] = true,
  ["/footsteps options: open the settings"] = true,
  ["/footsteps record [<kind> on|off]: what is recorded, or switch one kind"] = true,
  ["/footsteps shots [<kind> on|off]: what takes a picture, or switch one kind"] = true,
  ["/footsteps hideui [on|off]: whether pictures hide the interface"] = true,
  ["/footsteps caption [on|off]: whether pictures have a caption"] = true,
  ["/footsteps help: these commands"] = true,
  ["Kinds: %s"] = true, -- the kinds, as typed after record and shots
})
