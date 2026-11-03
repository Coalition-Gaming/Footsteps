-- Maps: the zone or dungeon a first visit is about, and the dungeon a boss falls in
-- (DECISION-004, "Milestones"). Outside a dungeon, the map the client reports is walked
-- up through its parents to the first zone, so a subzone, a mine or a cave counts as its
-- zone. Inside a dungeon or raid the instance names the place, because a dungeon may
-- have no map at all or one map per floor. Probe Q5 confirms in the game which maps
-- Forever reports. The glue passes a lookup that reads C_Map.GetMapInfo with nil for any
-- field that arrives secret, Enum.UIMapType and GetInstanceInfo.

local _, ns = ...

local Maps = {}
ns.Maps = Maps

---@class FootstepsPlace
---@field id number a uiMapID for a zone, an instance id for a dungeon
---@field name string
---@field dungeon boolean

---@class FootstepsMapInfo
---@field name string?
---@field mapType number?
---@field parentMapID number?

---@class FootstepsInstance
---@field name string? GetInstanceInfo's name
---@field type string? its instanceType: "none", "party", "raid", "pvp", "arena", "scenario"
---@field id number? its instanceID

-- Instance types that are dungeons. A battleground, an arena and a scenario are walked
-- like the open world.
local DUNGEONS = { party = true, raid = true }

-- The name of the dungeon or raid the player is in, as GetInstanceInfo gives it, or
-- nothing: outside one, where GetInstanceInfo names the continent, or without a type
-- or a name. It is the dungeon a boss falls in.
---@param instance FootstepsInstance
---@return string?
function Maps.dungeonName(instance)
  local name = instance.name
  if not DUNGEONS[instance.type] or type(name) ~= "string" or name == "" then
    return nil
  end
  return name
end

-- What GetInstanceInfo says about a dungeon, or nothing without a name and an id.
---@param instance FootstepsInstance
---@return FootstepsPlace?
local function dungeon(instance)
  local name, id = Maps.dungeonName(instance), instance.id
  if name == nil or type(id) ~= "number" then
    return nil
  end
  return { id = id, name = name, dungeon = true }
end

-- A continent, the world or the cosmos: past every zone.
---@param mapType number
---@param types table<string, number>
---@return boolean
local function aboveZones(mapType, types)
  return mapType == types.Continent or mapType == types.World or mapType == types.Cosmic
end

-- The place a map belongs to, or nothing: a continent or the world, a map the client
-- does not know, or a walk that ends before it finds a zone. A map whose type is not
-- known ends the walk: it may be a zone itself, and the zone above it would be the wrong
-- place, kept for good.
---@param mapID number? C_Map.GetBestMapForUnit("player")
---@param getInfo fun(mapID: number): FootstepsMapInfo? C_Map.GetMapInfo, read by the glue
---@param types table<string, number> Enum.UIMapType
---@param instance FootstepsInstance? GetInstanceInfo's name, instanceType and instanceID
---@return FootstepsPlace?
function Maps.place(mapID, getInfo, types, instance)
  if instance and DUNGEONS[instance.type] then
    return dungeon(instance)
  end
  local visited = {}
  local id = mapID
  -- A parent of 0 or nil ends the walk, and so does a map seen before: a loop.
  while type(id) == "number" and id ~= 0 and not visited[id] do
    visited[id] = true
    local info = getInfo(id)
    if info == nil or info.mapType == nil or aboveZones(info.mapType, types) then
      return nil
    end
    if info.mapType == types.Zone then
      if type(info.name) ~= "string" or info.name == "" then
        return nil
      end
      return { id = id, name = info.name, dungeon = false }
    end
    -- Micro, Orphan, and Dungeon maps outside a dungeon instance (a city's cellar, a
    -- mine) belong to the zone above them.
    id = info.parentMapID
  end
  return nil
end
