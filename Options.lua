-- The settings panel (DECISION-004, "The settings panel"; the design's "The settings
-- panel"): one category, Footsteps, in the AddOns list of the game's Settings window.
-- Every row is a checkbox bound to the saved journal's settings with
-- Settings.RegisterAddOnSetting, which reads and writes the saved table itself, so there
-- is no code between a box and its value. Blizzard's own guide to the API is
-- Blizzard_Settings_Shared/Blizzard_ImplementationReadme.lua (Gethe forever at e3ecc27),
-- lines 45 to 98 and 192 to 211; the functions are in Blizzard_Settings.lua (lines 134,
-- 144, 154, 174 and 388) and the section header in Blizzard_SettingControls.lua (line
-- 112). Blizzard_Settings_Shared.toc loads both for every game type (lines 7, 13 and 20).
-- If the client will not build the panel, a stand-in takes its place (Options.new).

local _, ns = ...

local Options = {}
ns.Options = Options

local L = ns.L
local Migrations, Timeline = ns.Migrations, ns.Timeline

-- The category's name is the addon's, which is not translated.
local CATEGORY = "Footsteps"

---@class FootstepsOptions
---@field open fun() opens the game's settings at Footsteps' category, or once combat ends; without a panel, says so
---@field set fun(tbl: table, key: string, value: boolean) changes a saved setting the way its checkbox does

-- The panel itself, with Options.new's arguments.
---@param db FootstepsDB
---@param events table
---@param chat FootstepsChat
---@param minimapShown fun()
---@return FootstepsOptions
local function build(db, events, chat, minimapShown)
  -- Opening is the one call made later, when the panel is asked for, so a client without
  -- it is found now, before anything is registered, while the stand-in can take the
  -- panel's place (Q16).
  if type(Settings.OpenToCategory) ~= "function" then
    error("Settings.OpenToCategory is missing")
  end
  local settings = db.settings
  local defaults = Migrations.schema.defaults.settings
  local category, layout = Settings.RegisterVerticalLayoutCategory(CATEGORY)
  -- Each setting by the saved table and key it is bound to, for the slash command.
  ---@type table<table, table<string, AddOnSetting>>
  local bound = {}

  -- A checkbox bound to tbl[key], the saved table itself and never a copy. The variable
  -- names the setting for the whole client, so it starts with the addon's name. The
  -- default is the one a new journal starts with, which the panel's Defaults button
  -- puts back.
  local function checkbox(variable, tbl, key, label, default)
    local setting = Settings.RegisterAddOnSetting(
      category,
      "Footsteps_" .. variable,
      key,
      tbl,
      Settings.VarType.Boolean,
      label,
      default
    )
    bound[tbl] = bound[tbl] or {}
    bound[tbl][key] = setting
    return setting, Settings.CreateCheckbox(category, setting)
  end

  checkbox("hideUI", settings, "hideUI", L["Hide the interface for pictures"], defaults.hideUI)
  checkbox("caption", settings, "caption", L["Add a caption to pictures"], defaults.caption)
  checkbox("announce", settings, "announce", L["Say in chat when a milestone is recorded"], defaults.announce)
  local shown =
    checkbox("minimapShown", settings.minimap, "shown", L["Show the minimap button"], defaults.minimap.shown)
  -- The button follows the box at once, whatever changed it: a click, or Defaults.
  shown:SetValueChangedCallback(function()
    minimapShown()
  end)

  -- Under each kind's name, as the window's filter names it: Record, then Take a picture.
  -- The picture's box is indented under its Record box and greyed while that is off,
  -- because it does nothing then. That is how Blizzard's own panels tie one setting to
  -- another: SetParentInitializer with a predicate, as the colorblind filter's strength
  -- slider is tied to the filter (Blizzard_SettingsDefinitions_Frame/Colorblind.lua,
  -- lines 30 to 34, at e3ecc27, loaded for every game type). The child is indented while
  -- its parent is in the list (Blizzard_SettingControls.lua, lines 204 to 226),
  -- evaluated again when the parent's setting changes (lines 311 to 320 and 370 to 372),
  -- and enabled only while its predicates hold (lines 536 to 544 and 646 to 663).
  for _, kind in ipairs(Migrations.kinds) do
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(Timeline.kindName(kind, L)))
    local _, record = checkbox("record_" .. kind, settings.record, kind, L["Record"], defaults.record[kind])
    local _, picture = checkbox("shots_" .. kind, settings.shots, kind, L["Take a picture"], defaults.shots[kind])
    picture:SetParentInitializer(record, function()
      return settings.record[kind]
    end)
  end

  -- Registered last, once its rows exist, as Blizzard's guide does (line 97).
  Settings.RegisterAddOnCategory(category)

  local function openNow()
    Settings.OpenToCategory(category:GetID())
  end

  -- Whether a request made in combat waits for it to end.
  local waiting = false

  ---@type FootstepsOptions
  return {
    -- C_SettingsUtil.OpenSettingsPanel, which Settings.OpenToCategory calls, is flagged
    -- HasRestrictions (Blizzard_APIDocumentationGenerated/SettingsUtilDocumentation.lua,
    -- line 17), without saying what it refuses. In combat it is not called: the request
    -- waits for PLAYER_REGEN_ENABLED, as production rule 2 has protected work wait, and
    -- chat says so each time. However many come in one fight, the panel opens once.
    -- Whether combat refuses it is the beta checklist's.
    open = function()
      if not InCombatLockdown() then
        openNow()
        return
      end
      chat(L["The settings open when combat ends."])
      if not waiting then
        waiting = true
        events:Once("PLAYER_REGEN_ENABLED", function()
          waiting = false
          openNow()
        end)
      end
    end,
    -- Through the setting, which writes the saved table and runs its callbacks once with
    -- the new value: an open panel shows it, and a Take a picture box greys or comes
    -- back with its Record box. Every switch the slash command changes has a box.
    set = function(tbl, key, value)
      bound[tbl][key]:SetValue(value)
    end,
  }
