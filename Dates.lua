-- An entry's date, written by the client's date() in the form Core/Format.lua chooses
-- from the entry's year and this one. The window's rows and detail view (Window.lua,
-- through Core/Timeline.lua) and the chat list (Slash.lua) all write dates with this, so
-- a row and its line in chat always agree.

local _, ns = ...

local Dates = {}
ns.Dates = Dates

local L, Format = ns.L, ns.Format

-- "Nov 04 16:53" for an entry from this year and "Nov 04 2025" for one from another, or
-- with `full`, the detail view's "Nov 04 2025 16:53". Local time, as the client keeps it.
---@param at number the entry's time()
---@param full boolean? the detail view's form
---@return string
function Dates.entry(at, full)
  return date(Format.dateFormat(date("%Y", at), date("%Y"), L, full), at)
end
