-- One hidden frame per addon dispatching client events to any number of handlers.
--
--   local events = Kit.Events.new()
--   events:On("PLAYER_LOGIN", function(event, ...) end)
--   events:Once("PLAYER_ENTERING_WORLD", handler)
--   events:Off("PLAYER_LOGIN", handler)
--
-- An event is registered with the client when its first handler arrives and
-- unregistered when its last one leaves, so nothing fires that nobody handles. A
-- handler that raises is reported through the error handler (securecallfunction) and
-- the remaining handlers still run.

local _, ns = ...
local Kit = ns.Kit or {}
ns.Kit = Kit

local Events = {}
Events.__index = Events
Kit.Events = Events

function Events.new()
  local self = setmetatable({ handlers = {} }, Events)
  self.frame = CreateFrame("Frame")
  self.frame:SetScript("OnEvent", function(_, event, ...)
    self:_dispatch(event, ...)
  end)
  return self
end

function Events:_dispatch(event, ...)
  local list = self.handlers[event]
  if not list then
    return
  end
  -- Iterate a snapshot: a handler may add or remove handlers while this runs.
  local snapshot = {}
  for i, handler in ipairs(list) do
    snapshot[i] = handler
  end
  for _, handler in ipairs(snapshot) do
    securecallfunction(handler, event, ...)
  end
end

function Events:On(event, handler)
  local list = self.handlers[event]
  if not list then
    self.frame:RegisterEvent(event)
    list = {}
    self.handlers[event] = list
  end
  list[#list + 1] = handler
  return handler
end

function Events:Off(event, handler)
  local list = self.handlers[event]
  if not list then
    return
  end
  for i = #list, 1, -1 do
    if list[i] == handler then
      table.remove(list, i)
    end
  end
  if #list == 0 then
    self.handlers[event] = nil
    self.frame:UnregisterEvent(event)
  end
end

function Events:Once(event, handler)
  local function once(...)
    self:Off(event, once)
    handler(...)
  end
  return self:On(event, once)
end
