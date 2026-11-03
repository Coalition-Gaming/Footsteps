-- The detail view (DECISION-004, "The window": the detail view, notes and hiding; the
-- design's "The detail view"). A click on a row opens its entry beside the list: its
-- icon and sentence, the fields Core/Timeline.lua's detail gives, the picture's file name
-- in a box it can be copied from, with a line saying its time may be a second off, a note
-- box and a Hide button that reads Restore for a hidden entry. Which entry is open, and
-- what the button and the note box do, are Core/Selection.lua's decisions, which
-- Window.lua makes; this file puts one detail on screen and passes the player's clicks
-- and typing back. The three templates are Blizzard's, in Blizzard_SharedXML, which loads
-- for every game type (Gethe/wow-ui-source, forever at e3ecc27, build 70205):
--   - Blizzard_SharedXML/Shared/InputBox/InputBoxTemplates.xml, line 70: InputBoxTemplate,
--     an EditBox that highlights all its text when it takes the keyboard and gives the
--     keyboard up on Escape (lines 7 to 9).
--   - The same file, lines 72 to 175: InputScrollFrameTemplate, a ScrollFrame around a
--     multi-line EditBox that does not take the keyboard when shown (line 150), with a
--     count of the letters left. Blizzard's report dialog uses it for its comment box
--     (Blizzard_ReportFrameShared/ReportFrameShared.xml, lines 164 to 171).
--   - Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml, line 315:
--     UIPanelButtonTemplate, the game's red panel button.

local _, ns = ...

local Detail = {}
ns.Detail = Detail

local L = ns.L
local Journal = ns.Journal

Detail.WIDTH = 300
local ICON_SIZE = 36
local FIELDS_TOP = -(ICON_SIZE + 12)
local FIELD_HEIGHT = 18
local LABEL_WIDTH = 96
local GAP = 10
local BOX_HEIGHT = 20
local HINT_HEIGHT = 12
local NOTE_HEIGHT = 110
-- InputBoxTemplate's border reaches 5 to the left of the box, and
-- InputScrollFrameTemplate's 5 around it (InputBoxTemplates.xml, lines 49, 85 and 91).
local BORDER = 6
local BUTTON_WIDTH = 96
-- The production rule on OnUpdate (docs/process/production.md, section 3): at most 10
-- runs a second.
local SCROLL_EVERY = 0.1

---@class FootstepsDetailField
---@field Label FontString
---@field Value FontString

---@class FootstepsNoteFrame : ScrollFrame
---@field EditBox EditBox the note, multi-line
---@field CharCount FontString the letters left

---@class FootstepsDetailFrame : Frame
---@field Icon Texture
---@field Title FontString the sentence
---@field Fields FootstepsDetailField[] made as they are needed; those past the entry's lines are hidden
---@field FileLabel FontString
---@field File EditBox the picture's file name, to copy
---@field FileHint FontString under the file name: its time may be a second off
---@field NoteLabel FontString
---@field Note FootstepsNoteFrame
---@field HideButton Button

---@class FootstepsDetailActions
---@field hideOrRestore fun() a click on the button
---@field noteTyped fun(text: string) the note box's text, after the player changed it

---@class FootstepsDetailView
---@field frame FootstepsDetailFrame
---@field show fun(detail: FootstepsDetail?, loadNote: boolean) an entry's detail, or nothing

-- The view, inside `parent` and hidden until an entry opens.
---@param parent Frame the window
---@param actions FootstepsDetailActions
---@return FootstepsDetailView
function Detail.create(parent, actions)
  local frame = CreateFrame("Frame", nil, parent) --[[@as FootstepsDetailFrame]]
  -- The file name the box shows, which it goes back to when the player types in it.
  local fileName

  frame.Icon = frame:CreateTexture(nil, "ARTWORK")
  frame.Icon:SetSize(ICON_SIZE, ICON_SIZE)
  frame.Icon:SetPoint("TOPLEFT")
  -- The sentence, on up to two lines beside the icon, as high as the icon.
  frame.Title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  frame.Title:SetPoint("TOPLEFT", frame.Icon, "TOPRIGHT", 8, 0)
  frame.Title:SetSize(Detail.WIDTH - ICON_SIZE - 8, ICON_SIZE)
  frame.Title:SetJustifyH("LEFT")
  frame.Title:SetJustifyV("MIDDLE")
  frame.Fields = {}

  -- The file name. The box stays enabled so the player can click into it, which
  -- highlights all of it, and copy it with Ctrl+C. The game's CopyToClipboard is
  -- restricted (HasRestrictions, Blizzard_APIDocumentationGenerated/OsDocumentation.lua,
  -- line 12), so the addon does not copy for the player. Whatever the player types is
  -- put back.
  frame.FileLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  frame.FileLabel:SetWidth(LABEL_WIDTH)
  frame.FileLabel:SetJustifyH("LEFT")
  frame.FileLabel:SetText(L["Screenshot"])
  local file = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
  -- An edit box takes the keyboard whenever it is shown unless told not to, and then
  -- the player's keys move nothing until they press Escape. Blizzard's own code says so
  -- straight after CreateFrame (Blizzard_PTRFeedback/Blizzard_PTRFeedback_Frames.lua,
  -- lines 117 and 121).
  file:SetAutoFocus(false)
  file:SetSize(Detail.WIDTH - LABEL_WIDTH - 8 - BORDER, BOX_HEIGHT)
  file:SetPoint("LEFT", frame.FileLabel, "RIGHT", 8 + BORDER, 0)
  file:SetScript("OnTextChanged", function(self, isUserInput)
    if isUserInput then
      self:SetText(fileName or "")
      self:HighlightText()
    end
  end)
  -- Enter leaves the box, as Escape does through the template.
  file:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
  end)
  frame.File = file
  -- The name is predicted from the clock, not read, so it can be a second off
  -- (DECISION-002, "Linking the file"). The line under the box says so, and the box
  -- keeps the bare name for copying.
  frame.FileHint = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  frame.FileHint:SetWidth(Detail.WIDTH)
  frame.FileHint:SetJustifyH("LEFT")
  frame.FileHint:SetWordWrap(false)

  -- The note. The template's own OnTextChanged keeps the count of letters left, so the
  -- save is hooked after it rather than set in its place.
  frame.NoteLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  frame.NoteLabel:SetJustifyH("LEFT")
  frame.NoteLabel:SetText(L["Note"])
  local note = CreateFrame("ScrollFrame", nil, frame, "InputScrollFrameTemplate") --[[@as FootstepsNoteFrame]]
  -- The template sizes its box from the frame's size when it loads (InputScrollFrame_OnLoad,
  -- InputBoxTemplates.lua, line 90). Made from Lua, the frame has no size then, so the
  -- box is given the width it would have had. The note box shows no instructions.
  note:SetSize(Detail.WIDTH - 2 * BORDER, NOTE_HEIGHT)
  note.EditBox:SetWidth(Detail.WIDTH - 2 * BORDER - 18)
  -- Before any text: Journal keeps 500 characters, and so does the box. The client counts
  -- letters as characters, as Journal does; the beta checklist confirms it. The
  -- template's count of letters left follows the limit.
  note.EditBox:SetMaxLetters(Journal.NOTE_LIMIT)
  -- Each change the player makes is saved at once. It is one string on the entry, and
  -- nothing is lost however the box is left: Escape, the window closing at a death or
  -- a loading screen, or another row clicked. Text set by the addon is never saved.
  note.EditBox:HookScript("OnTextChanged", function(self, isUserInput)
    if isUserInput then
      actions.noteTyped(self:GetText())
    end
  end)
  -- The template's box runs InputScrollFrame_OnUpdate on every frame while it is visible
  -- (InputBoxTemplates.xml, line 169). It scrolls the box to its cursor once the cursor
  -- has moved, and otherwise returns at once (InputBoxTemplates.lua, lines 45 to 80 and
  -- 123). The player moves the cursor only while the box has the keyboard, and the
  -- template's OnTextChanged calls the same function at once when the text changes
  -- (lines 107 to 109 and 21 to 25). So the handler is taken off here, and only while the
  -- box has the keyboard does Footsteps' own OnUpdate run it: an entry left open costs
  -- nothing per frame. That OnUpdate adds up the seconds the client gives it each frame
  -- and runs the template's once a tenth of a second has passed, as the performance
  -- budget asks (docs/process/production.md, section 3), so a cursor moved by the arrow
  -- keys is followed within a tenth of a second. It is one of Footsteps' two OnUpdates;
  -- the other is the minimap button's, while the player drags it (the design's
  -- Performance section).
  local scrollToCursor = note.EditBox:GetScript("OnUpdate")
  local sinceScroll = 0
  ---@param elapsed number seconds since the last frame
  local function throttledScroll(self, elapsed)
    sinceScroll = sinceScroll + elapsed
    if sinceScroll < SCROLL_EVERY then
      return
    end
    local since = sinceScroll
    sinceScroll = 0
    scrollToCursor(self, since)
  end
  note.EditBox:SetScript("OnUpdate", nil)
  note.EditBox:SetScript("OnEditFocusGained", function(self)
    sinceScroll = 0
    self:SetScript("OnUpdate", throttledScroll)
  end)
  note.EditBox:SetScript("OnEditFocusLost", function(self)
    self:SetScript("OnUpdate", nil)
  end)
  frame.Note = note

  local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  button:SetSize(BUTTON_WIDTH, 22)
  button:SetPoint("BOTTOMRIGHT", -BORDER, BORDER)
  button:SetScript("OnClick", actions.hideOrRestore)
  frame.HideButton = button

  -- A box that is hidden may keep the keyboard, and then the player's keys go nowhere.
  -- Whenever the view stops being visible (its entry closed, the window closed by its
  -- button or by the game at a death), it gives the keyboard up. The selection is
  -- Window.lua's and does not change.
  frame:SetScript("OnHide", function()
    file:ClearFocus()
    note.EditBox:ClearFocus()
  end)
  frame:Hide()

  ---@param index number
  ---@return FootstepsDetailField
  local function field(index)
    local made = frame.Fields[index]
    if made then
      return made
    end
    local label = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("TOPLEFT", 0, FIELDS_TOP - (index - 1) * FIELD_HEIGHT)
    label:SetWidth(LABEL_WIDTH)
    label:SetJustifyH("LEFT")
    local value = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    value:SetPoint("TOPLEFT", label, "TOPRIGHT", 8, 0)
    value:SetWidth(Detail.WIDTH - LABEL_WIDTH - 8)
    value:SetJustifyH("LEFT")
    value:SetWordWrap(false)
    made = { Label = label, Value = value }
    frame.Fields[index] = made
    return made
  end

  -- Everything the view shows, from Timeline.detail. The note box is loaded only with
  -- `loadNote` (another entry opened, or the window opening) or when the view was
  -- closed, so a refresh never takes away what the player is typing.
  ---@param detail FootstepsDetail?
  ---@param loadNote boolean
  local function show(detail, loadNote)
    if detail == nil then
      frame:Hide()
      return
    end
    frame.Icon:SetTexture(detail.icon)
    frame.Icon:SetDesaturated(detail.hidden)
    frame.Title:SetText(detail.text)
    local lines = detail.lines
    for index, line in ipairs(lines) do
      local shown = field(index)
      shown.Label:SetText(line.label)
      shown.Value:SetText(line.value)
      shown.Label:Show()
      shown.Value:Show()
    end
    for index = #lines + 1, #frame.Fields do
      frame.Fields[index].Label:Hide()
      frame.Fields[index].Value:Hide()
    end
    -- The file name and the note follow the fields, however many there are.
    local top = FIELDS_TOP - #lines * FIELD_HEIGHT - GAP
    fileName = detail.file
    if fileName then
      frame.FileLabel:SetPoint("TOPLEFT", 0, top - 3)
      -- Set only when it changed, so a refresh keeps the highlight of a box in use.
      if file:GetText() ~= fileName then
        file:SetText(fileName)
      end
      top = top - BOX_HEIGHT - 2
      frame.FileHint:SetPoint("TOPLEFT", 0, top)
      frame.FileHint:SetText(detail.fileHint or "")
      top = top - HINT_HEIGHT - GAP
    else
      file:ClearFocus()
    end
    frame.FileLabel:SetShown(fileName ~= nil)
    file:SetShown(fileName ~= nil)
    frame.FileHint:SetShown(fileName ~= nil)
    frame.NoteLabel:SetPoint("TOPLEFT", 0, top)
    note:SetPoint("TOPLEFT", BORDER, top - FIELD_HEIGHT - BORDER)
    if loadNote or not frame:IsShown() then
      note.EditBox:SetText(detail.note)
    end
    button:SetText(detail.button)
    frame:Show()
  end

  return { frame = frame, show = show }
end
