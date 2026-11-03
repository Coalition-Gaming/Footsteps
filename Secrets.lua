-- The glue's guard for values the client may hand out secret (production rule 2). Any
-- value from a unit, map or combat API may be secret, and a secret may not be compared,
-- counted or tested. Core never sees one: the glue reads each value through this and
-- passes nil in its place. Footsteps.lua and Window.lua use it, so it loads before
-- every other glue file.

local _, ns = ...

local Secrets = {}
ns.Secrets = Secrets

-- A value the client may hand out secret, as nil when it does.
function Secrets.readable(value)
  if issecretvalue(value) then
    return nil
  end
  return value
end