end

-- What takes the panel's place when the client will not build it. The saved settings are
-- read where they are kept whatever becomes of the panel, so recording goes on as they
-- say. set writes the saved table itself and, for the minimap button's switch, runs what
-- the box would; open says in chat that there is no panel and what still works.
---@param settings table the journal's settings
---@param chat FootstepsChat
---@param minimapShown fun()
---@return FootstepsOptions
local function standIn(settings, chat, minimapShown)
  ---@type FootstepsOptions
  return {
    open = function()
      chat(L["The settings panel could not be built. /footsteps record, shots, hideui and caption still work."])
    end,
    set = function(tbl, key, value)
      tbl[key] = value
      if tbl == settings.minimap and key == "shown" then
        minimapShown()
      end
    end,
  }
end

-- Build the category. Once a session, when the journal is loaded and writable: the
-- client refuses a variable registered twice. Settings is not yet confirmed in game
-- (probe Q16), so the panel is built through securecallfunction: if any of its calls
-- raises, the client's error handler reports it, as for an event handler that raises
-- (ForeverKit's Events), and a stand-in comes back instead. Blizzard's own settings code
-- takes a result back the same way (Blizzard_Settings_Shared/Blizzard_SettingsInbound.lua,
-- line 185, Gethe forever at e3ecc27).
---@param db FootstepsDB the journal, loaded and writable
---@param events table Kit.Events, for PLAYER_REGEN_ENABLED when the settings are asked for in combat
---@param chat FootstepsChat
---@param minimapShown fun() runs when "Show the minimap button" changes, by any means
---@return FootstepsOptions
function Options.new(db, events, chat, minimapShown)
  return securecallfunction(build, db, events, chat, minimapShown) or standIn(db.settings, chat, minimapShown)
end
