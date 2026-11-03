-- /footsteps and /steps (DECISION-004, "Commands"). Core/Commands.lua turns what was
-- typed into an action and this runs it. The bare command opens or closes the window
-- (Window.lua), and options opens the settings panel (Options.lua). A switch changes
-- through the panel's setting, so an open panel follows it, or through the stand-in
-- Options.lua leaves when the client will not build the panel. Kind words and
-- "/footsteps" are what the player types, so they are not translated.

local _, ns = ...

local Slash = {}
ns.Slash = Slash

local L = ns.L

---@param on boolean?
---@return string
local function word(on)
  return on and L["on"] or L["off"]
end

-- One line per entry, newest first, and nothing else. Hidden entries are left out; when
-- every entry is hidden the journal still has them, so the line says so and names the
-- window's checkbox that lists them, in the window's own words.
---@param db FootstepsDB
---@param count number
---@param chat fun(text: string)
local function list(db, count, chat)
  local entries = ns.Journal.latest(db, count)
  if #entries == 0 then
    if #db.entries == 0 then
      chat(L["The journal has no entries yet."])
    else
      chat(
        L["No entries to show: every entry is hidden. The window lists them with %s ticked under %s."]:format(
          L["Show hidden"],
          L["Filter"]
        )
      )
    end
    return
  end
  for _, entry in ipairs(entries) do
    print(ns.Format.listLine(entry, L, ns.Dates.entry(entry.at)))
  end
end

-- A header, then one line per kind in Migrations.kinds' order.
---@param switches table<string, boolean>
---@param header string
---@param chat fun(text: string)
local function listSwitches(switches, header, chat)
  chat(header)
  for _, kind in ipairs(ns.Migrations.kinds) do
    print("  " .. L["%s: %s"]:format(kind, word(switches[kind])))
  end
end

local function help(unknown, chat)
  if unknown then
    chat(L["Not understood: %s"]:format(unknown))
  end
  chat(L["Commands:"])
  for _, line in ipairs({
    L["/footsteps or /steps: open or close the journal window"],
    L["/footsteps list [n]: the last n entries, 10 unless given, up to 50"],
    L["/footsteps options: open the settings"],
    L["/footsteps record [<kind> on|off]: what is recorded, or switch one kind"],
    L["/footsteps shots [<kind> on|off]: what takes a picture, or switch one kind"],
    L["/footsteps hideui [on|off]: whether pictures hide the interface"],
    L["/footsteps caption [on|off]: whether pictures have a caption"],
    L["/footsteps help: these commands"],
    L["Kinds: %s"]:format(table.concat(ns.Migrations.kinds, ", ")),
  }) do
    print("  " .. line)
  end
end

---@alias FootstepsSlashCommand { action: string, count: number?, kind: string?, on: boolean?, unknown: string? }

-- Prints one line with Footsteps' name before it.
---@alias FootstepsChat fun(text: string)

-- What each action is given: the journal, what was typed, the chat line and the panel.
---@type table<string, fun(db: FootstepsDB, cmd: FootstepsSlashCommand, chat: FootstepsChat, ui: FootstepsOptions)>
local ACTIONS = {}

function ACTIONS.list(db, command, chat)
  list(db, command.count, chat)
end

-- The panel, and nothing in chat; without a panel, the line that says so.
function ACTIONS.options(_, _, _, options)
  options.open()
end

function ACTIONS.record(db, command, chat, options)
  if command.kind == nil then
    listSwitches(db.settings.record, L["Recorded, by kind:"], chat)
    return
  end
  options.set(db.settings.record, command.kind, command.on)
  chat(L["Record %s: %s"]:format(command.kind, word(command.on)))
end

function ACTIONS.shots(db, command, chat, options)
  if command.kind == nil then
    listSwitches(db.settings.shots, L["Pictures, by kind:"], chat)
    return
  end
  options.set(db.settings.shots, command.kind, command.on)
  chat(L["Pictures for %s: %s"]:format(command.kind, word(command.on)))
end

function ACTIONS.hideui(db, command, chat, options)
  if command.on ~= nil then
    options.set(db.settings, "hideUI", command.on)
  end
  chat(L["Pictures hide the interface: %s"]:format(word(db.settings.hideUI)))
end

function ACTIONS.caption(db, command, chat, options)
  if command.on ~= nil then
    options.set(db.settings, "caption", command.on)
  end
  chat(L["Pictures have a caption: %s"]:format(word(db.settings.caption)))
end

function ACTIONS.help(_, command, chat)
  help(command.unknown, chat)
end

-- Run what followed /footsteps against the journal.
---@param db FootstepsDB
---@param message string?
---@param chat FootstepsChat
---@param window FootstepsWindow the journal window
---@param options FootstepsOptions the settings panel
function Slash.run(db, message, chat, window, options)
  local command = ns.Commands.parse(message, ns.Migrations.kinds)
  if command.action == "toggle" then
    window.toggle() -- and nothing in chat
    return
  end
  ACTIONS[command.action](db, command, chat, options)
end
