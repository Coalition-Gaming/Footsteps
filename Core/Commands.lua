-- What the player typed after /footsteps, turned into an action for the glue to run:
--
--   (nothing)               { action = "toggle" }                 open or close the window
--   list [n]                { action = "list", count }            the last n entries in chat
--   options                 { action = "options" }                open the settings
--   record [<kind> on|off]  { action = "record", kind, on }       without arguments: show them
--   shots [<kind> on|off]   { action = "shots", kind, on }
--   hideui [on|off]         { action = "hideui", on }
--   caption [on|off]        { action = "caption", on }
--   help, or anything else  { action = "help", unknown }

local _, ns = ...

local Commands = {}
ns.Commands = Commands

local LIST_DEFAULT, LIST_MAX = 10, 50
local ON_OFF = { on = true, off = false }

local function help(unknown)
  return { action = "help", unknown = unknown }
end

-- "on" or "off" as a boolean; anything else is the word that was not understood.
local function switch(action, word, kind)
  local on = ON_OFF[word]
  if on == nil then
    return help(word)
  end
  return { action = action, kind = kind, on = on }
end

---@param message string? what followed the slash command
---@param kinds string[] the kinds a player can switch (Migrations.kinds)
---@return { action: string, count: number?, kind: string?, on: boolean?, unknown: string? }
function Commands.parse(message, kinds)
  local words = {}
  for word in (message or ""):lower():gmatch("%S+") do
    words[#words + 1] = word
  end
  local command, first, second = words[1], words[2], words[3]

  if command == nil then
    return { action = "toggle" }
  elseif command == "list" then
    local count = math.floor(tonumber(first) or LIST_DEFAULT)
    return { action = "list", count = math.max(1, math.min(count, LIST_MAX)) }
  elseif command == "options" or command == "help" then
    return { action = command }
  elseif command == "hideui" or command == "caption" then
    if first == nil then
      return { action = command }
    end
    return switch(command, first)
  elseif command == "record" or command == "shots" then
    if first == nil then
      return { action = command }
    end
    local known = false
    for _, kind in ipairs(kinds) do
      known = known or kind == first
    end
    if not known then
      return help(first)
    elseif second == nil then
      return help()
    end
    return switch(command, second, first)
  end
  return help(command)
end
