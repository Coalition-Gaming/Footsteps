-- Locale tables for player-facing strings (docs/process/production.md, rule 4).
--
--   local L = Kit.Locale.new(GetLocale(), {           -- enUS, the base and fallback
--     ["Screenshot saved"] = true,                    -- true: the key is the text
--     ["Reached level %d"] = true,
--   })
--   Kit.Locale.add(L, "deDE", { ["Screenshot saved"] = "Screenshot gespeichert" })
--   print(L["Reached level %d"]:format(level))
--
-- A translation for a locale other than the client's is ignored. A string the client
-- locale lacks falls back to enUS. An unknown key returns itself and is listed by
-- Kit.Locale.missing(L), so a spec can assert every key used exists.

local _, ns = ...
local Kit = ns.Kit or {}
ns.Kit = Kit

local Locale = {}
Kit.Locale = Locale

local state = setmetatable({}, { __mode = "k" }) -- L -> { current, base, translated, missing }

function Locale.new(current, base)
  local L = {}
  local s = { current = current, base = base, translated = {}, missing = {}, missingList = {} }
  state[L] = s
  return setmetatable(L, {
    __index = function(_, key)
      local text = s.translated[key] or s.base[key]
      if text == true then
        return key
      elseif text ~= nil then
        return text
      end
      if not s.missing[key] then
        s.missing[key] = true
        s.missingList[#s.missingList + 1] = key
      end
      return key
    end,
  })
end

function Locale.add(L, locale, strings)
  local s = state[L]
  for key, text in pairs(strings) do
    if type(text) ~= "string" then
      error(string.format('Locale: %s translation of "%s" must be a string', locale, tostring(key)), 2)
    end
    if locale == s.current then
      s.translated[key] = text
    end
  end
end

function Locale.missing(L)
  local list = {}
  for i, key in ipairs(state[L].missingList) do
    list[i] = key
  end
  return list
end
