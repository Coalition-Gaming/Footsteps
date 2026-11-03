-- Which entry the detail view shows, and what its Hide button and its note box do
-- (DECISION-004, "The window": the detail view, notes and hiding). A click on a row
-- selects its entry. The selection lasts for the session and is never saved; it is
-- cleared once its entry is no longer listed. The button hides a shown entry and
-- restores a hidden one, with nothing to confirm (assumption 9). What a hide, a restore
-- or a note does to an entry is Journal's: the glue binds Journal's functions to the
-- saved journal and passes them in, because Journal is another Core module.

local _, ns = ...

local Selection = {}
ns.Selection = Selection

---@class FootstepsJournalActions
---@field hide fun(index: number) Journal.hide on the saved journal
---@field restore fun(index: number) Journal.restore on the saved journal
---@field setNote fun(index: number, text: string) Journal.setNote on the saved journal

---@class FootstepsSelection
---@field journal FootstepsJournalActions
---@field index number? the selected entry
local methods = {}
methods.__index = methods

---@param journal FootstepsJournalActions
---@return FootstepsSelection
function Selection.new(journal)
  return setmetatable({ journal = journal }, methods)
end

-- The selected entry's index, or nil.
---@return number?
function methods:get()
  return self.index
end

-- A click on a row. True when the view now shows another entry than before, nothing
-- selected included; false when the entry was already selected, so the glue loads the
-- note box only on true and keeps what the player is typing.
---@param index number
---@return boolean
function methods:select(index)
  if self.index == index then
    return false
  end
  self.index = index
  return true
end

-- After the journal or the filter changes: keep the selection while `listed` says its
-- entry is listed, and clear it otherwise. Returns the entry still selected, or nil.
---@param listed fun(index: number): boolean Timeline.listed, bound by the glue
---@return number?
function methods:follow(listed)
  if self.index ~= nil and not listed(self.index) then
    self.index = nil
  end
  return self.index
end

-- A click on the button: restore the selected entry when it is hidden, hide it
-- otherwise. The entry stays selected; whether it is still listed is follow's to say.
---@param entries FootstepsEntry[]
---@return "hidden" | "restored" | nil
function methods:hideOrRestore(entries)
  local index = self.index
  local entry = index and entries[index]
  if not entry then
    return nil
  end
  if entry.hidden then
    self.journal.restore(index)
    return "restored"
  end
  self.journal.hide(index)
  return "hidden"
end

-- What the player typed in the note box, saved on the selected entry as it is; Journal
-- trims it and keeps it to its limit. True when the entry gained a note or lost one,
-- which is when the row's note mark changes.
---@param entries FootstepsEntry[]
---@param text string
---@return boolean
function methods:saveNote(entries, text)
  local index = self.index
  local entry = index and entries[index]
  if not entry then
    return false
  end
  local had = entry.note ~= nil
  self.journal.setNote(index, text)
  return had ~= (entry.note ~= nil)
end
